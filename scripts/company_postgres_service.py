#!/usr/bin/env python3
"""Run the authenticated, fixed-read PostgreSQL company service.

The rehearsal adapters and the browser read-model server intentionally use one
``psql`` process per query.  This service keeps bounded, reusable PostgreSQL
sessions behind a fixed HTTP read surface so the service contract can be
exercised without introducing a third-party runtime dependency.  The managed
deployment still owns TLS termination, token issuance, observability sinks,
and provider-level capacity controls.

The bounded service exposes these endpoints:

* ``/api/health``
* ``/api/company/summary``
* ``/api/company/receipts``
* ``/api/company/projections?aggregate_type=<optional>``
* ``/api/company/expenses`` and ``/api/company/expenses/<id>`` (GET)
* ``/api/company/expenses`` (POST create draft)
* ``/api/company/expenses/<id>/{submit,approve,reject,resubmit}`` (POST)
* ``/api/company/contracts`` and ``/api/company/contracts/<id>`` (GET)
* ``/api/company/contracts`` (POST create draft)
* ``/api/company/contracts/<id>/{submit,approve,reject,resubmit}`` (POST)
* ``/api/company/payment-applies`` and ``/api/company/payment-applies/<id>`` (GET)
* ``/api/company/payment-applies/eligibility`` (GET)
* ``/api/company/payment-applies`` (POST create draft)
* ``/api/company/payment-applies/<id>/{submit,approve,reject,resubmit,update,void}`` (POST)
* ``/api/company/tenders`` and ``/api/company/tenders/<id>`` (GET)
* ``/api/company/tenders`` (POST create planning draft)
* ``/api/company/tenders/<id>/{publish,open_bidding,award,complete,cancel}`` (POST)
* ``/api/company/suppliers`` and ``/api/company/suppliers/<id>`` (GET)
* ``/api/company/suppliers`` (POST create draft)
* ``/api/company/suppliers/<id>/{update,submit_review,review,blacklist,void}`` (POST)
* ``/api/company/suppliers/<id>/risk`` (GET)
* ``/api/company/tender-splits`` (GET/POST)
* ``/api/company/sales/{customers,subscriptions,contracts,mortgages,refunds,revenues}`` (GET)
* ``/api/company/receivables`` (GET)
* ``/api/company/sales/{customers,subscriptions,contracts,mortgages,refunds}`` (POST)
  with idempotent lifecycle commands
* ``/api/company/delivery/{progress,outputs,tasks,task-reports,plan-summary}`` (GET)
* ``/api/company/delivery/{progress,outputs,tasks}/...`` (POST)
  with source-preserving reads and idempotent local commands
* ``/api/company/reports/{cost-summary,contract-payment-ledger,
  supplier-analysis,approval-efficiency,project-stage-matrix,overview}`` (GET)
* ``/api/company/workflow/process-defs`` and
  ``/api/company/workflow/process-defs/<process-key>/preview`` (GET)
* ``/api/company/projects`` and ``/api/company/projects/<id>`` (GET)
* ``/api/company/business-units/tree`` (GET, source-compatible MDM read)
* ``/api/company/budget/dict/cost-subjects`` and
  ``/api/company/budget/proceedings`` (GET, source-compatible budget reads)
* ``/api/company/investment/{projects,versions,meta}/...`` (GET,
  source-compatible investment reads)
* ``/api/company/projects/<id>/tasks``, ``/api/company/tasks/<id>`` and
  ``/api/company/projects/<id>/{lifecycle,plan-summary}`` and
  ``/api/company/tasks/<id>/delay-impact`` (GET, source-compatible project reads)
* ``/api/company/loans`` and ``/api/company/loans/<id>`` (GET)
* ``/api/company/loans`` (POST create draft)
* ``/api/company/loans/<id>/{submit-for-approval,offset,update,void}`` (POST)
* ``PUT|DELETE /api/company/loans/<id>`` (source-compatible update/void aliases)
  (workflow synchronization stays explicitly gated until source workflow rows exist)

The bearer token is read from an environment variable named by
``--token-env``.  The token itself is never accepted as a command-line
argument or written to logs. When ``--actor-signing-secret-env`` is supplied,
company commands also require a gateway-signed actor assertion.
"""

from __future__ import annotations

import argparse
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
import hashlib
import hmac
import json
import os
import queue
import re
import select
import subprocess
import sys
import threading
import time
import uuid
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse

from company_postgres_target_apply import executable, sql_literal


class ServiceError(RuntimeError):
    """A fail-closed service or database boundary error."""


class PoolExhausted(ServiceError):
    """No reusable database session became available before the deadline."""


class CommandRejected(ServiceError):
    """A validated company command could not be applied."""

    def __init__(self, message: str, status: int = 409) -> None:
        super().__init__(message)
        self.status = status


IDENTIFIER = re.compile(r"^[A-Za-z0-9_.:-]{1,128}$")


@dataclass
class PsqlSession:
    command: list[str]
    query_timeout: float
    process: subprocess.Popen[str] | None = None

    def start(self) -> None:
        if self.process is not None and self.process.poll() is None:
            return
        self.close()
        self.process = subprocess.Popen(
            self.command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=os.environ.copy(),
        )

    def close(self) -> None:
        process = self.process
        self.process = None
        if process is None:
            return
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=1)

    def execute(self, sql: str) -> list[str]:
        self.start()
        process = self.process
        if process is None or process.stdin is None or process.stdout is None:
            raise ServiceError("database session failed to start")
        marker = "__moonproj_service_" + uuid.uuid4().hex + "__"
        command = sql.strip().rstrip(";") + ";\nSELECT " + sql_literal(marker) + ";\n"
        try:
            process.stdin.write(command)
            process.stdin.flush()
            rows: list[str] = []
            deadline = time.monotonic() + self.query_timeout
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise ServiceError("database query timed out")
                ready, _, _ = select.select([process.stdout], [], [], remaining)
                if not ready:
                    raise ServiceError("database query timed out")
                line = process.stdout.readline()
                if line == "":
                    raise ServiceError("database session closed unexpectedly")
                value = line.rstrip("\r\n")
                if value == marker:
                    return rows
                rows.append(value)
        except (OSError, ValueError) as error:
            raise ServiceError("database session I/O failed") from error
        except ServiceError:
            self.close()
            raise


class PsqlPool:
    """A bounded pool of persistent ``psql`` sessions.

    Each checked-out session is used by one request at a time.  If a session
    dies or times out it is discarded and replaced on the next checkout; a
    failed replacement never turns into an unbounded connection attempt.
    """

    def __init__(
        self,
        *,
        psql: str | None,
        pg_host: str | None,
        pg_port: str | None,
        pg_user: str | None,
        database: str | None,
        size: int,
        acquire_timeout: float,
        query_timeout: float,
    ) -> None:
        if size <= 0 or size > 64:
            raise ServiceError("pool size must be between 1 and 64")
        if acquire_timeout <= 0 or acquire_timeout > 300:
            raise ServiceError("acquire timeout must be between 0 and 300 seconds")
        if query_timeout <= 0 or query_timeout > 300:
            raise ServiceError("query timeout must be between 0 and 300 seconds")
        self.acquire_timeout = acquire_timeout
        self.query_timeout = query_timeout
        self.size = size
        command = [
            executable(psql),
            "-X",
            "-q",
            "-v",
            "ON_ERROR_STOP=1",
            "-A",
            "-t",
            "-F",
            "|",
        ]
        for flag, value in (("-h", pg_host), ("-p", pg_port), ("-U", pg_user), ("-d", database)):
            if value:
                command.extend((flag, value))
        self._command = command
        self._available: queue.Queue[PsqlSession] = queue.Queue(maxsize=size)
        self._closed = False
        self._lock = threading.Lock()
        for _ in range(size):
            self._available.put(self._new_session())

    def _new_session(self) -> PsqlSession:
        return PsqlSession(self._command.copy(), self.query_timeout)

    def close(self) -> None:
        with self._lock:
            if self._closed:
                return
            self._closed = True
            while True:
                try:
                    self._available.get_nowait().close()
                except queue.Empty:
                    return

    def execute(self, sql: str) -> list[str]:
        with self._lock:
            if self._closed:
                raise ServiceError("database pool is closed")
        try:
            session = self._available.get(timeout=self.acquire_timeout)
        except queue.Empty as error:
            raise PoolExhausted("database pool exhausted") from error
        replacement = False
        try:
            return session.execute(sql)
        except ServiceError:
            session.close()
            replacement = True
            raise
        finally:
            with self._lock:
                closed = self._closed
            if closed:
                session.close()
            else:
                if replacement:
                    session = self._new_session()
                self._available.put(session)


def query_lines(pool: PsqlPool, sql: str) -> list[str]:
    return [line for line in pool.execute("\n".join(line.strip() for line in sql.splitlines() if line.strip())) if line]


def summary(pool: PsqlPool, expected_schema_version: int) -> dict[str, Any]:
    lines = query_lines(
        pool,
        """
        SELECT
          (SELECT count(*) FROM company_record),
          (SELECT count(*) FROM company_aggregate_projection),
          (SELECT count(*) FROM company_accounting_event_link),
          (SELECT count(*) FROM company_migration_receipt),
          (SELECT coalesce(max(version), 0) FROM company_schema)
        """,
    )
    if len(lines) != 1 or len(lines[0].split("|")) != 5:
        raise ServiceError("unexpected company summary shape")
    raw, projections, links, receipts, schema_version = [int(value) for value in lines[0].split("|")]
    if schema_version != expected_schema_version:
        raise ServiceError("company schema version is not ready")
    return {
        "product": "moonproj-company",
        "target": "postgresql",
        "read_only": False,
        "capabilities": [
            "read_model",
            "expense_command",
            "contract_command",
            "payment_application_read",
            "payment_application_command",
            "procurement_read",
            "supplier_read",
            "supplier_command",
            "tender_command",
            "contract_split_command",
            "sales_read",
            "sales_command",
            "receivable_read",
            "invoice_read",
            "delivery_read",
            "delivery_command",
            "report_read",
            "workflow_definition_read",
            "project_read",
            "loan_read",
            "loan_command",
            "audit_receipt",
        ],
        "schema_version": schema_version,
        "raw_records": raw,
        "aggregate_projections": projections,
        "accounting_links": links,
        "receipts": receipts,
    }


def health(pool: PsqlPool, expected_schema_version: int) -> dict[str, Any]:
    summary(pool, expected_schema_version)
    return {
        "ok": True,
        "target": "postgresql",
        "read_only": False,
        "capabilities": [
            "read_model",
            "expense_command",
            "contract_command",
            "payment_application_read",
            "payment_application_command",
            "procurement_read",
            "supplier_read",
            "supplier_command",
            "tender_command",
            "contract_split_command",
            "sales_read",
            "sales_command",
            "receivable_read",
            "invoice_read",
            "delivery_read",
            "delivery_command",
            "report_read",
            "workflow_definition_read",
            "project_read",
            "loan_read",
            "loan_command",
            "audit_receipt",
        ],
        "schema_version": expected_schema_version,
    }


def decode_hex(value: str) -> str:
    try:
        return bytes.fromhex(value).decode("utf-8")
    except (ValueError, UnicodeDecodeError) as error:
        raise ServiceError("invalid database response encoding") from error


def receipts(pool: PsqlPool) -> list[dict[str, Any]]:
    lines = query_lines(
        pool,
        """
        SELECT encode(convert_to(run_id, 'UTF8'), 'hex'),
               encode(convert_to(source_snapshot_id, 'UTF8'), 'hex'),
               target_schema_version::text,
               encode(convert_to(mapping_version, 'UTF8'), 'hex'),
               encode(convert_to(state, 'UTF8'), 'hex'),
               encode(convert_to(coalesce(applied_hash, ''), 'UTF8'), 'hex')
        FROM company_migration_receipt
        ORDER BY certified_at NULLS LAST, run_id
        """,
    )
    result: list[dict[str, Any]] = []
    for line in lines:
        fields = line.split("|")
        if len(fields) != 6:
            raise ServiceError("unexpected company receipt shape")
        result.append(
            {
                "run_id": decode_hex(fields[0]),
                "source_snapshot_id": decode_hex(fields[1]),
                "target_schema_version": int(fields[2]),
                "mapping_version": decode_hex(fields[3]),
                "state": decode_hex(fields[4]),
                "applied_hash": decode_hex(fields[5]),
            }
        )
    return result


def projections(pool: PsqlPool, aggregate_type: str | None, max_rows: int) -> list[dict[str, Any]]:
    clause = ""
    if aggregate_type is not None:
        if not IDENTIFIER.fullmatch(aggregate_type):
            raise ValueError("invalid aggregate_type")
        clause = f"WHERE aggregate_type = {sql_literal(aggregate_type)}"
    lines = query_lines(
        pool,
        f"""
        SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'),
               encode(convert_to(aggregate_id, 'UTF8'), 'hex'),
               revision::text,
               encode(convert_to(payload::text, 'UTF8'), 'hex'),
               encode(convert_to(source_event_id, 'UTF8'), 'hex')
        FROM company_aggregate_projection
        {clause}
        ORDER BY aggregate_type, aggregate_id, revision
        LIMIT {max_rows}
        """,
    )
    result: list[dict[str, Any]] = []
    for line in lines:
        fields = line.split("|")
        if len(fields) != 5:
            raise ServiceError("unexpected company projection shape")
        try:
            payload = json.loads(decode_hex(fields[3]))
        except json.JSONDecodeError as error:
            raise ServiceError("invalid company projection JSON") from error
        result.append(
            {
                "aggregate_type": decode_hex(fields[0]),
                "aggregate_id": decode_hex(fields[1]),
                "revision": int(fields[2]),
                "payload": payload,
                "source_event_id": decode_hex(fields[4]),
            }
        )
    return result


def _decode_projection_line(line: str) -> dict[str, Any]:
    fields = line.split("|")
    if len(fields) != 5:
        raise ServiceError("unexpected expense projection shape")
    try:
        payload = json.loads(decode_hex(fields[3]))
    except json.JSONDecodeError as error:
        raise ServiceError("invalid expense projection JSON") from error
    return {
        "aggregate_type": decode_hex(fields[0]),
        "expense_id": decode_hex(fields[1]),
        "revision": int(fields[2]),
        "payload": payload,
        "source_event_id": decode_hex(fields[4]),
    }


def expenses(pool: PsqlPool, expense_id: str | None, max_rows: int) -> list[dict[str, Any]]:
    if expense_id is not None and not IDENTIFIER.fullmatch(expense_id):
        raise ValueError("invalid expense_id")
    if expense_id is None:
        query = f"""
        SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'),
               encode(convert_to(aggregate_id, 'UTF8'), 'hex'),
               revision::text,
               encode(convert_to(payload::text, 'UTF8'), 'hex'),
               encode(convert_to(source_event_id, 'UTF8'), 'hex')
        FROM (
          SELECT DISTINCT ON (aggregate_id)
                 aggregate_type, aggregate_id, revision, payload, source_event_id
          FROM company_aggregate_projection
          WHERE aggregate_type = 'expense_claim'
          ORDER BY aggregate_id, revision DESC
        ) latest
        ORDER BY aggregate_id
        LIMIT {max_rows}
        """
    else:
        query = f"""
        SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'),
               encode(convert_to(aggregate_id, 'UTF8'), 'hex'),
               revision::text,
               encode(convert_to(payload::text, 'UTF8'), 'hex'),
               encode(convert_to(source_event_id, 'UTF8'), 'hex')
        FROM company_aggregate_projection
        WHERE aggregate_type = 'expense_claim'
          AND aggregate_id = {sql_literal(expense_id)}
        ORDER BY revision DESC
        LIMIT {max_rows}
        """
    return [_decode_projection_line(line) for line in query_lines(pool, query)]


def _decode_contract_fields(line: str) -> dict[str, Any]:
    fields = line.split("|")
    if len(fields) != 14:
        raise ServiceError("unexpected contract projection shape")
    try:
        return {
            "contract_id": decode_hex(fields[0]),
            "contract_code": decode_hex(fields[1]),
            "contract_name": decode_hex(fields[2]),
            "project_id": decode_hex(fields[3]),
            "project_name": decode_hex(fields[4]),
            "supplier_id": decode_hex(fields[5]),
            "supplier_name": decode_hex(fields[6]),
            "amount_minor": int(fields[7]),
            "currency": decode_hex(fields[8]),
            "sign_date": decode_hex(fields[9]),
            "state": decode_hex(fields[10]),
            "paid_amount_minor": int(fields[11]),
            "milestone_count": int(fields[12]),
            "source_kind": decode_hex(fields[13]),
        }
    except (ValueError, UnicodeDecodeError) as error:
        raise ServiceError("invalid contract projection encoding") from error


def contracts(pool: PsqlPool, contract_id: str | None, max_rows: int) -> list[dict[str, Any]]:
    if contract_id is not None and not IDENTIFIER.fullmatch(contract_id):
        raise ValueError("invalid contract_id")
    where = ""
    if contract_id is not None:
        where = f"WHERE base.contract_id = {sql_literal(contract_id)}"
    query = f"""
    WITH commitment_latest AS (
      SELECT DISTINCT ON (aggregate_id)
             aggregate_id AS contract_id, payload, 'imported' AS source_kind
      FROM company_aggregate_projection
      WHERE aggregate_type = 'commitment'
      ORDER BY aggregate_id, revision DESC
    ),
    contract_latest AS (
      SELECT DISTINCT ON (aggregate_id)
             aggregate_id AS contract_id, payload, 'command' AS source_kind
      FROM company_aggregate_projection
      WHERE aggregate_type = 'contract'
      ORDER BY aggregate_id, revision DESC
    ),
    base AS (
      SELECT contract_id, payload, source_kind
      FROM commitment_latest
      UNION ALL
      SELECT contract_id, payload, source_kind
      FROM contract_latest
    ),
    deduped AS (
      SELECT DISTINCT ON (contract_id) contract_id, payload, source_kind
      FROM base
      ORDER BY contract_id, CASE WHEN source_kind = 'command' THEN 1 ELSE 0 END DESC
    ),
    raw_contract AS (
      SELECT record_id, payload
      FROM company_record
      WHERE record_type = 'legacy/raw/cb_contract'
    ),
    raw_project AS (
      SELECT record_id, payload
      FROM company_record
      WHERE record_type = 'legacy/raw/ep_project'
    ),
    raw_payment AS (
      SELECT payload
      FROM company_record
      WHERE record_type = 'legacy/raw/cb_htfk_apply'
    ),
    milestone_counts AS (
      SELECT payload->'candidate'->'milestone'->>'contract_guid' AS contract_id,
             count(*)::text AS milestone_count
      FROM company_aggregate_projection
      WHERE aggregate_type = 'contract_milestone'
      GROUP BY payload->'candidate'->'milestone'->>'contract_guid'
    ),
    payment_totals AS (
      SELECT payload->>'contract_guid' AS contract_id,
             coalesce(sum(
               CASE WHEN payload->>'pay_state' = '完全支付'
                 THEN round((payload->>'apply_amount')::numeric * 100)::bigint
                 ELSE 0 END
             ), 0)::text AS paid_amount_minor
      FROM raw_payment
      GROUP BY payload->>'contract_guid'
    )
    SELECT encode(convert_to(base.contract_id, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(raw.payload->>'contract_code', base.payload->>'contract_code', base.contract_id), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(raw.payload->>'contract_name', base.payload->>'contract_name', base.contract_id), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(raw.payload->>'proj_guid', base.payload->>'project_id', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(project.payload->>'proj_name', base.payload->>'project_name', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(base.payload->'candidate'->>'counterparty_id', base.payload->>'supplier_id', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(raw.payload->>'yf_provider_name', base.payload->>'supplier_name', base.payload->>'supplier_id', ''), 'UTF8'), 'hex'),
           coalesce(base.payload->'candidate'->>'amount_minor', base.payload->>'amount_minor',
                    round(coalesce((raw.payload->>'ht_amount')::numeric, 0) * 100)::bigint::text, '0'),
           encode(convert_to(coalesce(base.payload->'candidate'->>'currency', base.payload->>'currency', 'CNY'), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(raw.payload->>'sign_date', base.payload->>'sign_date', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(base.payload->>'state', 'active'), 'UTF8'), 'hex'),
           coalesce(payment.paid_amount_minor, '0'),
           coalesce(milestone.milestone_count, '0'),
           encode(convert_to(base.source_kind, 'UTF8'), 'hex')
    FROM deduped base
    LEFT JOIN raw_contract raw ON raw.record_id = base.contract_id
    LEFT JOIN raw_project project ON project.record_id = raw.payload->>'proj_guid'
    LEFT JOIN milestone_counts milestone ON milestone.contract_id = base.contract_id
    LEFT JOIN payment_totals payment ON payment.contract_id = base.contract_id
    {where}
    ORDER BY base.contract_id
    LIMIT {max_rows}
    """
    result = [_decode_contract_fields(line) for line in query_lines(pool, query)]
    for item in result:
        item["amount_display"] = f"¥{item['amount_minor'] / 100:,.2f}"
        item["paid_amount_display"] = f"¥{item['paid_amount_minor'] / 100:,.2f}"
    return result


def contract_milestones(pool: PsqlPool, contract_id: str, max_rows: int) -> list[dict[str, Any]]:
    if not IDENTIFIER.fullmatch(contract_id):
        raise ValueError("invalid contract_id")
    query = f"""
    SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(payload->'candidate'->'milestone'->>'node_name', ''), 'UTF8'), 'hex'),
           coalesce(payload->'candidate'->'milestone'->>'plan_amount_minor', '0'),
           encode(convert_to(coalesce(payload->'candidate'->'milestone'->>'plan_pct_bps', '0'), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(payload->'candidate'->'milestone'->>'trigger_type', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(payload->'candidate'->'milestone'->>'contract_guid', ''), 'UTF8'), 'hex')
    FROM company_aggregate_projection
    WHERE aggregate_type = 'contract_milestone'
      AND payload->'candidate'->'milestone'->>'contract_guid' = {sql_literal(contract_id)}
    ORDER BY aggregate_id
    LIMIT {max_rows}
    """
    result: list[dict[str, Any]] = []
    for line in query_lines(pool, query):
        fields = line.split("|")
        if len(fields) != 6:
            raise ServiceError("unexpected contract milestone shape")
        try:
            result.append(
                {
                    "milestone_id": decode_hex(fields[0]),
                    "node_name": decode_hex(fields[1]),
                    "plan_amount_minor": int(fields[2]),
                    "plan_amount_display": f"¥{int(fields[2]) / 100:,.2f}",
                    "plan_pct_bps": decode_hex(fields[3]),
                    "trigger_type": decode_hex(fields[4]),
                    "contract_id": decode_hex(fields[5]),
                }
            )
        except (ValueError, UnicodeDecodeError) as error:
            raise ServiceError("invalid contract milestone encoding") from error
    return result


def _decode_tender_fields(line: str) -> dict[str, Any]:
    fields = line.split("|")
    if len(fields) != 14:
        raise ServiceError("unexpected tender projection shape")
    try:
        bids = json.loads(decode_hex(fields[10]))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ServiceError("invalid tender bids projection JSON") from error
    if not isinstance(bids, list):
        raise ServiceError("tender bids projection is not an array")
    try:
        return {
            "tender_id": decode_hex(fields[0]),
            "name": decode_hex(fields[1]),
            "project_scope": decode_hex(fields[2]),
            "category": decode_hex(fields[3]),
            "estimated_amount_minor": int(fields[4]),
            "currency": decode_hex(fields[5]),
            "state": decode_hex(fields[6]),
            "awarded_supplier_id": decode_hex(fields[7]),
            "awarded_amount_minor": int(fields[8]),
            "commitment_id": decode_hex(fields[9]),
            "bids": bids,
            "source_kind": decode_hex(fields[11]),
            "source_snapshot_id": decode_hex(fields[12]),
            "mapping_version": decode_hex(fields[13]),
        }
    except (ValueError, UnicodeDecodeError) as error:
        raise ServiceError("invalid tender projection encoding") from error


def tenders(
    pool: PsqlPool,
    tender_id: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    if tender_id is not None and not IDENTIFIER.fullmatch(tender_id):
        raise ValueError("invalid tender_id")
    where = ""
    if tender_id is not None:
        where = f"WHERE latest.aggregate_id = {sql_literal(tender_id)}"
    query = f"""
    WITH latest AS (
      SELECT DISTINCT ON (aggregate_id)
             aggregate_id, payload
      FROM company_aggregate_projection
      WHERE aggregate_type = 'tender'
      ORDER BY aggregate_id, revision DESC
    )
    SELECT encode(convert_to(latest.aggregate_id, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'name', latest.payload->>'name', latest.aggregate_id), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'project_scope', latest.payload->>'project_scope', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'category', latest.payload->>'category', ''), 'UTF8'), 'hex'),
           coalesce(latest.payload->'candidate'->>'estimated_amount_minor', latest.payload->>'estimated_amount_minor', '0'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'currency', latest.payload->>'currency', 'CNY'), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'state', latest.payload->>'state', 'planning'), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'awarded_supplier_id', latest.payload->>'awarded_supplier_id', ''), 'UTF8'), 'hex'),
           coalesce(latest.payload->'candidate'->>'awarded_amount_minor', latest.payload->>'awarded_amount_minor', '0'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'commitment_id', latest.payload->>'commitment_id', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->'bids', latest.payload->'bids', '[]'::jsonb)::text, 'UTF8'), 'hex'),
           encode(convert_to(CASE WHEN latest.payload ? 'candidate' THEN 'imported' ELSE coalesce(latest.payload->>'source_kind', 'command') END, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->>'source_snapshot_id', latest.payload->'candidate'->>'source_snapshot_id', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->>'mapping_version', latest.payload->'candidate'->>'mapping_version', ''), 'UTF8'), 'hex')
    FROM latest
    {where}
    ORDER BY latest.aggregate_id
    LIMIT {max_rows}
    """
    result = [_decode_tender_fields(line) for line in query_lines(pool, query)]
    for item in result:
        item["estimated_amount_display"] = f"¥{item['estimated_amount_minor'] / 100:,.2f}"
        item["awarded_amount_display"] = (
            f"¥{item['awarded_amount_minor'] / 100:,.2f}"
            if item["awarded_amount_minor"] > 0
            else "—"
        )
    return result


def _decode_supplier_fields(line: str) -> dict[str, Any]:
    fields = line.split("|")
    if len(fields) != 11:
        raise ServiceError("unexpected supplier projection shape")
    try:
        return {
            "supplier_id": decode_hex(fields[0]),
            "supplier_code": decode_hex(fields[1]),
            "name": decode_hex(fields[2]),
            "category_code": decode_hex(fields[3]),
            "evaluation": decode_hex(fields[4]),
            "state": decode_hex(fields[5]),
            "scope": decode_hex(fields[6]),
            "principal_id": decode_hex(fields[7]),
            "source_kind": decode_hex(fields[8]),
            "source_snapshot_id": decode_hex(fields[9]),
            "mapping_version": decode_hex(fields[10]),
        }
    except (ValueError, UnicodeDecodeError) as error:
        raise ServiceError("invalid supplier projection encoding") from error


def suppliers(
    pool: PsqlPool,
    supplier_id: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    if supplier_id is not None and not IDENTIFIER.fullmatch(supplier_id):
        raise ValueError("invalid supplier_id")
    where = ""
    if supplier_id is not None:
        where = f"WHERE latest.aggregate_id = {sql_literal(supplier_id)}"
    query = f"""
    WITH latest AS (
      SELECT DISTINCT ON (aggregate_id)
             aggregate_id, payload
      FROM company_aggregate_projection
      WHERE aggregate_type = 'supplier'
      ORDER BY aggregate_id, revision DESC
    )
    SELECT encode(convert_to(latest.aggregate_id, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'supplier_code', latest.payload->>'supplier_code', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'name', latest.payload->>'name', latest.aggregate_id), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'category_code', latest.payload->>'category_code', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'evaluation', latest.payload->>'evaluation', 'unrated'), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'state', latest.payload->>'state', 'draft'), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'scope', latest.payload->>'scope', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->'candidate'->>'principal_id', latest.payload->>'principal_id', ''), 'UTF8'), 'hex'),
           encode(convert_to(CASE WHEN latest.payload ? 'candidate' THEN 'imported' ELSE coalesce(latest.payload->>'source_kind', 'command') END, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->>'source_snapshot_id', latest.payload->'candidate'->>'source_snapshot_id', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->>'mapping_version', latest.payload->'candidate'->>'mapping_version', ''), 'UTF8'), 'hex')
    FROM latest
    {where}
    ORDER BY latest.aggregate_id
    LIMIT {max_rows}
    """
    return [_decode_supplier_fields(line) for line in query_lines(pool, query)]


def supplier_risk(
    pool: PsqlPool,
    supplier_id: str,
) -> dict[str, Any] | None:
    if not IDENTIFIER.fullmatch(supplier_id):
        raise ValueError("invalid supplier_id")
    rows = suppliers(pool, supplier_id, 1)
    if not rows:
        return None
    supplier = rows[0]
    state = str(supplier["state"])
    evaluation = str(supplier["evaluation"])
    if state in {"voided", "blacklisted"} or evaluation == "unqualified":
        score, rating = 0, "E"
    elif state == "active" and evaluation == "strategic":
        score, rating = 95, "A"
    elif state == "active" and evaluation == "qualified":
        score, rating = 85, "B"
    elif state == "pending_review":
        score, rating = 60, "C"
    elif state == "suspended":
        score, rating = 35, "D"
    else:
        score, rating = 50, "C"
    tags: list[str] = []
    if state == "pending_review":
        tags.append("pending_review")
    if state == "suspended":
        tags.append("suspended")
    if state == "blacklisted":
        tags.append("blacklist")
    if evaluation == "unqualified":
        tags.append("unqualified")
    return {
        "supplier_id": supplier_id,
        "score": score,
        "rating": rating,
        "tags": tags,
        "state": state,
        "evaluation": evaluation,
        "source_kind": supplier["source_kind"],
    }


def supplier_risk_board(
    pool: PsqlPool,
    max_rows: int,
) -> list[dict[str, Any]]:
    rows = suppliers(pool, None, max_rows)
    result: list[dict[str, Any]] = []
    for row in rows:
        risk = supplier_risk(pool, str(row["supplier_id"]))
        if risk is not None:
            result.append({**row, **risk})
    result.sort(key=lambda item: (int(item["score"]), str(item["supplier_id"])))
    return result[:max_rows]


def _decode_split_fields(line: str) -> dict[str, Any]:
    fields = line.split("|")
    if len(fields) != 10:
        raise ServiceError("unexpected contract split projection shape")
    try:
        return {
            "split_id": decode_hex(fields[0]),
            "parent_contract_id": decode_hex(fields[1]),
            "split_name": decode_hex(fields[2]),
            "split_amount_minor": int(fields[3]),
            "split_pct_bps": int(fields[4]),
            "scope": decode_hex(fields[5]),
            "state": decode_hex(fields[6]),
            "source_kind": decode_hex(fields[7]),
            "source_snapshot_id": decode_hex(fields[8]),
            "mapping_version": decode_hex(fields[9]),
        }
    except (ValueError, UnicodeDecodeError) as error:
        raise ServiceError("invalid contract split projection encoding") from error


def contract_splits(
    pool: PsqlPool,
    split_id: str | None,
    parent_contract_id: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    for value, name in ((split_id, "split_id"), (parent_contract_id, "parent_contract_id")):
        if value is not None and not IDENTIFIER.fullmatch(value):
            raise ValueError(f"invalid {name}")
    filters: list[str] = []
    if split_id is not None:
        filters.append(f"latest.aggregate_id = {sql_literal(split_id)}")
    if parent_contract_id is not None:
        filters.append(
            "coalesce(latest.payload->>'parent_contract_id', "
            "latest.payload->'candidate'->>'parent_contract_id', '') = "
            + sql_literal(parent_contract_id)
        )
    where = "WHERE " + " AND ".join(filters) if filters else ""
    query = f"""
    WITH latest AS (
      SELECT DISTINCT ON (aggregate_id)
             aggregate_id, payload
      FROM company_aggregate_projection
      WHERE aggregate_type = 'contract_split'
      ORDER BY aggregate_id, revision DESC
    )
    SELECT encode(convert_to(latest.aggregate_id, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->>'parent_contract_id', latest.payload->'candidate'->>'parent_contract_id', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->>'split_name', latest.payload->'candidate'->>'split_name', ''), 'UTF8'), 'hex'),
           coalesce(latest.payload->>'split_amount_minor', latest.payload->'candidate'->>'split_amount_minor', '0'),
           coalesce(latest.payload->>'split_pct_bps', latest.payload->'candidate'->>'split_pct_bps', '0'),
           encode(convert_to(coalesce(latest.payload->>'scope', latest.payload->'candidate'->>'scope', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->>'state', latest.payload->'candidate'->>'state', 'planned'), 'UTF8'), 'hex'),
           encode(convert_to(CASE WHEN latest.payload ? 'candidate' THEN 'imported' ELSE coalesce(latest.payload->>'source_kind', 'command') END, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->>'source_snapshot_id', latest.payload->'candidate'->>'source_snapshot_id', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(latest.payload->>'mapping_version', latest.payload->'candidate'->>'mapping_version', ''), 'UTF8'), 'hex')
    FROM latest
    {where}
    ORDER BY latest.aggregate_id
    LIMIT {max_rows}
    """
    result = [_decode_split_fields(line) for line in query_lines(pool, query)]
    for item in result:
        item["split_amount_display"] = f"¥{item['split_amount_minor'] / 100:,.2f}"
        item["split_pct_display"] = f"{item['split_pct_bps'] / 100:.2f}%"
    return result


SALES_AGGREGATE_TYPES = {
    "customers": "customer",
    "subscriptions": "subscription",
    "contracts": "sales_agreement",
    "mortgages": "mortgage",
    "refunds": "refund",
    "revenues": "sale_revenue",
    "receivables": "receivable",
    "invoices": "invoice",
    "payables": "payable",
}


def _latest_sales_projection_rows(
    pool: PsqlPool,
    aggregate_type: str,
    aggregate_id: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    if aggregate_type not in set(SALES_AGGREGATE_TYPES.values()):
        raise ValueError("unsupported sales aggregate type")
    if aggregate_id is not None and not IDENTIFIER.fullmatch(aggregate_id):
        raise ValueError("invalid sales aggregate id")
    where = f"AND aggregate_id = {sql_literal(aggregate_id)}" if aggregate_id else ""
    query = f"""
    SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'),
           encode(convert_to(aggregate_id, 'UTF8'), 'hex'),
           revision::text,
           encode(convert_to(payload::text, 'UTF8'), 'hex'),
           encode(convert_to(source_event_id, 'UTF8'), 'hex')
    FROM (
      SELECT DISTINCT ON (aggregate_id)
             aggregate_type, aggregate_id, revision, payload, source_event_id
      FROM company_aggregate_projection
      WHERE aggregate_type = {sql_literal(aggregate_type)}
        {where}
      ORDER BY aggregate_id, revision DESC
    ) latest
    ORDER BY aggregate_id
    LIMIT {max_rows}
    """
    result: list[dict[str, Any]] = []
    for line in query_lines(pool, query):
        fields = line.split("|")
        if len(fields) != 5:
            raise ServiceError("unexpected sales projection shape")
        try:
            payload = json.loads(decode_hex(fields[3]))
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ServiceError("invalid sales projection JSON") from error
        if not isinstance(payload, dict):
            raise ServiceError("sales projection payload is not an object")
        result.append(
            {
                "aggregate_type": decode_hex(fields[0]),
                "aggregate_id": decode_hex(fields[1]),
                "revision": int(fields[2]),
                "payload": payload,
                "source_event_id": decode_hex(fields[4]),
            }
        )
    return result


def _sales_value(payload: dict[str, Any], key: str, default: Any = "") -> Any:
    candidate = payload.get("candidate")
    if isinstance(candidate, dict) and key in candidate:
        return candidate[key]
    return payload.get(key, default)


def _sales_int(value: Any, default: int = 0) -> int:
    if isinstance(value, bool):
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _sales_row(row: dict[str, Any]) -> dict[str, Any]:
    payload = row["payload"]
    aggregate_type = str(row["aggregate_type"])
    source_kind = "imported" if isinstance(payload.get("candidate"), dict) else str(
        payload.get("source_kind", "command")
    )
    result: dict[str, Any] = {
        "aggregate_type": aggregate_type,
        "aggregate_id": row["aggregate_id"],
        "revision": row["revision"],
        "source_event_id": row["source_event_id"],
        "source_kind": source_kind,
        "source_snapshot_id": str(_sales_value(payload, "source_snapshot_id", "")),
        "mapping_version": str(_sales_value(payload, "mapping_version", "")),
    }
    if aggregate_type == "customer":
        result.update(
            {
                "customer_id": str(_sales_value(payload, "customer_id", row["aggregate_id"])),
                "principal_id": str(_sales_value(payload, "principal_id")),
                "scope": str(_sales_value(payload, "scope")),
                "customer_code": str(_sales_value(payload, "customer_code")),
                "name": str(_sales_value(payload, "name", row["aggregate_id"])),
                "contact_reference": str(_sales_value(payload, "contact_reference")),
                "state": str(_sales_value(payload, "state", "active")),
            }
        )
    elif aggregate_type == "subscription":
        result.update(
            {
                "subscription_id": str(_sales_value(payload, "subscription_id", row["aggregate_id"])),
                "customer_id": str(_sales_value(payload, "customer_id")),
                "principal_id": str(_sales_value(payload, "principal_id")),
                "scope": str(_sales_value(payload, "scope")),
                "unit_reference": str(_sales_value(payload, "unit_reference")),
                "amount_minor": _sales_int(_sales_value(payload, "amount_minor")),
                "currency": str(_sales_value(payload, "currency", "CNY")),
                "state": str(_sales_value(payload, "state", "reserved")),
            }
        )
    elif aggregate_type == "sales_agreement":
        result.update(
            {
                "agreement_id": str(_sales_value(payload, "agreement_id", row["aggregate_id"])),
                "customer_id": str(_sales_value(payload, "customer_id")),
                "principal_id": str(_sales_value(payload, "principal_id")),
                "scope": str(_sales_value(payload, "scope")),
                "amount_minor": _sales_int(_sales_value(payload, "amount_minor")),
                "currency": str(_sales_value(payload, "currency", "CNY")),
                "state": str(_sales_value(payload, "state", "draft")),
                "subscription_id": str(_sales_value(payload, "subscription_id")),
            }
        )
    elif aggregate_type == "receivable":
        result.update(
            {
                "receivable_id": str(_sales_value(payload, "receivable_id", row["aggregate_id"])),
                "source_id": str(_sales_value(payload, "source_id")),
                "invoice_id": str(_sales_value(payload, "invoice_id")),
                "customer_id": str(_sales_value(payload, "customer_id")),
                "principal_id": str(_sales_value(payload, "principal_id")),
                "scope": str(_sales_value(payload, "scope")),
                "amount_minor": _sales_int(_sales_value(payload, "amount_minor")),
                "collected_minor": _sales_int(_sales_value(payload, "collected_minor")),
                "outstanding_minor": _sales_int(_sales_value(payload, "outstanding_minor")),
                "currency": str(_sales_value(payload, "currency", "CNY")),
                "state": str(_sales_value(payload, "state", "open")),
            }
        )
    elif aggregate_type == "mortgage":
        result.update(
            {
                "mortgage_id": str(_sales_value(payload, "mortgage_id", row["aggregate_id"])),
                "contract_id": str(_sales_value(payload, "contract_id")),
                "customer_id": str(_sales_value(payload, "customer_id")),
                "principal_id": str(_sales_value(payload, "principal_id")),
                "scope": str(_sales_value(payload, "scope")),
                "bank_reference": str(_sales_value(payload, "bank_reference")),
                "loan_amount_minor": _sales_int(_sales_value(payload, "loan_amount_minor", _sales_value(payload, "amount_minor"))),
                "annual_rate_bps": _sales_int(_sales_value(payload, "annual_rate_bps")),
                "state": str(_sales_value(payload, "state", "applying")),
            }
        )
    elif aggregate_type == "refund":
        result.update(
            {
                "refund_id": str(_sales_value(payload, "refund_id", row["aggregate_id"])),
                "contract_id": str(_sales_value(payload, "contract_id")),
                "customer_id": str(_sales_value(payload, "customer_id")),
                "principal_id": str(_sales_value(payload, "principal_id")),
                "scope": str(_sales_value(payload, "scope")),
                "reason": str(_sales_value(payload, "reason")),
                "amount_minor": _sales_int(_sales_value(payload, "amount_minor")),
                "currency": str(_sales_value(payload, "currency", "CNY")),
                "state": str(_sales_value(payload, "state", "requested")),
            }
        )
    elif aggregate_type == "sale_revenue":
        result.update(
            {
                "revenue_id": str(_sales_value(payload, "revenue_id", row["aggregate_id"])),
                "revenue_code": str(_sales_value(payload, "revenue_code")),
                "contract_code": str(_sales_value(payload, "contract_code")),
                "principal_id": str(_sales_value(payload, "principal_id")),
                "scope": str(_sales_value(payload, "scope")),
                "amount_minor": _sales_int(_sales_value(payload, "amount_minor")),
                "currency": str(_sales_value(payload, "currency", "CNY")),
                "status": str(_sales_value(payload, "status", "expected")),
                "evidence_state": str(_sales_value(payload, "evidence_state", "source_evidence_only")),
            }
        )
    elif aggregate_type == "invoice":
        result.update(
            {
                "invoice_id": str(_sales_value(payload, "invoice_id", row["aggregate_id"])),
                "receivable_id": str(_sales_value(payload, "receivable_id")),
                "principal_id": str(_sales_value(payload, "principal_id")),
                "customer_id": str(_sales_value(payload, "customer_id")),
                "source_id": str(_sales_value(payload, "source_id")),
                "amount_minor": _sales_int(_sales_value(payload, "amount_minor")),
                "paid_minor": _sales_int(_sales_value(payload, "paid_minor")),
                "outstanding_minor": _sales_int(_sales_value(payload, "outstanding_minor")),
                "currency": str(_sales_value(payload, "currency", "CNY")),
                "state": str(_sales_value(payload, "state", "draft")),
            }
        )
    elif aggregate_type == "payable":
        result.update(
            {
                "payable_id": str(_sales_value(payload, "payable_id", row["aggregate_id"])),
                "principal_id": str(_sales_value(payload, "principal_id")),
                "project_scope": str(_sales_value(payload, "project_scope")),
                "supplier_id": str(_sales_value(payload, "supplier_id")),
                "source_reference": str(_sales_value(payload, "source_reference")),
                "amount_minor": _sales_int(_sales_value(payload, "amount_minor")),
                "outstanding_minor": _sales_int(_sales_value(payload, "outstanding_minor")),
                "currency": str(_sales_value(payload, "currency", "CNY")),
                "state": str(_sales_value(payload, "state", "open")),
            }
        )
    else:
        raise ServiceError("unsupported sales aggregate type")
    if "amount_minor" in result:
        result["amount_display"] = f"¥{int(result['amount_minor']) / 100:,.2f}"
    if "outstanding_minor" in result:
        result["outstanding_display"] = f"¥{int(result['outstanding_minor']) / 100:,.2f}"
    return result


def sales_rows(
    pool: PsqlPool,
    family: str,
    aggregate_id: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    aggregate_type = SALES_AGGREGATE_TYPES.get(family)
    if aggregate_type is None:
        raise ValueError("unsupported sales read family")
    return [
        _sales_row(row)
        for row in _latest_sales_projection_rows(pool, aggregate_type, aggregate_id, max_rows)
    ]


def _sales_command_text(
    body: dict[str, Any],
    key: str,
    *,
    identifier: bool = False,
    allow_empty: bool = False,
) -> str:
    value = body.get(key)
    if not isinstance(value, str) or (not allow_empty and not value.strip()):
        raise CommandRejected(f"{key} is required", 422)
    value = value.strip()
    if identifier and not IDENTIFIER.fullmatch(value):
        raise CommandRejected(f"{key} contains unsupported characters", 422)
    return value


def _sales_amount(body: dict[str, Any], key: str = "amount_minor", positive: bool = True) -> int:
    value = body.get(key)
    if isinstance(value, bool) or not isinstance(value, int) or (value <= 0 if positive else value < 0):
        requirement = "positive" if positive else "non-negative"
        raise CommandRejected(f"{key} must be a {requirement} integer", 422)
    return value


def _sales_request(
    family: str,
    command_type: str,
    aggregate_id: str | None,
    body: dict[str, Any],
    actor_id: str,
) -> tuple[str, str, dict[str, Any], str | None]:
    allowed = {
        "customers": {"create", "update", "block", "archive"},
        "subscriptions": {"create", "convert", "cancel"},
        "contracts": {"create", "fulfill", "cancel", "open_receivable"},
        "mortgages": {"create", "approve", "release"},
        "refunds": {"create", "approve", "pay", "reject"},
    }
    if family not in allowed or command_type not in allowed[family]:
        raise CommandRejected("unsupported sales command", 404)
    aggregate_type = SALES_AGGREGATE_TYPES[family]
    id_key = {
        "customers": "customer_id",
        "subscriptions": "subscription_id",
        "contracts": "agreement_id",
        "mortgages": "mortgage_id",
        "refunds": "refund_id",
    }[family]
    if command_type == "create":
        identifier = _sales_command_text(body, id_key, identifier=True)
        request: dict[str, Any] = {
            "command_type": command_type,
            id_key: identifier,
            "actor_id": actor_id,
        }
        if family == "customers":
            for key in ("principal_id", "scope", "customer_code", "name", "contact_reference"):
                request[key] = _sales_command_text(body, key, identifier=key in {"principal_id", "scope", "customer_code"})
            request["state"] = "active"
        elif family == "subscriptions":
            for key in ("customer_id", "principal_id", "scope", "unit_reference"):
                request[key] = _sales_command_text(body, key, identifier=key != "unit_reference")
            request["amount_minor"] = _sales_amount(body)
            request["currency"] = _sales_command_text(body, "currency", identifier=True).upper()
            if not re.fullmatch(r"[A-Z]{3}", request["currency"]):
                raise CommandRejected("currency must be a three-letter code", 422)
            request["state"] = "reserved"
        elif family == "contracts":
            for key in ("customer_id", "principal_id", "scope"):
                request[key] = _sales_command_text(body, key, identifier=True)
            request["amount_minor"] = _sales_amount(body)
            request["currency"] = _sales_command_text(body, "currency", identifier=True).upper()
            if not re.fullmatch(r"[A-Z]{3}", request["currency"]):
                raise CommandRejected("currency must be a three-letter code", 422)
            subscription_id = body.get("subscription_id", "")
            if subscription_id and (not isinstance(subscription_id, str) or not IDENTIFIER.fullmatch(subscription_id)):
                raise CommandRejected("subscription_id contains unsupported characters", 422)
            request["subscription_id"] = subscription_id
            request["state"] = "signed"
        elif family == "mortgages":
            for key in ("contract_id", "customer_id", "principal_id", "scope", "bank_reference"):
                request[key] = _sales_command_text(body, key, identifier=True)
            request["loan_amount_minor"] = _sales_amount(body, "loan_amount_minor")
            request["annual_rate_bps"] = _sales_amount(body, "annual_rate_bps", positive=False)
            if request["annual_rate_bps"] > 10000:
                raise CommandRejected("annual_rate_bps must be between 0 and 10000", 422)
            request["state"] = "applying"
        elif family == "refunds":
            for key in ("contract_id", "customer_id", "principal_id", "scope"):
                request[key] = _sales_command_text(body, key, identifier=True)
            request["reason"] = _sales_command_text(body, "reason")
            request["amount_minor"] = _sales_amount(body)
            request["currency"] = _sales_command_text(body, "currency", identifier=True).upper()
            if not re.fullmatch(r"[A-Z]{3}", request["currency"]):
                raise CommandRejected("currency must be a three-letter code", 422)
            request["state"] = "requested"
        return identifier, aggregate_type, request, None
    if aggregate_id is None or not IDENTIFIER.fullmatch(aggregate_id):
        raise CommandRejected(f"{id_key} is required", 422)
    request = {"command_type": command_type, id_key: aggregate_id, "actor_id": actor_id}
    reason = body.get("reason", "")
    if not isinstance(reason, str):
        raise CommandRejected("reason must be text", 422)
    request["reason"] = reason.strip()
    if command_type == "update" and family == "customers":
        changes: dict[str, str] = {}
        for key in ("scope", "customer_code", "name", "contact_reference"):
            value = body.get(key)
            if value is not None:
                if not isinstance(value, str) or not value.strip():
                    raise CommandRejected(f"{key} must be non-empty text", 422)
                cleaned = value.strip()
                if key in {"scope", "customer_code"} and not IDENTIFIER.fullmatch(cleaned):
                    raise CommandRejected(f"{key} contains unsupported characters", 422)
                changes[key] = cleaned
        if not changes:
            raise CommandRejected("update requires at least one mutable field", 422)
        request["changes"] = changes
    if command_type == "open_receivable":
        request["receivable_id"] = _sales_command_text(body, "receivable_id", identifier=True)
        request["amount_minor"] = _sales_amount(body)
        request["currency"] = _sales_command_text(body, "currency", identifier=True).upper()
        request["customer_id"] = _sales_command_text(body, "customer_id", identifier=True)
        request["principal_id"] = _sales_command_text(body, "principal_id", identifier=True)
        request["scope"] = _sales_command_text(body, "scope", identifier=True)
        request["source_id"] = aggregate_id
    return aggregate_id, aggregate_type, request, {
        "customers": {"update": ("active", "active"), "block": ("active", "blocked"), "archive": ("blocked", "archived")},
        "subscriptions": {"convert": ("reserved", "converted"), "cancel": (("reserved", "converted"), "cancelled")},
        "contracts": {"fulfill": ("signed", "fulfilled"), "cancel": (("signed", "fulfilled"), "cancelled")},
        "mortgages": {"approve": ("applying", "approved"), "release": ("approved", "released")},
        "refunds": {"approve": ("requested", "approved"), "pay": ("approved", "paid"), "reject": (("requested", "approved"), "rejected")},
    }[family].get(command_type)


def _lifecycle_command(
    pool: PsqlPool,
    *,
    family: str,
    command_type: str,
    aggregate_id: str,
    aggregate_type: str,
    request: dict[str, Any],
    transition: tuple[Any, str] | None,
    idempotency_key: str,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(idempotency_key):
        raise CommandRejected("Idempotency-Key contains unsupported characters", 422)
    existing = _existing_command(pool, idempotency_key)
    if existing is not None:
        if existing.get("request") != request:
            raise CommandRejected("Idempotency-Key was already used for another request", 409)
        result = existing.get("result")
        if not isinstance(result, dict):
            raise ServiceError("stored sales command receipt has no result")
        return {"command": existing, family.rstrip("s"): result, "idempotent_replay": True}
    current = _latest_sales_projection_rows(pool, aggregate_type, aggregate_id, 1)
    if command_type == "create":
        if current:
            raise CommandRejected(f"{family[:-1]} already exists", 409)
        current_row = None
        next_state = str(request["state"])
        next_revision = 1
    else:
        if not current:
            raise CommandRejected(f"{family[:-1]} not found", 404)
        current_row = _sales_row(current[0])
        if current_row.get("source_kind") != "command":
            raise CommandRejected(f"imported {family[:-1]} is read-only; create a local record first", 409)
        current_state = str(current_row.get("state", ""))
        if transition is None:
            raise CommandRejected("sales transition is not configured", 409)
        expected, next_state = transition
        expected_states = expected if isinstance(expected, tuple) else (expected,)
        if current_state not in expected_states:
            raise CommandRejected(
                f"{family[:-1]} transition {command_type} requires {','.join(expected_states)}, found {current_state}",
                409,
            )
        next_revision = int(current_row["revision"]) + 1
    event_id = f"{aggregate_type}:{command_type}:{idempotency_key}"
    command_source = f"moonproj:command:{idempotency_key}"
    audit_id = event_id + ":audit"
    request_json = json.dumps(request, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    command_json = json.dumps(
        {
            "kind": "company_command",
            "command_family": family,
            "command_type": command_type,
            "idempotency_key": idempotency_key,
            "aggregate_type": aggregate_type,
            "aggregate_id": aggregate_id,
            "actor_id": request["actor_id"],
            "request": request,
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    sql = f"""
    BEGIN;
    CREATE TEMP TABLE command_attempt(created boolean) ON COMMIT DROP;
    WITH inserted AS (
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_command', {sql_literal(event_id)}, 4,
        {sql_literal(command_json)}::jsonb, {sql_literal(command_source)})
      ON CONFLICT (source_id) DO NOTHING
      RETURNING 1
    )
    INSERT INTO command_attempt(created) SELECT EXISTS (SELECT 1 FROM inserted);
    DO $$
    DECLARE
      is_new boolean;
      current_payload jsonb;
      next_payload jsonb;
      current_state text;
      next_revision integer;
      result jsonb;
    BEGIN
      SELECT created INTO is_new FROM command_attempt LIMIT 1;
      IF NOT is_new THEN RETURN; END IF;
      SELECT p.payload INTO current_payload
      FROM company_aggregate_projection p
      WHERE p.aggregate_type = {sql_literal(aggregate_type)}
        AND p.aggregate_id = {sql_literal(aggregate_id)}
      ORDER BY p.revision DESC LIMIT 1;
      IF {sql_literal(command_type)} = 'create' THEN
        IF current_payload IS NOT NULL THEN RAISE EXCEPTION 'sales record already exists'; END IF;
        next_revision := 1;
        next_payload := {sql_literal(request_json)}::jsonb || jsonb_build_object(
          'state', {sql_literal(str(request.get('state', next_state)))},
          'source_kind', 'command', 'event_id', {sql_literal(event_id)},
          'updated_by', {sql_literal(str(request['actor_id']))});
      ELSE
        IF current_payload IS NULL THEN RAISE EXCEPTION 'sales record not found'; END IF;
        IF current_payload ? 'candidate' THEN RAISE EXCEPTION 'imported sales record is read-only'; END IF;
        current_state := current_payload->>'state';
        next_revision := {next_revision};
        next_payload := current_payload || jsonb_build_object(
          'state', {sql_literal(next_state)}, 'source_kind', 'command',
          'event_id', {sql_literal(event_id)}, 'updated_by', {sql_literal(str(request['actor_id']))},
          'reason', {sql_literal(str(request.get('reason', '')))});
      END IF;
      INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id)
      VALUES ({sql_literal(aggregate_type)}, {sql_literal(aggregate_id)}, next_revision,
        next_payload, {sql_literal(event_id)});
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_audit_event', {sql_literal(audit_id)}, 4,
        jsonb_build_object('audit_id', {sql_literal(audit_id)}, 'action',
          {sql_literal(family + '.' + command_type)}, 'aggregate_type', {sql_literal(aggregate_type)},
          'aggregate_id', {sql_literal(aggregate_id)}, 'actor_id', {sql_literal(str(request['actor_id']))},
          'event_id', {sql_literal(event_id)}, 'state', {sql_literal(next_state)}, 'revision', next_revision),
        {sql_literal('moonproj:audit:' + event_id)});
      result := jsonb_build_object('aggregate_id', {sql_literal(aggregate_id)},
        'state', {sql_literal(next_state)}, 'revision', next_revision,
        'event_id', {sql_literal(event_id)}, 'audit_id', {sql_literal(audit_id)},
        'actor_id', {sql_literal(str(request['actor_id']))});
      UPDATE company_record SET payload = payload || jsonb_build_object('result', result)
      WHERE source_id = {sql_literal(command_source)};
    END $$;
    SELECT coalesce((SELECT created::text FROM command_attempt LIMIT 1), 'false')
      || '|' || encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM company_record WHERE source_id = {sql_literal(command_source)};
    COMMIT;
    """
    lines = query_lines(pool, sql)
    if len(lines) != 1:
        raise ServiceError("sales command did not return a command receipt")
    fields = lines[0].split("|", 1)
    if len(fields) != 2:
        raise ServiceError("unexpected sales command receipt shape")
    created = fields[0] == "true"
    try:
        receipt = json.loads(decode_hex(fields[1]))
    except json.JSONDecodeError as error:
        raise ServiceError("invalid stored sales command receipt") from error
    if not created and receipt.get("request") != request:
        raise CommandRejected("Idempotency-Key was already used for another request", 409)
    result = receipt.get("result")
    if not isinstance(result, dict):
        raise ServiceError("sales command receipt has no result")
    return {"command": receipt, family.rstrip("s"): result, "idempotent_replay": not created}


def sales_command(
    pool: PsqlPool,
    *,
    family: str,
    command_type: str,
    aggregate_id: str | None,
    body: dict[str, Any],
    actor_id: str,
    idempotency_key: str,
) -> dict[str, Any]:
    aggregate_id, aggregate_type, request, transition = _sales_request(
        family, command_type, aggregate_id, body, actor_id
    )
    if command_type == "open_receivable":
        contract_rows = sales_rows(pool, "contracts", aggregate_id, 1)
        if not contract_rows or contract_rows[0]["source_kind"] != "command":
            raise CommandRejected("only local sales contracts can open receivables", 409)
        if contract_rows[0].get("state") != "fulfilled":
            raise CommandRejected("receivable opening requires a fulfilled contract", 409)
        receivable_id = str(request["receivable_id"])
        receivable_request = {
            "command_type": "create",
            "receivable_id": receivable_id,
            "source_id": aggregate_id,
            "customer_id": request["customer_id"],
            "principal_id": request["principal_id"],
            "scope": request["scope"],
            "amount_minor": request["amount_minor"],
            "outstanding_minor": request["amount_minor"],
            "collected_minor": 0,
            "currency": request["currency"],
            "state": "open",
            "actor_id": actor_id,
        }
        return _lifecycle_command(
            pool,
            family="receivable",
            command_type="create",
            aggregate_id=receivable_id,
            aggregate_type="receivable",
            request=receivable_request,
            transition=None,
            idempotency_key=idempotency_key,
        )
    return _lifecycle_command(
        pool,
        family=family,
        command_type=command_type,
        aggregate_id=aggregate_id,
        aggregate_type=aggregate_type,
        request=request,
        transition=transition,
        idempotency_key=idempotency_key,
    )


def _supplier_text(
    body: dict[str, Any],
    key: str,
    *,
    identifier: bool = False,
) -> str:
    value = body.get(key)
    if not isinstance(value, str) or not value.strip():
        raise CommandRejected(f"{key} is required", 422)
    value = value.strip()
    if identifier and not IDENTIFIER.fullmatch(value):
        raise CommandRejected(f"{key} contains unsupported characters", 422)
    return value


def _supplier_request(
    command_type: str,
    supplier_id: str | None,
    body: dict[str, Any],
    actor_id: str,
) -> tuple[str, dict[str, Any]]:
    allowed = {"create", "update", "submit_review", "review", "blacklist", "void"}
    if command_type not in allowed:
        raise CommandRejected("unsupported supplier command", 404)
    if command_type == "create":
        supplier_id = _supplier_text(body, "supplier_id", identifier=True)
        principal_id = _supplier_text(body, "principal_id", identifier=True)
        scope = _supplier_text(body, "scope", identifier=True)
        supplier_code = _supplier_text(body, "supplier_code", identifier=True)
        name = _supplier_text(body, "name")
        category_code = _supplier_text(body, "category_code", identifier=True)
        return supplier_id, {
            "command_type": command_type,
            "supplier_id": supplier_id,
            "principal_id": principal_id,
            "scope": scope,
            "supplier_code": supplier_code,
            "name": name,
            "category_code": category_code,
            "actor_id": actor_id,
        }
    if supplier_id is None or not IDENTIFIER.fullmatch(supplier_id):
        raise CommandRejected("supplier_id is required", 422)
    request: dict[str, Any] = {
        "command_type": command_type,
        "supplier_id": supplier_id,
        "actor_id": actor_id,
    }
    if command_type == "update":
        changes: dict[str, str] = {}
        for key in ("scope", "supplier_code", "name", "category_code"):
            value = body.get(key)
            if value is not None:
                if not isinstance(value, str) or not value.strip():
                    raise CommandRejected(f"{key} must be non-empty text", 422)
                cleaned = value.strip()
                if key != "name" and not IDENTIFIER.fullmatch(cleaned):
                    raise CommandRejected(f"{key} contains unsupported characters", 422)
                changes[key] = cleaned
        if not changes:
            raise CommandRejected("update requires at least one mutable field", 422)
        request["changes"] = changes
    elif command_type == "review":
        evaluation = _supplier_text(body, "evaluation", identifier=True).lower()
        if evaluation not in {"reviewed", "qualified", "unqualified", "strategic"}:
            raise CommandRejected("evaluation is invalid", 422)
        request["evaluation"] = evaluation
    reason = body.get("reason", "")
    if not isinstance(reason, str):
        raise CommandRejected("reason must be text", 422)
    request["reason"] = reason.strip()
    return supplier_id, request


def supplier_command(
    pool: PsqlPool,
    *,
    command_type: str,
    supplier_id: str | None,
    body: dict[str, Any],
    actor_id: str,
    idempotency_key: str,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(idempotency_key):
        raise CommandRejected("Idempotency-Key contains unsupported characters", 422)
    supplier_id, request = _supplier_request(command_type, supplier_id, body, actor_id)
    existing = _existing_command(pool, idempotency_key)
    if existing is not None:
        if existing.get("request") != request:
            raise CommandRejected("Idempotency-Key was already used for another request", 409)
        result = existing.get("result")
        if not isinstance(result, dict):
            raise ServiceError("stored supplier command receipt has no result")
        return {"command": existing, "supplier": result, "idempotent_replay": True}
    current = suppliers(pool, supplier_id, 1)
    if command_type == "create" and current:
        raise CommandRejected("supplier already exists", 409)
    if command_type != "create":
        if not current:
            raise CommandRejected("supplier not found", 404)
        current_row = current[0]
        if current_row.get("source_kind") != "command":
            raise CommandRejected("imported supplier is read-only; create a local supplier first", 409)
        current_state = str(current_row.get("state", ""))
        if command_type == "update" and current_state == "voided":
            raise CommandRejected("voided supplier cannot be updated", 409)
        if command_type == "submit_review" and current_state != "draft":
            raise CommandRejected(f"supplier transition submit_review requires draft, found {current_state}", 409)
        if command_type == "review" and current_state != "pending_review":
            raise CommandRejected(f"supplier transition review requires pending_review, found {current_state}", 409)
        if command_type in {"blacklist", "void"} and current_state == "voided":
            raise CommandRejected("voided supplier cannot change state", 409)
    event_id = f"supplier:{command_type}:{idempotency_key}"
    command_source = f"moonproj:command:{idempotency_key}"
    audit_id = event_id + ":audit"
    request_json = json.dumps(request, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    command_json = json.dumps(
        {
            "kind": "company_command",
            "command_type": command_type,
            "idempotency_key": idempotency_key,
            "supplier_id": supplier_id,
            "actor_id": actor_id,
            "request": request,
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    sql = f"""
    BEGIN;
    CREATE TEMP TABLE command_attempt(created boolean) ON COMMIT DROP;
    WITH inserted AS (
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_command', {sql_literal(event_id)}, 4,
        {sql_literal(command_json)}::jsonb, {sql_literal(command_source)})
      ON CONFLICT (source_id) DO NOTHING
      RETURNING 1
    )
    INSERT INTO command_attempt(created) SELECT EXISTS (SELECT 1 FROM inserted);
    DO $$
    DECLARE
      is_new boolean;
      current_payload jsonb;
      next_payload jsonb;
      current_state text;
      next_state text;
      next_evaluation text;
      next_revision integer;
      result jsonb;
    BEGIN
      SELECT created INTO is_new FROM command_attempt LIMIT 1;
      IF NOT is_new THEN RETURN; END IF;
      SELECT p.payload INTO current_payload
      FROM company_aggregate_projection p
      WHERE p.aggregate_type = 'supplier'
        AND p.aggregate_id = {sql_literal(supplier_id)}
      ORDER BY p.revision DESC LIMIT 1;
      IF {sql_literal(command_type)} = 'create' THEN
        IF current_payload IS NOT NULL THEN RAISE EXCEPTION 'supplier already exists'; END IF;
        next_revision := 1;
        next_state := 'draft';
        next_evaluation := 'unrated';
        next_payload := {sql_literal(request_json)}::jsonb || jsonb_build_object(
          'state', next_state, 'evaluation', next_evaluation, 'source_kind', 'command',
          'event_id', {sql_literal(event_id)}, 'updated_by', {sql_literal(actor_id)});
      ELSE
        IF current_payload IS NULL THEN RAISE EXCEPTION 'supplier not found'; END IF;
        current_state := current_payload->>'state';
        next_state := current_state;
        next_evaluation := coalesce(current_payload->>'evaluation', 'unrated');
        IF {sql_literal(command_type)} = 'update' THEN
          next_payload := current_payload || coalesce({sql_literal(request_json)}::jsonb->'changes', '{{}}'::jsonb);
        ELSIF {sql_literal(command_type)} = 'submit_review' THEN
          IF current_state <> 'draft' THEN RAISE EXCEPTION 'invalid supplier state'; END IF;
          next_state := 'pending_review';
          next_payload := current_payload;
        ELSIF {sql_literal(command_type)} = 'review' THEN
          IF current_state <> 'pending_review' THEN RAISE EXCEPTION 'invalid supplier state'; END IF;
          next_evaluation := {sql_literal(request_json)}::jsonb->>'evaluation';
          IF next_evaluation IN ('qualified', 'strategic') THEN
            next_state := 'active';
          ELSE
            next_state := 'suspended';
          END IF;
          next_payload := current_payload;
        ELSIF {sql_literal(command_type)} = 'blacklist' THEN
          IF current_state = 'voided' THEN RAISE EXCEPTION 'invalid supplier state'; END IF;
          next_state := 'blacklisted';
          next_payload := current_payload;
        ELSIF {sql_literal(command_type)} = 'void' THEN
          IF current_state = 'voided' THEN RAISE EXCEPTION 'invalid supplier state'; END IF;
          next_state := 'voided';
          next_payload := current_payload;
        ELSE
          RAISE EXCEPTION 'unsupported supplier command';
        END IF;
        next_payload := next_payload || jsonb_build_object(
          'state', next_state, 'evaluation', next_evaluation, 'source_kind', 'command',
          'event_id', {sql_literal(event_id)}, 'updated_by', {sql_literal(actor_id)},
          'reason', {sql_literal(request_json)}::jsonb->>'reason');
        SELECT coalesce(max(p.revision), 0) + 1 INTO next_revision
        FROM company_aggregate_projection p
        WHERE p.aggregate_type = 'supplier' AND p.aggregate_id = {sql_literal(supplier_id)};
      END IF;
      INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id)
      VALUES ('supplier', {sql_literal(supplier_id)}, next_revision, next_payload, {sql_literal(event_id)});
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_audit_event', {sql_literal(audit_id)}, 4,
        jsonb_build_object('audit_id', {sql_literal(audit_id)}, 'action', 'supplier.' || {sql_literal(command_type)},
          'aggregate_type', 'supplier', 'aggregate_id', {sql_literal(supplier_id)}, 'actor_id', {sql_literal(actor_id)},
          'event_id', {sql_literal(event_id)}, 'state', next_state, 'evaluation', next_evaluation, 'revision', next_revision),
        {sql_literal('moonproj:audit:' + event_id)});
      result := jsonb_build_object('supplier_id', {sql_literal(supplier_id)}, 'state', next_state,
        'evaluation', next_evaluation, 'revision', next_revision, 'event_id', {sql_literal(event_id)},
        'audit_id', {sql_literal(audit_id)}, 'actor_id', {sql_literal(actor_id)});
      UPDATE company_record SET payload = payload || jsonb_build_object('result', result)
      WHERE source_id = {sql_literal(command_source)};
    END $$;
    SELECT coalesce((SELECT created::text FROM command_attempt LIMIT 1), 'false')
      || '|' || encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM company_record WHERE source_id = {sql_literal(command_source)};
    COMMIT;
    """
    lines = query_lines(pool, sql)
    if len(lines) != 1:
        raise ServiceError("supplier command did not return a command receipt")
    fields = lines[0].split("|", 1)
    if len(fields) != 2:
        raise ServiceError("unexpected supplier command receipt shape")
    created = fields[0] == "true"
    try:
        receipt = json.loads(decode_hex(fields[1]))
    except json.JSONDecodeError as error:
        raise ServiceError("invalid supplier command receipt JSON") from error
    if not created and receipt.get("request") != request:
        raise CommandRejected("Idempotency-Key was already used for another request", 409)
    result = receipt.get("result")
    if not isinstance(result, dict):
        raise ServiceError("supplier command receipt has no result")
    return {"command": receipt, "supplier": result, "idempotent_replay": not created}


def _tender_text(
    body: dict[str, Any],
    key: str,
    *,
    identifier: bool = False,
) -> str:
    value = body.get(key)
    if not isinstance(value, str) or not value.strip():
        raise CommandRejected(f"{key} is required", 422)
    value = value.strip()
    if identifier and not IDENTIFIER.fullmatch(value):
        raise CommandRejected(f"{key} contains unsupported characters", 422)
    return value


def _tender_request(
    command_type: str,
    tender_id: str | None,
    body: dict[str, Any],
    actor_id: str,
) -> tuple[str, dict[str, Any]]:
    allowed = {"create", "publish", "open_bidding", "award", "complete", "cancel"}
    if command_type not in allowed:
        raise CommandRejected("unsupported tender command", 404)
    if command_type == "create":
        value = body.get("tender_id")
        tender_id = value.strip() if isinstance(value, str) and value.strip() else "TD-" + uuid.uuid4().hex[:20]
        if not IDENTIFIER.fullmatch(tender_id):
            raise CommandRejected("tender_id contains unsupported characters", 422)
        name = _tender_text(body, "name")
        project_scope = _tender_text(body, "project_scope", identifier=True)
        category = _tender_text(body, "category")
        currency = _tender_text(body, "currency", identifier=True).upper()
        if not re.fullmatch(r"[A-Z]{3}", currency):
            raise CommandRejected("currency must be a three-letter code", 422)
        estimated_amount_minor = body.get("estimated_amount_minor")
        if (
            isinstance(estimated_amount_minor, bool)
            or not isinstance(estimated_amount_minor, int)
            or estimated_amount_minor <= 0
        ):
            raise CommandRejected("estimated_amount_minor must be a positive integer", 422)
        bids = body.get("bids", [])
        if not isinstance(bids, list):
            raise CommandRejected("bids must be an array", 422)
        normalized_bids: list[dict[str, Any]] = []
        seen_supplier_ids: set[str] = set()
        for index, bid in enumerate(bids):
            if not isinstance(bid, dict):
                raise CommandRejected(f"bids[{index}] must be an object", 422)
            supplier_id = bid.get("supplier_id")
            amount_minor = bid.get("amount_minor")
            if not isinstance(supplier_id, str) or not IDENTIFIER.fullmatch(supplier_id.strip()):
                raise CommandRejected(f"bids[{index}].supplier_id is invalid", 422)
            supplier_id = supplier_id.strip()
            if supplier_id in seen_supplier_ids:
                raise CommandRejected("a supplier may bid only once", 422)
            if isinstance(amount_minor, bool) or not isinstance(amount_minor, int) or amount_minor <= 0:
                raise CommandRejected(f"bids[{index}].amount_minor must be positive", 422)
            if amount_minor > estimated_amount_minor:
                raise CommandRejected("bid amount exceeds tender estimate", 422)
            seen_supplier_ids.add(supplier_id)
            normalized_bids.append({
                "supplier_id": supplier_id,
                "amount_minor": amount_minor,
                "currency": currency,
            })
        return tender_id, {
            "command_type": command_type,
            "tender_id": tender_id,
            "project_scope": project_scope,
            "name": name,
            "category": category,
            "estimated_amount_minor": estimated_amount_minor,
            "currency": currency,
            "bids": normalized_bids,
            "actor_id": actor_id,
        }
    if tender_id is None or not IDENTIFIER.fullmatch(tender_id):
        raise CommandRejected("tender_id is required", 422)
    request: dict[str, Any] = {
        "command_type": command_type,
        "tender_id": tender_id,
        "actor_id": actor_id,
    }
    if command_type == "award":
        supplier_id = _tender_text(body, "awarded_supplier_id", identifier=True)
        amount_minor = body.get("awarded_amount_minor")
        if isinstance(amount_minor, bool) or not isinstance(amount_minor, int) or amount_minor <= 0:
            raise CommandRejected("awarded_amount_minor must be a positive integer", 422)
        request["awarded_supplier_id"] = supplier_id
        request["awarded_amount_minor"] = amount_minor
    reason = body.get("reason", "")
    if not isinstance(reason, str):
        raise CommandRejected("reason must be text", 422)
    request["reason"] = reason.strip()
    return tender_id, request


def tender_command(
    pool: PsqlPool,
    *,
    command_type: str,
    tender_id: str | None,
    body: dict[str, Any],
    actor_id: str,
    idempotency_key: str,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(idempotency_key):
        raise CommandRejected("Idempotency-Key contains unsupported characters", 422)
    tender_id, request = _tender_request(command_type, tender_id, body, actor_id)
    existing = _existing_command(pool, idempotency_key)
    if existing is not None:
        if existing.get("request") != request:
            raise CommandRejected("Idempotency-Key was already used for another request", 409)
        result = existing.get("result")
        if not isinstance(result, dict):
            raise ServiceError("stored tender command receipt has no result")
        return {"command": existing, "tender": result, "idempotent_replay": True}
    current = tenders(pool, tender_id, 1)
    if command_type == "create" and current:
        raise CommandRejected("tender already exists", 409)
    if command_type != "create":
        if not current:
            raise CommandRejected("tender not found", 404)
        if current[0].get("source_kind") != "command":
            raise CommandRejected("imported tender is read-only; create a local planning draft first", 409)
        current_state = str(current[0].get("state", ""))
        expected = {
            "publish": "planning",
            "open_bidding": "publishing",
            "award": "bidding",
            "complete": "awarded",
        }.get(command_type)
        if command_type == "cancel":
            if current_state not in {"planning", "publishing", "bidding"}:
                raise CommandRejected(f"tender cancellation requires an active planning state, found {current_state}", 409)
        elif current_state != expected:
            raise CommandRejected(
                f"tender transition {command_type} requires {expected}, found {current_state}",
                409,
            )
        if command_type == "award":
            awarded_supplier_id = str(request["awarded_supplier_id"])
            awarded_amount_minor = int(request["awarded_amount_minor"])
            bids = current[0].get("bids", [])
            matching_bid = next(
                (bid for bid in bids if isinstance(bid, dict) and bid.get("supplier_id") == awarded_supplier_id),
                None,
            )
            if matching_bid is None or int(matching_bid.get("amount_minor", 0)) != awarded_amount_minor:
                raise CommandRejected("award must match an existing bid", 422)
            suppliers = query_lines(
                pool,
                f"""
                SELECT 1
                FROM (
                  SELECT DISTINCT ON (aggregate_id) aggregate_id, payload
                  FROM company_aggregate_projection
                  WHERE aggregate_type = 'supplier'
                  ORDER BY aggregate_id, revision DESC
                ) latest
                WHERE coalesce(latest.payload->'candidate'->>'supplier_id', latest.payload->>'supplier_id', latest.aggregate_id) = {sql_literal(awarded_supplier_id)}
                  AND coalesce(latest.payload->'candidate'->>'state', latest.payload->>'state', '') = 'active'
                  AND coalesce(latest.payload->'candidate'->>'evaluation', latest.payload->>'evaluation', '') IN ('qualified', 'strategic')
                LIMIT 1
                """,
            )
            if not suppliers:
                raise CommandRejected("award requires an active qualified supplier projection", 409)
    event_id = f"tender:{command_type}:{idempotency_key}"
    command_source = f"moonproj:command:{idempotency_key}"
    audit_id = event_id + ":audit"
    request_json = json.dumps(request, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    command_json = json.dumps(
        {
            "kind": "company_command",
            "command_type": command_type,
            "idempotency_key": idempotency_key,
            "tender_id": tender_id,
            "actor_id": actor_id,
            "request": request,
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    sql = f"""
    BEGIN;
    CREATE TEMP TABLE command_attempt(created boolean) ON COMMIT DROP;
    WITH inserted AS (
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_command', {sql_literal(event_id)}, 4,
        {sql_literal(command_json)}::jsonb, {sql_literal(command_source)})
      ON CONFLICT (source_id) DO NOTHING
      RETURNING 1
    )
    INSERT INTO command_attempt(created) SELECT EXISTS (SELECT 1 FROM inserted);
    DO $$
    DECLARE
      is_new boolean;
      current_payload jsonb;
      next_payload jsonb;
      current_state text;
      next_state text;
      next_revision integer;
      result jsonb;
    BEGIN
      SELECT created INTO is_new FROM command_attempt LIMIT 1;
      IF NOT is_new THEN RETURN; END IF;
      SELECT p.payload INTO current_payload
      FROM company_aggregate_projection p
      WHERE p.aggregate_type = 'tender'
        AND p.aggregate_id = {sql_literal(tender_id)}
      ORDER BY p.revision DESC LIMIT 1;
      IF {sql_literal(command_type)} = 'create' THEN
        IF current_payload IS NOT NULL THEN RAISE EXCEPTION 'tender already exists'; END IF;
        next_revision := 1;
        next_state := 'planning';
        next_payload := {sql_literal(request_json)}::jsonb || jsonb_build_object(
          'state', next_state, 'source_kind', 'command', 'event_id', {sql_literal(event_id)},
          'updated_by', {sql_literal(actor_id)});
      ELSE
        IF current_payload IS NULL THEN RAISE EXCEPTION 'tender not found'; END IF;
        current_state := current_payload->>'state';
        IF {sql_literal(command_type)} = 'publish' THEN
          IF current_state <> 'planning' THEN RAISE EXCEPTION 'invalid tender state'; END IF;
          next_state := 'publishing';
        ELSIF {sql_literal(command_type)} = 'open_bidding' THEN
          IF current_state <> 'publishing' THEN RAISE EXCEPTION 'invalid tender state'; END IF;
          next_state := 'bidding';
        ELSIF {sql_literal(command_type)} = 'award' THEN
          IF current_state <> 'bidding' THEN RAISE EXCEPTION 'invalid tender state'; END IF;
          next_state := 'awarded';
        ELSIF {sql_literal(command_type)} = 'complete' THEN
          IF current_state <> 'awarded' THEN RAISE EXCEPTION 'invalid tender state'; END IF;
          next_state := 'completed';
        ELSIF {sql_literal(command_type)} = 'cancel' THEN
          IF current_state NOT IN ('planning', 'publishing', 'bidding') THEN RAISE EXCEPTION 'invalid tender state'; END IF;
          next_state := 'cancelled';
        ELSE RAISE EXCEPTION 'unsupported tender command'; END IF;
        SELECT coalesce(max(p.revision), 0) + 1 INTO next_revision
        FROM company_aggregate_projection p
        WHERE p.aggregate_type = 'tender' AND p.aggregate_id = {sql_literal(tender_id)};
        next_payload := current_payload || coalesce({sql_literal(request_json)}::jsonb->'changes', '{{}}'::jsonb) || jsonb_build_object(
          'state', next_state, 'source_kind', 'command', 'event_id', {sql_literal(event_id)},
          'updated_by', {sql_literal(actor_id)}, 'reason', {sql_literal(request_json)}::jsonb->>'reason');
        IF {sql_literal(command_type)} = 'award' THEN
          next_payload := next_payload || jsonb_build_object(
            'awarded_supplier_id', {sql_literal(request_json)}::jsonb->>'awarded_supplier_id',
            'awarded_amount_minor', {sql_literal(request_json)}::jsonb->'awarded_amount_minor');
        END IF;
      END IF;
      INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id)
      VALUES ('tender', {sql_literal(tender_id)}, next_revision, next_payload, {sql_literal(event_id)});
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_audit_event', {sql_literal(audit_id)}, 4,
        jsonb_build_object('audit_id', {sql_literal(audit_id)}, 'action', 'tender.' || {sql_literal(command_type)},
          'aggregate_type', 'tender', 'aggregate_id', {sql_literal(tender_id)}, 'actor_id', {sql_literal(actor_id)},
          'event_id', {sql_literal(event_id)}, 'state', next_state, 'revision', next_revision),
        {sql_literal('moonproj:audit:' + event_id)});
      result := jsonb_build_object('tender_id', {sql_literal(tender_id)}, 'state', next_state,
        'revision', next_revision, 'event_id', {sql_literal(event_id)}, 'audit_id', {sql_literal(audit_id)},
        'actor_id', {sql_literal(actor_id)});
      UPDATE company_record SET payload = payload || jsonb_build_object('result', result)
      WHERE source_id = {sql_literal(command_source)};
    END $$;
    SELECT coalesce((SELECT created::text FROM command_attempt LIMIT 1), 'false')
      || '|' || encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM company_record WHERE source_id = {sql_literal(command_source)};
    COMMIT;
    """
    lines = query_lines(pool, sql)
    if len(lines) != 1:
        raise ServiceError("tender command did not return a command receipt")
    fields = lines[0].split("|", 1)
    if len(fields) != 2:
        raise ServiceError("unexpected tender command receipt shape")
    created = fields[0] == "true"
    try:
        receipt = json.loads(decode_hex(fields[1]))
    except json.JSONDecodeError as error:
        raise ServiceError("invalid tender command receipt JSON") from error
    if not created and receipt.get("request") != request:
        raise CommandRejected("Idempotency-Key was already used for another request", 409)
    result = receipt.get("result")
    if not isinstance(result, dict):
        raise ServiceError("tender command receipt has no result")
    return {"command": receipt, "tender": result, "idempotent_replay": not created}


def _split_request(
    command_type: str,
    split_id: str | None,
    body: dict[str, Any],
    actor_id: str,
) -> tuple[str, dict[str, Any]]:
    if command_type != "create":
        raise CommandRejected("unsupported contract split command", 404)
    split_id = _supplier_text(body, "split_id", identifier=True)
    parent_contract_id = _supplier_text(body, "parent_contract_id", identifier=True)
    split_name = _supplier_text(body, "split_name")
    amount_minor = body.get("split_amount_minor", 0)
    if isinstance(amount_minor, bool) or not isinstance(amount_minor, int) or amount_minor < 0:
        raise CommandRejected("split_amount_minor must be a non-negative integer", 422)
    split_pct_bps = body.get("split_pct_bps", 0)
    if isinstance(split_pct_bps, bool) or not isinstance(split_pct_bps, int) or not 0 <= split_pct_bps <= 10000:
        raise CommandRejected("split_pct_bps must be between 0 and 10000", 422)
    scope = body.get("scope", "")
    if not isinstance(scope, str):
        raise CommandRejected("scope must be text", 422)
    return split_id, {
        "command_type": command_type,
        "split_id": split_id,
        "parent_contract_id": parent_contract_id,
        "split_name": split_name,
        "split_amount_minor": amount_minor,
        "split_pct_bps": split_pct_bps,
        "scope": scope.strip(),
        "state": "planned",
        "actor_id": actor_id,
    }


def split_command(
    pool: PsqlPool,
    *,
    command_type: str,
    split_id: str | None,
    body: dict[str, Any],
    actor_id: str,
    idempotency_key: str,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(idempotency_key):
        raise CommandRejected("Idempotency-Key contains unsupported characters", 422)
    split_id, request = _split_request(command_type, split_id, body, actor_id)
    existing = _existing_command(pool, idempotency_key)
    if existing is not None:
        if existing.get("request") != request:
            raise CommandRejected("Idempotency-Key was already used for another request", 409)
        result = existing.get("result")
        if not isinstance(result, dict):
            raise ServiceError("stored contract split command receipt has no result")
        return {"command": existing, "split": result, "idempotent_replay": True}
    current = contract_splits(pool, split_id, None, 1)
    if current:
        raise CommandRejected("contract split already exists", 409)
    parent_contract_id = str(request["parent_contract_id"])
    if not contracts(pool, parent_contract_id, 1):
        raise CommandRejected("parent contract not found", 404)
    event_id = f"contract_split:{command_type}:{idempotency_key}"
    command_source = f"moonproj:command:{idempotency_key}"
    audit_id = event_id + ":audit"
    request_json = json.dumps(request, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    command_json = json.dumps(
        {
            "kind": "company_command",
            "command_type": command_type,
            "idempotency_key": idempotency_key,
            "split_id": split_id,
            "actor_id": actor_id,
            "request": request,
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    sql = f"""
    BEGIN;
    CREATE TEMP TABLE command_attempt(created boolean) ON COMMIT DROP;
    WITH inserted AS (
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_command', {sql_literal(event_id)}, 4,
        {sql_literal(command_json)}::jsonb, {sql_literal(command_source)})
      ON CONFLICT (source_id) DO NOTHING
      RETURNING 1
    )
    INSERT INTO command_attempt(created) SELECT EXISTS (SELECT 1 FROM inserted);
    DO $$
    DECLARE
      is_new boolean;
      result jsonb;
    BEGIN
      SELECT created INTO is_new FROM command_attempt LIMIT 1;
      IF NOT is_new THEN RETURN; END IF;
      IF EXISTS (
        SELECT 1 FROM company_aggregate_projection
        WHERE aggregate_type = 'contract_split' AND aggregate_id = {sql_literal(split_id)}
      ) THEN RAISE EXCEPTION 'contract split already exists'; END IF;
      INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id)
      VALUES ('contract_split', {sql_literal(split_id)}, 1,
        {sql_literal(request_json)}::jsonb || jsonb_build_object(
          'source_kind', 'command', 'event_id', {sql_literal(event_id)}, 'updated_by', {sql_literal(actor_id)}),
        {sql_literal(event_id)});
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_audit_event', {sql_literal(audit_id)}, 4,
        jsonb_build_object('audit_id', {sql_literal(audit_id)}, 'action', 'contract_split.create',
          'aggregate_type', 'contract_split', 'aggregate_id', {sql_literal(split_id)},
          'parent_contract_id', {sql_literal(parent_contract_id)}, 'actor_id', {sql_literal(actor_id)},
          'event_id', {sql_literal(event_id)}, 'state', 'planned', 'revision', 1),
        {sql_literal('moonproj:audit:' + event_id)});
      result := jsonb_build_object('split_id', {sql_literal(split_id)}, 'parent_contract_id', {sql_literal(parent_contract_id)},
        'state', 'planned', 'revision', 1, 'event_id', {sql_literal(event_id)},
        'audit_id', {sql_literal(audit_id)}, 'actor_id', {sql_literal(actor_id)});
      UPDATE company_record SET payload = payload || jsonb_build_object('result', result)
      WHERE source_id = {sql_literal(command_source)};
    END $$;
    SELECT coalesce((SELECT created::text FROM command_attempt LIMIT 1), 'false')
      || '|' || encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM company_record WHERE source_id = {sql_literal(command_source)};
    COMMIT;
    """
    lines = query_lines(pool, sql)
    if len(lines) != 1:
        raise ServiceError("contract split command did not return a command receipt")
    fields = lines[0].split("|", 1)
    if len(fields) != 2:
        raise ServiceError("unexpected contract split command receipt shape")
    created = fields[0] == "true"
    try:
        receipt = json.loads(decode_hex(fields[1]))
    except json.JSONDecodeError as error:
        raise ServiceError("invalid contract split command receipt JSON") from error
    if not created and receipt.get("request") != request:
        raise CommandRejected("Idempotency-Key was already used for another request", 409)
    result = receipt.get("result")
    if not isinstance(result, dict):
        raise ServiceError("contract split command receipt has no result")
    return {"command": receipt, "split": result, "idempotent_replay": not created}


def _contract_text(body: dict[str, Any], key: str, *, identifier: bool = False) -> str:
    value = body.get(key)
    if not isinstance(value, str) or not value.strip():
        raise CommandRejected(f"{key} is required", 422)
    value = value.strip()
    if identifier and not IDENTIFIER.fullmatch(value):
        raise CommandRejected(f"{key} contains unsupported characters", 422)
    return value


def _contract_request(
    command_type: str,
    contract_id: str | None,
    body: dict[str, Any],
    actor_id: str,
) -> tuple[str, dict[str, Any]]:
    if command_type not in {"create", "submit", "approve", "reject", "resubmit"}:
        raise CommandRejected("unsupported contract command", 404)
    if command_type == "create":
        contract_id = _contract_text(body, "contract_id", identifier=True)
        contract_code = _contract_text(body, "contract_code", identifier=True)
        contract_name = _contract_text(body, "contract_name")
        project_id = _contract_text(body, "project_id", identifier=True)
        project_name = _contract_text(body, "project_name")
        supplier_id = _contract_text(body, "supplier_id", identifier=True)
        supplier_name = _contract_text(body, "supplier_name")
        sign_date = _contract_text(body, "sign_date")
        currency = _contract_text(body, "currency", identifier=True).upper()
        if not re.fullmatch(r"[A-Z]{3}", currency):
            raise CommandRejected("currency must be a three-letter code", 422)
        amount_minor = body.get("amount_minor")
        if isinstance(amount_minor, bool) or not isinstance(amount_minor, int) or amount_minor <= 0:
            raise CommandRejected("amount_minor must be a positive integer", 422)
        return contract_id, {
            "command_type": command_type,
            "contract_id": contract_id,
            "contract_code": contract_code,
            "contract_name": contract_name,
            "project_id": project_id,
            "project_name": project_name,
            "supplier_id": supplier_id,
            "supplier_name": supplier_name,
            "sign_date": sign_date,
            "amount_minor": amount_minor,
            "currency": currency,
            "actor_id": actor_id,
        }
    if contract_id is None or not IDENTIFIER.fullmatch(contract_id):
        raise CommandRejected("contract_id is required", 422)
    reason = body.get("reason", "")
    if not isinstance(reason, str):
        raise CommandRejected("reason must be text", 422)
    return contract_id, {
        "command_type": command_type,
        "contract_id": contract_id,
        "reason": reason.strip(),
        "actor_id": actor_id,
    }


def contract_command(
    pool: PsqlPool,
    *,
    command_type: str,
    contract_id: str | None,
    body: dict[str, Any],
    actor_id: str,
    idempotency_key: str,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(idempotency_key):
        raise CommandRejected("Idempotency-Key contains unsupported characters", 422)
    contract_id, request = _contract_request(command_type, contract_id, body, actor_id)
    existing = _existing_command(pool, idempotency_key)
    if existing is not None:
        if existing.get("request") != request:
            raise CommandRejected("Idempotency-Key was already used for another request", 409)
        result = existing.get("result")
        if not isinstance(result, dict):
            raise ServiceError("stored contract command receipt has no result")
        return {"command": existing, "contract": result, "idempotent_replay": True}
    current = contracts(pool, contract_id, 1)
    if command_type == "create" and current:
        raise CommandRejected("contract already exists", 409)
    if command_type != "create":
        if not current:
            raise CommandRejected("contract not found", 404)
        current_state = str(current[0].get("state", ""))
        expected = {
            "submit": "draft",
            "approve": "submitted",
            "reject": "submitted",
            "resubmit": "rejected",
        }[command_type]
        if current_state != expected:
            raise CommandRejected(
                f"contract transition {command_type} requires {expected}, found {current_state}",
                409,
            )
    event_id = f"contract:{command_type}:{idempotency_key}"
    command_source = f"moonproj:command:{idempotency_key}"
    audit_id = event_id + ":audit"
    request_json = json.dumps(request, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    command_json = json.dumps(
        {
            "kind": "company_command",
            "command_type": command_type,
            "idempotency_key": idempotency_key,
            "contract_id": contract_id,
            "actor_id": actor_id,
            "request": request,
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    sql = f"""
    BEGIN;
    CREATE TEMP TABLE command_attempt(created boolean) ON COMMIT DROP;
    WITH inserted AS (
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES (
        'company_command', {sql_literal(event_id)}, 4,
        {sql_literal(command_json)}::jsonb, {sql_literal(command_source)}
      )
      ON CONFLICT (source_id) DO NOTHING
      RETURNING 1
    )
    INSERT INTO command_attempt(created)
    SELECT EXISTS (SELECT 1 FROM inserted);
    DO $$
    DECLARE
      is_new boolean;
      current_payload jsonb;
      next_payload jsonb;
      current_state text;
      next_state text;
      next_revision integer;
      result jsonb;
    BEGIN
      SELECT created INTO is_new FROM command_attempt LIMIT 1;
      IF NOT is_new THEN
        RETURN;
      END IF;
      SELECT p.payload INTO current_payload
      FROM company_aggregate_projection p
      WHERE p.aggregate_type = 'contract'
        AND p.aggregate_id = {sql_literal(contract_id)}
      ORDER BY p.revision DESC
      LIMIT 1;
      IF {sql_literal(command_type)} = 'create' THEN
        IF current_payload IS NOT NULL THEN
          RAISE EXCEPTION 'contract already exists';
        END IF;
        next_revision := 1;
        next_state := 'draft';
        next_payload := {sql_literal(request_json)}::jsonb || jsonb_build_object(
          'state', next_state, 'event_id', {sql_literal(event_id)},
          'updated_by', {sql_literal(actor_id)}
        );
      ELSE
        IF current_payload IS NULL THEN
          RAISE EXCEPTION 'contract not found';
        END IF;
        current_state := current_payload->>'state';
        IF {sql_literal(command_type)} = 'submit' THEN
          IF current_state <> 'draft' THEN RAISE EXCEPTION 'invalid contract state'; END IF;
          next_state := 'submitted';
        ELSIF {sql_literal(command_type)} = 'approve' THEN
          IF current_state <> 'submitted' THEN RAISE EXCEPTION 'invalid contract state'; END IF;
          next_state := 'approved';
        ELSIF {sql_literal(command_type)} = 'reject' THEN
          IF current_state <> 'submitted' THEN RAISE EXCEPTION 'invalid contract state'; END IF;
          next_state := 'rejected';
        ELSIF {sql_literal(command_type)} = 'resubmit' THEN
          IF current_state <> 'rejected' THEN RAISE EXCEPTION 'invalid contract state'; END IF;
          next_state := 'submitted';
        ELSE
          RAISE EXCEPTION 'unsupported contract command';
        END IF;
        SELECT coalesce(max(p.revision), 0) + 1 INTO next_revision
        FROM company_aggregate_projection p
        WHERE p.aggregate_type = 'contract'
          AND p.aggregate_id = {sql_literal(contract_id)};
        next_payload := current_payload || jsonb_build_object(
          'state', next_state, 'event_id', {sql_literal(event_id)},
          'updated_by', {sql_literal(actor_id)},
          'reason', {sql_literal(request_json)}::jsonb->>'reason'
        );
      END IF;
      INSERT INTO company_aggregate_projection(
        aggregate_type, aggregate_id, revision, payload, source_event_id
      ) VALUES (
        'contract', {sql_literal(contract_id)}, next_revision,
        next_payload, {sql_literal(event_id)}
      );
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES (
        'company_audit_event', {sql_literal(audit_id)}, 4,
        jsonb_build_object(
          'audit_id', {sql_literal(audit_id)},
          'action', 'contract.' || {sql_literal(command_type)},
          'aggregate_type', 'contract',
          'aggregate_id', {sql_literal(contract_id)},
          'actor_id', {sql_literal(actor_id)},
          'event_id', {sql_literal(event_id)},
          'state', next_state,
          'revision', next_revision
        ),
        {sql_literal('moonproj:audit:' + event_id)}
      );
      result := jsonb_build_object(
        'contract_id', {sql_literal(contract_id)}, 'state', next_state,
        'revision', next_revision, 'event_id', {sql_literal(event_id)},
        'audit_id', {sql_literal(audit_id)}, 'actor_id', {sql_literal(actor_id)}
      );
      UPDATE company_record
      SET payload = payload || jsonb_build_object('result', result)
      WHERE source_id = {sql_literal(command_source)};
    END $$;
    SELECT coalesce((SELECT created::text FROM command_attempt LIMIT 1), 'false')
           || '|' || encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM company_record
    WHERE source_id = {sql_literal(command_source)};
    COMMIT;
    """
    lines = query_lines(pool, sql)
    if len(lines) != 1:
        raise ServiceError("contract command did not return a command receipt")
    fields = lines[0].split("|", 1)
    if len(fields) != 2:
        raise ServiceError("unexpected contract command receipt shape")
    created = fields[0] == "true"
    try:
        receipt = json.loads(decode_hex(fields[1]))
    except json.JSONDecodeError as error:
        raise ServiceError("invalid contract command receipt JSON") from error
    if not created and receipt.get("request") != request:
        raise CommandRejected("Idempotency-Key was already used for another request", 409)
    result = receipt.get("result")
    if not isinstance(result, dict):
        raise ServiceError("contract command receipt has no result")
    return {"command": receipt, "contract": result, "idempotent_replay": not created}


def _decode_payment_application_fields(line: str) -> dict[str, Any]:
    fields = line.split("|")
    if len(fields) != 21:
        raise ServiceError("unexpected payment application projection shape")
    try:
        return {
            "apply_id": decode_hex(fields[0]),
            "apply_code": decode_hex(fields[1]),
            "contract_id": decode_hex(fields[2]),
            "contract_name": decode_hex(fields[3]),
            "project_id": decode_hex(fields[4]),
            "project_name": decode_hex(fields[5]),
            "supplier_name": decode_hex(fields[6]),
            "subject": decode_hex(fields[7]),
            "amount_minor": int(fields[8]),
            "currency": decode_hex(fields[9]),
            "apply_date": decode_hex(fields[10]),
            "operation_state": decode_hex(fields[11]),
            "apply_state": decode_hex(fields[12]),
            "pay_state": decode_hex(fields[13]),
            "apply_type_code": decode_hex(fields[14]),
            "pay_class": decode_hex(fields[15]),
            "applied_by": decode_hex(fields[16]),
            "applied_by_name": decode_hex(fields[17]),
            "source_kind": decode_hex(fields[18]),
            "plan_id": decode_hex(fields[19]),
            "milestone_id": decode_hex(fields[20]),
        }
    except (ValueError, UnicodeDecodeError) as error:
        raise ServiceError("invalid payment application projection encoding") from error


def payment_applications(
    pool: PsqlPool,
    apply_id: str | None,
    view: str,
    max_rows: int,
) -> list[dict[str, Any]]:
    if apply_id is not None and not IDENTIFIER.fullmatch(apply_id):
        raise ValueError("invalid payment application id")
    if view not in {"all", "approving", "approved", "fullpaid"}:
        raise ValueError("unsupported payment application view")
    where = ""
    if apply_id is not None:
        where = f"WHERE base.apply_id = {sql_literal(apply_id)}"
    query = f"""
    WITH imported AS (
      SELECT DISTINCT ON (aggregate_id)
             aggregate_id AS apply_id, payload, 'imported' AS source_kind
      FROM company_aggregate_projection
      WHERE aggregate_type = 'payment_application'
      ORDER BY aggregate_id, revision DESC
    ),
    command AS (
      SELECT DISTINCT ON (aggregate_id)
             aggregate_id AS apply_id, payload, 'command' AS source_kind
      FROM company_aggregate_projection
      WHERE aggregate_type = 'payment_application_command'
      ORDER BY aggregate_id, revision DESC
    ),
    base AS (
      SELECT apply_id, payload, source_kind FROM imported
      UNION ALL
      SELECT apply_id, payload, source_kind FROM command
    ),
    deduped AS (
      SELECT DISTINCT ON (apply_id) apply_id, payload, source_kind
      FROM base
      ORDER BY apply_id, CASE WHEN source_kind = 'command' THEN 1 ELSE 0 END DESC
    ),
    raw_apply AS (
      SELECT record_id, payload
      FROM company_record
      WHERE record_type = 'legacy/raw/cb_htfk_apply'
    ),
    raw_contract AS (
      SELECT record_id, payload
      FROM company_record
      WHERE record_type = 'legacy/raw/cb_contract'
    ),
    raw_project AS (
      SELECT record_id, payload
      FROM company_record
      WHERE record_type = 'legacy/raw/ep_project'
    ),
    raw_user AS (
      SELECT record_id, payload
      FROM company_record
      WHERE record_type = 'legacy/raw/sys_user'
    )
    SELECT encode(convert_to(base.apply_id, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(base.payload->'payment_application'->>'apply_code',
             base.payload->'candidate'->'application'->>'apply_code', raw_apply.payload->>'apply_code', base.apply_id), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(base.payload->'payment_application'->>'contract_id',
             base.payload->'candidate'->'application'->>'contract_guid', raw_apply.payload->>'contract_guid', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(raw_contract.payload->>'contract_name', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(base.payload->'payment_application'->>'project_id',
             base.payload->'candidate'->'application'->>'proj_guid', raw_apply.payload->>'proj_guid', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(raw_project.payload->>'proj_name', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(raw_contract.payload->>'yf_provider_name', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(base.payload->'payment_application'->>'subject',
             base.payload->'candidate'->'application'->>'subject', raw_apply.payload->>'subject', ''), 'UTF8'), 'hex'),
           coalesce(base.payload->'payment_application'->>'amount_minor',
             base.payload->'candidate'->'application'->>'amount_minor',
             round(coalesce((raw_apply.payload->>'apply_amount')::numeric, 0) * 100)::bigint::text, '0'),
           encode(convert_to(coalesce(base.payload->>'currency',
             base.payload->'candidate'->>'currency', 'CNY'), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(base.payload->'payment_application'->>'apply_date',
             base.payload->'candidate'->'application'->>'apply_date', raw_apply.payload->>'apply_date', ''), 'UTF8'), 'hex'),
           encode(convert_to(
             CASE WHEN base.source_kind = 'command' THEN coalesce(base.payload->>'state', 'draft')
               WHEN coalesce(raw_apply.payload->>'pay_state', '') = '完全支付' THEN 'paid'
               WHEN coalesce(raw_apply.payload->>'pay_state', '') = '部分支付' THEN 'partially_paid'
               WHEN coalesce(raw_apply.payload->>'apply_state', '') IN ('已审核', 'approved', 'Approved') THEN 'approved'
               WHEN coalesce(raw_apply.payload->>'apply_state', '') IN ('已驳回', 'rejected', 'Rejected') THEN 'rejected'
               WHEN coalesce(raw_apply.payload->>'apply_state', '') IN ('申请审批中', 'submitted', 'Approving') THEN 'submitted'
               ELSE 'draft'
             END, 'UTF8'), 'hex'),
           encode(convert_to(
             CASE WHEN base.source_kind = 'command' THEN
               CASE base.payload->>'state' WHEN 'draft' THEN '草稿' WHEN 'submitted' THEN '申请审批中'
                 WHEN 'rejected' THEN '已驳回' WHEN 'approved' THEN '已审核' WHEN 'voided' THEN '已作废'
                 ELSE coalesce(base.payload->>'state', '草稿') END
               ELSE coalesce(base.payload->'candidate'->'application'->>'apply_state', raw_apply.payload->>'apply_state', '')
             END, 'UTF8'), 'hex'),
           encode(convert_to(
             CASE WHEN base.source_kind = 'command' THEN coalesce(base.payload->'payment_application'->>'pay_state', '未支付')
               ELSE coalesce(base.payload->'candidate'->'application'->>'pay_state', raw_apply.payload->>'pay_state', '')
             END, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(base.payload->'payment_application'->>'apply_type_code',
             base.payload->'candidate'->'application'->>'apply_type_code', raw_apply.payload->>'apply_type_code', ''), 'UTF8'), 'hex'),
           encode(convert_to(CASE WHEN coalesce(base.payload->'payment_application'->>'apply_class',
             base.payload->'candidate'->'application'->>'apply_class', raw_apply.payload->>'apply_class', '0') = '0'
             THEN '合同' ELSE '非合同' END, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(base.payload->'payment_application'->>'applied_by',
             base.payload->'candidate'->'application'->>'applied_by', raw_apply.payload->>'applied_by', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(raw_user.payload->>'emp_name', raw_user.payload->>'user_name',
             base.payload->'payment_application'->>'applied_by', base.payload->'candidate'->'application'->>'applied_by', ''), 'UTF8'), 'hex'),
           encode(convert_to(base.source_kind, 'UTF8'), 'hex'),
           encode(convert_to(coalesce(base.payload->'payment_application'->>'plan_id',
             base.payload->'candidate'->'application'->>'plan_guid', raw_apply.payload->>'htfk_plan_guid', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(base.payload->'payment_application'->>'milestone_id',
             base.payload->'candidate'->'application'->>'milestone_guid', raw_apply.payload->>'milestone_guid', ''), 'UTF8'), 'hex')
    FROM deduped base
    LEFT JOIN raw_apply ON raw_apply.record_id = base.apply_id
    LEFT JOIN raw_contract ON raw_contract.record_id = coalesce(base.payload->'payment_application'->>'contract_id',
      base.payload->'candidate'->'application'->>'contract_guid', raw_apply.payload->>'contract_guid')
    LEFT JOIN raw_project ON raw_project.record_id = coalesce(base.payload->'payment_application'->>'project_id',
      base.payload->'candidate'->'application'->>'proj_guid', raw_apply.payload->>'proj_guid')
    LEFT JOIN raw_user ON raw_user.record_id = coalesce(base.payload->'payment_application'->>'applied_by',
      base.payload->'candidate'->'application'->>'applied_by', raw_apply.payload->>'applied_by')
    {where}
    ORDER BY base.apply_id
    LIMIT {max_rows}
    """
    result = [_decode_payment_application_fields(line) for line in query_lines(pool, query)]
    for item in result:
        item["amount_display"] = f"¥{item['amount_minor'] / 100:,.2f}"
    if view == "approving":
        result = [item for item in result if item["operation_state"] == "submitted"]
    elif view == "approved":
        result = [item for item in result if item["operation_state"] == "approved"]
    elif view == "fullpaid":
        result = [item for item in result if item["operation_state"] == "paid"]
    return result


def payment_application_eligibility(
    pool: PsqlPool,
    plan_id: str,
    amount_minor: int,
) -> dict[str, Any] | None:
    if not IDENTIFIER.fullmatch(plan_id):
        raise ValueError("invalid payment plan id")
    if isinstance(amount_minor, bool) or amount_minor <= 0:
        raise ValueError("amount_minor must be a positive integer")
    query = f"""
    SELECT encode(convert_to(p.aggregate_id, 'UTF8'), 'hex'),
           coalesce(p.payload->'candidate'->'milestone'->>'contract_guid', ''),
           coalesce(p.payload->'candidate'->'milestone'->>'plan_amount_minor', '0'),
           encode(convert_to(coalesce(p.payload->'candidate'->'milestone'->>'trigger_type', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(raw.payload->>'jhfk_date', ''), 'UTF8'), 'hex'),
           encode(convert_to(coalesce(raw.payload->>'plan_period', ''), 'UTF8'), 'hex'),
           coalesce((
             SELECT sum(round((a.payload->>'apply_amount')::numeric * 100))
             FROM company_record a
             WHERE a.record_type = 'legacy/raw/cb_htfk_apply'
               AND a.payload->>'htfk_plan_guid' = p.aggregate_id
               AND coalesce(a.payload->>'pay_state', '') IN ('完全支付', '部分支付')
           ), 0)::bigint
    FROM company_aggregate_projection p
    LEFT JOIN company_record raw
      ON raw.record_type = 'legacy/raw/cb_htfkplan'
     AND raw.record_id = p.aggregate_id
    WHERE p.aggregate_type = 'contract_milestone'
      AND p.aggregate_id = {sql_literal(plan_id)}
    ORDER BY p.revision DESC
    LIMIT 1
    """
    lines = query_lines(pool, query)
    if not lines:
        return None
    fields = lines[0].split("|")
    if len(fields) != 7:
        raise ServiceError("unexpected payment eligibility shape")
    try:
        contract_id = fields[1]
        planned_minor = int(fields[2])
        trigger_type = decode_hex(fields[3])
        plan_date = decode_hex(fields[4])
        plan_period = decode_hex(fields[5])
        actual_minor = int(fields[6])
    except (ValueError, UnicodeDecodeError) as error:
        raise ServiceError("invalid payment eligibility encoding") from error
    early_flag = trigger_type == "time" and bool(plan_date) and plan_date > time.strftime("%Y-%m-%d")
    over_pay = planned_minor > 0 and actual_minor + amount_minor > planned_minor
    warnings: list[dict[str, str]] = []
    if early_flag:
        warnings.append({"level": "warn", "code": "early_time", "message": f"节点计划付款日 {plan_date}, 尚未到达"})
    if trigger_type in {"progress", "event"}:
        warnings.append({"level": "warn", "code": "trigger_review", "message": f"节点触发类型 {trigger_type} 需要履约证据复核"})
    if over_pay:
        warnings.append({"level": "error", "code": "over_pay", "message": "本次申请会超过付款节点计划金额"})
    return {
        "plan_id": plan_id,
        "contract_id": contract_id,
        "plan_period": plan_period,
        "plan_date": plan_date,
        "trigger_type": trigger_type,
        "planned_amount_minor": planned_minor,
        "planned_amount_display": f"¥{planned_minor / 100:,.2f}",
        "actual_amount_minor": actual_minor,
        "actual_amount_display": f"¥{actual_minor / 100:,.2f}",
        "requested_amount_minor": amount_minor,
        "requested_amount_display": f"¥{amount_minor / 100:,.2f}",
        "early_flag": early_flag,
        "over_pay": over_pay,
        "warnings": warnings,
    }


def _payment_text(body: dict[str, Any], key: str, *, identifier: bool = False) -> str:
    value = body.get(key)
    if not isinstance(value, str) or not value.strip():
        raise CommandRejected(f"{key} is required", 422)
    value = value.strip()
    if identifier and not IDENTIFIER.fullmatch(value):
        raise CommandRejected(f"{key} contains unsupported characters", 422)
    return value


def _payment_request(
    command_type: str,
    apply_id: str | None,
    body: dict[str, Any],
    actor_id: str,
    pool: PsqlPool,
) -> tuple[str, dict[str, Any]]:
    if command_type not in {"create", "submit", "approve", "reject", "resubmit", "update", "void"}:
        raise CommandRejected("unsupported payment application command", 404)
    if command_type == "create":
        apply_id = body.get("apply_id")
        if not isinstance(apply_id, str) or not apply_id.strip():
            apply_id = "PAY-" + uuid.uuid4().hex[:20]
        apply_id = apply_id.strip()
        if not IDENTIFIER.fullmatch(apply_id):
            raise CommandRejected("apply_id contains unsupported characters", 422)
        apply_code = _payment_text(body, "apply_code", identifier=True)
        contract_id = _payment_text(body, "contract_id", identifier=True)
        subject = _payment_text(body, "subject")
        currency = _payment_text(body, "currency", identifier=True).upper()
        if not re.fullmatch(r"[A-Z]{3}", currency):
            raise CommandRejected("currency must be a three-letter code", 422)
        amount_minor = body.get("amount_minor")
        if isinstance(amount_minor, bool) or not isinstance(amount_minor, int) or amount_minor <= 0:
            raise CommandRejected("amount_minor must be a positive integer", 422)
        contract = contracts(pool, contract_id, 1)
        if not contract:
            raise CommandRejected("contract not found", 404)
        plan_id = body.get("plan_id", "")
        if not isinstance(plan_id, str):
            raise CommandRejected("plan_id must be text", 422)
        plan_id = plan_id.strip()
        if plan_id:
            plan_rows = query_lines(
                pool,
                f"""
                SELECT 1
                FROM company_record
                WHERE record_type = 'legacy/raw/cb_htfkplan'
                  AND record_id = {sql_literal(plan_id)}
                  AND payload->>'contract_guid' = {sql_literal(contract_id)}
                LIMIT 1
                """,
            )
            if not plan_rows:
                raise CommandRejected("plan_id does not belong to contract", 422)
        existing_amount_lines = query_lines(
            pool,
            f"""
            SELECT coalesce(sum(round((payload->>'apply_amount')::numeric * 100)), 0)::bigint
            FROM company_record
            WHERE record_type = 'legacy/raw/cb_htfk_apply'
              AND payload->>'contract_guid' = {sql_literal(contract_id)}
              AND coalesce(payload->>'apply_state', '') <> '已驳回'
            """,
        )
        existing_amount_minor = int(existing_amount_lines[0]) if existing_amount_lines else 0
        if existing_amount_minor + amount_minor > int(contract[0].get("amount_minor", 0)):
            raise CommandRejected("payment application exceeds contract amount", 409)
        apply_type_code = body.get("apply_type_code", "WORK_PROGRESS")
        if not isinstance(apply_type_code, str) or not apply_type_code.strip():
            raise CommandRejected("apply_type_code must be text", 422)
        return apply_id, {
            "command_type": command_type,
            "apply_id": apply_id,
            "apply_code": apply_code,
            "contract_id": contract_id,
            "plan_id": plan_id,
            "apply_class": int(body.get("apply_class", 0)) if isinstance(body.get("apply_class", 0), int) else 0,
            "apply_type_code": apply_type_code.strip(),
            "subject": subject,
            "amount_minor": amount_minor,
            "currency": currency,
            "apply_date": body.get("apply_date", time.strftime("%Y-%m-%d")),
            "applied_by": actor_id,
            "project_id": contract[0].get("project_id", ""),
            "actor_id": actor_id,
        }
    if apply_id is None or not IDENTIFIER.fullmatch(apply_id):
        raise CommandRejected("apply_id is required", 422)
    if command_type == "update":
        subject = body.get("subject")
        amount_minor = body.get("amount_minor")
        apply_type_code = body.get("apply_type_code")
        if subject is not None and (not isinstance(subject, str) or not subject.strip()):
            raise CommandRejected("subject must be non-empty text", 422)
        if amount_minor is not None and (
            isinstance(amount_minor, bool) or not isinstance(amount_minor, int) or amount_minor <= 0
        ):
            raise CommandRejected("amount_minor must be a positive integer", 422)
        if apply_type_code is not None and (not isinstance(apply_type_code, str) or not apply_type_code.strip()):
            raise CommandRejected("apply_type_code must be non-empty text", 422)
        if subject is None and amount_minor is None and apply_type_code is None:
            raise CommandRejected("update requires subject, amount_minor, or apply_type_code", 422)
        request: dict[str, Any] = {
            "command_type": command_type,
            "apply_id": apply_id,
            "actor_id": actor_id,
        }
        if subject is not None:
            request["subject"] = subject.strip()
        if amount_minor is not None:
            request["amount_minor"] = amount_minor
        if apply_type_code is not None:
            request["apply_type_code"] = apply_type_code.strip()
        return apply_id, request
    reason = body.get("reason", "")
    if not isinstance(reason, str):
        raise CommandRejected("reason must be text", 422)
    return apply_id, {
        "command_type": command_type,
        "apply_id": apply_id,
        "reason": reason.strip(),
        "actor_id": actor_id,
    }


def payment_application_command(
    pool: PsqlPool,
    *,
    command_type: str,
    apply_id: str | None,
    body: dict[str, Any],
    actor_id: str,
    idempotency_key: str,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(idempotency_key):
        raise CommandRejected("Idempotency-Key contains unsupported characters", 422)
    apply_id, request = _payment_request(command_type, apply_id, body, actor_id, pool)
    existing = _existing_command(pool, idempotency_key)
    if existing is not None:
        if existing.get("request") != request:
            raise CommandRejected("Idempotency-Key was already used for another request", 409)
        result = existing.get("result")
        if not isinstance(result, dict):
            raise ServiceError("stored payment application command receipt has no result")
        return {"command": existing, "payment_application": result, "idempotent_replay": True}
    current = payment_applications(pool, apply_id, "all", 1)
    if command_type == "create" and current:
        raise CommandRejected("payment application already exists", 409)
    if command_type != "create":
        if not current:
            raise CommandRejected("payment application not found", 404)
        if command_type in {"update", "void"} and current[0].get("source_kind") != "command":
            raise CommandRejected("source payment application is read-only; create a local command draft first", 409)
        if command_type == "update":
            expected = "submitted"
            if current[0].get("operation_state") != expected:
                raise CommandRejected(
                    f"payment application transition update requires {expected}, found {current[0].get('operation_state')}",
                    409,
                )
        elif command_type == "void":
            if current[0].get("pay_state") != "未支付":
                raise CommandRejected("paid payment application cannot be voided", 409)
            if current[0].get("operation_state") == "voided":
                raise CommandRejected("payment application is already voided", 409)
        else:
            expected = {
                "submit": "draft",
                "approve": "submitted",
                "reject": "submitted",
                "resubmit": "rejected",
            }[command_type]
            if current[0].get("operation_state") != expected:
                raise CommandRejected(
                    f"payment application transition {command_type} requires {expected}, found {current[0].get('operation_state')}",
                    409,
                )
    event_id = f"payment-application:{command_type}:{idempotency_key}"
    command_source = f"moonproj:command:{idempotency_key}"
    audit_id = event_id + ":audit"
    request_json = json.dumps(request, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    command_json = json.dumps(
        {
            "kind": "company_command",
            "command_type": command_type,
            "idempotency_key": idempotency_key,
            "apply_id": apply_id,
            "actor_id": actor_id,
            "request": request,
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    sql = f"""
    BEGIN;
    CREATE TEMP TABLE command_attempt(created boolean) ON COMMIT DROP;
    WITH inserted AS (
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_command', {sql_literal(event_id)}, 4,
        {sql_literal(command_json)}::jsonb, {sql_literal(command_source)})
      ON CONFLICT (source_id) DO NOTHING
      RETURNING 1
    )
    INSERT INTO command_attempt(created) SELECT EXISTS (SELECT 1 FROM inserted);
    DO $$
    DECLARE
      is_new boolean;
      current_payload jsonb;
      next_payload jsonb;
      current_state text;
      next_state text;
      next_revision integer;
      result jsonb;
    BEGIN
      SELECT created INTO is_new FROM command_attempt LIMIT 1;
      IF NOT is_new THEN RETURN; END IF;
      SELECT p.payload INTO current_payload
      FROM company_aggregate_projection p
      WHERE p.aggregate_type = 'payment_application_command'
        AND p.aggregate_id = {sql_literal(apply_id)}
      ORDER BY p.revision DESC LIMIT 1;
      IF {sql_literal(command_type)} = 'create' THEN
        IF current_payload IS NOT NULL THEN RAISE EXCEPTION 'payment application already exists'; END IF;
        next_revision := 1;
        next_state := 'draft';
        next_payload := jsonb_build_object(
          'format', 'moonproj.company.payment-application-command.v1',
          'state', next_state,
          'payment_application', {sql_literal(request_json)}::jsonb,
          'event_id', {sql_literal(event_id)},
          'updated_by', {sql_literal(actor_id)});
      ELSE
        IF current_payload IS NULL THEN RAISE EXCEPTION 'payment application command not found'; END IF;
        current_state := current_payload->>'state';
        IF {sql_literal(command_type)} = 'submit' THEN
          IF current_state <> 'draft' THEN RAISE EXCEPTION 'invalid payment application state'; END IF;
          next_state := 'submitted';
        ELSIF {sql_literal(command_type)} = 'approve' THEN
          IF current_state <> 'submitted' THEN RAISE EXCEPTION 'invalid payment application state'; END IF;
          next_state := 'approved';
        ELSIF {sql_literal(command_type)} = 'reject' THEN
          IF current_state <> 'submitted' THEN RAISE EXCEPTION 'invalid payment application state'; END IF;
          next_state := 'rejected';
        ELSIF {sql_literal(command_type)} = 'resubmit' THEN
          IF current_state <> 'rejected' THEN RAISE EXCEPTION 'invalid payment application state'; END IF;
          next_state := 'submitted';
        ELSIF {sql_literal(command_type)} = 'update' THEN
          IF current_state <> 'submitted' THEN RAISE EXCEPTION 'invalid payment application state'; END IF;
          next_state := current_state;
        ELSIF {sql_literal(command_type)} = 'void' THEN
          IF current_state = 'voided' THEN RAISE EXCEPTION 'payment application already voided'; END IF;
          next_state := 'voided';
        ELSE RAISE EXCEPTION 'unsupported payment application command'; END IF;
        SELECT coalesce(max(p.revision), 0) + 1 INTO next_revision
        FROM company_aggregate_projection p
        WHERE p.aggregate_type = 'payment_application_command'
          AND p.aggregate_id = {sql_literal(apply_id)};
        IF {sql_literal(command_type)} = 'update' THEN
          next_payload := current_payload || jsonb_build_object(
            'state', next_state, 'event_id', {sql_literal(event_id)},
            'updated_by', {sql_literal(actor_id)},
            'payment_application', current_payload->'payment_application' ||
              jsonb_strip_nulls(jsonb_build_object(
                'subject', {sql_literal(request_json)}::jsonb->>'subject',
                'amount_minor', {sql_literal(request_json)}::jsonb->'amount_minor',
                'apply_type_code', {sql_literal(request_json)}::jsonb->>'apply_type_code')));
        ELSE
          next_payload := current_payload || jsonb_build_object(
            'state', next_state, 'event_id', {sql_literal(event_id)},
            'updated_by', {sql_literal(actor_id)},
            'reason', {sql_literal(request_json)}::jsonb->>'reason');
        END IF;
      END IF;
      INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id)
      VALUES ('payment_application_command', {sql_literal(apply_id)}, next_revision,
        next_payload, {sql_literal(event_id)});
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_audit_event', {sql_literal(audit_id)}, 4,
        jsonb_build_object('audit_id', {sql_literal(audit_id)},
          'action', 'payment_application.' || {sql_literal(command_type)},
          'aggregate_type', 'payment_application', 'aggregate_id', {sql_literal(apply_id)},
          'actor_id', {sql_literal(actor_id)}, 'event_id', {sql_literal(event_id)},
          'state', next_state, 'revision', next_revision),
        {sql_literal('moonproj:audit:' + event_id)});
      result := jsonb_build_object('apply_id', {sql_literal(apply_id)}, 'state', next_state,
        'revision', next_revision, 'event_id', {sql_literal(event_id)},
        'audit_id', {sql_literal(audit_id)}, 'actor_id', {sql_literal(actor_id)});
      UPDATE company_record SET payload = payload || jsonb_build_object('result', result)
      WHERE source_id = {sql_literal(command_source)};
    END $$;
    SELECT coalesce((SELECT created::text FROM command_attempt LIMIT 1), 'false')
      || '|' || encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM company_record WHERE source_id = {sql_literal(command_source)};
    COMMIT;
    """
    lines = query_lines(pool, sql)
    if len(lines) != 1:
        raise ServiceError("payment application command did not return a command receipt")
    fields = lines[0].split("|", 1)
    if len(fields) != 2:
        raise ServiceError("unexpected payment application command receipt shape")
    created = fields[0] == "true"
    try:
        receipt = json.loads(decode_hex(fields[1]))
    except json.JSONDecodeError as error:
        raise ServiceError("invalid payment application command receipt JSON") from error
    if not created and receipt.get("request") != request:
        raise CommandRejected("Idempotency-Key was already used for another request", 409)
    result = receipt.get("result")
    if not isinstance(result, dict):
        raise ServiceError("payment application command receipt has no result")
    return {"command": receipt, "payment_application": result, "idempotent_replay": not created}


def _required_text(body: dict[str, Any], key: str) -> str:
    value = body.get(key)
    if not isinstance(value, str) or not value.strip():
        raise CommandRejected(f"{key} is required", 422)
    value = value.strip()
    if not IDENTIFIER.fullmatch(value) and key not in {"summary", "reason"}:
        raise CommandRejected(f"{key} contains unsupported characters", 422)
    return value


def _expense_request(
    command_type: str,
    expense_id: str | None,
    body: dict[str, Any],
    actor_id: str,
) -> tuple[str, dict[str, Any]]:
    if command_type not in {"create", "submit", "approve", "reject", "resubmit"}:
        raise CommandRejected("unsupported expense command", 404)
    if command_type == "create":
        requested_id = body.get("expense_id")
        expense_id = requested_id if isinstance(requested_id, str) and requested_id.strip() else None
        if expense_id is None:
            expense_id = "EXP-" + uuid.uuid4().hex[:20]
        if not IDENTIFIER.fullmatch(expense_id):
            raise CommandRejected("expense_id contains unsupported characters", 422)
        employee_id = _required_text(body, "employee_id")
        summary = _required_text(body, "summary")
        currency = _required_text(body, "currency").upper()
        if not re.fullmatch(r"[A-Z]{3}", currency):
            raise CommandRejected("currency must be a three-letter code", 422)
        amount_minor = body.get("amount_minor")
        if isinstance(amount_minor, bool) or not isinstance(amount_minor, int) or amount_minor <= 0:
            raise CommandRejected("amount_minor must be a positive integer", 422)
        request = {
            "command_type": command_type,
            "expense_id": expense_id,
            "employee_id": employee_id,
            "summary": summary,
            "amount_minor": amount_minor,
            "currency": currency,
            "project_id": body.get("project_id"),
            "cost_subject": body.get("cost_subject"),
            "actor_id": actor_id,
        }
        return expense_id, request
    if expense_id is None or not IDENTIFIER.fullmatch(expense_id):
        raise CommandRejected("expense_id is required", 422)
    request = {
        "command_type": command_type,
        "expense_id": expense_id,
        "reason": body.get("reason", ""),
        "actor_id": actor_id,
    }
    return expense_id, request


def _existing_command(pool: PsqlPool, idempotency_key: str) -> dict[str, Any] | None:
    lines = query_lines(
        pool,
        f"""
        SELECT encode(convert_to(payload::text, 'UTF8'), 'hex')
        FROM company_record
        WHERE record_type = 'company_command'
          AND source_id = {sql_literal('moonproj:command:' + idempotency_key)}
        LIMIT 1
        """,
    )
    if not lines:
        return None
    try:
        value = json.loads(decode_hex(lines[0]))
    except json.JSONDecodeError as error:
        raise ServiceError("invalid stored company command receipt") from error
    if not isinstance(value, dict):
        raise ServiceError("stored company command receipt is not an object")
    return value


def _raw_delivery_rows(
    pool: PsqlPool,
    table: str,
    *,
    record_id: str | None,
    project_id: str | None,
    task_id: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    """Read a fixed, redacted ERP table without promoting it to company state."""

    if table not in {"proj_progress", "proj_output", "jd_task", "jd_task_report"}:
        raise ServiceError("unsupported delivery source table")
    for name, value in (("record_id", record_id), ("project_id", project_id), ("task_id", task_id)):
        if value is not None and not IDENTIFIER.fullmatch(value):
            raise ValueError(f"invalid {name}")
    predicates = [f"record_type = {sql_literal('legacy/raw/' + table)}"]
    if record_id is not None:
        predicates.append(f"record_id = {sql_literal(record_id)}")
    if project_id is not None:
        predicates.append(f"payload->>'proj_guid' = {sql_literal(project_id)}")
    if task_id is not None:
        if table == "jd_task":
            predicates.append(f"payload->>'task_guid' = {sql_literal(task_id)}")
        else:
            predicates.append(f"payload->>'task_guid' = {sql_literal(task_id)}")
    query = f"""
    SELECT encode(convert_to(record_id, 'UTF8'), 'hex'),
           encode(convert_to(source_id, 'UTF8'), 'hex'),
           encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM company_record
    WHERE {' AND '.join(predicates)}
    ORDER BY record_id
    LIMIT {max_rows}
    """
    rows: list[dict[str, Any]] = []
    for line in query_lines(pool, query):
        fields = line.split("|")
        if len(fields) != 3:
            raise ServiceError("unexpected delivery source row shape")
        try:
            payload = json.loads(decode_hex(fields[2]))
        except json.JSONDecodeError as error:
            raise ServiceError("invalid delivery source row JSON") from error
        if not isinstance(payload, dict):
            raise ServiceError("delivery source row payload is not an object")
        rows.append(
            {
                "record_id": decode_hex(fields[0]),
                "source_id": decode_hex(fields[1]),
                "payload": payload,
            }
        )
    return rows


def _latest_delivery_projection_rows(
    pool: PsqlPool,
    aggregate_type: str,
    aggregate_id: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    if not IDENTIFIER.fullmatch(aggregate_type):
        raise ValueError("invalid delivery aggregate type")
    if aggregate_id is not None and not IDENTIFIER.fullmatch(aggregate_id):
        raise ValueError("invalid delivery aggregate id")
    filters = [f"aggregate_type = {sql_literal(aggregate_type)}"]
    if aggregate_id is not None:
        filters.append(f"aggregate_id = {sql_literal(aggregate_id)}")
    query = f"""
    SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'),
           encode(convert_to(aggregate_id, 'UTF8'), 'hex'),
           revision::text,
           encode(convert_to(payload::text, 'UTF8'), 'hex'),
           encode(convert_to(source_event_id, 'UTF8'), 'hex')
    FROM (
      SELECT DISTINCT ON (aggregate_id)
             aggregate_type, aggregate_id, revision, payload, source_event_id
      FROM company_aggregate_projection
      WHERE {' AND '.join(filters)}
      ORDER BY aggregate_id, revision DESC
    ) latest
    ORDER BY aggregate_id
    LIMIT {max_rows}
    """
    result: list[dict[str, Any]] = []
    for line in query_lines(pool, query):
        fields = line.split("|")
        if len(fields) != 5:
            raise ServiceError("unexpected delivery projection shape")
        try:
            payload = json.loads(decode_hex(fields[3]))
        except json.JSONDecodeError as error:
            raise ServiceError("invalid delivery projection JSON") from error
        if not isinstance(payload, dict):
            raise ServiceError("delivery projection payload is not an object")
        result.append(
            {
                "aggregate_type": decode_hex(fields[0]),
                "aggregate_id": decode_hex(fields[1]),
                "revision": int(fields[2]),
                "payload": payload,
                "source_event_id": decode_hex(fields[4]),
            }
        )
    return result


def _delivery_text(payload: dict[str, Any], key: str, fallback: str = "") -> str:
    value = payload.get(key)
    if value is None:
        return fallback
    return str(value)


def _delivery_int(payload: dict[str, Any], key: str, fallback: int = 0) -> int:
    value = payload.get(key)
    if value is None or value == "":
        return fallback
    try:
        return int(round(float(value)))
    except (TypeError, ValueError) as error:
        raise ServiceError(f"invalid delivery numeric field: {key}") from error


def _delivery_source_fields(
    row: dict[str, Any],
    *,
    table: str,
) -> dict[str, Any]:
    payload = row["payload"]
    if table == "proj_progress":
        return {
            "progress_id": row["record_id"],
            "project_id": _delivery_text(payload, "proj_guid"),
            "building_no": _delivery_text(payload, "building_no"),
            "stage": _delivery_text(payload, "stage"),
            "plan_date": _delivery_text(payload, "plan_date"),
            "plan_pct": _delivery_text(payload, "plan_pct", "0"),
            "actual_pct": _delivery_text(payload, "actual_pct", "0"),
            "actual_date": _delivery_text(payload, "actual_date"),
            "contract_id": _delivery_text(payload, "contract_guid"),
            "milestone_id": _delivery_text(payload, "milestone_guid"),
            "state": _delivery_text(payload, "state", "pending"),
            "remark": _delivery_text(payload, "remark"),
            "reported_by": _delivery_text(payload, "reported_by"),
            "evidence_ids": [],
            "completed_value_minor": 0,
            "source_kind": "imported",
            "source_id": row["source_id"],
            "source_table": table,
        }
    if table == "proj_output":
        return {
            "output_id": row["record_id"],
            "output_code": _delivery_text(payload, "output_code"),
            "project_id": _delivery_text(payload, "proj_guid"),
            "contract_id": _delivery_text(payload, "contract_guid"),
            "period": _delivery_text(payload, "period"),
            "output_amount": _delivery_text(payload, "output_amount", "0"),
            "confirm_amount": _delivery_text(payload, "confirm_amount", "0"),
            "state": _delivery_text(payload, "state", "reported"),
            "remark": _delivery_text(payload, "remark"),
            "confirmed_by": _delivery_text(payload, "confirmed_by"),
            "confirmed_at": _delivery_text(payload, "confirmed_at"),
            "evidence_ids": [],
            "source_kind": "imported",
            "source_id": row["source_id"],
            "source_table": table,
        }
    if table == "jd_task":
        progress_pct = _delivery_int(payload, "progress_pct")
        return {
            "task_id": row["record_id"],
            "task_code": _delivery_text(payload, "task_code"),
            "task_name": _delivery_text(payload, "task_name"),
            "project_id": _delivery_text(payload, "proj_guid"),
            "task_type": _delivery_text(payload, "task_type", "task"),
            "parent_task_id": _delivery_text(payload, "parent_task_guid"),
            "plan_begin_date": _delivery_text(payload, "plan_begin_date"),
            "plan_end_date": _delivery_text(payload, "plan_end_date"),
            "actual_begin_date": _delivery_text(payload, "actual_begin_date"),
            "actual_end_date": _delivery_text(payload, "actual_end_date"),
            "progress_pct": str(progress_pct),
            "progress_bps": progress_pct * 100,
            "owner_id": _delivery_text(payload, "owner_guid"),
            "status": _delivery_text(payload, "status", "pending"),
            "remarks": _delivery_text(payload, "remarks"),
            "sort_order": _delivery_int(payload, "sort_order"),
            "source_kind": "imported",
            "source_id": row["source_id"],
            "source_table": table,
        }
    return {
        "report_id": row["record_id"],
        "task_id": _delivery_text(payload, "task_guid"),
        "project_id": "",
        "progress_pct": _delivery_text(payload, "progress_pct", "0"),
        "progress_bps": _delivery_int(payload, "progress_pct") * 100,
        "report_date": _delivery_text(payload, "report_date"),
        "summary": _delivery_text(payload, "summary"),
        "operator_id": _delivery_text(payload, "operator_guid"),
        "state": "observed",
        "source_kind": "imported",
        "source_id": row["source_id"],
        "source_table": table,
    }


def _delivery_projection_fields(
    row: dict[str, Any],
    *,
    family: str,
) -> dict[str, Any]:
    payload = row["payload"]
    if family == "progress":
        progress_bps = _delivery_int(payload, "actual_progress_bps", _delivery_int(payload, "progress_bps"))
        return {
            "progress_id": row["aggregate_id"],
            "project_id": _delivery_text(payload, "project_id"),
            "building_no": _delivery_text(payload, "building_no"),
            "stage": _delivery_text(payload, "stage"),
            "plan_date": _delivery_text(payload, "plan_date"),
            "plan_pct": str(_delivery_int(payload, "plan_pct_bps") / 100),
            "actual_pct": str(progress_bps / 100),
            "actual_date": _delivery_text(payload, "actual_date"),
            "contract_id": _delivery_text(payload, "contract_id"),
            "milestone_id": _delivery_text(payload, "milestone_id"),
            "state": _delivery_text(payload, "state", "draft"),
            "remark": _delivery_text(payload, "remark"),
            "reported_by": _delivery_text(payload, "actor_id"),
            "evidence_ids": payload.get("evidence_ids", []),
            "completed_value_minor": _delivery_int(payload, "completed_value_minor"),
            "source_kind": "command",
            "source_id": row["source_event_id"],
            "source_table": "company_command",
            "revision": row["revision"],
        }
    if family == "output":
        return {
            "output_id": row["aggregate_id"],
            "output_code": _delivery_text(payload, "output_code"),
            "project_id": _delivery_text(payload, "project_id"),
            "contract_id": _delivery_text(payload, "contract_id"),
            "period": _delivery_text(payload, "period"),
            "output_amount": _delivery_text(payload, "output_amount", "0"),
            "confirm_amount": _delivery_text(payload, "confirm_amount", "0"),
            "state": _delivery_text(payload, "state", "reported"),
            "remark": _delivery_text(payload, "remark"),
            "confirmed_by": _delivery_text(payload, "actor_id") if payload.get("state") == "confirmed" else "",
            "confirmed_at": _delivery_text(payload, "confirmed_at"),
            "evidence_ids": payload.get("evidence_ids", []),
            "source_kind": "command",
            "source_id": row["source_event_id"],
            "source_table": "company_command",
            "revision": row["revision"],
        }
    return {
        "report_id": row["aggregate_id"],
        "task_id": _delivery_text(payload, "task_id"),
        "project_id": _delivery_text(payload, "project_id"),
        "progress_pct": str(_delivery_int(payload, "progress_bps") / 100),
        "progress_bps": _delivery_int(payload, "progress_bps"),
        "report_date": _delivery_text(payload, "report_date"),
        "summary": _delivery_text(payload, "summary"),
        "operator_id": _delivery_text(payload, "actor_id"),
        "state": _delivery_text(payload, "state", "observed"),
        "evidence_ids": payload.get("evidence_ids", []),
        "source_kind": "command",
        "source_id": row["source_event_id"],
        "source_table": "company_command",
        "revision": row["revision"],
    }


def delivery_progress(
    pool: PsqlPool,
    progress_id: str | None,
    project_id: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    raw = [
        _delivery_source_fields(row, table="proj_progress")
        for row in _raw_delivery_rows(
            pool,
            "proj_progress",
            record_id=progress_id,
            project_id=project_id,
            task_id=None,
            max_rows=max_rows,
        )
    ]
    commands = [
        _delivery_projection_fields(row, family="progress")
        for row in _latest_delivery_projection_rows(pool, "delivery_progress", progress_id, max_rows)
    ]
    if project_id is not None:
        commands = [row for row in commands if row.get("project_id") == project_id]
    return raw + commands


def delivery_outputs(
    pool: PsqlPool,
    output_id: str | None,
    project_id: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    raw = [
        _delivery_source_fields(row, table="proj_output")
        for row in _raw_delivery_rows(
            pool,
            "proj_output",
            record_id=output_id,
            project_id=project_id,
            task_id=None,
            max_rows=max_rows,
        )
    ]
    commands = [
        _delivery_projection_fields(row, family="output")
        for row in _latest_delivery_projection_rows(pool, "delivery_output", output_id, max_rows)
    ]
    if project_id is not None:
        commands = [row for row in commands if row.get("project_id") == project_id]
    return raw + commands


def delivery_tasks(
    pool: PsqlPool,
    task_id: str | None,
    project_id: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    return [
        _delivery_source_fields(row, table="jd_task")
        for row in _raw_delivery_rows(
            pool,
            "jd_task",
            record_id=task_id,
            project_id=project_id,
            task_id=task_id,
            max_rows=max_rows,
        )
    ]


def delivery_task_reports(
    pool: PsqlPool,
    report_id: str | None,
    task_id: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    raw = [
        _delivery_source_fields(row, table="jd_task_report")
        for row in _raw_delivery_rows(
            pool,
            "jd_task_report",
            record_id=report_id,
            project_id=None,
            task_id=task_id,
            max_rows=max_rows,
        )
    ]
    commands = [
        _delivery_projection_fields(row, family="task_report")
        for row in _latest_delivery_projection_rows(pool, "task_report", report_id, max_rows)
    ]
    if task_id is not None:
        commands = [row for row in commands if row.get("task_id") == task_id]
    return raw + commands


def delivery_plan_summary(pool: PsqlPool, project_id: str, max_rows: int) -> dict[str, Any]:
    tasks = delivery_tasks(pool, None, project_id, max_rows)
    summary = {"done": 0, "in_progress": 0, "pending": 0, "overdue": 0, "blocked": 0, "total": len(tasks)}
    for task in tasks:
        state = str(task.get("status", "pending"))
        if state in summary:
            summary[state] += 1
        else:
            summary["pending"] += 1
    upcoming = sorted(
        [task for task in tasks if task.get("status") != "done"],
        key=lambda value: str(value.get("plan_end_date", "")),
    )[:3]
    return {
        "project_id": project_id,
        "summary": summary,
        "upcoming": [
            {
                "task_id": task.get("task_id", ""),
                "task_name": task.get("task_name", ""),
                "plan_end_date": task.get("plan_end_date", ""),
                "progress_pct": task.get("progress_pct", "0"),
                "delayed": False,
            }
            for task in upcoming
        ],
        "source_kind": "imported",
    }


def _plan_task_source_fields(task: dict[str, Any]) -> dict[str, Any]:
    plan_end = _report_date(str(task.get("plan_end_date", "")))
    actual_end = _report_date(str(task.get("actual_end_date", "")))
    today = date.today()
    delayed = bool(
        str(task.get("status", "")) == "overdue"
        or (
            plan_end is not None
            and str(task.get("status", "")) != "done"
            and plan_end < today
        )
    )
    actual_delay_days = None
    if plan_end is not None and actual_end is not None and actual_end > plan_end:
        actual_delay_days = (actual_end - plan_end).days
    return {
        "taskGuid": task.get("task_id", ""),
        "taskCode": task.get("task_code", ""),
        "taskName": task.get("task_name", ""),
        "taskType": task.get("task_type", "task"),
        "parentTaskGuid": task.get("parent_task_id", ""),
        "planBeginDate": task.get("plan_begin_date", ""),
        "planEndDate": task.get("plan_end_date", ""),
        "actualBeginDate": task.get("actual_begin_date", ""),
        "actualEndDate": task.get("actual_end_date", ""),
        "progressPct": task.get("progress_pct", "0"),
        "status": task.get("status", "pending"),
        "ownerGuid": task.get("owner_id", ""),
        "ownerName": task.get("owner_name", ""),
        "remarks": task.get("remarks", ""),
        "sortOrder": task.get("sort_order", 0),
        "delayed": delayed,
        "actualDelayDays": actual_delay_days,
        "sourceKind": "imported",
        "sourceId": task.get("source_id", ""),
    }


def plan_tasks(
    pool: PsqlPool,
    project_id: str,
    task_type: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    if task_type is not None and not IDENTIFIER.fullmatch(task_type):
        raise ValueError("invalid task_type")
    raw = _raw_delivery_rows(
        pool,
        "jd_task",
        record_id=None,
        project_id=project_id,
        task_id=None,
        max_rows=max_rows,
    )
    user_rows = _raw_source_rows(pool, "sys_user", max(max_rows, 100), PROJECT_SOURCE_TABLES)
    user_names = {
        str(row["payload"].get("user_id", row["record_id"])): str(
            row["payload"].get("emp_name") or row["payload"].get("user_name") or ""
        )
        for row in user_rows
    }
    tasks: list[dict[str, Any]] = []
    for row in raw:
        if task_type is not None and str(row["payload"].get("task_type") or "task") != task_type:
            continue
        source_task = _delivery_source_fields(row, table="jd_task")
        source_task["owner_name"] = user_names.get(str(source_task.get("owner_id") or ""), "")
        tasks.append(_plan_task_source_fields(source_task))
    tasks.sort(key=lambda value: (int(value.get("sortOrder", 0)), str(value.get("planBeginDate", ""))))
    return {
        "success": True,
        "code": 0,
        "data": tasks,
        "source_kind": "imported",
        "source_coverage": {"jd_task": len(raw)},
    }


def plan_task_detail(
    pool: PsqlPool,
    task_id: str,
    max_rows: int,
) -> dict[str, Any] | None:
    if not IDENTIFIER.fullmatch(task_id):
        raise ValueError("invalid task_id")
    # The project is not known until the source row is found; query the bounded
    # raw table by task identity rather than guessing a project.
    raw_rows = _raw_delivery_rows(
        pool,
        "jd_task",
        record_id=task_id,
        project_id=None,
        task_id=task_id,
        max_rows=max_rows,
    )
    if not raw_rows:
        return None
    user_rows = _raw_source_rows(pool, "sys_user", max(max_rows, 100), PROJECT_SOURCE_TABLES)
    user_names = {
        str(row["payload"].get("user_id", row["record_id"])): str(
            row["payload"].get("emp_name") or row["payload"].get("user_name") or ""
        )
        for row in user_rows
    }
    source_task = _delivery_source_fields(raw_rows[0], table="jd_task")
    source_task["owner_name"] = user_names.get(str(source_task.get("owner_id") or ""), "")
    task = _plan_task_source_fields(source_task)
    project_id = str(raw_rows[0]["payload"].get("proj_guid") or "")
    reports = [
        _delivery_source_fields(row, table="jd_task_report")
        for row in _raw_delivery_rows(
            pool,
            "jd_task_report",
            record_id=None,
            project_id=None,
            task_id=task_id,
            max_rows=max_rows,
        )
    ]
    project_name = ""
    if project_id:
        project_result = projects(pool, project_id, None, None, max_rows)
        if project_result["items"]:
            project_name = str(project_result["items"][0].get("project_name", ""))
    task["projGuid"] = project_id
    task["projName"] = project_name
    return {
        "success": True,
        "code": 0,
        "data": {
            "task": task,
            "reports": [
                {
                    "reportGuid": report.get("report_id", ""),
                    "reportDate": report.get("report_date", ""),
                    "progressPct": report.get("progress_pct", "0"),
                    "summary": report.get("summary", ""),
                    "operatorGuid": report.get("operator_id", ""),
                    "operatorName": user_names.get(str(report.get("operator_id") or ""), ""),
                    "sourceKind": "imported",
                }
                for report in reports
            ],
        },
        "source_kind": "imported",
        "source_coverage": {
            "jd_task": 1,
            "jd_task_report": len(reports),
        },
    }


def plan_summary(pool: PsqlPool, project_id: str, max_rows: int) -> dict[str, Any]:
    result = plan_tasks(pool, project_id, "key_node", max_rows)
    tasks = result["data"]
    summary = {"done": 0, "in_progress": 0, "pending": 0, "overdue": 0, "blocked": 0, "total": len(tasks)}
    for task in tasks:
        status = str(task.get("status", "pending"))
        if status in summary:
            summary[status] += 1
        else:
            summary["pending"] += 1
    upcoming = sorted(
        [task for task in tasks if task.get("status") != "done"],
        key=lambda value: str(value.get("planEndDate", "")),
    )[:3]
    return {
        "success": True,
        "code": 0,
        "data": {
            "summary": summary,
            "upcoming": [
                {
                    "taskGuid": task.get("taskGuid", ""),
                    "taskName": task.get("taskName", ""),
                    "planEndDate": task.get("planEndDate", ""),
                    "progressPct": task.get("progressPct", "0"),
                    "delayed": task.get("delayed", False),
                }
                for task in upcoming
            ],
        },
        "project_id": project_id,
        "source_kind": "imported",
        "source_coverage": result["source_coverage"],
    }


def project_lifecycle(pool: PsqlPool, project_id: str, max_rows: int) -> dict[str, Any] | None:
    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    result = projects(pool, project_id, None, None, max_rows)
    if not result["items"]:
        return None
    project = result["items"][0]
    return {
        "success": True,
        "code": 0,
        "data": {
            "project": {
                "projGuid": project["project_id"],
                "projCode": project["project_code"],
                "projName": project["project_name"],
                "buGuid": project["bu_guid"],
                "buName": project["bu_name"],
                "projStatus": project["proj_status"],
            },
            "stages": [
                {
                    "stageCode": stage["stage_code"],
                    "stageName": stage["stage_name"],
                    "stageOrder": stage["stage_order"],
                    "status": stage["status"],
                    "progressPct": stage["progress_pct"],
                    "plannedStart": stage["planned_start"],
                    "plannedEnd": stage["planned_end"],
                    "actualStart": stage["actual_start"],
                    "actualEnd": stage["actual_end"],
                    "sourceKind": "imported",
                }
                for stage in project["lifecycle"]
            ],
        },
        "source_kind": "imported",
        "source_coverage": {
            "ep_project": 1,
            "proj_lifecycle_stage": len(project["lifecycle"]),
            "proj_lifecycle_instance": result["source_coverage"].get("proj_lifecycle_instance", 0),
        },
    }


def business_units_tree(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    raw_units = _raw_source_rows(pool, "mu_business_unit", max(max_rows, 100), PROJECT_SOURCE_TABLES)
    payloads = [row["payload"] for row in raw_units]
    payloads.sort(key=lambda value: (int(value.get("level") or 0), str(value.get("bu_code") or "")))
    nodes: dict[str, dict[str, Any]] = {}
    for payload in payloads:
        guid = str(payload.get("bu_guid") or "")
        if not guid:
            continue
        nodes[guid] = {
            "buGuid": guid,
            "buCode": str(payload.get("bu_code") or ""),
            "buName": str(payload.get("bu_name") or ""),
            "legalName": str(payload.get("legal_name") or ""),
            "hierarchyCode": str(payload.get("hierarchy_code") or ""),
            "level": int(payload.get("level") or 0),
            "buType": str(payload.get("bu_type") or ""),
            "children": [],
            "sourceKind": "imported",
        }
    roots: list[dict[str, Any]] = []
    for payload in payloads:
        guid = str(payload.get("bu_guid") or "")
        node = nodes.get(guid)
        if node is None:
            continue
        parent_guid = str(payload.get("parent_guid") or "")
        parent = nodes.get(parent_guid)
        if parent is None:
            roots.append(node)
        else:
            parent["children"].append(node)
    return {
        "success": True,
        "code": 0,
        "data": roots,
        "source_kind": "imported",
        "source_coverage": {"mu_business_unit": len(raw_units)},
    }


def budget_cost_subjects(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    raw = _raw_source_rows(pool, "my_biz_param_option", max(max_rows, 100), BUDGET_SOURCE_TABLES)
    options = [
        row["payload"]
        for row in raw
        if str(row["payload"].get("param_name") or "") == "cost_subject"
        and bool(row["payload"].get("enabled", 0))
    ]
    options.sort(
        key=lambda value: (
            int(value.get("display_order") or 0),
            str(value.get("param_code") or ""),
        )
    )
    return {
        "success": True,
        "code": 0,
        "data": [
            {
                "code": str(option.get("param_code") or ""),
                "name": str(option.get("param_value") or ""),
                "sourceKind": "imported",
            }
            for option in options
        ],
        "source_kind": "imported",
        "source_coverage": {"my_biz_param_option": len(raw)},
    }


def budget_proceedings(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    raw = _raw_source_rows(pool, "vys_proceeding", max(max_rows, 100), BUDGET_SOURCE_TABLES)
    proceedings = [row["payload"] for row in raw if bool(row["payload"].get("enabled", 0))]
    proceedings.sort(
        key=lambda value: (
            str(value.get("proceeding_code") or ""),
            str(value.get("proceeding_guid") or ""),
        )
    )
    return {
        "success": True,
        "code": 0,
        "data": [
            {
                "guid": str(item.get("proceeding_guid") or ""),
                "code": str(item.get("proceeding_code") or ""),
                "name": str(item.get("proceeding_name") or ""),
                "sourceKind": "imported",
            }
            for item in proceedings
        ],
        "source_kind": "imported",
        "source_coverage": {"vys_proceeding": len(raw)},
    }


INVESTMENT_DIMENSIONS = [
    {"code": "key_point", "name": "项目关键节点", "icon": "📅"},
    {"code": "tax", "name": "项目税费", "icon": "💸"},
    {"code": "financing", "name": "项目融资", "icon": "🏦"},
    {"code": "investment", "name": "项目投资及其他", "icon": "💰"},
    {"code": "carry_over", "name": "项目结转", "icon": "📈"},
]


def _investment_source_rows(
    pool: PsqlPool,
    table: str,
    max_rows: int,
) -> list[dict[str, Any]]:
    return _raw_source_rows(pool, table, max(max_rows, 100), INVESTMENT_SOURCE_TABLES)


def investment_versions(
    pool: PsqlPool,
    project_id: str,
    max_rows: int,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    rows = [
        row["payload"]
        for row in _investment_source_rows(pool, "tzsy_version", max_rows)
        if str(row["payload"].get("proj_guid") or "") == project_id
        and not row["payload"].get("deleted_at")
    ]
    users = {
        str(row["payload"].get("user_id", row["record_id"])): str(
            row["payload"].get("emp_name") or row["payload"].get("user_name") or ""
        )
        for row in _investment_source_rows(pool, "sys_user", max_rows)
    }
    rows.sort(key=lambda value: (-int(value.get("version_no") or 0), str(value.get("version_guid") or "")))
    return {
        "success": True,
        "code": 0,
        "data": [
            {
                "versionGuid": str(row.get("version_guid") or ""),
                "versionName": str(row.get("version_name") or ""),
                "versionNo": int(row.get("version_no") or 0),
                "isCurrent": bool(row.get("is_current", 0)),
                "creatorName": users.get(str(row.get("created_by") or ""), ""),
                "createdAt": str(row.get("created_at") or ""),
                "remark": str(row.get("remark") or ""),
                "sourceKind": "imported",
            }
            for row in rows
        ],
        "source_kind": "imported",
        "source_coverage": {"tzsy_version": len(rows)},
    }


def investment_indices(
    pool: PsqlPool,
    version_id: str,
    dimension: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(version_id):
        raise ValueError("invalid version_id")
    if dimension is not None and not IDENTIFIER.fullmatch(dimension):
        raise ValueError("invalid investment dimension")
    rows = [
        row["payload"]
        for row in _investment_source_rows(pool, "tzsy_plan_index", max_rows)
        if str(row["payload"].get("version_guid") or "") == version_id
        and not row["payload"].get("deleted_at")
        and (dimension is None or str(row["payload"].get("dimension") or "") == dimension)
    ]
    rows.sort(key=lambda value: (str(value.get("dimension") or ""), int(value.get("sort_order") or 0)))
    by_dimension: dict[str, dict[str, Any]] = {
        value["code"]: {**value, "items": []} for value in INVESTMENT_DIMENSIONS
    }
    for row in rows:
        group = by_dimension.get(str(row.get("dimension") or ""))
        if group is None:
            continue
        group["items"].append(
            {
                "indexGuid": str(row.get("index_guid") or ""),
                "fullCode": str(row.get("full_code") or ""),
                "indexName": str(row.get("index_name") or ""),
                "parentCode": str(row.get("parent_code") or ""),
                "unit": str(row.get("unit") or ""),
                "indexValue": row.get("index_value"),
                "remark": str(row.get("remark") or ""),
                "sourceKind": "imported",
            }
        )
    return {
        "success": True,
        "code": 0,
        "data": list(by_dimension.values()),
        "source_kind": "imported",
        "source_coverage": {"tzsy_plan_index": len(rows)},
    }


def investment_profit_summary(
    pool: PsqlPool,
    project_id: str,
    max_rows: int,
) -> dict[str, Any]:
    versions = investment_versions(pool, project_id, max_rows)["data"]
    current = next((version for version in versions if version.get("isCurrent")), None)
    if current is None:
        return {"success": True, "code": 0, "data": None, "source_kind": "imported"}
    rows = [
        row["payload"]
        for row in _investment_source_rows(pool, "tzsy_plan_index", max_rows)
        if str(row["payload"].get("version_guid") or "") == current["versionGuid"]
        and not row["payload"].get("deleted_at")
    ]
    values = {
        str(row.get("full_code") or ""): _report_float(row, "index_value")
        for row in rows
    }
    revenue = values.get("CO.Revenue")
    gross_profit = values.get("CO.GrossProfit")
    net_profit = values.get("CO.NetProfit")
    return {
        "success": True,
        "code": 0,
        "data": {
            "versionGuid": current["versionGuid"],
            "versionName": current["versionName"],
            "revenue": revenue,
            "cost": values.get("CO.Cost"),
            "grossProfit": gross_profit,
            "netProfit": net_profit,
            "irr": values.get("CO.IRR"),
            "npv": values.get("CO.NPV"),
            "grossProfitMargin": round(gross_profit / revenue * 100, 2) if revenue and gross_profit is not None else None,
            "netProfitMargin": round(net_profit / revenue * 100, 2) if revenue and net_profit is not None else None,
            "investment": values.get("Inv.Total"),
            "taxTotal": values.get("Tax.Total"),
            "finTotal": values.get("Fin.Total"),
            "sourceKind": "imported",
        },
        "source_kind": "imported",
        "source_coverage": {"tzsy_version": len(versions), "tzsy_plan_index": len(rows)},
    }


def _shift_plan_date(value: Any, delay_days: int) -> str:
    parsed = _report_date(str(value or ""))
    if parsed is None:
        return str(value or "")
    return (parsed + timedelta(days=delay_days)).isoformat()


def plan_delay_impact(
    pool: PsqlPool,
    task_id: str,
    delay_days: int,
    max_rows: int,
) -> dict[str, Any] | None:
    if not IDENTIFIER.fullmatch(task_id):
        raise ValueError("invalid task_id")
    if delay_days < -3650 or delay_days > 3650:
        raise ValueError("delay_days is outside the supported range")
    raw_rows = _raw_delivery_rows(
        pool,
        "jd_task",
        record_id=task_id,
        project_id=None,
        task_id=task_id,
        max_rows=max_rows,
    )
    if not raw_rows:
        return None
    source = raw_rows[0]["payload"]
    project_id = str(source.get("proj_guid") or "")
    old_end = str(source.get("plan_end_date") or "")
    tasks = plan_tasks(pool, project_id, None, max_rows)["data"]
    old_end_date = _report_date(old_end)
    followers = []
    for task in tasks:
        begin = _report_date(str(task.get("planBeginDate") or ""))
        if begin is None or old_end_date is None or begin < old_end_date:
            continue
        followers.append(
            {
                "taskGuid": task.get("taskGuid", ""),
                "taskName": task.get("taskName", ""),
                "taskType": task.get("taskType", "task"),
                "oldBegin": task.get("planBeginDate", ""),
                "oldEnd": task.get("planEndDate", ""),
                "newBegin": _shift_plan_date(task.get("planBeginDate"), delay_days),
                "newEnd": _shift_plan_date(task.get("planEndDate"), delay_days),
                "sourceKind": "imported",
            }
        )
    followers.sort(key=lambda value: (str(value["oldBegin"]), str(value["taskGuid"])))
    return {
        "success": True,
        "code": 0,
        "data": {
            "source": {
                "taskName": str(source.get("task_name") or ""),
                "oldEnd": old_end,
                "newEnd": _shift_plan_date(old_end, delay_days),
                "delayDays": delay_days,
            },
            "impact": followers,
            "impactCount": len(followers),
        },
        "source_kind": "imported",
        "source_coverage": {"jd_task": len(tasks)},
    }


def delivery_overview(pool: PsqlPool, project_id: str, max_rows: int) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    tasks = delivery_tasks(pool, None, project_id, max_rows)
    task_ids = {str(task.get("task_id", "")) for task in tasks}
    reports = [
        report
        for report in delivery_task_reports(pool, None, None, max_rows)
        if str(report.get("task_id", "")) in task_ids
    ]
    return {
        "project_id": project_id,
        "progress": delivery_progress(pool, None, project_id, max_rows),
        "outputs": delivery_outputs(pool, None, project_id, max_rows),
        "tasks": tasks,
        "reports": reports,
        "plan_summary": delivery_plan_summary(pool, project_id, max_rows),
        "source_kind": "imported_or_command",
    }


REPORT_SOURCE_TABLES = {
    "ep_project",
    "mu_business_unit",
    "cb_cost",
    "cb_contract",
    "cb_htfkplan",
    "cb_htfk_apply",
    "srm_provider",
    "srm_category",
    "wf_process_instance",
    "wf_step_action",
    "proj_lifecycle_stage",
    "proj_lifecycle_instance",
}


def _raw_source_rows(
    pool: PsqlPool,
    table: str,
    max_rows: int,
    allowed_tables: set[str],
) -> list[dict[str, Any]]:
    """Read a fixed source table without promoting it to company state."""

    if table not in allowed_tables:
        raise ServiceError("unsupported source table")
    query = f"""
    SELECT encode(convert_to(record_id, 'UTF8'), 'hex'),
           encode(convert_to(source_id, 'UTF8'), 'hex'),
           encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM company_record
    WHERE record_type = {sql_literal('legacy/raw/' + table)}
    ORDER BY record_id
    LIMIT {max_rows}
    """
    result: list[dict[str, Any]] = []
    for line in query_lines(pool, query):
        fields = line.split("|")
        if len(fields) != 3:
            raise ServiceError("unexpected source row shape")
        try:
            payload = json.loads(decode_hex(fields[2]))
        except json.JSONDecodeError as error:
            raise ServiceError("invalid source row JSON") from error
        if not isinstance(payload, dict):
            raise ServiceError("source row payload is not an object")
        result.append(
            {
                "record_id": decode_hex(fields[0]),
                "source_id": decode_hex(fields[1]),
                "payload": payload,
            }
        )
    return result


def _raw_report_rows(pool: PsqlPool, table: str, max_rows: int) -> list[dict[str, Any]]:
    return _raw_source_rows(pool, table, max_rows, REPORT_SOURCE_TABLES)


def _report_float(payload: dict[str, Any], key: str, fallback: float = 0.0) -> float:
    value = payload.get(key)
    if value is None or value == "":
        return fallback
    try:
        return float(value)
    except (TypeError, ValueError) as error:
        raise ServiceError(f"invalid report numeric field: {key}") from error


def _report_text(payload: dict[str, Any], key: str, fallback: str = "") -> str:
    value = payload.get(key)
    return fallback if value is None else str(value)


def _report_date(value: Any) -> date | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        return date.fromisoformat(value.strip()[:10])
    except ValueError:
        return None


PROJECT_SOURCE_TABLES = {
    "ep_project",
    "mu_business_unit",
    "proj_lifecycle_stage",
    "proj_lifecycle_instance",
    "jd_task",
    "jd_task_report",
    "sys_user",
}

BUDGET_SOURCE_TABLES = {
    "my_biz_param_option",
    "vys_proceeding",
}

INVESTMENT_SOURCE_TABLES = {
    "ep_project",
    "mu_business_unit",
    "sys_user",
    "tzsy_version",
    "tzsy_plan_index",
}


def projects(
    pool: PsqlPool,
    project_id: str | None,
    status: str | None,
    keyword: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if project_id is not None and not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    if status is not None and len(status) > 64:
        raise ValueError("invalid project status")
    if keyword is not None and len(keyword) > 128:
        raise ValueError("invalid project keyword")
    coverage = {
        table: len(_raw_source_rows(pool, table, max_rows, PROJECT_SOURCE_TABLES))
        for table in sorted(PROJECT_SOURCE_TABLES)
    }
    raw_projects = _raw_source_rows(pool, "ep_project", max_rows, PROJECT_SOURCE_TABLES)
    raw_units = _raw_source_rows(pool, "mu_business_unit", max(max_rows, 100), PROJECT_SOURCE_TABLES)
    raw_stages = _raw_source_rows(pool, "proj_lifecycle_stage", max(max_rows, 100), PROJECT_SOURCE_TABLES)
    raw_instances = _raw_source_rows(
        pool,
        "proj_lifecycle_instance",
        max(max_rows, 500),
        PROJECT_SOURCE_TABLES,
    )
    raw_tasks = _raw_source_rows(pool, "jd_task", max(max_rows, 500), PROJECT_SOURCE_TABLES)
    raw_reports = _raw_source_rows(pool, "jd_task_report", max(max_rows, 500), PROJECT_SOURCE_TABLES)
    raw_users = _raw_source_rows(pool, "sys_user", max(max_rows, 100), PROJECT_SOURCE_TABLES)
    units: dict[str, dict[str, Any]] = {}
    for row in raw_units:
        payload = row["payload"]
        units[str(payload.get("bu_guid", row["record_id"]))] = payload
    stages = sorted(
        [row["payload"] for row in raw_stages],
        key=lambda value: (int(value.get("stage_order") or 0), str(value.get("stage_code", ""))),
    )
    instances: dict[tuple[str, str], dict[str, Any]] = {}
    for row in raw_instances:
        payload = row["payload"]
        instances[(str(payload.get("proj_guid", "")), str(payload.get("stage_code", "")))] = payload
    user_names = {
        str(row["payload"].get("user_id", row["record_id"])): str(
            row["payload"].get("emp_name") or row["payload"].get("user_name") or ""
        )
        for row in raw_users
    }
    tasks_by_project: dict[str, list[dict[str, Any]]] = {}
    for row in raw_tasks:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        project_key = str(payload.get("proj_guid", ""))
        if not project_key:
            continue
        task = {
            "task_id": str(payload.get("task_guid", row["record_id"])),
            "task_code": str(payload.get("task_code") or ""),
            "task_name": str(payload.get("task_name") or ""),
            "task_type": str(payload.get("task_type") or "task"),
            "parent_task_id": str(payload.get("parent_task_guid") or ""),
            "plan_begin_date": str(payload.get("plan_begin_date") or ""),
            "plan_end_date": str(payload.get("plan_end_date") or ""),
            "actual_begin_date": str(payload.get("actual_begin_date") or ""),
            "actual_end_date": str(payload.get("actual_end_date") or ""),
            "progress_pct": str(payload.get("progress_pct") if payload.get("progress_pct") is not None else 0),
            "status": str(payload.get("status") or "pending"),
            "owner_id": str(payload.get("owner_guid") or ""),
            "owner_name": user_names.get(str(payload.get("owner_guid") or ""), ""),
            "remarks": str(payload.get("remarks") or ""),
            "sort_order": int(payload.get("sort_order") or 0),
            "source_kind": "imported",
        }
        tasks_by_project.setdefault(project_key, []).append(task)
    for values in tasks_by_project.values():
        values.sort(key=lambda value: (int(value["sort_order"]), str(value["plan_begin_date"]), str(value["task_id"])))
    reports_by_task: dict[str, list[dict[str, Any]]] = {}
    for row in raw_reports:
        payload = row["payload"]
        task_key = str(payload.get("task_guid", ""))
        if not task_key:
            continue
        reports_by_task.setdefault(task_key, []).append(
            {
                "report_id": str(payload.get("report_guid", row["record_id"])),
                "report_date": str(payload.get("report_date") or ""),
                "progress_pct": str(payload.get("progress_pct") if payload.get("progress_pct") is not None else 0),
                "summary": str(payload.get("summary") or ""),
                "operator_id": str(payload.get("operator_guid") or ""),
                "operator_name": user_names.get(str(payload.get("operator_guid") or ""), ""),
                "source_kind": "imported",
            }
        )
    for values in reports_by_task.values():
        values.sort(key=lambda value: (str(value["report_date"]), str(value["report_id"])), reverse=True)
    items: list[dict[str, Any]] = []
    for row in raw_projects:
        payload = row["payload"]
        pid = str(payload.get("proj_guid", row["record_id"]))
        if payload.get("deleted_at"):
            continue
        if project_id is not None and pid != project_id:
            continue
        if status is not None and str(payload.get("proj_status") or "") != status:
            continue
        if keyword is not None:
            needle = keyword.casefold()
            if needle not in str(payload.get("proj_name") or "").casefold() and needle not in str(
                payload.get("proj_code") or ""
            ).casefold():
                continue
        lifecycle: list[dict[str, Any]] = []
        current_stage = ""
        last_done = ""
        for stage in stages:
            code = str(stage.get("stage_code") or "")
            instance = instances.get((pid, code), {})
            stage_status = str(instance.get("status") or "pending")
            if stage_status == "in_progress" and not current_stage:
                current_stage = str(stage.get("stage_name") or code)
            if stage_status == "done":
                last_done = str(stage.get("stage_name") or code)
            lifecycle.append(
                {
                    "stage_code": code,
                    "stage_name": str(stage.get("stage_name") or code),
                    "stage_order": int(stage.get("stage_order") or 0),
                    "status": stage_status,
                    "progress_pct": str(instance.get("progress_pct") if instance.get("progress_pct") is not None else 0),
                    "planned_start": str(instance.get("planned_start") or ""),
                    "planned_end": str(instance.get("planned_end") or ""),
                    "actual_start": str(instance.get("actual_start") or ""),
                    "actual_end": str(instance.get("actual_end") or ""),
                    "source_kind": "imported",
                }
            )
        project_tasks = tasks_by_project.get(pid, [])
        status_counts: dict[str, int] = {}
        for task in project_tasks:
            task_status = str(task["status"])
            status_counts[task_status] = status_counts.get(task_status, 0) + 1
        items.append(
            {
                "project_id": pid,
                "project_code": str(payload.get("proj_code") or pid),
                "project_name": str(payload.get("proj_name") or pid),
                "project_short_name": str(payload.get("proj_short_name") or ""),
                "bu_guid": str(payload.get("bu_guid") or ""),
                "bu_name": str(units.get(str(payload.get("bu_guid") or ""), {}).get("bu_name") or ""),
                "level": int(payload.get("level") or 0),
                "level_code": str(payload.get("level_code") or ""),
                "if_end": bool(payload.get("if_end", 0)),
                "begin_date": str(payload.get("begin_date") or ""),
                "end_date": str(payload.get("end_date") or ""),
                "proj_status": str(payload.get("proj_status") or ""),
                "created_at": str(payload.get("created_at") or ""),
                "current_stage": current_stage or last_done,
                "task_count": len(project_tasks),
                "task_status_counts": status_counts,
                "lifecycle": lifecycle,
                "tasks": project_tasks,
                "reports": [
                    report
                    for task in project_tasks
                    for report in reports_by_task.get(str(task["task_id"]), [])
                ],
                "source_kind": "imported",
            }
        )
    items.sort(key=lambda value: (str(value["project_code"]), str(value["project_id"])))
    return {
        "items": items,
        "source_kind": "imported",
        "source_coverage": coverage,
        "missing_source_tables": [table for table, count in coverage.items() if count == 0],
    }


WORKFLOW_SOURCE_TABLES = {
    "wf_process_def",
    "wf_step_def",
    "wf_step_assignee",
    "wf_process_instance",
    "wf_step_action",
}


def _workflow_rows(
    pool: PsqlPool,
    table: str,
    max_rows: int,
) -> list[dict[str, Any]]:
    return _raw_source_rows(
        pool,
        table,
        min(max_rows, 5000),
        WORKFLOW_SOURCE_TABLES,
    )


def workflow_process_defs(
    pool: PsqlPool,
    process_key: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if process_key is not None and not IDENTIFIER.fullmatch(process_key):
        raise ValueError("invalid process_key")
    coverage = {
        table: len(_workflow_rows(pool, table, max_rows))
        for table in sorted(WORKFLOW_SOURCE_TABLES)
    }
    process_rows = _workflow_rows(pool, "wf_process_def", max_rows)
    step_rows = _workflow_rows(pool, "wf_step_def", max(max_rows, 500))
    assignee_rows = _workflow_rows(pool, "wf_step_assignee", max(max_rows, 500))
    assignees_by_step: dict[str, list[dict[str, Any]]] = {}
    for row in assignee_rows:
        payload = row["payload"]
        step_guid = str(payload.get("step_guid", ""))
        if not step_guid:
            continue
        assignees_by_step.setdefault(step_guid, []).append(
            {
                "assignee_guid": str(payload.get("assignee_guid", row["record_id"])),
                "user_guid": str(payload.get("assignee_user_guid", "")),
                "weight": int(payload.get("weight") or 1),
                "source_kind": "imported",
            }
        )
    steps_by_process: dict[str, list[dict[str, Any]]] = {}
    for row in step_rows:
        payload = row["payload"]
        process_guid = str(payload.get("process_guid", ""))
        if not process_guid:
            continue
        step_guid = str(payload.get("step_guid", row["record_id"]))
        steps_by_process.setdefault(process_guid, []).append(
            {
                "step_guid": step_guid,
                "step_key": str(payload.get("step_key", "")),
                "step_order": int(payload.get("step_order") or 0),
                "step_type": int(payload.get("step_type") or 0),
                "step_name": str(payload.get("step_name", "")),
                "threshold": int(payload.get("threshold") or 1),
                "remind_days": payload.get("remind_days"),
                "warn_days": payload.get("warn_days"),
                "assignees": assignees_by_step.get(step_guid, []),
                "source_kind": "imported",
            }
        )
    items: list[dict[str, Any]] = []
    for row in process_rows:
        payload = row["payload"]
        key = str(payload.get("process_key", ""))
        if process_key is not None and key != process_key:
            continue
        process_guid = str(payload.get("process_guid", row["record_id"]))
        steps = sorted(
            steps_by_process.get(process_guid, []),
            key=lambda value: (int(value["step_order"]), str(value["step_guid"])),
        )
        items.append(
            {
                "process_guid": process_guid,
                "process_key": key,
                "process_name": str(payload.get("process_name", key)),
                "biz_type": str(payload.get("biz_type", "")),
                "is_active": bool(payload.get("is_active", 0)),
                "is_mandatory": bool(payload.get("is_mandatory", 0)),
                "step_count": len(steps),
                "instances_available": coverage["wf_process_instance"],
                "actions_available": coverage["wf_step_action"],
                "steps": steps,
                "source_kind": "imported",
            }
        )
    items.sort(key=lambda value: (str(value["process_key"]), str(value["process_guid"])))
    return {
        "items": items,
        "source_kind": "imported",
        "source_coverage": coverage,
        "missing_source_tables": [table for table, count in coverage.items() if count == 0],
        "instances_available": coverage["wf_process_instance"],
        "actions_available": coverage["wf_step_action"],
    }


LOAN_SOURCE_TABLES = {
    "vcb_loan_simple",
    "cb_loan_offset",
    "sys_user",
    "mu_business_unit",
    "ep_project",
}


def loans(
    pool: PsqlPool,
    loan_id: str | None,
    apply_state: str | None,
    max_rows: int,
) -> list[dict[str, Any]]:
    if loan_id is not None and not IDENTIFIER.fullmatch(loan_id):
        raise ValueError("invalid loan_id")
    if apply_state is not None and len(apply_state) > 64:
        raise ValueError("invalid apply_state")
    loan_rows = _raw_source_rows(pool, "vcb_loan_simple", max_rows, LOAN_SOURCE_TABLES)
    offset_rows = _raw_source_rows(pool, "cb_loan_offset", max_rows, LOAN_SOURCE_TABLES)
    users = {
        str(row["payload"].get("user_id", row["record_id"])): row["payload"]
        for row in _raw_source_rows(pool, "sys_user", max_rows, LOAN_SOURCE_TABLES)
    }
    departments = {
        str(row["payload"].get("bu_guid", row["record_id"])): row["payload"]
        for row in _raw_source_rows(pool, "mu_business_unit", max_rows, LOAN_SOURCE_TABLES)
    }
    projects = {
        str(row["payload"].get("proj_guid", row["record_id"])): row["payload"]
        for row in _raw_source_rows(pool, "ep_project", max_rows, LOAN_SOURCE_TABLES)
    }
    offsets_by_loan: dict[str, list[dict[str, Any]]] = {}
    for row in offset_rows:
        payload = row["payload"]
        offset_loan_id = _report_text(payload, "loan_guid")
        operator_id = _report_text(payload, "operator_guid")
        offsets_by_loan.setdefault(offset_loan_id, []).append(
            {
                "offset_id": _report_text(payload, "offset_guid", row["record_id"]),
                "offset_amount": _report_float(payload, "offset_amount"),
                "offset_date": _report_text(payload, "offset_date"),
                "related_expense_id": _report_text(payload, "related_expense_guid"),
                "remark": _report_text(payload, "remark"),
                "operator_name": _report_text(users.get(operator_id, {}), "emp_name", operator_id),
                "source_kind": "imported",
                "source_id": row["source_id"],
            }
        )
    result: list[dict[str, Any]] = []
    for row in sorted(
        loan_rows,
        key=lambda value: _report_text(value["payload"], "created_at"),
        reverse=True,
    ):
        payload = row["payload"]
        current_id = _report_text(payload, "loan_guid", row["record_id"])
        state = _report_text(payload, "apply_state")
        if loan_id is not None and current_id != loan_id:
            continue
        if apply_state is not None and state != apply_state:
            continue
        employee_id = _report_text(payload, "applied_by")
        department_id = _report_text(payload, "apply_dept_guid")
        project_id = _report_text(payload, "proj_guid")
        amount = _report_float(payload, "loan_amount")
        balance = _report_float(payload, "balance_amount")
        remain = _report_float(payload, "remain_amount", amount - balance)
        result.append(
            {
                "loan_id": current_id,
                "loan_code": _report_text(payload, "loan_code", current_id),
                "subject": _report_text(payload, "subject"),
                "apply_state": state,
                "loan_amount": amount,
                "balance_amount": balance,
                "remain_amount": remain,
                "amount_display": f"¥{amount:,.2f}",
                "remain_amount_display": f"¥{remain:,.2f}",
                "applied_by": employee_id,
                "applied_by_name": _report_text(users.get(employee_id, {}), "emp_name", employee_id),
                "apply_dept_guid": department_id,
                "apply_dept_name": _report_text(departments.get(department_id, {}), "bu_name", department_id),
                "project_id": project_id,
                "project_name": _report_text(projects.get(project_id, {}), "proj_name", project_id),
                "apply_date": _report_text(payload, "apply_date"),
                "pay_unit": _report_text(payload, "pay_unit"),
                "process_instance_id": _report_text(payload, "process_instance_guid"),
                "offsets": offsets_by_loan.get(current_id, []),
                "source_kind": "imported",
                "source_id": row["source_id"],
                "source_table": "vcb_loan_simple",
            }
        )
    command_offset_rows: list[dict[str, Any]] = []
    command_offset_query = f"""
    SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'),
           revision::text,
           encode(convert_to(payload::text, 'UTF8'), 'hex'),
           encode(convert_to(source_event_id, 'UTF8'), 'hex')
    FROM company_aggregate_projection
    WHERE aggregate_type = 'loan_offset'
      AND payload->>'source_kind' = 'command'
    ORDER BY aggregate_id, revision DESC
    LIMIT {max_rows}
    """
    for line in query_lines(pool, command_offset_query):
        fields = line.split("|")
        if len(fields) != 4:
            raise ServiceError("unexpected loan offset projection shape")
        try:
            payload = json.loads(decode_hex(fields[2]))
        except json.JSONDecodeError as error:
            raise ServiceError("invalid loan offset projection JSON") from error
        if not isinstance(payload, dict):
            raise ServiceError("loan offset projection payload is not an object")
        command_offset_rows.append(
            {
                "offset_id": decode_hex(fields[0]),
                "payload": payload,
                "source_event_id": decode_hex(fields[3]),
            }
        )
    command_offsets_by_loan: dict[str, list[dict[str, Any]]] = {}
    for row in command_offset_rows:
        payload = row["payload"]
        offset_loan_id = _report_text(payload, "loan_id")
        amount_minor = int(payload.get("offset_amount_minor", 0))
        command_offsets_by_loan.setdefault(offset_loan_id, []).append(
            {
                "offset_id": row["offset_id"],
                "offset_amount": amount_minor / 100,
                "offset_date": _report_text(payload, "offset_date"),
                "related_expense_id": _report_text(payload, "related_expense_id"),
                "remark": _report_text(payload, "remark"),
                "operator_name": _report_text(payload, "operator_id"),
                "source_kind": "command",
                "source_id": row["source_event_id"],
            }
        )
    command_query = f"""
    SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'),
           revision::text,
           encode(convert_to(payload::text, 'UTF8'), 'hex'),
           encode(convert_to(source_event_id, 'UTF8'), 'hex')
    FROM (
      SELECT DISTINCT ON (aggregate_id)
             aggregate_id, revision, payload, source_event_id
      FROM company_aggregate_projection
      WHERE aggregate_type = 'employee_advance'
        AND payload->>'source_kind' = 'command'
      ORDER BY aggregate_id, revision DESC
    ) latest
    ORDER BY aggregate_id
    LIMIT {max_rows}
    """
    for line in query_lines(pool, command_query):
        fields = line.split("|")
        if len(fields) != 4:
            raise ServiceError("unexpected loan command projection shape")
        try:
            payload = json.loads(decode_hex(fields[2]))
        except json.JSONDecodeError as error:
            raise ServiceError("invalid loan command projection JSON") from error
        if not isinstance(payload, dict):
            raise ServiceError("loan command projection payload is not an object")
        current_id = decode_hex(fields[0])
        state = _report_text(payload, "apply_state", "Draft")
        if loan_id is not None and current_id != loan_id:
            continue
        if apply_state is not None and state != apply_state:
            continue
        amount_minor = int(payload.get("loan_amount_minor", 0))
        balance_minor = int(payload.get("balance_amount_minor", 0))
        remain_minor = int(payload.get("remain_amount_minor", amount_minor - balance_minor))
        command_offsets = command_offsets_by_loan.get(current_id, [])
        result.append(
            {
                "loan_id": current_id,
                "loan_code": _report_text(payload, "loan_code", current_id),
                "subject": _report_text(payload, "subject"),
                "apply_state": state,
                "loan_amount": amount_minor / 100,
                "balance_amount": balance_minor / 100,
                "remain_amount": remain_minor / 100,
                "amount_display": f"¥{amount_minor / 100:,.2f}",
                "remain_amount_display": f"¥{remain_minor / 100:,.2f}",
                "applied_by": _report_text(payload, "applied_by"),
                "applied_by_name": _report_text(payload, "applied_by"),
                "apply_dept_guid": _report_text(payload, "apply_dept_guid"),
                "apply_dept_name": _report_text(payload, "apply_dept_guid"),
                "project_id": _report_text(payload, "proj_guid"),
                "project_name": _report_text(payload, "proj_guid"),
                "apply_date": _report_text(payload, "apply_date"),
                "pay_unit": _report_text(payload, "pay_unit"),
                "process_instance_id": _report_text(payload, "process_instance_guid"),
                "offsets": command_offsets,
                "source_kind": "command",
                "source_id": decode_hex(fields[3]),
                "source_table": "employee_advance",
                "currency": _report_text(payload, "currency", "CNY"),
            }
        )
    result.sort(key=lambda item: str(item.get("apply_date", "")), reverse=True)
    return result[:max_rows]


def _loan_required_text(
    body: dict[str, Any],
    key: str,
    *,
    identifier: bool = False,
) -> str:
    value = body.get(key)
    if not isinstance(value, str) or not value.strip():
        raise CommandRejected(f"{key} is required", 422)
    cleaned = value.strip()
    if identifier and not IDENTIFIER.fullmatch(cleaned):
        raise CommandRejected(f"{key} contains unsupported characters", 422)
    return cleaned


def _loan_amount_minor(body: dict[str, Any], key: str = "amount_minor", *, required: bool = True) -> int:
    value = body.get(key)
    if value is None and key == "amount_minor":
        value = body.get("loan_amount")
        if value is not None:
            try:
                value = int((Decimal(str(value)) * 100).quantize(Decimal("1")))
            except (InvalidOperation, ValueError, TypeError) as error:
                raise CommandRejected("loan_amount must be a decimal number", 422) from error
    if value is None:
        if required:
            raise CommandRejected(f"{key} is required", 422)
        return 0
    try:
        amount = int(value)
    except (TypeError, ValueError) as error:
        raise CommandRejected(f"{key} must be an integer amount in minor units", 422) from error
    if amount <= 0:
        raise CommandRejected("loan amount must be > 0", 422)
    return amount


def _loan_authority(
    body: dict[str, Any],
    *,
    actor_id: str,
    principal_id: str,
    employee_id: str,
    capability: str,
    amount_minor: int,
) -> dict[str, Any]:
    value = body.get("authority")
    if not isinstance(value, dict):
        raise CommandRejected("authority grant is required", 403)
    if value.get("active") is not True:
        raise CommandRejected("authority grant is inactive", 403)
    if value.get("principal_id") != principal_id:
        raise CommandRejected("authority grant principal does not match loan", 403)
    if value.get("actor_id") != actor_id:
        raise CommandRejected("authority grant actor does not match signed actor", 403)
    if value.get("capability") != capability:
        raise CommandRejected(f"authority grant must allow {capability}", 403)
    if value.get("scope") != f"employee:{employee_id}":
        raise CommandRejected("authority grant scope must be employee-scoped", 403)
    try:
        max_amount = int(value.get("max_amount_minor"))
    except (TypeError, ValueError) as error:
        raise CommandRejected("authority grant max_amount_minor is required", 403) from error
    if max_amount < amount_minor:
        raise CommandRejected("authority grant amount is exceeded", 403)
    return {
        "active": True,
        "principal_id": principal_id,
        "actor_id": actor_id,
        "capability": capability,
        "scope": f"employee:{employee_id}",
        "max_amount_minor": max_amount,
    }


def _loan_projection_rows(
    pool: PsqlPool,
    loan_id: str,
    max_rows: int = 1,
) -> list[dict[str, Any]]:
    if not IDENTIFIER.fullmatch(loan_id):
        raise ValueError("invalid loan_id")
    query = f"""
    SELECT encode(convert_to(aggregate_id, 'UTF8'), 'hex'),
           revision::text,
           encode(convert_to(payload::text, 'UTF8'), 'hex'),
           encode(convert_to(source_event_id, 'UTF8'), 'hex')
    FROM company_aggregate_projection
    WHERE aggregate_type = 'employee_advance'
      AND aggregate_id = {sql_literal(loan_id)}
    ORDER BY revision DESC
    LIMIT {max_rows}
    """
    result: list[dict[str, Any]] = []
    for line in query_lines(pool, query):
        fields = line.split("|")
        if len(fields) != 4:
            raise ServiceError("unexpected loan projection shape")
        try:
            payload = json.loads(decode_hex(fields[2]))
        except json.JSONDecodeError as error:
            raise ServiceError("invalid loan projection JSON") from error
        if not isinstance(payload, dict):
            raise ServiceError("loan projection payload is not an object")
        result.append(
            {
                "aggregate_id": decode_hex(fields[0]),
                "revision": int(fields[1]),
                "payload": payload,
                "source_event_id": decode_hex(fields[3]),
            }
        )
    return result


def _loan_request(
    pool: PsqlPool,
    command_type: str,
    loan_id: str | None,
    body: dict[str, Any],
    actor_id: str,
    idempotency_key: str,
) -> tuple[str, dict[str, Any], bool, str | None, str]:
    allowed = {"create", "submit", "offset", "sync_from_workflow", "update", "void"}
    if command_type not in allowed:
        raise CommandRejected("unsupported loan command", 404)
    if command_type == "create":
        identifier = body.get("loan_id")
        if identifier is None:
            identifier = "loan-" + idempotency_key
        if not isinstance(identifier, str) or not IDENTIFIER.fullmatch(identifier):
            raise CommandRejected("loan_id contains unsupported characters", 422)
        employee_id = _loan_required_text(body, "employee_id", identifier=True)
        principal_id = _loan_required_text(body, "principal_id", identifier=True)
        scope = _loan_required_text(body, "scope", identifier=True)
        if scope != f"employee:{employee_id}":
            raise CommandRejected("scope must equal employee:<employee_id>", 422)
        amount_minor = _loan_amount_minor(body)
        authority = _loan_authority(
            body,
            actor_id=actor_id,
            principal_id=principal_id,
            employee_id=employee_id,
            capability="advance:create",
            amount_minor=amount_minor,
        )
        loan_code = body.get("loan_code", "JK-" + identifier)
        if not isinstance(loan_code, str) or not loan_code.strip():
            raise CommandRejected("loan_code must be non-empty text", 422)
        request: dict[str, Any] = {
            "command_type": "create",
            "loan_id": identifier,
            "loan_code": loan_code.strip(),
            "subject": _loan_required_text(body, "subject"),
            "employee_id": employee_id,
            "principal_id": principal_id,
            "scope": scope,
            "currency": _loan_required_text(body, "currency", identifier=True).upper()
            if body.get("currency") is not None
            else "CNY",
            "loan_amount_minor": amount_minor,
            "balance_amount_minor": 0,
            "remain_amount_minor": amount_minor,
            "apply_dept_guid": _loan_required_text(body, "apply_dept_guid", identifier=True),
            "applied_by": actor_id,
            "apply_date": _loan_required_text(body, "apply_date"),
            "pay_unit": str(body.get("pay_unit", "")).strip(),
            "proj_guid": str(body.get("proj_guid", "")).strip(),
            "process_instance_guid": "",
            "evidence_ids": body.get("evidence_ids", []),
            "authority": authority,
            "state": "Draft",
            "source_kind": "command",
        }
        if not re.fullmatch(r"[A-Z]{3}", request["currency"]):
            raise CommandRejected("currency must be a three-letter code", 422)
        if not isinstance(request["evidence_ids"], list) or not all(
            isinstance(value, str) and IDENTIFIER.fullmatch(value) for value in request["evidence_ids"]
        ):
            raise CommandRejected("evidence_ids must be identifier strings", 422)
        return identifier, request, True, None, "Draft"
    if loan_id is None or not IDENTIFIER.fullmatch(loan_id):
        raise CommandRejected("loan_id is required", 422)
    request = {"command_type": command_type, "loan_id": loan_id, "actor_id": actor_id}
    if command_type == "sync_from_workflow":
        raise CommandRejected(
            "workflow synchronization is gated until wf_process_instance source rows are available",
            409,
        )
    if command_type == "offset":
        current = _loan_projection_rows(pool, loan_id, 1)
        if not current or current[0]["payload"].get("source_kind") != "command":
            raise CommandRejected("imported loans are read-only; create a local loan first", 409)
        payload = current[0]["payload"]
        employee_id = _loan_required_text(payload, "employee_id", identifier=True)
        principal_id = _loan_required_text(payload, "principal_id", identifier=True)
        amount_minor = _loan_amount_minor(body, "offset_amount_minor")
        remain_minor = int(payload.get("remain_amount_minor", 0))
        if amount_minor > remain_minor:
            raise CommandRejected("offset amount exceeds remaining loan balance", 422)
        request.update(
            {
                "offset_id": "offset-" + idempotency_key,
                "offset_amount_minor": amount_minor,
                "offset_date": _loan_required_text(body, "offset_date"),
                "related_expense_id": str(body.get("related_expense_id", "")).strip(),
                "remark": str(body.get("remark", "")).strip(),
                "authority": _loan_authority(
                    body,
                    actor_id=actor_id,
                    principal_id=principal_id,
                    employee_id=employee_id,
                    capability="advance:offset",
                    amount_minor=amount_minor,
                ),
            }
        )
    elif command_type == "update":
        changes: dict[str, Any] = {}
        if "subject" in body:
            changes["subject"] = _loan_required_text(body, "subject")
        if "loan_amount" in body or "amount_minor" in body:
            amount_minor = _loan_amount_minor(body)
            current = _loan_projection_rows(pool, loan_id, 1)
            if not current:
                raise CommandRejected("loan not found", 404)
            balance_minor = int(current[0]["payload"].get("balance_amount_minor", 0))
            if amount_minor <= balance_minor:
                raise CommandRejected("loan amount must exceed already offset balance", 422)
            changes["loan_amount_minor"] = amount_minor
            request["next_remain_amount_minor"] = amount_minor - balance_minor
        for key in ("pay_unit", "proj_guid"):
            if key in body:
                value = body[key]
                if not isinstance(value, str):
                    raise CommandRejected(f"{key} must be text", 422)
                changes[key] = value.strip()
        if not changes:
            raise CommandRejected("update requires at least one mutable field", 422)
        request["changes"] = changes
    elif command_type == "void":
        reason = body.get("reason", "")
        if not isinstance(reason, str):
            raise CommandRejected("reason must be text", 422)
        request["reason"] = reason.strip()
    return loan_id, request, False, {
        "submit": "Draft",
        "update": "Draft",
        "void": "Draft,Rejected",
        "offset": "Approved",
    }[command_type], {
        "submit": "Approving",
        "update": "Draft",
        "void": "Voided",
        "offset": "Approved",
    }[command_type]


def loan_command(
    pool: PsqlPool,
    *,
    command_type: str,
    loan_id: str | None,
    body: dict[str, Any],
    actor_id: str,
    idempotency_key: str,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(idempotency_key):
        raise CommandRejected("Idempotency-Key contains unsupported characters", 422)
    loan_id, request, create_mode, expected_state, next_state = _loan_request(
        pool, command_type, loan_id, body, actor_id, idempotency_key
    )
    existing = _existing_command(pool, idempotency_key)
    if existing is not None:
        if existing.get("request") != request:
            raise CommandRejected("Idempotency-Key was already used for another request", 409)
        result = existing.get("result")
        if not isinstance(result, dict):
            raise ServiceError("stored loan command receipt has no result")
        return {"command": existing, "loan": result, "idempotent_replay": True}
    current = _loan_projection_rows(pool, loan_id, 1)
    imported = loans(pool, loan_id, None, 1)
    if create_mode:
        if current or imported:
            raise CommandRejected("loan already exists", 409)
    else:
        if not current:
            if imported:
                raise CommandRejected("imported loans are read-only; create a local loan first", 409)
            raise CommandRejected("loan not found", 404)
        payload = current[0]["payload"]
        if payload.get("source_kind") != "command":
            raise CommandRejected("imported loans are read-only", 409)
        actual_state = str(payload.get("apply_state", ""))
        expected_states = tuple(expected_state.split(",")) if expected_state else ()
        if actual_state not in expected_states:
            raise CommandRejected(
                f"loan transition {command_type} requires {','.join(expected_states)}, found {actual_state}",
                409,
            )
        if command_type in {"submit", "update", "void"} and payload.get("applied_by") != actor_id:
            raise CommandRejected("only the loan applicant may change this loan", 403)
    event_id = f"employee_advance:{command_type}:{idempotency_key}"
    command_source = f"moonproj:command:{idempotency_key}"
    audit_id = event_id + ":audit"
    request_json = json.dumps(request, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    command_json = json.dumps(
        {
            "kind": "company_command",
            "command_family": "loan",
            "command_type": command_type,
            "idempotency_key": idempotency_key,
            "aggregate_type": "employee_advance",
            "aggregate_id": loan_id,
            "actor_id": actor_id,
            "request": request,
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    offset_projection = command_type == "offset"
    sql = f"""
    BEGIN;
    CREATE TEMP TABLE command_attempt(created boolean) ON COMMIT DROP;
    WITH inserted AS (
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_command', {sql_literal(event_id)}, 4,
        {sql_literal(command_json)}::jsonb, {sql_literal(command_source)})
      ON CONFLICT (source_id) DO NOTHING
      RETURNING 1
    )
    INSERT INTO command_attempt(created) SELECT EXISTS (SELECT 1 FROM inserted);
    DO $$
    DECLARE
      is_new boolean;
      current_payload jsonb;
      next_payload jsonb;
      next_revision integer;
      next_balance bigint;
      next_remain bigint;
      result jsonb;
    BEGIN
      SELECT created INTO is_new FROM command_attempt LIMIT 1;
      IF NOT is_new THEN RETURN; END IF;
      SELECT p.payload INTO current_payload
      FROM company_aggregate_projection p
      WHERE p.aggregate_type = 'employee_advance'
        AND p.aggregate_id = {sql_literal(loan_id)}
      ORDER BY p.revision DESC LIMIT 1;
      IF {str(create_mode).lower()} THEN
        IF current_payload IS NOT NULL THEN RAISE EXCEPTION 'loan already exists'; END IF;
        next_revision := 1;
        next_payload := {sql_literal(request_json)}::jsonb || jsonb_build_object(
          'apply_state', 'Draft', 'source_kind', 'command',
          'event_id', {sql_literal(event_id)}, 'updated_by', {sql_literal(actor_id)});
      ELSE
        IF current_payload IS NULL THEN RAISE EXCEPTION 'loan not found'; END IF;
        IF current_payload->>'source_kind' <> 'command' THEN RAISE EXCEPTION 'imported loan is read-only'; END IF;
        IF NOT ((current_payload->>'apply_state') = ANY(string_to_array({sql_literal(expected_state or '')}, ','))) THEN
          RAISE EXCEPTION 'loan transition state conflict';
        END IF;
        SELECT coalesce(max(p.revision), 0) + 1 INTO next_revision
        FROM company_aggregate_projection p
        WHERE p.aggregate_type = 'employee_advance' AND p.aggregate_id = {sql_literal(loan_id)};
        IF {sql_literal(command_type)} = 'offset' THEN
          next_balance := coalesce((current_payload->>'balance_amount_minor')::bigint, 0)
            + ({sql_literal(request_json)}::jsonb->>'offset_amount_minor')::bigint;
          next_remain := coalesce((current_payload->>'loan_amount_minor')::bigint, 0) - next_balance;
          IF next_remain < 0 THEN RAISE EXCEPTION 'offset exceeds remaining loan balance'; END IF;
          next_payload := current_payload || jsonb_build_object(
            'balance_amount_minor', next_balance, 'remain_amount_minor', next_remain,
            'apply_state', 'Approved', 'event_id', {sql_literal(event_id)},
            'updated_by', {sql_literal(actor_id)});
        ELSIF {sql_literal(command_type)} = 'update' THEN
          next_payload := current_payload || coalesce({sql_literal(request_json)}::jsonb->'changes', '{{}}'::jsonb)
            || jsonb_build_object('remain_amount_minor', coalesce(({sql_literal(request_json)}::jsonb->>'next_remain_amount_minor')::bigint,
              (current_payload->>'remain_amount_minor')::bigint), 'apply_state', 'Draft',
              'event_id', {sql_literal(event_id)}, 'updated_by', {sql_literal(actor_id)});
        ELSE
          next_payload := current_payload || jsonb_build_object(
            'apply_state', {sql_literal(next_state)}, 'event_id', {sql_literal(event_id)},
            'updated_by', {sql_literal(actor_id)}, 'reason', {sql_literal(request_json)}::jsonb->>'reason');
        END IF;
      END IF;
      INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id)
      VALUES ('employee_advance', {sql_literal(loan_id)}, next_revision, next_payload, {sql_literal(event_id)});
      IF {str(offset_projection).lower()} THEN
        INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id)
        VALUES ('loan_offset', {sql_literal(request.get('offset_id', ''))}, 1,
          {sql_literal(request_json)}::jsonb || jsonb_build_object(
            'loan_id', {sql_literal(loan_id)}, 'source_kind', 'command',
            'source_id', {sql_literal(event_id)}), {sql_literal(event_id)} || ':offset');
      END IF;
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_audit_event', {sql_literal(audit_id)}, 4,
        jsonb_build_object('audit_id', {sql_literal(audit_id)}, 'action',
          'loan.' || {sql_literal(command_type)}, 'aggregate_type', 'employee_advance',
          'aggregate_id', {sql_literal(loan_id)}, 'actor_id', {sql_literal(actor_id)},
          'event_id', {sql_literal(event_id)}, 'state', next_payload->>'apply_state',
          'revision', next_revision), {sql_literal('moonproj:audit:' + event_id)});
      result := jsonb_build_object('loan_id', {sql_literal(loan_id)},
        'state', next_payload->>'apply_state', 'revision', next_revision,
        'event_id', {sql_literal(event_id)}, 'audit_id', {sql_literal(audit_id)},
        'actor_id', {sql_literal(actor_id)});
      IF {str(offset_projection).lower()} THEN
        result := result || jsonb_build_object(
          'offset_id', {sql_literal(request.get('offset_id', ''))},
          'balance_amount_minor', next_payload->>'balance_amount_minor',
          'remain_amount_minor', next_payload->>'remain_amount_minor');
      END IF;
      UPDATE company_record SET payload = payload || jsonb_build_object('result', result)
      WHERE source_id = {sql_literal(command_source)};
    END $$;
    SELECT coalesce((SELECT created::text FROM command_attempt LIMIT 1), 'false')
      || '|' || encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM company_record WHERE source_id = {sql_literal(command_source)};
    COMMIT;
    """
    lines = query_lines(pool, sql)
    if len(lines) != 1:
        raise ServiceError("loan command did not return a command receipt")
    fields = lines[0].split("|", 1)
    if len(fields) != 2:
        raise ServiceError("unexpected loan command receipt shape")
    created = fields[0] == "true"
    try:
        receipt = json.loads(decode_hex(fields[1]))
    except json.JSONDecodeError as error:
        raise ServiceError("invalid stored loan command receipt") from error
    if not created and receipt.get("request") != request:
        raise CommandRejected("Idempotency-Key was already used for another request", 409)
    result = receipt.get("result")
    if not isinstance(result, dict):
        raise ServiceError("loan command receipt has no result")
    return {"command": receipt, "loan": result, "idempotent_replay": not created}


def report_cost_summary(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    projects = _raw_report_rows(pool, "ep_project", max_rows)
    business_units = {
        str(row["payload"].get("bu_guid", row["record_id"])): row["payload"]
        for row in _raw_report_rows(pool, "mu_business_unit", max_rows)
    }
    costs_by_project: dict[str, dict[str, float]] = {}
    for row in _raw_report_rows(pool, "cb_cost", max_rows):
        payload = row["payload"]
        if not bool(payload.get("is_end_cost")):
            continue
        project_id = str(payload.get("proj_guid", ""))
        totals = costs_by_project.setdefault(
            project_id,
            {"target": 0.0, "d": 0.0, "e": 0.0, "f": 0.0, "g": 0.0},
        )
        totals["target"] += _report_float(payload, "target_cost")
        totals["d"] += _report_float(payload, "ht_alter_amount")
        totals["e"] += _report_float(payload, "zt_cost")
        totals["f"] += _report_float(payload, "dfs_budget")
        totals["g"] += _report_float(payload, "yg_alter")
    rows: list[dict[str, Any]] = []
    for row in projects:
        payload = row["payload"]
        project_id = str(payload.get("proj_guid", row["record_id"]))
        totals = costs_by_project.get(
            project_id,
            {"target": 0.0, "d": 0.0, "e": 0.0, "f": 0.0, "g": 0.0},
        )
        dynamic = totals["d"] + totals["e"] + totals["f"] + totals["g"]
        target = totals["target"]
        spare = target - dynamic
        deviation = ((target - dynamic) / target * 100) if target else 0.0
        bu = business_units.get(str(payload.get("bu_guid", "")), {})
        rows.append(
            {
                "buName": str(bu.get("bu_name") or payload.get("bu_guid", "")),
                "projCode": _report_text(payload, "proj_code", project_id),
                "projName": _report_text(payload, "proj_name", project_id),
                "projStatus": _report_text(payload, "proj_status"),
                "targetCost": target,
                "dynamicCost": dynamic,
                "spare": spare,
                "deviationPct": round(deviation, 2),
                "d": totals["d"],
                "e": totals["e"],
                "f": totals["f"],
                "g": totals["g"],
                "source_kind": "imported",
            }
        )
    total = {
        key: sum(float(row[key]) for row in rows)
        for key in ("targetCost", "dynamicCost", "spare", "d", "e", "f", "g")
    }
    total["deviationPct"] = round(
        (total["targetCost"] - total["dynamicCost"])
        / total["targetCost"]
        * 100
        if total["targetCost"]
        else 0.0,
        2,
    )
    return {"rows": rows, "total": total, "source_kind": "imported"}


def report_contract_payment_ledger(pool: PsqlPool, max_rows: int) -> list[dict[str, Any]]:
    projects = {
        str(row["payload"].get("proj_guid", row["record_id"])): row["payload"]
        for row in _raw_report_rows(pool, "ep_project", max_rows)
    }
    business_units = {
        str(row["payload"].get("bu_guid", row["record_id"])): row["payload"]
        for row in _raw_report_rows(pool, "mu_business_unit", max_rows)
    }
    plans_by_contract: dict[str, float] = {}
    for row in _raw_report_rows(pool, "cb_htfkplan", max_rows):
        payload = row["payload"]
        contract_id = str(payload.get("contract_guid", ""))
        plans_by_contract[contract_id] = plans_by_contract.get(contract_id, 0.0) + _report_float(
            payload, "jhfk_amount"
        )
    applies_by_contract: dict[str, dict[str, float]] = {}
    for row in _raw_report_rows(pool, "cb_htfk_apply", max_rows):
        payload = row["payload"]
        contract_id = str(payload.get("contract_guid", ""))
        totals = applies_by_contract.setdefault(contract_id, {"applied": 0.0, "paid": 0.0})
        amount = _report_float(payload, "apply_amount")
        if str(payload.get("apply_state", "")) == "已审核":
            totals["applied"] += amount
        if str(payload.get("pay_state", "")) in {"完全支付", "部分支付"}:
            totals["paid"] += amount
    contracts = sorted(
        _raw_report_rows(pool, "cb_contract", max_rows),
        key=lambda row: str(row["payload"].get("sign_date", "")),
        reverse=True,
    )
    result: list[dict[str, Any]] = []
    for row in contracts[:200]:
        payload = row["payload"]
        contract_id = str(payload.get("contract_guid", row["record_id"]))
        project_id = str(payload.get("proj_guid", ""))
        bu_id = str(payload.get("bu_guid", ""))
        current_amount = _report_float(payload, "ht_amount") + _report_float(payload, "sum_alter_amount")
        totals = applies_by_contract.get(contract_id, {"applied": 0.0, "paid": 0.0})
        paid = totals["paid"]
        result.append(
            {
                "contractGuid": contract_id,
                "contractCode": _report_text(payload, "contract_code", contract_id),
                "contractName": _report_text(payload, "contract_name", contract_id),
                "buName": str(business_units.get(bu_id, {}).get("bu_name") or bu_id),
                "projName": str(projects.get(project_id, {}).get("proj_name") or project_id),
                "provider": _report_text(payload, "yf_provider_name"),
                "signDate": _report_text(payload, "sign_date"),
                "htCfState": _report_text(payload, "ht_cf_state"),
                "htAmount": _report_float(payload, "ht_amount"),
                "alterAmount": _report_float(payload, "sum_alter_amount"),
                "currentAmount": current_amount,
                "planTotal": plans_by_contract.get(contract_id, 0.0),
                "appliedTotal": totals["applied"],
                "paidTotal": paid,
                "remainAmount": current_amount - paid,
                "paidPct": round(paid / current_amount * 100, 2) if current_amount else 0.0,
                "source_kind": "imported",
            }
        )
    return result


def report_supplier_analysis(pool: PsqlPool, max_rows: int) -> list[dict[str, Any]]:
    providers = _raw_report_rows(pool, "srm_provider", max_rows)
    if not providers:
        return []
    categories = {
        str(row["payload"].get("category_code", row["record_id"])): row["payload"]
        for row in _raw_report_rows(pool, "srm_category", max_rows)
    }
    contracts = [row["payload"] for row in _raw_report_rows(pool, "cb_contract", max_rows)]
    cutoff = date.today() - timedelta(days=365)
    result: list[dict[str, Any]] = []
    for row in providers:
        payload = row["payload"]
        name = str(payload.get("provider_name", row["record_id"]))
        short_name = str(payload.get("short_name", ""))
        matched = [
            contract
            for contract in contracts
            if str(contract.get("yf_provider_name", "")) == name
            or (short_name and short_name in str(contract.get("yf_provider_name", "")))
        ]
        if not matched:
            continue
        total_amount = sum(
            _report_float(contract, "ht_amount") + _report_float(contract, "sum_alter_amount")
            for contract in matched
        )
        recent_amount = sum(
            _report_float(contract, "ht_amount") + _report_float(contract, "sum_alter_amount")
            for contract in matched
            if (_report_date(contract.get("sign_date")) or date.min) >= cutoff
        )
        result.append(
            {
                "providerGuid": str(payload.get("provider_guid", row["record_id"])),
                "providerName": name,
                "shortName": short_name,
                "evalResult": str(payload.get("eval_result", "")),
                "categoryName": str(
                    categories.get(str(payload.get("main_category_code", "")), {}).get(
                        "category_name", payload.get("main_category_code", "")
                    )
                ),
                "contractCount": len(matched),
                "buCount": len({str(contract.get("bu_guid", "")) for contract in matched}),
                "projCount": len({str(contract.get("proj_guid", "")) for contract in matched}),
                "totalAmount": total_amount,
                "recentAmount": recent_amount,
                "source_kind": "imported",
            }
        )
    return sorted(result, key=lambda row: float(row["totalAmount"]), reverse=True)


def report_approval_efficiency(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    instances = _raw_report_rows(pool, "wf_process_instance", max_rows)
    by_type: dict[str, dict[str, Any]] = {}
    for row in instances:
        payload = row["payload"]
        biz_type = str(payload.get("biz_type", ""))
        stats = by_type.setdefault(
            biz_type,
            {"total": 0, "completed": 0, "rejected": 0, "running": 0, "overdue": 0, "durations": []},
        )
        stats["total"] += 1
        status = str(payload.get("status", ""))
        if status in {"Completed", "Archived"}:
            stats["completed"] += 1
        if status == "Rejected":
            stats["rejected"] += 1
        if status == "Running":
            stats["running"] += 1
            initiated = _report_date(payload.get("initiated_at"))
            if initiated is not None and initiated < date.today() - timedelta(days=7):
                stats["overdue"] += 1
        initiated = _report_date(payload.get("initiated_at"))
        completed = _report_date(payload.get("completed_at"))
        if initiated is not None and completed is not None:
            stats["durations"].append((completed - initiated).days)
    by_type_rows = []
    for biz_type, stats in sorted(by_type.items(), key=lambda item: item[1]["total"], reverse=True):
        total = int(stats["total"])
        by_type_rows.append(
            {
                "bizType": biz_type,
                "total": total,
                "completed": stats["completed"],
                "rejected": stats["rejected"],
                "running": stats["running"],
                "overdue": stats["overdue"],
                "avgDays": round(sum(stats["durations"]) / len(stats["durations"]), 2)
                if stats["durations"]
                else None,
                "rejectRate": round(stats["rejected"] / total * 100, 1) if total else 0.0,
            }
        )
    actions_by_process: dict[str, list[dict[str, Any]]] = {}
    for row in _raw_report_rows(pool, "wf_step_action", max_rows):
        payload = row["payload"]
        process_id = str(payload.get("process_instance_guid", ""))
        actions_by_process.setdefault(process_id, []).append(payload)
    slow: dict[tuple[str, str], list[int]] = {}
    for actions in actions_by_process.values():
        indexed = {int(_report_float(action, "step_order")): action for action in actions}
        for action in actions:
            if str(action.get("decision", "")) != "APPROVED":
                continue
            order = int(_report_float(action, "step_order"))
            previous = indexed.get(order - 1)
            current_date = _report_date(action.get("action_time"))
            previous_date = _report_date(previous.get("action_time")) if previous else None
            if current_date is None or previous_date is None:
                continue
            key = (str(action.get("step_name", "")), str(action.get("assignee_emp_name", "")))
            slow.setdefault(key, []).append((current_date - previous_date).days)
    slow_steps = [
        {
            "stepName": key[0],
            "empName": key[1],
            "avgDays": round(sum(values) / len(values), 2),
            "count": len(values),
        }
        for key, values in slow.items()
        if len(values) >= 3
    ]
    slow_steps.sort(key=lambda row: float(row["avgDays"]), reverse=True)
    return {"byType": by_type_rows, "slowSteps": slow_steps[:10], "source_kind": "imported"}


def report_project_stage_matrix(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    stage_rows = _raw_report_rows(pool, "proj_lifecycle_stage", max_rows)
    stages = sorted(
        [row["payload"] for row in stage_rows],
        key=lambda payload: _report_float(payload, "stage_order"),
    )
    instances: dict[tuple[str, str], dict[str, Any]] = {}
    for row in _raw_report_rows(pool, "proj_lifecycle_instance", max_rows):
        payload = row["payload"]
        instances[(str(payload.get("proj_guid", "")), str(payload.get("stage_code", "")))] = payload
    business_units = {
        str(row["payload"].get("bu_guid", row["record_id"])): row["payload"]
        for row in _raw_report_rows(pool, "mu_business_unit", max_rows)
    }
    projects = sorted(
        _raw_report_rows(pool, "ep_project", max_rows),
        key=lambda row: (
            str(business_units.get(str(row["payload"].get("bu_guid", "")), {}).get("bu_name", "")),
            str(row["payload"].get("proj_code", "")),
        ),
    )
    matrix = []
    for row in projects:
        payload = row["payload"]
        project_id = str(payload.get("proj_guid", row["record_id"]))
        cells = []
        for stage in stages:
            stage_code = str(stage.get("stage_code", ""))
            instance = instances.get((project_id, stage_code))
            cells.append(
                {
                    "stageCode": stage_code,
                    "stageName": str(stage.get("stage_name", stage_code)),
                    "status": str(instance.get("status", "pending")) if instance else "pending",
                    "progressPct": _report_float(instance or {}, "progress_pct"),
                }
            )
        matrix.append(
            {
                "projGuid": project_id,
                "projCode": _report_text(payload, "proj_code", project_id),
                "projName": _report_text(payload, "proj_name", project_id),
                "buName": str(business_units.get(str(payload.get("bu_guid", "")), {}).get("bu_name") or ""),
                "projStatus": _report_text(payload, "proj_status"),
                "beginDate": _report_text(payload, "begin_date"),
                "endDate": _report_text(payload, "end_date"),
                "cells": cells,
                "source_kind": "imported",
            }
        )
    return {
        "stages": [
            {"code": str(stage.get("stage_code", "")), "name": str(stage.get("stage_name", ""))}
            for stage in stages
        ],
        "projects": matrix,
        "source_kind": "imported",
    }


def reports_overview(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = {
        table: len(_raw_report_rows(pool, table, max_rows))
        for table in sorted(REPORT_SOURCE_TABLES)
    }
    return {
        "cost_summary": report_cost_summary(pool, max_rows),
        "contract_payment_ledger": report_contract_payment_ledger(pool, max_rows),
        "supplier_analysis": report_supplier_analysis(pool, max_rows),
        "approval_efficiency": report_approval_efficiency(pool, max_rows),
        "project_stage_matrix": report_project_stage_matrix(pool, max_rows),
        "source_kind": "imported",
        "source_coverage": coverage,
        "missing_source_tables": [table for table, count in coverage.items() if count == 0],
    }


def _delivery_required_text(body: dict[str, Any], key: str, *, identifier: bool = False) -> str:
    value = body.get(key)
    if not isinstance(value, str) or not value.strip():
        raise CommandRejected(f"{key} is required", 422)
    value = value.strip()
    if identifier and not IDENTIFIER.fullmatch(value):
        raise CommandRejected(f"{key} contains unsupported characters", 422)
    return value


def _delivery_evidence(body: dict[str, Any], key: str = "evidence_ids") -> list[str]:
    value = body.get(key)
    if not isinstance(value, list) or not value:
        raise CommandRejected(f"{key} must contain at least one evidence id", 422)
    result: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item.strip() or not IDENTIFIER.fullmatch(item.strip()):
            raise CommandRejected(f"{key} contains an invalid evidence id", 422)
        result.append(item.strip())
    return result


def _delivery_progress_bps(body: dict[str, Any], key: str = "progress_pct") -> int:
    if "progress_bps" in body:
        value = body.get("progress_bps")
        if isinstance(value, bool) or not isinstance(value, int):
            raise CommandRejected("progress_bps must be an integer", 422)
        bps = value
    else:
        value = body.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise CommandRejected(f"{key} must be a number", 422)
        bps = round(float(value) * 100)
    if bps < 0 or bps > 10000:
        raise CommandRejected("progress must be between 0 and 100 percent", 422)
    return int(bps)


def _delivery_amount(body: dict[str, Any], key: str, *, positive: bool = False) -> int:
    value = body.get(key)
    if isinstance(value, bool) or not isinstance(value, int) or (value <= 0 if positive else value < 0):
        requirement = "positive" if positive else "non-negative"
        raise CommandRejected(f"{key} must be a {requirement} integer", 422)
    return value


def _delivery_request(
    pool: PsqlPool,
    family: str,
    command_type: str,
    aggregate_id: str | None,
    body: dict[str, Any],
    actor_id: str,
) -> tuple[str, str, dict[str, Any], bool, str | None, str]:
    if family == "progress":
        aggregate_type = "delivery_progress"
        allowed = {"create", "report", "accept", "reject"}
        id_key = "progress_id"
    elif family == "output":
        aggregate_type = "delivery_output"
        allowed = {"create", "confirm"}
        id_key = "output_id"
    elif family == "task_report":
        aggregate_type = "task_report"
        allowed = {"report"}
        id_key = "report_id"
    else:
        raise CommandRejected("unsupported delivery command family", 404)
    if command_type not in allowed:
        raise CommandRejected("unsupported delivery command", 404)
    if family == "task_report":
        report_id = _delivery_required_text(body, "report_id", identifier=True)
        task_id = _delivery_required_text(body, "task_id", identifier=True)
        project_id = _delivery_required_text(body, "project_id", identifier=True)
        if not delivery_tasks(pool, task_id, project_id, 1):
            raise CommandRejected("task report target task was not found in the source projection", 404)
        request = {
            "command_type": command_type,
            "report_id": report_id,
            "task_id": task_id,
            "project_id": project_id,
            "progress_bps": _delivery_progress_bps(body),
            "report_date": _delivery_required_text(body, "report_date"),
            "summary": _delivery_required_text(body, "summary"),
            "evidence_ids": _delivery_evidence(body),
            "actor_id": actor_id,
            "state": "observed",
        }
        if delivery_task_reports(pool, report_id, task_id, 1):
            raise CommandRejected("imported task report ids are read-only; use a new local report id", 409)
        return report_id, aggregate_type, request, True, None, "observed"
    if command_type == "create":
        identifier = _delivery_required_text(body, id_key, identifier=True)
        if family == "progress":
            request = {
                "command_type": command_type,
                "progress_id": identifier,
                "project_id": _delivery_required_text(body, "project_id", identifier=True),
                "principal_id": _delivery_required_text(body, "principal_id", identifier=True),
                "project_scope": _delivery_required_text(body, "project_scope", identifier=True),
                "building_no": str(body.get("building_no", "")).strip(),
                "stage": _delivery_required_text(body, "stage"),
                "plan_date": str(body.get("plan_date", "")).strip(),
                "plan_pct_bps": _delivery_progress_bps(body, "plan_pct"),
                "completed_value_minor": _delivery_amount(body, "completed_value_minor"),
                "currency": _delivery_required_text(body, "currency", identifier=True).upper(),
                "contract_id": str(body.get("contract_id", "")).strip(),
                "milestone_id": str(body.get("milestone_id", "")).strip(),
                "evidence_ids": _delivery_evidence(body),
                "remark": str(body.get("remark", "")).strip(),
                "actor_id": actor_id,
                "state": "draft",
            }
            if not re.fullmatch(r"[A-Z]{3}", request["currency"]):
                raise CommandRejected("currency must be a three-letter code", 422)
            if _raw_delivery_rows(
                pool,
                "proj_progress",
                record_id=identifier,
                project_id=None,
                task_id=None,
                max_rows=1,
            ):
                raise CommandRejected("imported progress rows are read-only; use a new local progress id", 409)
            return identifier, aggregate_type, request, True, None, "draft"
        request = {
            "command_type": command_type,
            "output_id": identifier,
            "output_code": str(body.get("output_code", "")).strip(),
            "project_id": _delivery_required_text(body, "project_id", identifier=True),
            "contract_id": _delivery_required_text(body, "contract_id", identifier=True),
            "period": _delivery_required_text(body, "period"),
            "output_amount": _delivery_required_text(body, "output_amount"),
            "confirm_amount": "0",
            "evidence_ids": _delivery_evidence(body),
            "remark": str(body.get("remark", "")).strip(),
            "actor_id": actor_id,
            "state": "reported",
        }
        if _raw_delivery_rows(
            pool,
            "proj_output",
            record_id=identifier,
            project_id=None,
            task_id=None,
            max_rows=1,
        ):
            raise CommandRejected("imported output rows are read-only; use a new local output id", 409)
        return identifier, aggregate_type, request, True, None, "reported"
    if aggregate_id is None or not IDENTIFIER.fullmatch(aggregate_id):
        raise CommandRejected(f"{id_key} is required", 422)
    request: dict[str, Any] = {
        "command_type": command_type,
        id_key: aggregate_id,
        "actor_id": actor_id,
    }
    if family == "progress":
        if command_type == "report":
            request["actual_progress_bps"] = _delivery_progress_bps(body)
            request["actual_date"] = _delivery_required_text(body, "actual_date")
            request["evidence_ids"] = _delivery_evidence(body)
            request["remark"] = str(body.get("remark", "")).strip()
            return aggregate_id, aggregate_type, request, False, "draft", "submitted"
        if command_type == "accept":
            request["acceptance_evidence_ids"] = _delivery_evidence(body, "acceptance_evidence_ids")
            request["acceptance_id"] = _delivery_required_text(body, "acceptance_id", identifier=True)
            return aggregate_id, aggregate_type, request, False, "submitted", "accepted"
        request["reason"] = _delivery_required_text(body, "reason")
        return aggregate_id, aggregate_type, request, False, "submitted", "rejected"
    request["confirm_amount"] = _delivery_required_text(body, "confirm_amount")
    request["evidence_ids"] = _delivery_evidence(body, "evidence_ids")
    request["confirmed_at"] = _delivery_required_text(body, "confirmed_at")
    return aggregate_id, aggregate_type, request, False, "reported", "confirmed"


def _delivery_persist_command(
    pool: PsqlPool,
    *,
    family: str,
    command_type: str,
    aggregate_id: str,
    aggregate_type: str,
    request: dict[str, Any],
    create_mode: bool,
    expected_state: str | None,
    next_state: str,
    idempotency_key: str,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(idempotency_key):
        raise CommandRejected("Idempotency-Key contains unsupported characters", 422)
    existing = _existing_command(pool, idempotency_key)
    if existing is not None:
        if existing.get("request") != request:
            raise CommandRejected("Idempotency-Key was already used for another request", 409)
        result = existing.get("result")
        if not isinstance(result, dict):
            raise ServiceError("stored delivery command receipt has no result")
        return {
            "command": existing,
            family: result,
            "idempotent_replay": True,
        }
    current = _latest_delivery_projection_rows(pool, aggregate_type, aggregate_id, 1)
    if create_mode:
        if current:
            raise CommandRejected("delivery record already exists", 409)
        next_revision = 1
    else:
        if not current:
            raise CommandRejected("delivery record not found", 404)
        current_payload = current[0]["payload"]
        if current_payload.get("source_kind") != "command":
            raise CommandRejected("imported delivery records are read-only", 409)
        actual_state = str(current_payload.get("state", ""))
        if expected_state is not None and actual_state != expected_state:
            raise CommandRejected(
                f"delivery transition {command_type} requires {expected_state}, found {actual_state}",
                409,
            )
        next_revision = int(current[0]["revision"]) + 1
    event_id = f"{aggregate_type}:{command_type}:{idempotency_key}"
    command_source = f"moonproj:command:{idempotency_key}"
    audit_id = event_id + ":audit"
    request_json = json.dumps(request, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    command_json = json.dumps(
        {
            "kind": "company_command",
            "command_family": family,
            "command_type": command_type,
            "idempotency_key": idempotency_key,
            "aggregate_type": aggregate_type,
            "aggregate_id": aggregate_id,
            "actor_id": request["actor_id"],
            "request": request,
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    sql = f"""
    BEGIN;
    CREATE TEMP TABLE command_attempt(created boolean) ON COMMIT DROP;
    WITH inserted AS (
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_command', {sql_literal(event_id)}, 4,
        {sql_literal(command_json)}::jsonb, {sql_literal(command_source)})
      ON CONFLICT (source_id) DO NOTHING
      RETURNING 1
    )
    INSERT INTO command_attempt(created) SELECT EXISTS (SELECT 1 FROM inserted);
    DO $$
    DECLARE
      is_new boolean;
      current_payload jsonb;
      next_payload jsonb;
      next_revision integer;
      result jsonb;
    BEGIN
      SELECT created INTO is_new FROM command_attempt LIMIT 1;
      IF NOT is_new THEN RETURN; END IF;
      SELECT p.payload INTO current_payload
      FROM company_aggregate_projection p
      WHERE p.aggregate_type = {sql_literal(aggregate_type)}
        AND p.aggregate_id = {sql_literal(aggregate_id)}
      ORDER BY p.revision DESC LIMIT 1;
      IF {str(create_mode).lower()} THEN
        IF current_payload IS NOT NULL THEN RAISE EXCEPTION 'delivery record already exists'; END IF;
        next_revision := 1;
        next_payload := {sql_literal(request_json)}::jsonb || jsonb_build_object(
          'state', {sql_literal(next_state)}, 'source_kind', 'command',
          'event_id', {sql_literal(event_id)}, 'updated_by', {sql_literal(str(request['actor_id']))});
      ELSE
        IF current_payload IS NULL THEN RAISE EXCEPTION 'delivery record not found'; END IF;
        IF current_payload->>'source_kind' <> 'command' THEN RAISE EXCEPTION 'imported delivery record is read-only'; END IF;
        IF {sql_literal(expected_state or '')} <> current_payload->>'state' THEN
          RAISE EXCEPTION 'delivery transition state conflict';
        END IF;
        next_revision := {next_revision};
        next_payload := current_payload || {sql_literal(request_json)}::jsonb || jsonb_build_object(
          'state', {sql_literal(next_state)}, 'source_kind', 'command',
          'event_id', {sql_literal(event_id)}, 'updated_by', {sql_literal(str(request['actor_id']))});
      END IF;
      INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id)
      VALUES ({sql_literal(aggregate_type)}, {sql_literal(aggregate_id)}, next_revision,
        next_payload, {sql_literal(event_id)});
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES ('company_audit_event', {sql_literal(audit_id)}, 4,
        jsonb_build_object('audit_id', {sql_literal(audit_id)}, 'action',
          {sql_literal('delivery.' + family + '.' + command_type)}, 'aggregate_type', {sql_literal(aggregate_type)},
          'aggregate_id', {sql_literal(aggregate_id)}, 'actor_id', {sql_literal(str(request['actor_id']))},
          'event_id', {sql_literal(event_id)}, 'state', {sql_literal(next_state)}, 'revision', next_revision),
        {sql_literal('moonproj:audit:' + event_id)});
      result := jsonb_build_object('aggregate_id', {sql_literal(aggregate_id)},
        'state', {sql_literal(next_state)}, 'revision', next_revision,
        'event_id', {sql_literal(event_id)}, 'audit_id', {sql_literal(audit_id)},
        'actor_id', {sql_literal(str(request['actor_id']))});
      UPDATE company_record SET payload = payload || jsonb_build_object('result', result)
      WHERE source_id = {sql_literal(command_source)};
    END $$;
    SELECT coalesce((SELECT created::text FROM command_attempt LIMIT 1), 'false')
      || '|' || encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM company_record WHERE source_id = {sql_literal(command_source)};
    COMMIT;
    """
    lines = query_lines(pool, sql)
    if len(lines) != 1:
        raise ServiceError("delivery command did not return a command receipt")
    fields = lines[0].split("|", 1)
    if len(fields) != 2:
        raise ServiceError("unexpected delivery command receipt shape")
    created = fields[0] == "true"
    try:
        receipt = json.loads(decode_hex(fields[1]))
    except json.JSONDecodeError as error:
        raise ServiceError("invalid stored delivery command receipt") from error
    if not created and receipt.get("request") != request:
        raise CommandRejected("Idempotency-Key was already used for another request", 409)
    result = receipt.get("result")
    if not isinstance(result, dict):
        raise ServiceError("delivery command receipt has no result")
    return {"command": receipt, family: result, "idempotent_replay": not created}


def delivery_command(
    pool: PsqlPool,
    *,
    family: str,
    command_type: str,
    aggregate_id: str | None,
    body: dict[str, Any],
    actor_id: str,
    idempotency_key: str,
) -> dict[str, Any]:
    aggregate_id, aggregate_type, request, create_mode, expected_state, next_state = _delivery_request(
        pool, family, command_type, aggregate_id, body, actor_id
    )
    return _delivery_persist_command(
        pool,
        family=family,
        command_type=command_type,
        aggregate_id=aggregate_id,
        aggregate_type=aggregate_type,
        request=request,
        create_mode=create_mode,
        expected_state=expected_state,
        next_state=next_state,
        idempotency_key=idempotency_key,
    )


def expense_command(
    pool: PsqlPool,
    *,
    command_type: str,
    expense_id: str | None,
    body: dict[str, Any],
    actor_id: str,
    idempotency_key: str,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(idempotency_key):
        raise CommandRejected("Idempotency-Key contains unsupported characters", 422)
    expense_id, request = _expense_request(command_type, expense_id, body, actor_id)
    existing = _existing_command(pool, idempotency_key)
    if existing is not None:
        if existing.get("request") != request:
            raise CommandRejected("Idempotency-Key was already used for another request", 409)
        result = existing.get("result")
        if not isinstance(result, dict):
            raise ServiceError("stored company command receipt has no result")
        return {
            "command": existing,
            "expense": result,
            "idempotent_replay": True,
        }
    current = expenses(pool, expense_id, 1)
    if command_type == "create" and current:
        raise CommandRejected("expense already exists", 409)
    if command_type != "create":
        if not current:
            raise CommandRejected("expense not found", 404)
        current_state = str(current[0]["payload"].get("state", ""))
        expected = {
            "submit": "draft",
            "approve": "submitted",
            "reject": "submitted",
            "resubmit": "rejected",
        }[command_type]
        if current_state != expected:
            raise CommandRejected(
                f"expense transition {command_type} requires {expected}, found {current_state}",
                409,
            )
    event_id = f"expense:{command_type}:{idempotency_key}"
    command_source = f"moonproj:command:{idempotency_key}"
    audit_id = event_id + ":audit"
    request_json = json.dumps(request, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    command_payload = {
        "kind": "company_command",
        "command_type": command_type,
        "idempotency_key": idempotency_key,
        "expense_id": expense_id,
        "actor_id": actor_id,
        "request": request,
    }
    command_json = json.dumps(command_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    sql = f"""
    BEGIN;
    CREATE TEMP TABLE command_attempt(created boolean) ON COMMIT DROP;
    WITH inserted AS (
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES (
        'company_command', {sql_literal(event_id)}, 4,
        {sql_literal(command_json)}::jsonb, {sql_literal(command_source)}
      )
      ON CONFLICT (source_id) DO NOTHING
      RETURNING 1
    )
    INSERT INTO command_attempt(created)
    SELECT EXISTS (SELECT 1 FROM inserted);
    DO $$
    DECLARE
      is_new boolean;
      current_payload jsonb;
      next_payload jsonb;
      current_state text;
      next_state text;
      next_revision integer;
      result jsonb;
    BEGIN
      SELECT created INTO is_new FROM command_attempt LIMIT 1;
      IF NOT is_new THEN
        RETURN;
      END IF;
      SELECT p.payload INTO current_payload
      FROM company_aggregate_projection p
      WHERE p.aggregate_type = 'expense_claim'
        AND p.aggregate_id = {sql_literal(expense_id)}
      ORDER BY p.revision DESC
      LIMIT 1;
      IF {sql_literal(command_type)} = 'create' THEN
        IF current_payload IS NOT NULL THEN
          RAISE EXCEPTION 'expense already exists';
        END IF;
        next_revision := 1;
        next_state := 'draft';
        next_payload := {sql_literal(request_json)}::jsonb || jsonb_build_object(
          'state', next_state, 'event_id', {sql_literal(event_id)},
          'updated_by', {sql_literal(actor_id)}
        );
      ELSE
        IF current_payload IS NULL THEN
          RAISE EXCEPTION 'expense not found';
        END IF;
        current_state := current_payload->>'state';
        IF {sql_literal(command_type)} = 'submit' THEN
          IF current_state <> 'draft' THEN RAISE EXCEPTION 'invalid expense state'; END IF;
          next_state := 'submitted';
        ELSIF {sql_literal(command_type)} = 'approve' THEN
          IF current_state <> 'submitted' THEN RAISE EXCEPTION 'invalid expense state'; END IF;
          next_state := 'approved';
        ELSIF {sql_literal(command_type)} = 'reject' THEN
          IF current_state <> 'submitted' THEN RAISE EXCEPTION 'invalid expense state'; END IF;
          next_state := 'rejected';
        ELSIF {sql_literal(command_type)} = 'resubmit' THEN
          IF current_state <> 'rejected' THEN RAISE EXCEPTION 'invalid expense state'; END IF;
          next_state := 'submitted';
        ELSE
          RAISE EXCEPTION 'unsupported expense command';
        END IF;
        SELECT coalesce(max(p.revision), 0) + 1 INTO next_revision
        FROM company_aggregate_projection p
        WHERE p.aggregate_type = 'expense_claim'
          AND p.aggregate_id = {sql_literal(expense_id)};
        next_payload := current_payload || jsonb_build_object(
          'state', next_state, 'event_id', {sql_literal(event_id)},
          'updated_by', {sql_literal(actor_id)}, 'reason', {sql_literal(request_json)}::jsonb->>'reason'
        );
      END IF;
      INSERT INTO company_aggregate_projection(
        aggregate_type, aggregate_id, revision, payload, source_event_id
      ) VALUES (
        'expense_claim', {sql_literal(expense_id)}, next_revision,
        next_payload, {sql_literal(event_id)}
      );
      INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
      VALUES (
        'company_audit_event', {sql_literal(audit_id)}, 4,
        jsonb_build_object(
          'audit_id', {sql_literal(audit_id)},
          'action', 'expense.' || {sql_literal(command_type)},
          'aggregate_type', 'expense_claim',
          'aggregate_id', {sql_literal(expense_id)},
          'actor_id', {sql_literal(actor_id)},
          'event_id', {sql_literal(event_id)},
          'state', next_state,
          'revision', next_revision
        ),
        {sql_literal('moonproj:audit:' + event_id)}
      );
      result := jsonb_build_object(
        'expense_id', {sql_literal(expense_id)}, 'state', next_state,
        'revision', next_revision, 'event_id', {sql_literal(event_id)},
        'audit_id', {sql_literal(audit_id)}, 'actor_id', {sql_literal(actor_id)}
      );
      UPDATE company_record
      SET payload = payload || jsonb_build_object('result', result)
      WHERE source_id = {sql_literal(command_source)};
    END $$;
    SELECT coalesce((SELECT created::text FROM command_attempt LIMIT 1), 'false')
           || '|' || encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM company_record
    WHERE source_id = {sql_literal(command_source)};
    COMMIT;
    """
    lines = query_lines(pool, sql)
    if len(lines) != 1:
        raise ServiceError("expense command did not return a command receipt")
    fields = lines[0].split("|", 1)
    if len(fields) != 2:
        raise ServiceError("unexpected expense command receipt shape")
    created = fields[0] == "true"
    try:
        receipt = json.loads(decode_hex(fields[1]))
    except json.JSONDecodeError as error:
        raise ServiceError("invalid expense command receipt JSON") from error
    if not created:
        existing_request = receipt.get("request")
        if existing_request != request:
            raise CommandRejected("Idempotency-Key was already used for another request", 409)
    result = receipt.get("result")
    if not isinstance(result, dict):
        raise ServiceError("expense command receipt has no result")
    return {
        "command": receipt,
        "expense": result,
        "idempotent_replay": not created,
    }


def response(handler: BaseHTTPRequestHandler, status: int, payload: Any, origin: str | None) -> None:
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    if origin is not None:
        handler.send_header("Access-Control-Allow-Origin", origin)
        handler.send_header("Vary", "Origin")
    handler.end_headers()
    handler.wfile.write(body)


def handler_factory(
    pool: PsqlPool,
    *,
    expected_schema_version: int,
    bearer_token: str,
    require_forwarded_tls: bool,
    cors_origins: set[str],
    max_response_rows: int,
    actor_id: str,
    actor_signing_secret: bytes | None,
) -> type[BaseHTTPRequestHandler]:
    token_digest = hashlib.sha256(bearer_token.encode("utf-8")).digest()

    class Handler(BaseHTTPRequestHandler):
        def _origin(self) -> str | None:
            origin = self.headers.get("Origin")
            if origin is None:
                return None
            return origin if origin in cors_origins else ""

        def _authorized(self) -> bool:
            value = self.headers.get("Authorization", "")
            if not value.startswith("Bearer "):
                return False
            supplied = value[7:].strip()
            return hmac.compare_digest(hashlib.sha256(supplied.encode("utf-8")).digest(), token_digest)

        def _tls_ok(self) -> bool:
            if not require_forwarded_tls:
                return True
            return self.headers.get("X-Forwarded-Proto", "").lower() == "https"

        def _authorize(self, origin: str | None) -> bool:
            if origin == "":
                response(self, 403, {"error": "origin not allowed"}, None)
                return False
            if not self._tls_ok():
                response(self, 400, {"error": "forwarded TLS is required"}, origin)
                return False
            if not self._authorized():
                self.send_response(401)
                self.send_header("WWW-Authenticate", "Bearer")
                self.end_headers()
                return False
            return True

        def _json_body(self) -> dict[str, Any]:
            raw_length = self.headers.get("Content-Length", "")
            try:
                length = int(raw_length)
            except ValueError as error:
                raise CommandRejected("Content-Length is required", 400) from error
            if length <= 0 or length > 128 * 1024:
                raise CommandRejected("request body is empty or too large", 413)
            try:
                value = json.loads(self.rfile.read(length).decode("utf-8"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
                raise CommandRejected("request body must be valid JSON", 400) from error
            if not isinstance(value, dict):
                raise CommandRejected("request body must be a JSON object", 400)
            return value

        def _request_actor_id(self) -> str:
            if actor_signing_secret is None:
                return actor_id
            supplied_actor = self.headers.get("X-Moonproj-Actor", "").strip()
            supplied_signature = self.headers.get("X-Moonproj-Actor-Signature", "").strip()
            if not IDENTIFIER.fullmatch(supplied_actor) or not supplied_signature:
                raise CommandRejected("signed actor assertion is required", 403)
            expected_signature = hmac.new(
                actor_signing_secret,
                supplied_actor.encode("utf-8"),
                hashlib.sha256,
            ).hexdigest()
            if not hmac.compare_digest(supplied_signature, expected_signature):
                raise CommandRejected("signed actor assertion is invalid", 403)
            return supplied_actor

        def _loan_method_alias(self, method: str) -> None:
            """Translate source PUT/DELETE loan actions to audited commands."""

            origin = self._origin()
            if not self._authorize(origin):
                return
            parsed = urlparse(self.path)
            match = re.fullmatch(r"/api/company/loans/([A-Za-z0-9_.:-]{1,128})", parsed.path)
            if match is None:
                response(self, 404, {"error": "unknown company command"}, origin)
                return
            try:
                if self.headers.get("Content-Length"):
                    body = self._json_body()
                else:
                    body = {}
                idempotency_key = self.headers.get("Idempotency-Key", "").strip()
                if not idempotency_key:
                    raise CommandRejected("Idempotency-Key is required", 400)
                actor = self._request_actor_id()
                result = loan_command(
                    pool,
                    command_type="update" if method == "PUT" else "void",
                    loan_id=match.group(1),
                    body=body,
                    actor_id=actor,
                    idempotency_key=idempotency_key,
                )
                response(self, 200, result, origin)
            except PoolExhausted as error:
                response(self, 503, {"error": str(error)}, origin)
            except CommandRejected as error:
                response(self, error.status, {"error": str(error)}, origin)
            except (OSError, ServiceError, ValueError) as error:
                response(self, 503, {"error": str(error)}, origin)

        def do_OPTIONS(self) -> None:  # noqa: N802
            origin = self.headers.get("Origin")
            if origin not in cors_origins:
                response(self, 403, {"error": "origin not allowed"}, None)
                return
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
            self.send_header(
                "Access-Control-Allow-Headers",
                "Authorization, Content-Type, Idempotency-Key, X-Moonproj-Actor, X-Moonproj-Actor-Signature",
            )
            self.send_header("Vary", "Origin")
            self.end_headers()

        def do_GET(self) -> None:  # noqa: N802
            origin = self._origin()
            if not self._authorize(origin):
                return
            parsed = urlparse(self.path)
            try:
                if parsed.path == "/api/health":
                    response(self, 200, health(pool, expected_schema_version), origin)
                elif parsed.path == "/api/company/summary":
                    response(self, 200, summary(pool, expected_schema_version), origin)
                elif parsed.path == "/api/company/receipts":
                    response(self, 200, {"items": receipts(pool)}, origin)
                elif parsed.path == "/api/company/projections":
                    value = parse_qs(parsed.query).get("aggregate_type", [None])[0]
                    response(self, 200, {"items": projections(pool, value, max_response_rows)}, origin)
                elif parsed.path == "/api/company/expenses":
                    value = parse_qs(parsed.query).get("expense_id", [None])[0]
                    response(self, 200, {"items": expenses(pool, value, max_response_rows)}, origin)
                elif re.fullmatch(r"/api/company/expenses/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    expense_id = parsed.path.rsplit("/", 1)[-1]
                    items = expenses(pool, expense_id, max_response_rows)
                    if not items:
                        response(self, 404, {"error": "expense not found"}, origin)
                    else:
                        response(self, 200, items[0], origin)
                elif parsed.path == "/api/company/contracts":
                    value = parse_qs(parsed.query).get("contract_id", [None])[0]
                    response(self, 200, {"items": contracts(pool, value, max_response_rows)}, origin)
                elif re.fullmatch(r"/api/company/contracts/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    contract_id = parsed.path.rsplit("/", 1)[-1]
                    items = contracts(pool, contract_id, max_response_rows)
                    if not items:
                        response(self, 404, {"error": "contract not found"}, origin)
                    else:
                        detail = dict(items[0])
                        detail["milestones"] = contract_milestones(pool, contract_id, max_response_rows)
                        response(self, 200, detail, origin)
                elif parsed.path == "/api/company/payment-applies":
                    query = parse_qs(parsed.query)
                    apply_value = query.get("apply_id", [None])[0]
                    view = query.get("view", ["all"])[0]
                    response(
                        self,
                        200,
                        {"items": payment_applications(pool, apply_value, view, max_response_rows)},
                        origin,
                    )
                elif parsed.path == "/api/company/payment-applies/eligibility":
                    query = parse_qs(parsed.query)
                    plan_value = query.get("plan_id", [""])[0]
                    amount_value = int(query.get("amount_minor", ["0"])[0])
                    result = payment_application_eligibility(pool, plan_value, amount_value)
                    if result is None:
                        response(self, 404, {"error": "payment plan not found"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/tenders":
                    value = parse_qs(parsed.query).get("tender_id", [None])[0]
                    response(self, 200, {"items": tenders(pool, value, max_response_rows)}, origin)
                elif re.fullmatch(r"/api/company/tenders/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    tender_id = parsed.path.rsplit("/", 1)[-1]
                    items = tenders(pool, tender_id, max_response_rows)
                    if not items:
                        response(self, 404, {"error": "tender not found"}, origin)
                    else:
                        response(self, 200, items[0], origin)
                elif parsed.path == "/api/company/suppliers":
                    value = parse_qs(parsed.query).get("supplier_id", [None])[0]
                    response(self, 200, {"items": suppliers(pool, value, max_response_rows)}, origin)
                elif parsed.path == "/api/company/supplier-risk-board":
                    response(self, 200, {"items": supplier_risk_board(pool, max_response_rows)}, origin)
                elif re.fullmatch(r"/api/company/suppliers/[A-Za-z0-9_.:-]{1,128}/risk", parsed.path):
                    supplier_id = parsed.path.split("/")[-2]
                    result = supplier_risk(pool, supplier_id)
                    if result is None:
                        response(self, 404, {"error": "supplier not found"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif re.fullmatch(r"/api/company/suppliers/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    supplier_id = parsed.path.rsplit("/", 1)[-1]
                    items = suppliers(pool, supplier_id, max_response_rows)
                    if not items:
                        response(self, 404, {"error": "supplier not found"}, origin)
                    else:
                        response(self, 200, items[0], origin)
                elif parsed.path == "/api/company/tender-splits":
                    parent_contract_id = parse_qs(parsed.query).get("parent_contract_id", [None])[0]
                    response(
                        self,
                        200,
                        {"items": contract_splits(pool, None, parent_contract_id, max_response_rows)},
                        origin,
                    )
                elif re.fullmatch(r"/api/company/tender-splits/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    split_id = parsed.path.rsplit("/", 1)[-1]
                    items = contract_splits(pool, split_id, None, max_response_rows)
                    if not items:
                        response(self, 404, {"error": "contract split not found"}, origin)
                    else:
                        response(self, 200, items[0], origin)
                elif re.fullmatch(r"/api/company/payment-applies/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    apply_value = parsed.path.rsplit("/", 1)[-1]
                    items = payment_applications(pool, apply_value, "all", max_response_rows)
                    if not items:
                        response(self, 404, {"error": "payment application not found"}, origin)
                    else:
                        response(self, 200, items[0], origin)
                elif re.fullmatch(
                    r"/api/company/sales/(customers|subscriptions|contracts|mortgages|refunds|revenues)(/[A-Za-z0-9_.:-]{1,128})?",
                    parsed.path,
                ):
                    match = re.fullmatch(
                        r"/api/company/sales/(customers|subscriptions|contracts|mortgages|refunds|revenues)(?:/([A-Za-z0-9_.:-]{1,128}))?",
                        parsed.path,
                    )
                    if match is None:
                        raise ServiceError("invalid sales read path")
                    family, aggregate_id = match.group(1), match.group(2)
                    items = sales_rows(pool, family, aggregate_id, max_response_rows)
                    if aggregate_id is not None:
                        if not items:
                            response(self, 404, {"error": f"sales {family[:-1]} not found"}, origin)
                        else:
                            response(self, 200, items[0], origin)
                    else:
                        response(self, 200, {"items": items}, origin)
                elif re.fullmatch(r"/api/company/receivables(/[A-Za-z0-9_.:-]{1,128})?", parsed.path):
                    receivable_id = parsed.path.rsplit("/", 1)[-1] if parsed.path.count("/") > 3 else None
                    items = sales_rows(pool, "receivables", receivable_id, max_response_rows)
                    if receivable_id is not None:
                        if not items:
                            response(self, 404, {"error": "receivable not found"}, origin)
                        else:
                            response(self, 200, items[0], origin)
                    else:
                        response(self, 200, {"items": items}, origin)
                elif re.fullmatch(r"/api/company/invoices(/[A-Za-z0-9_.:-]{1,128})?", parsed.path):
                    invoice_id = parsed.path.rsplit("/", 1)[-1] if parsed.path.count("/") > 3 else None
                    items = sales_rows(pool, "invoices", invoice_id, max_response_rows)
                    if invoice_id is not None:
                        if not items:
                            response(self, 404, {"error": "invoice not found"}, origin)
                        else:
                            response(self, 200, items[0], origin)
                    else:
                        response(self, 200, {"items": items}, origin)
                elif parsed.path == "/api/company/reports/overview":
                    response(self, 200, reports_overview(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/reports/cost-summary":
                    response(self, 200, report_cost_summary(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/reports/contract-payment-ledger":
                    response(self, 200, report_contract_payment_ledger(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/reports/supplier-analysis":
                    response(self, 200, report_supplier_analysis(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/reports/approval-efficiency":
                    response(self, 200, report_approval_efficiency(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/reports/project-stage-matrix":
                    response(self, 200, report_project_stage_matrix(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/projects":
                    query = parse_qs(parsed.query)
                    result = projects(
                        pool,
                        query.get("project_id", [None])[0],
                        query.get("status", [None])[0],
                        query.get("keyword", [None])[0],
                        max_response_rows,
                    )
                    response(self, 200, result, origin)
                elif re.fullmatch(r"/api/company/projects/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    project_value = parsed.path.rsplit("/", 1)[-1]
                    result = projects(pool, project_value, None, None, max_response_rows)
                    if not result["items"]:
                        response(self, 404, {"error": "project not found"}, origin)
                    else:
                        response(self, 200, result["items"][0], origin)
                elif parsed.path == "/api/company/business-units/tree":
                    response(self, 200, business_units_tree(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/budget/dict/cost-subjects":
                    response(self, 200, budget_cost_subjects(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/budget/proceedings":
                    response(self, 200, budget_proceedings(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/investment/meta/dimensions":
                    response(
                        self,
                        200,
                        {"success": True, "code": 0, "data": INVESTMENT_DIMENSIONS, "source_kind": "imported"},
                        origin,
                    )
                elif re.fullmatch(
                    r"/api/company/investment/projects/[A-Za-z0-9_.:-]{1,128}/versions",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    response(self, 200, investment_versions(pool, project_value, max_response_rows), origin)
                elif re.fullmatch(
                    r"/api/company/investment/versions/[A-Za-z0-9_.:-]{1,128}/indices",
                    parsed.path,
                ):
                    version_value = parsed.path.split("/")[-2]
                    dimension_value = parse_qs(parsed.query).get("dimension", [None])[0]
                    response(
                        self,
                        200,
                        investment_indices(pool, version_value, dimension_value, max_response_rows),
                        origin,
                    )
                elif re.fullmatch(
                    r"/api/company/investment/projects/[A-Za-z0-9_.:-]{1,128}/profit-summary",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    response(self, 200, investment_profit_summary(pool, project_value, max_response_rows), origin)
                elif re.fullmatch(
                    r"/api/company/projects/[A-Za-z0-9_.:-]{1,128}/tasks",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    task_type = parse_qs(parsed.query).get("type", [None])[0]
                    response(
                        self,
                        200,
                        plan_tasks(pool, project_value, task_type, max_response_rows),
                        origin,
                    )
                elif re.fullmatch(r"/api/company/tasks/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    task_value = parsed.path.rsplit("/", 1)[-1]
                    result = plan_task_detail(pool, task_value, max_response_rows)
                    if result is None:
                        response(
                            self,
                            404,
                            {"success": False, "code": 43001, "message": "任务不存在"},
                            origin,
                        )
                    else:
                        response(self, 200, result, origin)
                elif re.fullmatch(
                    r"/api/company/projects/[A-Za-z0-9_.:-]{1,128}/plan-summary",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    response(self, 200, plan_summary(pool, project_value, max_response_rows), origin)
                elif re.fullmatch(
                    r"/api/company/projects/[A-Za-z0-9_.:-]{1,128}/lifecycle",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    result = project_lifecycle(pool, project_value, max_response_rows)
                    if result is None:
                        response(
                            self,
                            404,
                            {"success": False, "code": 43001, "message": "项目不存在"},
                            origin,
                        )
                    else:
                        response(self, 200, result, origin)
                elif re.fullmatch(
                    r"/api/company/tasks/[A-Za-z0-9_.:-]{1,128}/delay-impact",
                    parsed.path,
                ):
                    task_value = parsed.path.split("/")[-2]
                    delay_text = parse_qs(parsed.query).get("delayDays", ["0"])[0]
                    try:
                        delay_value = int(delay_text)
                    except (TypeError, ValueError) as error:
                        raise ValueError("invalid delayDays") from error
                    result = plan_delay_impact(pool, task_value, delay_value, max_response_rows)
                    if result is None:
                        response(
                            self,
                            404,
                            {"success": False, "code": 43001, "message": "任务不存在"},
                            origin,
                        )
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/workflow/process-defs":
                    process_value = parse_qs(parsed.query).get("process_key", [None])[0]
                    response(
                        self,
                        200,
                        workflow_process_defs(pool, process_value, max_response_rows),
                        origin,
                    )
                elif re.fullmatch(
                    r"/api/company/workflow/process-defs/[A-Za-z0-9_.:-]{1,128}/preview",
                    parsed.path,
                ):
                    process_value = parsed.path.split("/")[-2]
                    result = workflow_process_defs(pool, process_value, max_response_rows)
                    if not result["items"]:
                        response(self, 404, {"error": "workflow process definition not found"}, origin)
                    else:
                        item = result["items"][0]
                        response(
                            self,
                            200,
                            {
                                "process_key": item["process_key"],
                                "process_name": item["process_name"],
                                "biz_type": item["biz_type"],
                                "steps": item["steps"],
                                "source_kind": item["source_kind"],
                                "instances_available": result["instances_available"],
                                "actions_available": result["actions_available"],
                            },
                            origin,
                        )
                elif parsed.path == "/api/company/loans":
                    query = parse_qs(parsed.query)
                    loan_value = query.get("loan_id", [None])[0]
                    state_value = query.get("apply_state", [None])[0]
                    response(
                        self,
                        200,
                        {"items": loans(pool, loan_value, state_value, max_response_rows)},
                        origin,
                    )
                elif re.fullmatch(r"/api/company/loans/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    loan_value = parsed.path.rsplit("/", 1)[-1]
                    items = loans(pool, loan_value, None, max_response_rows)
                    if not items:
                        response(self, 404, {"error": "loan not found"}, origin)
                    else:
                        response(self, 200, {"loan": items[0], "offsets": items[0].get("offsets", [])}, origin)
                elif parsed.path == "/api/company/delivery/progress":
                    query = parse_qs(parsed.query)
                    progress_value = query.get("progress_id", [None])[0]
                    project_value = query.get("project_id", [None])[0]
                    response(
                        self,
                        200,
                        {"items": delivery_progress(pool, progress_value, project_value, max_response_rows)},
                        origin,
                    )
                elif re.fullmatch(r"/api/company/delivery/progress/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    progress_id = parsed.path.rsplit("/", 1)[-1]
                    items = delivery_progress(pool, progress_id, None, max_response_rows)
                    if not items:
                        response(self, 404, {"error": "delivery progress not found"}, origin)
                    else:
                        response(self, 200, items[0], origin)
                elif parsed.path == "/api/company/delivery/outputs":
                    query = parse_qs(parsed.query)
                    output_value = query.get("output_id", [None])[0]
                    project_value = query.get("project_id", [None])[0]
                    response(
                        self,
                        200,
                        {"items": delivery_outputs(pool, output_value, project_value, max_response_rows)},
                        origin,
                    )
                elif re.fullmatch(r"/api/company/delivery/outputs/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    output_id = parsed.path.rsplit("/", 1)[-1]
                    items = delivery_outputs(pool, output_id, None, max_response_rows)
                    if not items:
                        response(self, 404, {"error": "delivery output not found"}, origin)
                    else:
                        response(self, 200, items[0], origin)
                elif parsed.path == "/api/company/delivery/tasks":
                    query = parse_qs(parsed.query)
                    task_value = query.get("task_id", [None])[0]
                    project_value = query.get("project_id", [None])[0]
                    response(
                        self,
                        200,
                        {"items": delivery_tasks(pool, task_value, project_value, max_response_rows)},
                        origin,
                    )
                elif re.fullmatch(r"/api/company/delivery/tasks/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    task_id = parsed.path.rsplit("/", 1)[-1]
                    items = delivery_tasks(pool, task_id, None, max_response_rows)
                    if not items:
                        response(self, 404, {"error": "delivery task not found"}, origin)
                    else:
                        detail = {"task": items[0], "reports": delivery_task_reports(pool, None, task_id, max_response_rows)}
                        response(self, 200, detail, origin)
                elif parsed.path == "/api/company/delivery/task-reports":
                    query = parse_qs(parsed.query)
                    report_value = query.get("report_id", [None])[0]
                    task_value = query.get("task_id", [None])[0]
                    response(
                        self,
                        200,
                        {"items": delivery_task_reports(pool, report_value, task_value, max_response_rows)},
                        origin,
                    )
                elif parsed.path == "/api/company/delivery/plan-summary":
                    project_value = parse_qs(parsed.query).get("project_id", [""])[0]
                    if not project_value:
                        raise CommandRejected("project_id is required", 422)
                    response(self, 200, delivery_plan_summary(pool, project_value, max_response_rows), origin)
                elif parsed.path == "/api/company/delivery/overview":
                    project_value = parse_qs(parsed.query).get("project_id", [""])[0]
                    if not project_value:
                        raise CommandRejected("project_id is required", 422)
                    response(self, 200, delivery_overview(pool, project_value, max_response_rows), origin)
                elif parsed.path.startswith("/api/"):
                    response(self, 404, {"error": "unknown read-model endpoint"}, origin)
                else:
                    response(self, 404, {"error": "not found"}, origin)
            except PoolExhausted as error:
                response(self, 503, {"error": str(error)}, origin)
            except CommandRejected as error:
                response(self, error.status, {"error": str(error)}, origin)
            except (OSError, ServiceError, ValueError) as error:
                response(self, 503, {"error": str(error)}, origin)

        def do_POST(self) -> None:  # noqa: N802
            origin = self._origin()
            if not self._authorize(origin):
                return
            parsed = urlparse(self.path)
            try:
                body = self._json_body()
                idempotency_key = self.headers.get("Idempotency-Key", "").strip()
                if not idempotency_key:
                    raise CommandRejected("Idempotency-Key is required", 400)
                command_family = "expense"
                if parsed.path == "/api/company/expenses":
                    command_type = "create"
                    aggregate_id = None
                elif parsed.path == "/api/company/contracts":
                    command_family = "contract"
                    command_type = "create"
                    aggregate_id = None
                elif parsed.path == "/api/company/payment-applies":
                    command_family = "payment_application"
                    command_type = "create"
                    aggregate_id = None
                elif parsed.path == "/api/company/tenders":
                    command_family = "tender"
                    command_type = "create"
                    aggregate_id = None
                elif parsed.path == "/api/company/suppliers":
                    command_family = "supplier"
                    command_type = "create"
                    aggregate_id = None
                elif parsed.path == "/api/company/loans":
                    command_family = "loan"
                    command_type = "create"
                    aggregate_id = None
                elif parsed.path == "/api/company/tender-splits":
                    command_family = "contract_split"
                    command_type = "create"
                    aggregate_id = None
                elif re.fullmatch(
                    r"/api/company/sales/(customers|subscriptions|contracts|mortgages|refunds)",
                    parsed.path,
                ):
                    command_family = "sales"
                    command_type = "create"
                    aggregate_id = None
                elif parsed.path == "/api/company/delivery/progress":
                    command_family = "delivery"
                    command_type = "create"
                    aggregate_id = None
                    body["_delivery_family"] = "progress"
                elif parsed.path == "/api/company/delivery/outputs":
                    command_family = "delivery"
                    command_type = "create"
                    aggregate_id = None
                    body["_delivery_family"] = "output"
                else:
                    expense_match = re.fullmatch(
                        r"/api/company/expenses/([A-Za-z0-9_.:-]{1,128})/(submit|approve|reject|resubmit)",
                        parsed.path,
                    )
                    contract_match = re.fullmatch(
                        r"/api/company/contracts/([A-Za-z0-9_.:-]{1,128})/(submit|approve|reject|resubmit)",
                        parsed.path,
                    )
                    payment_match = re.fullmatch(
                        r"/api/company/payment-applies/([A-Za-z0-9_.:-]{1,128})/(submit|approve|reject|resubmit|update|void)",
                        parsed.path,
                    )
                    tender_match = re.fullmatch(
                        r"/api/company/tenders/([A-Za-z0-9_.:-]{1,128})/(publish|open_bidding|award|complete|cancel)",
                        parsed.path,
                    )
                    supplier_match = re.fullmatch(
                        r"/api/company/suppliers/([A-Za-z0-9_.:-]{1,128})/(update|submit_review|review|blacklist|void)",
                        parsed.path,
                    )
                    loan_match = re.fullmatch(
                        r"/api/company/loans/([A-Za-z0-9_.:-]{1,128})/(submit-for-approval|offset|sync-from-workflow|update|void)",
                        parsed.path,
                    )
                    sales_match = re.fullmatch(
                        r"/api/company/sales/(customers|subscriptions|contracts|mortgages|refunds)/([A-Za-z0-9_.:-]{1,128})/(update|block|archive|convert|cancel|fulfill|open_receivable|approve|release|pay|reject)",
                        parsed.path,
                    )
                    delivery_progress_match = re.fullmatch(
                        r"/api/company/delivery/progress/([A-Za-z0-9_.:-]{1,128})/(report|accept|reject)",
                        parsed.path,
                    )
                    delivery_output_match = re.fullmatch(
                        r"/api/company/delivery/outputs/([A-Za-z0-9_.:-]{1,128})/confirm",
                        parsed.path,
                    )
                    delivery_task_report_match = re.fullmatch(
                        r"/api/company/delivery/tasks/([A-Za-z0-9_.:-]{1,128})/report",
                        parsed.path,
                    )
                    if expense_match is not None:
                        aggregate_id, command_type = expense_match.group(1), expense_match.group(2)
                    elif contract_match is not None:
                        command_family = "contract"
                        aggregate_id, command_type = contract_match.group(1), contract_match.group(2)
                    elif payment_match is not None:
                        command_family = "payment_application"
                        aggregate_id, command_type = payment_match.group(1), payment_match.group(2)
                    elif tender_match is not None:
                        command_family = "tender"
                        aggregate_id, command_type = tender_match.group(1), tender_match.group(2)
                    elif supplier_match is not None:
                        command_family = "supplier"
                        aggregate_id, command_type = supplier_match.group(1), supplier_match.group(2)
                    elif loan_match is not None:
                        command_family = "loan"
                        aggregate_id = loan_match.group(1)
                        command_type = {
                            "submit-for-approval": "submit",
                            "sync-from-workflow": "sync_from_workflow",
                        }.get(loan_match.group(2), loan_match.group(2))
                    elif sales_match is not None:
                        command_family = "sales"
                        aggregate_id = sales_match.group(2)
                        command_type = sales_match.group(3)
                        body["_sales_family"] = sales_match.group(1)
                    elif delivery_progress_match is not None:
                        command_family = "delivery"
                        aggregate_id = delivery_progress_match.group(1)
                        command_type = delivery_progress_match.group(2)
                        body["_delivery_family"] = "progress"
                    elif delivery_output_match is not None:
                        command_family = "delivery"
                        aggregate_id = delivery_output_match.group(1)
                        command_type = "confirm"
                        body["_delivery_family"] = "output"
                    elif delivery_task_report_match is not None:
                        command_family = "delivery"
                        aggregate_id = delivery_task_report_match.group(1)
                        command_type = "report"
                        body["_delivery_family"] = "task_report"
                    else:
                        if parsed.path.startswith("/api/"):
                            response(self, 404, {"error": "unknown company command"}, origin)
                        else:
                            response(self, 404, {"error": "not found"}, origin)
                        return
                actor = self._request_actor_id()
                if command_family == "contract":
                    result = contract_command(
                        pool,
                        command_type=command_type,
                        contract_id=aggregate_id,
                        body=body,
                        actor_id=actor,
                        idempotency_key=idempotency_key,
                    )
                elif command_family == "payment_application":
                    result = payment_application_command(
                        pool,
                        command_type=command_type,
                        apply_id=aggregate_id,
                        body=body,
                        actor_id=actor,
                        idempotency_key=idempotency_key,
                    )
                elif command_family == "tender":
                    result = tender_command(
                        pool,
                        command_type=command_type,
                        tender_id=aggregate_id,
                        body=body,
                        actor_id=actor,
                        idempotency_key=idempotency_key,
                    )
                elif command_family == "supplier":
                    result = supplier_command(
                        pool,
                        command_type=command_type,
                        supplier_id=aggregate_id,
                        body=body,
                        actor_id=actor,
                        idempotency_key=idempotency_key,
                    )
                elif command_family == "contract_split":
                    result = split_command(
                        pool,
                        command_type=command_type,
                        split_id=aggregate_id,
                        body=body,
                        actor_id=actor,
                        idempotency_key=idempotency_key,
                    )
                elif command_family == "sales":
                    family = str(body.pop("_sales_family", ""))
                    if not family:
                        family = parsed.path.rstrip("/").rsplit("/", 1)[-1]
                    result = sales_command(
                        pool,
                        family=family,
                        command_type=command_type,
                        aggregate_id=aggregate_id,
                        body=body,
                        actor_id=actor,
                        idempotency_key=idempotency_key,
                    )
                elif command_family == "delivery":
                    family = str(body.pop("_delivery_family", ""))
                    result = delivery_command(
                        pool,
                        family=family,
                        command_type=command_type,
                        aggregate_id=aggregate_id,
                        body=body,
                        actor_id=actor,
                        idempotency_key=idempotency_key,
                    )
                elif command_family == "loan":
                    result = loan_command(
                        pool,
                        command_type=command_type,
                        loan_id=aggregate_id,
                        body=body,
                        actor_id=actor,
                        idempotency_key=idempotency_key,
                    )
                else:
                    result = expense_command(
                        pool,
                        command_type=command_type,
                        expense_id=aggregate_id,
                        body=body,
                        actor_id=actor,
                        idempotency_key=idempotency_key,
                    )
                creates_record = command_type == "create" or (
                    command_family == "sales" and command_type == "open_receivable"
                ) or (
                    command_family == "delivery" and family == "task_report"
                )
                status = 201 if creates_record and not result["idempotent_replay"] else 200
                response(self, status, result, origin)
            except PoolExhausted as error:
                response(self, 503, {"error": str(error)}, origin)
            except CommandRejected as error:
                response(self, error.status, {"error": str(error)}, origin)
            except (OSError, ServiceError, ValueError) as error:
                response(self, 503, {"error": str(error)}, origin)

        def do_PUT(self) -> None:  # noqa: N802
            self._loan_method_alias("PUT")

        def do_DELETE(self) -> None:  # noqa: N802
            self._loan_method_alias("DELETE")

        def log_message(self, format: str, *values: object) -> None:
            sys.stderr.write("company-service: " + (format % values) + "\n")

    return Handler


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=4174)
    parser.add_argument("--psql", default=None)
    parser.add_argument("--pg-host", default=os.environ.get("PGHOST", "/tmp"))
    parser.add_argument("--pg-port", default=os.environ.get("PGPORT", "5432"))
    parser.add_argument("--pg-user", default=os.environ.get("PGUSER", "moonproj"))
    parser.add_argument("--database", default=os.environ.get("PGDATABASE", "moonproj"))
    parser.add_argument("--token-env", default="MOONPROJ_SERVICE_TOKEN")
    parser.add_argument("--schema-version", type=int, default=4)
    parser.add_argument("--pool-size", type=int, default=4)
    parser.add_argument("--acquire-timeout", type=float, default=2.0)
    parser.add_argument("--query-timeout", type=float, default=10.0)
    parser.add_argument("--max-response-rows", type=int, default=500)
    parser.add_argument("--actor-id", default=os.environ.get("MOONPROJ_ACTOR_ID", "service-operator"))
    parser.add_argument("--actor-signing-secret-env", default=None)
    parser.add_argument("--require-forwarded-tls", action="store_true")
    parser.add_argument("--cors-origin", action="append", default=[])
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Z][A-Z0-9_]{2,127}", args.token_env):
        parser.error("--token-env must be an uppercase environment variable name")
    bearer_token = os.environ.get(args.token_env, "")
    if not bearer_token:
        parser.error(f"token environment variable is not set: {args.token_env}")
    if args.schema_version <= 0:
        parser.error("--schema-version must be positive")
    if args.max_response_rows <= 0 or args.max_response_rows > 10000:
        parser.error("--max-response-rows must be between 1 and 10000")
    if not IDENTIFIER.fullmatch(args.actor_id):
        parser.error("--actor-id contains unsupported characters")
    actor_signing_secret = None
    if args.actor_signing_secret_env is not None:
        if not re.fullmatch(r"[A-Z][A-Z0-9_]{2,127}", args.actor_signing_secret_env):
            parser.error("--actor-signing-secret-env must be an uppercase environment variable name")
        secret = os.environ.get(args.actor_signing_secret_env, "")
        if not secret:
            parser.error(
                "actor signing secret environment variable is not set: "
                f"{args.actor_signing_secret_env}"
            )
        actor_signing_secret = secret.encode("utf-8")
    if args.host in {"0.0.0.0", "::", "[::]"}:
        parser.error("service must bind privately behind its gateway")
    try:
        pool = PsqlPool(
            psql=args.psql,
            pg_host=args.pg_host,
            pg_port=args.pg_port,
            pg_user=args.pg_user,
            database=args.database,
            size=args.pool_size,
            acquire_timeout=args.acquire_timeout,
            query_timeout=args.query_timeout,
        )
        server = ThreadingHTTPServer(
            (args.host, args.port),
            handler_factory(
                pool,
                expected_schema_version=args.schema_version,
                bearer_token=bearer_token,
                require_forwarded_tls=args.require_forwarded_tls,
                cors_origins=set(args.cors_origin),
                max_response_rows=args.max_response_rows,
                actor_id=args.actor_id,
                actor_signing_secret=actor_signing_secret,
            ),
        )
        print(f"company service listening on http://{args.host}:{args.port}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()
            pool.close()
        return 0
    except (OSError, ServiceError, ValueError) as error:
        print(f"company PostgreSQL service failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
