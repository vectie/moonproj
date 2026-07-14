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
* ``/api/company/import/{project,contract}/template`` (GET, static CSV
  template read; import commands remain authenticated and separate)
* ``/api/company/summary``
* ``/api/company/auth/me?userCode=<source user code>`` (GET, non-secret profile read)
* ``/api/company/receipts``
* ``/api/company/projections?aggregate_type=<optional>``
* ``/api/company/expenses`` and ``/api/company/expenses/<id>`` (GET)
* ``/api/company/budget/expenses`` (GET, source-compatible imported list)
* ``/api/company/budget/expenses/<guid>`` (GET, source-compatible imported detail)
* ``/api/company/expenses`` (POST create draft)
* ``/api/company/expenses/<id>/{submit,approve,reject,resubmit}`` (POST)
* ``/api/company/contracts`` and ``/api/company/contracts/<id>`` (GET)
* ``/api/company/source/cost/contracts[/{id}[/milestones]]`` and
  ``/api/company/source/cost/payment-applies`` (GET, imported-source contract
  and payment observations)
* ``/api/company/source/invoice/{in,out}`` and
  ``/api/company/source/invoice/tax-ledger`` (GET, imported-source invoice
  and tax-ledger observations)
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
* ``/api/company/srm/providers[/{guid}]``, ``/api/company/srm/providers/{guid}/risk``,
  ``/api/company/srm/stats/overview``,
  and ``/api/company/srm/risk-board`` (GET)
  source-compatible, non-authorizing reads with coverage metadata
* ``/api/company/source/srm/{categories,dict/eval-results,dict/sources}``
  (GET, source/definition dictionary observations)
* ``/api/company/tender-splits`` (GET/POST)
* ``/api/company/source/tender/{tenders,awards,splits}`` (GET, source ERP
  procurement observations; empty source tables stay explicit)
* ``/api/company/sales/{customers,subscriptions,contracts,mortgages,refunds,revenues}`` (GET)
* ``/api/company/receivables`` (GET)
* ``/api/company/sales/{customers,subscriptions,contracts,mortgages,refunds}`` (POST)
  with idempotent lifecycle commands
* ``/api/company/source/sales/{customers,subscriptions,contracts,mortgages,refunds,revenues}``
  (GET, source ERP sales observations; empty source tables stay explicit)
* ``/api/company/delivery/{progress,outputs,tasks,task-reports,plan-summary}`` (GET)
* ``/api/company/delivery/{progress,outputs,tasks}/...`` (POST)
  with source-preserving reads and idempotent local commands
* ``/api/company/source/delivery/{progress,outputs}`` (GET, source ERP
  progress/output observations; empty or missing source tables stay explicit)
* ``/api/company/reports/{cost-summary,contract-payment-ledger,
  supplier-analysis,approval-efficiency,project-stage-matrix,overview}`` (GET)
* ``/api/company/source/cost/dynamic-cost/<id>/remarks`` (GET, source
  cost-subject remark observation)
* ``/api/company/dashboard/group/{overview,funnel,top-anomalies}`` and
  ``/api/company/dashboard/project/<id>/{kpi,anomalies}`` (GET,
  source-backed bounded cockpit reads)
* ``/api/company/dashboard/v2/group`` (GET, scoped source-backed cockpit v2
  observation)
* ``/api/company/dashboard/v3/group`` (GET, source-shaped scoped cockpit v3
  observation with explicit missing-table coverage)
* ``/api/company/workflow/process-defs`` and
  ``/api/company/workflow/process-defs/<process-key>/preview`` (GET)
* ``/api/company/source/workflow/{tasks/mine,tasks/initiated,tasks/my-history,
  instances/by-biz,instances/<id>}`` (GET, non-authorizing workflow
  observations)
* ``/api/company/projects`` and ``/api/company/projects/<id>`` (GET)
* ``/api/company/business-units/tree`` (GET, source-compatible MDM read)
* ``/api/company/budget/dict/cost-subjects`` and
  ``/api/company/budget/proceedings`` (GET, source-compatible budget reads)
* ``/api/company/source/budget/users-in-bu`` and
  ``/api/company/source/budget/my-loan-balance`` (GET, explicit-scope source
  reads)
* ``/api/company/investment/{projects,versions,meta}/...`` (GET,
  source-compatible investment reads)
* ``/api/company/investment/projects/<id>/sensitivity`` (GET,
  source-compatible read-only sensitivity observation)
* ``/api/company/investment/projects/<id>/excel-imports`` (GET,
  source-compatible import-history observation; absent import rows stay empty)
* ``/api/company/investment/excel-imports/<id>[/bridge-plan|/index-upsert-preview|
  /profit-table|/plan-line-preview]`` and
  ``/api/company/investment/projects/<id>/{plan-lines,subject-mappings,
  profit-cockpit}`` (GET, source-preserving Excel/cockpit boundaries; absent
  workbook rows stay explicit)
* ``/api/company/investment/projects/<id>/profit-actual-v2`` (GET,
  source-compatible cost-dashboard v3 read)
* ``/api/company/admin/{dict,audit}/...`` (GET, source-compatible governance reads)
* ``/api/company/admin/quality/overview`` and
  ``/api/company/admin/health/{tables,bpm-pool,full}`` (GET, source-coverage
  governance reads; runtime metrics remain unavailable)
* ``/api/company/admin/{llm/status,ai/diag}`` (GET, redacted diagnostic reads;
  provider execution remains disabled)
* ``/api/company/admin/ocr/status`` and ``/api/company/admin/error-log`` (GET,
  source-compatible metadata reads; OCR execution and raw error-network fields
  remain gated)
* ``/api/company/ai-stats/{overview,activity,badge}`` (GET, source-compatible
  AI analytics reads; LLM/OCR execution and draft mutation remain gated)
* ``/api/company/ai-hub/{corrections,correction-stats,drafts,query-log,usage-stats}``
  (GET, source-compatible AI Hub observation reads; provider execution and
  draft/query mutations remain gated)
* ``/api/company/webhook/config`` (GET, source-compatible redacted webhook
  configuration read; provider delivery, writes, and overdue scans remain gated)
* ``/api/company/reports/templates/meta`` and ``/api/company/reports/templates``
  (GET, source-compatible report-builder metadata/template reads; execution and
  template mutation remain gated)
* ``/api/company/cashflow/forecast`` (GET, source-compatible cashflow read)
* ``/api/company/cashflow/forecast-v3`` (GET, source-compatible cashflow read)
* ``/api/company/cashflow/forecast/detail`` (GET, source-compatible drill-down)
* ``/api/company/cashflow/inflow`` (GET, source-compatible cashflow read)
* ``/api/company/cashflow/net`` (GET, source-compatible cashflow read)
* ``/api/company/cashflow/gap-alert`` (GET, source-compatible cashflow read)
* ``/api/company/cbs/*`` (GET, source-compatible non-authorizing CBS reads)
* ``/api/company/fund/{plans,gap-analysis,dispatches}`` (GET, source-compatible
  non-authorizing liquidity-plan reads)
* ``/api/company/warning/{badge,'',rules,scans,custom-rules,rule-templates,tickets/mine}``
  (GET, observed source-quality reads)
* ``/api/company/rbac/users`` (GET, source-backed identity roster read)
* ``/api/company/rbac/me`` (GET, source identity/role observation; never an
  authority decision)
* ``/api/company/rbac/roles`` and ``/api/company/rbac/roles/<code>`` (GET,
  source role observation; absent role tables remain explicit)
* ``/api/company/rbac/permission-catalog`` (GET, source-defined metadata;
  never an authority grant)
* ``/api/company/auth/prefs`` (GET, source preference observation; preference
  writes remain gated)
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


IMPORT_TEMPLATE_HEADERS: dict[str, tuple[str, ...]] = {
    "project": (
        "projCode",
        "projName",
        "projShortName",
        "buCode",
        "projStatus",
        "beginDate",
    ),
    "contract": (
        "contractCode",
        "contractName",
        "projCode",
        "htClass",
        "yfProviderName",
        "htAmount",
        "signDate",
    ),
}


def import_template(biz_type: str) -> str | None:
    """Return the source ERP CSV import template without touching data.

    The source ``import`` route only emits a fixed header row for these two
    business types.  Keeping this as a static read preserves the download
    contract while leaving the authenticated import commands and their
    durable audit boundary separate.
    """

    if not IDENTIFIER.fullmatch(biz_type):
        raise ValueError("invalid import business type")
    headers = IMPORT_TEMPLATE_HEADERS.get(biz_type)
    if headers is None:
        return None
    return "\ufeff" + ",".join(headers) + "\n"


@dataclass
class PsqlSession:
    command: list[str]
    query_timeout: float
    process: subprocess.Popen[bytes] | None = None

    def start(self) -> None:
        if self.process is not None and self.process.poll() is None:
            return
        self.close()
        self.process = subprocess.Popen(
            self.command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            # ``execute`` waits with ``select``.  Keep the pipe unbuffered so
            # TextIOWrapper read-ahead cannot hide bytes that select would no
            # longer report as ready on large dashboard result sets.
            text=False,
            bufsize=0,
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
            process.stdin.write(command.encode("utf-8"))
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
                if line == b"":
                    raise ServiceError("database session closed unexpectedly")
                value = line.rstrip(b"\r\n").decode("utf-8")
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

    def execute_read(self, sql: str) -> list[str]:
        """Run a read query once more after a stale session is discarded.

        A failed ``psql`` session is never reused by ``execute``.  Reads are
        safe to retry against the replacement session, which prevents a cold
        or externally-closed session from surfacing as a transient 503 while
        keeping command execution strictly single-attempt.
        """

        try:
            return self.execute(sql)
        except ServiceError:
            return self.execute(sql)


def query_lines(pool: PsqlPool, sql: str) -> list[str]:
    normalized = "\n".join(line.strip() for line in sql.splitlines() if line.strip())
    return [line for line in pool.execute_read(normalized) if line]


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
            "expense_detail_read",
            "contract_command",
            "payment_application_read",
            "payment_application_command",
            "procurement_read",
            "supplier_read",
            "supplier_source_read",
            "supplier_risk_read",
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
            "profile_observation_read",
            "preference_observation_read",
            "rbac_observation_read",
            "audit_receipt",
            "attachment_metadata_read",
            "notification_metadata_read",
            "ocr_status_read",
            "error_log_metadata_read",
            "ai_analytics_read",
            "ai_hub_read",
            "cost_dashboard_read",
            "dashboard_v2_read",
            "admin_health_full_read",
            "ai_diagnostic_read",
            "webhook_config_read",
            "report_template_read",
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
            "expense_detail_read",
            "contract_command",
            "payment_application_read",
            "payment_application_command",
            "procurement_read",
            "supplier_read",
            "supplier_source_read",
            "supplier_risk_read",
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
            "profile_observation_read",
            "preference_observation_read",
            "rbac_observation_read",
            "audit_receipt",
            "ai_hub_read",
            "cost_dashboard_read",
            "dashboard_v2_read",
            "admin_health_full_read",
            "ai_diagnostic_read",
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


EXPENSE_SOURCE_TABLES = {
    "vcb_expense",
    "cb_expense_detail",
    "cb_expense_split",
    "sys_user",
    "mu_business_unit",
}

EXPENSE_DETAIL_SOURCE_TABLES = EXPENSE_SOURCE_TABLES | {
    "my_biz_param_option",
    "vys_proceeding",
}


def budget_expenses(
    pool: PsqlPool,
    expense_id: str | None,
    user_code: str | None,
    apply_state: str | None,
    max_rows: int,
) -> dict[str, Any] | None:
    """Read source reimbursement rows for the ERP budget list.

    This is intentionally separate from ``expenses()``, which reads local
    command projections.  Imported rows and locally-created command rows have
    different ownership and provenance and must not be silently merged.
    """

    if expense_id is not None and not IDENTIFIER.fullmatch(expense_id):
        raise ValueError("invalid expense_id")
    if user_code is not None and not IDENTIFIER.fullmatch(user_code):
        raise ValueError("invalid user_code")
    users = _raw_source_rows(pool, "sys_user", max(max_rows, 100), EXPENSE_SOURCE_TABLES)
    units = {
        str(row["payload"].get("bu_guid") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "mu_business_unit", max(max_rows, 100), EXPENSE_SOURCE_TABLES)
    }
    user_id = None
    if user_code is not None:
        selected = next(
            (
                row
                for row in users
                if str(row["payload"].get("user_code") or "") == user_code
            ),
            None,
        )
        if selected is None:
            return None
        user_id = str(selected["payload"].get("user_id") or selected["record_id"])

    raw = _raw_source_rows(pool, "vcb_expense", max(max_rows, 500), EXPENSE_SOURCE_TABLES)
    filtered = []
    for row in raw:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        if expense_id is not None and str(payload.get("expense_guid") or row["record_id"]) != expense_id:
            continue
        if user_id is not None and str(payload.get("applied_by") or "") != user_id:
            continue
        if apply_state is not None and str(payload.get("apply_state") or "") != apply_state:
            continue
        filtered.append(row)
    filtered.sort(
        key=lambda row: (
            str(row["payload"].get("created_at") or row["payload"].get("apply_date") or ""),
            str(row["payload"].get("expense_guid") or row["record_id"]),
        ),
        reverse=True,
    )
    result: list[dict[str, Any]] = []
    for row in filtered[:max_rows]:
        payload = row["payload"]
        applied_by = str(payload.get("applied_by") or "")
        apply_dept = str(payload.get("apply_dept_guid") or payload.get("dept_guid") or "")
        user_payload = next(
            (user["payload"] for user in users if str(user["payload"].get("user_id") or "") == applied_by),
            {},
        )
        result.append(
            {
                "expenseGuid": str(payload.get("expense_guid") or row["record_id"]),
                "expenseCode": str(payload.get("expense_code") or ""),
                "subject": str(payload.get("subject") or ""),
                "applyState": str(payload.get("apply_state") or ""),
                "payState": str(payload.get("pay_state") or ""),
                "expenseAmount": _report_float(payload, "expense_amount"),
                "offsetAmount": _report_float(payload, "offset_amount"),
                "payAmount": _report_float(payload, "pay_amount"),
                "appliedByName": str(user_payload.get("emp_name") or user_payload.get("user_name") or applied_by),
                "applyDeptName": str(units.get(apply_dept, {}).get("bu_name") or apply_dept),
                "applyDate": str(payload.get("apply_date") or ""),
                "payUnit": str(payload.get("pay_unit") or ""),
                "processInstanceGuid": str(payload.get("process_instance_guid") or ""),
                "createdAt": str(payload.get("created_at") or ""),
                "sourceKind": "imported",
            }
        )
    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), EXPENSE_SOURCE_TABLES))
        for table in sorted(EXPENSE_SOURCE_TABLES)
    }
    return {
        "success": True,
        "code": 0,
        "data": result,
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [table for table, count in coverage.items() if count == 0],
    }


def budget_expense_detail(
    pool: PsqlPool,
    expense_id: str,
    user_code: str | None,
    max_rows: int,
) -> dict[str, Any] | None:
    """Read the source expense detail contract without promoting source rows.

    The ERP detail endpoint returns one expense plus its detail and four-
    dimensional allocation rows.  Empty source exports remain a successful
    read with ``expense: null`` so the browser can show an explicit empty
    source state instead of falling back to the designer fixture.
    """

    if not IDENTIFIER.fullmatch(expense_id):
        raise ValueError("invalid expense_id")
    source_list = budget_expenses(pool, expense_id, user_code, None, max_rows)
    if source_list is None:
        return None
    expense = source_list["data"][0] if source_list["data"] else None
    raw_details = _raw_source_rows(pool, "cb_expense_detail", max(max_rows, 500), EXPENSE_DETAIL_SOURCE_TABLES)
    raw_splits = _raw_source_rows(pool, "cb_expense_split", max(max_rows, 500), EXPENSE_DETAIL_SOURCE_TABLES)
    users = _raw_source_rows(pool, "sys_user", max(max_rows, 100), EXPENSE_DETAIL_SOURCE_TABLES)
    units = _raw_source_rows(pool, "mu_business_unit", max(max_rows, 100), EXPENSE_DETAIL_SOURCE_TABLES)
    options = _raw_source_rows(pool, "my_biz_param_option", max(max_rows, 500), EXPENSE_DETAIL_SOURCE_TABLES)
    proceedings = _raw_source_rows(pool, "vys_proceeding", max(max_rows, 500), EXPENSE_DETAIL_SOURCE_TABLES)

    def matches(payload: dict[str, Any]) -> bool:
        return str(payload.get("expense_guid") or "") == expense_id

    details: list[dict[str, Any]] = []
    for row in raw_details:
        payload = row["payload"]
        if matches(payload):
            details.append(
                {
                    "detailGuid": str(payload.get("detail_guid") or row["record_id"]),
                    "summary": str(payload.get("summary") or ""),
                    "amount": _report_float(payload, "amount"),
                    "occurDate": str(payload.get("occur_date") or ""),
                }
            )

    user_by_id = {
        str(row["payload"].get("user_id") or row["record_id"]): row["payload"]
        for row in users
    }
    unit_by_id = {
        str(row["payload"].get("bu_guid") or row["record_id"]): row["payload"]
        for row in units
    }
    option_by_code = {
        str(row["payload"].get("param_code") or ""): row["payload"]
        for row in options
        if str(row["payload"].get("param_name") or "") == "cost_subject"
    }
    proceeding_by_id = {
        str(row["payload"].get("proceeding_guid") or row["record_id"]): row["payload"]
        for row in proceedings
    }
    splits: list[dict[str, Any]] = []
    for row in raw_splits:
        payload = row["payload"]
        if not matches(payload):
            continue
        user_guid = str(payload.get("user_guid") or "")
        dept_guid = str(payload.get("dept_guid") or "")
        cost_code = str(payload.get("cost_subject_code") or "")
        proceeding_guid = str(payload.get("proceeding_guid") or "")
        user_payload = user_by_id.get(user_guid, {})
        dept_payload = unit_by_id.get(dept_guid, {})
        cost_payload = option_by_code.get(cost_code, {})
        proceeding_payload = proceeding_by_id.get(proceeding_guid, {})
        splits.append(
            {
                "splitGuid": str(payload.get("split_guid") or row["record_id"]),
                "user": {
                    "userGuid": user_guid,
                    "userName": str(user_payload.get("emp_name") or user_payload.get("user_name") or user_guid),
                },
                "dept": {
                    "deptGuid": dept_guid,
                    "deptName": str(dept_payload.get("bu_name") or dept_guid),
                },
                "costSubject": {
                    "code": cost_code,
                    "name": str(cost_payload.get("param_value") or cost_code),
                },
                "proceeding": (
                    {
                        "guid": proceeding_guid,
                        "name": str(proceeding_payload.get("proceeding_name") or proceeding_guid),
                    }
                    if proceeding_guid
                    else None
                ),
                "amount": _report_float(payload, "amount"),
            }
        )

    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), EXPENSE_DETAIL_SOURCE_TABLES))
        for table in sorted(EXPENSE_DETAIL_SOURCE_TABLES)
    }
    return {
        "success": True,
        "code": 0,
        "data": {"expense": expense, "details": details, "splits": splits},
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [table for table, count in coverage.items() if count == 0],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


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


COST_SOURCE_TABLES = {
    "cb_contract",
    "cb_htfk_apply",
    "cb_htfkplan",
    "cb_contract_milestone",
    "ep_project",
    "mu_business_unit",
    "sys_user",
    "jd_task",
}


def _cost_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _cost_source_coverage(pool: PsqlPool, max_rows: int) -> dict[str, int]:
    return {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), COST_SOURCE_TABLES))
        for table in sorted(COST_SOURCE_TABLES)
    }


def _cost_source_related_rows(
    pool: PsqlPool,
    max_rows: int,
) -> tuple[
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
]:
    return (
        _raw_source_rows(pool, "cb_contract", max(max_rows, 500), COST_SOURCE_TABLES),
        _raw_source_rows(pool, "cb_htfk_apply", max(max_rows, 500), COST_SOURCE_TABLES),
        _raw_source_rows(pool, "cb_htfkplan", max(max_rows, 500), COST_SOURCE_TABLES),
        _raw_source_rows(pool, "cb_contract_milestone", max(max_rows, 500), COST_SOURCE_TABLES),
        _raw_source_rows(pool, "ep_project", max(max_rows, 500), COST_SOURCE_TABLES),
        _raw_source_rows(pool, "mu_business_unit", max(max_rows, 500), COST_SOURCE_TABLES),
    )


def _cost_source_users(pool: PsqlPool, max_rows: int) -> dict[str, dict[str, Any]]:
    return {
        str(row["payload"].get("user_id") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "sys_user", max(max_rows, 500), COST_SOURCE_TABLES)
    }


def _cost_source_contract_row(
    row: dict[str, Any],
    projects: dict[str, dict[str, Any]],
    units: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    payload = row["payload"]
    contract_id = _report_text(payload, "contract_guid", row["record_id"])
    amount = _report_float(payload, "ht_amount")
    alteration = _report_float(payload, "sum_alter_amount")
    project_id = _report_text(payload, "proj_guid")
    bu_id = _report_text(payload, "bu_guid")
    result = {
        "contractGuid": contract_id,
        "contractCode": _report_text(payload, "contract_code", contract_id),
        "contractName": _report_text(payload, "contract_name", contract_id),
        "buGuid": bu_id,
        "buName": _report_text(units.get(bu_id, {}), "bu_name", bu_id),
        "projGuid": project_id,
        "projName": _report_text(projects.get(project_id, {}), "proj_name", project_id),
        "htTypeCode": _report_text(payload, "ht_type_code"),
        "htClass": payload.get("ht_class", 0),
        "yfProviderName": _report_text(payload, "yf_provider_name"),
        "yfCorporation": _report_text(payload, "yf_corporation"),
        "htAmount": amount,
        "sumAlterAmount": alteration,
        "currentAmount": amount + alteration,
        "signDate": _report_text(payload, "sign_date"),
        "htCfState": _report_text(payload, "ht_cf_state"),
        "jsState": _report_text(payload, "js_state"),
        "costCode": _report_text(payload, "cost_code"),
        "rCode": _report_text(payload, "r_code"),
        "l3Code": _report_text(payload, "l3_code"),
        "cbState": _report_text(payload, "cb_state"),
        "sourceKind": "imported",
        "sourceId": row["source_id"],
        # Compatibility fields used by the Rabbita table while the source
        # shape remains available above.
        "contract_id": contract_id,
        "contract_code": _report_text(payload, "contract_code", contract_id),
        "contract_name": _report_text(payload, "contract_name", contract_id),
        "project_id": project_id,
        "project_name": _report_text(projects.get(project_id, {}), "proj_name", project_id),
        "supplier_id": _report_text(payload, "yf_provider_name"),
        "supplier_name": _report_text(payload, "yf_provider_name"),
        "amount_minor": int(round(amount * 100)),
        "amount_display": f"¥{amount:,.2f}",
        "currency": "CNY",
        "sign_date": _report_text(payload, "sign_date"),
        "state": "active" if _report_text(payload, "ht_cf_state") not in {"已终止", "作废"} else "voided",
        "paid_amount_display": "¥0.00",
        "milestone_count": "0",
        "source_kind": "imported",
    }
    return result


def cost_source_contracts(
    pool: PsqlPool,
    contract_id: str | None,
    bu_guid: str | None,
    proj_guid: str | None,
    keyword: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Read ERP ``GET /cost/contracts`` from imported source envelopes only."""

    for value, label in ((contract_id, "contract_id"), (bu_guid, "bu_guid"), (proj_guid, "proj_guid")):
        if value is not None and not IDENTIFIER.fullmatch(value):
            raise ValueError(f"invalid {label}")
    if keyword is not None and len(keyword) > 128:
        raise ValueError("invalid keyword")
    raw_contracts, raw_applies, raw_plans, raw_milestones, raw_projects, raw_units = _cost_source_related_rows(
        pool, max_rows,
    )
    projects = {
        _report_text(row["payload"], "proj_guid", row["record_id"]): row["payload"]
        for row in raw_projects
    }
    units = {
        _report_text(row["payload"], "bu_guid", row["record_id"]): row["payload"]
        for row in raw_units
    }
    paid_by_contract: dict[str, float] = {}
    for row in raw_applies:
        payload = row["payload"]
        if _report_text(payload, "pay_state") in {"完全支付", "部分支付"}:
            key = _report_text(payload, "contract_guid")
            paid_by_contract[key] = paid_by_contract.get(key, 0.0) + _report_float(payload, "apply_amount")
    milestone_counts: dict[str, int] = {}
    for row in raw_milestones:
        key = _report_text(row["payload"], "contract_guid")
        milestone_counts[key] = milestone_counts.get(key, 0) + 1
    result: list[dict[str, Any]] = []
    for row in raw_contracts:
        payload = row["payload"]
        current_id = _report_text(payload, "contract_guid", row["record_id"])
        if contract_id is not None and current_id != contract_id:
            continue
        if bu_guid is not None and _report_text(payload, "bu_guid") != bu_guid:
            continue
        if proj_guid is not None and _report_text(payload, "proj_guid") != proj_guid:
            continue
        if keyword is not None:
            needle = keyword.casefold()
            haystack = " ".join(
                _report_text(payload, key)
                for key in ("contract_name", "contract_code", "yf_provider_name")
            ).casefold()
            if needle not in haystack:
                continue
        item = _cost_source_contract_row(row, projects, units)
        paid = paid_by_contract.get(current_id, 0.0)
        item["paidAmount"] = paid
        item["paid_amount_display"] = f"¥{paid:,.2f}"
        item["milestoneCount"] = milestone_counts.get(current_id, 0)
        item["milestone_count"] = str(milestone_counts.get(current_id, 0))
        result.append(item)
    result.sort(key=lambda item: (str(item.get("signDate", "")), str(item.get("contractGuid", ""))), reverse=True)
    coverage = _cost_source_coverage(pool, max_rows)
    return {"success": True, "code": 0, "data": result[:max_rows], **_cost_source_metadata(coverage)}


def cost_source_contract_detail(
    pool: PsqlPool,
    contract_id: str,
    max_rows: int,
) -> dict[str, Any] | None:
    if not IDENTIFIER.fullmatch(contract_id):
        raise ValueError("invalid contract_id")
    raw_contracts, raw_applies, raw_plans, raw_milestones, raw_projects, raw_units = _cost_source_related_rows(
        pool, max_rows,
    )
    projects = {_report_text(row["payload"], "proj_guid", row["record_id"]): row["payload"] for row in raw_projects}
    units = {_report_text(row["payload"], "bu_guid", row["record_id"]): row["payload"] for row in raw_units}
    contract_row = next(
        (row for row in raw_contracts if _report_text(row["payload"], "contract_guid", row["record_id"]) == contract_id),
        None,
    )
    if contract_row is None:
        return None
    contract = _cost_source_contract_row(contract_row, projects, units)
    contract_bu = _report_text(contract_row["payload"], "bu_guid")
    users = _cost_source_users(pool, max_rows)
    plans: list[dict[str, Any]] = []
    for row in raw_plans:
        payload = row["payload"]
        if _report_text(payload, "contract_guid") != contract_id or _report_text(payload, "bu_guid") != contract_bu:
            continue
        jbr = _report_text(payload, "jbr_guid")
        plans.append({
            "htfkPlanGuid": _report_text(payload, "htfk_plan_guid", row["record_id"]),
            "planPeriod": _report_text(payload, "plan_period"),
            "jhfkDate": _report_text(payload, "jhfk_date"),
            "jhfkAmount": _report_float(payload, "jhfk_amount"),
            "approveState": _report_text(payload, "approve_state"),
            "jbrName": _report_text(users.get(jbr, {}), "emp_name", jbr),
        })
    applies: list[dict[str, Any]] = []
    for row in raw_applies:
        payload = row["payload"]
        if _report_text(payload, "contract_guid") != contract_id or _report_text(payload, "bu_guid") != contract_bu:
            continue
        state = _report_text(payload, "pay_state")
        applies.append({
            "htfkApplyGuid": _report_text(payload, "htfk_apply_guid", row["record_id"]),
            "applyCode": _report_text(payload, "apply_code"),
            "subject": _report_text(payload, "subject"),
            "applyState": _report_text(payload, "apply_state"),
            "payState": state,
            "applyAmount": _report_float(payload, "apply_amount"),
            "applyDate": _report_text(payload, "apply_date"),
            "appliedByName": _report_text(users.get(_report_text(payload, "applied_by"), {}), "emp_name", _report_text(payload, "applied_by")),
            "milestoneGuid": _report_text(payload, "milestone_guid"),
            "earlyPayFlag": payload.get("early_pay_flag", 0),
            "operationState": state if state != "未支付" else _report_text(payload, "apply_state"),
        })
    tasks = {
        _report_text(row["payload"], "task_guid", row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "jd_task", max(max_rows, 500), COST_SOURCE_TABLES)
    }
    milestones: list[dict[str, Any]] = []
    for row in raw_milestones:
        payload = row["payload"]
        if _report_text(payload, "contract_guid") != contract_id:
            continue
        trigger_value = _report_text(payload, "trigger_value")
        task = tasks.get(trigger_value, {})
        milestones.append({
            "milestoneGuid": _report_text(payload, "milestone_guid", row["record_id"]),
            "seq": payload.get("seq", 0),
            "nodeName": _report_text(payload, "node_name"),
            "triggerType": _report_text(payload, "trigger_type"),
            "triggerValue": trigger_value,
            "triggerTaskName": _report_text(task, "task_name"),
            "triggerTaskStatus": _report_text(task, "status"),
            "planDate": _report_text(payload, "plan_date"),
            "planAmount": _report_float(payload, "plan_amount"),
            "planPct": _report_float(payload, "plan_pct"),
            "actualAmount": _report_float(payload, "actual_amount"),
            "state": _report_text(payload, "state"),
            "reachedAt": _report_text(payload, "reached_at"),
            "notes": _report_text(payload, "notes"),
        })
    contract["plans"] = plans
    contract["applies"] = applies
    contract["milestones"] = milestones
    paid = sum(
        float(item.get("applyAmount") or 0)
        for item in applies
        if str(item.get("payState") or "") in {"完全支付", "部分支付"}
    )
    contract["paidAmount"] = paid
    contract["paid_amount_display"] = f"¥{paid:,.2f}"
    contract["milestoneCount"] = len(milestones)
    contract["milestone_count"] = str(len(milestones))
    coverage = _cost_source_coverage(pool, max_rows)
    return {
        "success": True,
        "code": 0,
        "data": {"contract": contract, "plans": plans, "applies": applies, "milestones": milestones},
        **_cost_source_metadata(coverage),
    }


def cost_source_payment_applications(
    pool: PsqlPool,
    view: str,
    bu_guid: str | None,
    user_id: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if view not in {"all", "mine", "approving", "approved", "fullpaid"}:
        raise ValueError("unsupported payment application view")
    if bu_guid is not None and not IDENTIFIER.fullmatch(bu_guid):
        raise ValueError("invalid bu_guid")
    if user_id is not None and not IDENTIFIER.fullmatch(user_id):
        raise ValueError("invalid user_id")
    raw_contracts, raw_applies, _plans, _milestones, raw_projects, raw_units = _cost_source_related_rows(pool, max_rows)
    contracts = {_report_text(row["payload"], "contract_guid", row["record_id"]): row["payload"] for row in raw_contracts}
    projects = {_report_text(row["payload"], "proj_guid", row["record_id"]): row["payload"] for row in raw_projects}
    units = {_report_text(row["payload"], "bu_guid", row["record_id"]): row["payload"] for row in raw_units}
    users = _cost_source_users(pool, max_rows)
    result: list[dict[str, Any]] = []
    for row in raw_applies:
        payload = row["payload"]
        contract_id = _report_text(payload, "contract_guid")
        contract = contracts.get(contract_id)
        if contract is None or payload.get("deleted_at"):
            continue
        if bu_guid is not None and _report_text(payload, "bu_guid") != bu_guid:
            continue
        applied_by = _report_text(payload, "applied_by")
        if user_id is not None and applied_by != user_id:
            continue
        apply_state = _report_text(payload, "apply_state")
        pay_state = _report_text(payload, "pay_state")
        operation = pay_state if pay_state != "未支付" else apply_state
        if view == "mine" and user_id is None:
            continue
        if view == "mine" and applied_by != user_id:
            continue
        if view == "approving" and apply_state not in {"申请审批中", "Approving", "submitted"}:
            continue
        if view == "approved" and apply_state not in {"已审核", "Approved", "approved"}:
            continue
        if view == "fullpaid" and pay_state != "完全支付":
            continue
        amount = _report_float(payload, "apply_amount")
        project_id = _report_text(payload, "proj_guid")
        apply_dept = _report_text(payload, "apply_dept_guid")
        result.append({
            "htfkApplyGuid": _report_text(payload, "htfk_apply_guid", row["record_id"]),
            "applyCode": _report_text(payload, "apply_code"),
            "contractGuid": contract_id,
            "contractName": _report_text(contract, "contract_name", contract_id),
            "yfProviderName": _report_text(contract, "yf_provider_name"),
            "projGuid": project_id,
            "projName": _report_text(projects.get(project_id, {}), "proj_name", project_id),
            "payClass": "合同" if str(payload.get("apply_class", 0)) == "0" else "非合同",
            "operationState": operation,
            "applyState": apply_state,
            "payState": pay_state,
            "subject": _report_text(payload, "subject"),
            "applyDeptName": _report_text(units.get(apply_dept, {}), "bu_name", apply_dept),
            "appliedBy": applied_by,
            "appliedByName": _report_text(users.get(applied_by, {}), "emp_name", applied_by),
            "applyDate": _report_text(payload, "apply_date"),
            "applyAmount": amount,
            "applyTypeCode": _report_text(payload, "apply_type_code"),
            "htfkPlanGuid": _report_text(payload, "htfk_plan_guid"),
            "milestoneGuid": _report_text(payload, "milestone_guid"),
            "sourceKind": "imported",
            "sourceId": row["source_id"],
            "apply_id": _report_text(payload, "htfk_apply_guid", row["record_id"]),
            "apply_code": _report_text(payload, "apply_code"),
            "contract_id": contract_id,
            "contract_name": _report_text(contract, "contract_name", contract_id),
            "project_name": _report_text(projects.get(project_id, {}), "proj_name", project_id),
            "supplier_name": _report_text(contract, "yf_provider_name"),
            "amount_minor": int(round(amount * 100)),
            "amount_display": f"¥{amount:,.2f}",
            "currency": "CNY",
            "apply_date": _report_text(payload, "apply_date"),
            "operation_state": operation,
            "apply_state": apply_state,
            "pay_state": pay_state,
            "apply_type_code": _report_text(payload, "apply_type_code"),
            "pay_class": "合同" if str(payload.get("apply_class", 0)) == "0" else "非合同",
            "applied_by": applied_by,
            "applied_by_name": _report_text(users.get(applied_by, {}), "emp_name", applied_by),
            "source_kind": "imported",
            "plan_id": _report_text(payload, "htfk_plan_guid"),
            "milestone_id": _report_text(payload, "milestone_guid"),
        })
    result.sort(key=lambda item: (str(item.get("applyDate", "")), str(item.get("htfkApplyGuid", ""))), reverse=True)
    coverage = _cost_source_coverage(pool, max_rows)
    return {"success": True, "code": 0, "data": result[:max_rows], **_cost_source_metadata(coverage)}


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


TENDER_SOURCE_TABLES = {
    "tender_plan",
    "tender_award",
    "contract_split",
}


def _tender_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _tender_source_coverage(pool: PsqlPool, max_rows: int) -> dict[str, int]:
    return {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), TENDER_SOURCE_TABLES))
        for table in sorted(TENDER_SOURCE_TABLES)
    }


def _tender_source_number(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _tender_source_row(row: dict[str, Any]) -> dict[str, Any]:
    payload = dict(row["payload"])
    tender_id = str(payload.get("tender_guid") or row["record_id"])
    amount = _tender_source_number(payload.get("estimated_amount"))
    payload.setdefault("tender_guid", tender_id)
    payload.setdefault("tender_id", tender_id)
    payload.setdefault("name", payload.get("tender_name", tender_id))
    payload.setdefault("project_scope", "project:" + str(payload.get("proj_guid") or ""))
    payload.setdefault("estimated_amount_minor", int(round(amount * 100)))
    payload.setdefault("estimated_amount_display", f"¥{amount:,.2f}" if amount else "—")
    payload.setdefault("currency", "CNY")
    payload.setdefault("state", "planning")
    payload.setdefault("bids", [])
    payload.setdefault("source_kind", "imported")
    payload["aggregate_type"] = "tender"
    payload["aggregate_id"] = tender_id
    payload["source_id"] = row["source_id"]
    payload["source_table"] = "tender_plan"
    return payload


def _tender_source_award_row(row: dict[str, Any]) -> dict[str, Any]:
    payload = dict(row["payload"])
    award_id = str(payload.get("award_guid") or row["record_id"])
    amount = _tender_source_number(payload.get("award_amount"))
    payload.setdefault("award_guid", award_id)
    payload.setdefault("award_id", award_id)
    payload.setdefault("award_amount_display", f"¥{amount:,.2f}" if amount else "—")
    payload.setdefault("state", "awarded")
    payload.setdefault("source_kind", "imported")
    payload["aggregate_type"] = "tender_award"
    payload["aggregate_id"] = award_id
    payload["source_id"] = row["source_id"]
    payload["source_table"] = "tender_award"
    return payload


def _tender_source_split_row(row: dict[str, Any]) -> dict[str, Any]:
    payload = dict(row["payload"])
    split_id = str(payload.get("split_guid") or row["record_id"])
    amount = _tender_source_number(payload.get("split_amount"))
    payload.setdefault("split_guid", split_id)
    payload.setdefault("split_id", split_id)
    payload.setdefault("split_amount_display", f"¥{amount:,.2f}" if amount else "—")
    payload.setdefault("state", "planned")
    payload.setdefault("source_kind", "imported")
    payload["aggregate_type"] = "contract_split"
    payload["aggregate_id"] = split_id
    payload["source_id"] = row["source_id"]
    payload["source_table"] = "contract_split"
    return payload


def tender_source_rows(
    pool: PsqlPool,
    family: str,
    proj_guid: str | None,
    state: str | None,
    tender_guid: str | None,
    parent_contract_guid: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Read one ERP procurement table without promoting local commands."""

    if family not in {"tenders", "awards", "splits"}:
        raise ValueError("unsupported tender source family")
    for value, name in (
        (proj_guid, "proj_guid"),
        (state, "state"),
        (tender_guid, "tender_guid"),
        (parent_contract_guid, "parent_contract_guid"),
    ):
        if value is not None and len(value) > 128:
            raise ValueError(f"invalid {name}")
    table = {
        "tenders": "tender_plan",
        "awards": "tender_award",
        "splits": "contract_split",
    }[family]
    coverage = _tender_source_coverage(pool, max_rows)
    raw = _raw_source_rows(pool, table, max(max_rows, 500), TENDER_SOURCE_TABLES)
    rows: list[dict[str, Any]] = []
    for row in raw:
        payload = row["payload"]
        if proj_guid is not None and str(payload.get("proj_guid") or "") != proj_guid:
            continue
        if state is not None and str(payload.get("state") or "") != state:
            continue
        if tender_guid is not None and str(payload.get("tender_guid") or "") != tender_guid:
            continue
        if parent_contract_guid is not None and str(
            payload.get("parent_contract_guid") or ""
        ) != parent_contract_guid:
            continue
        if family == "tenders":
            rows.append(_tender_source_row(row))
        elif family == "awards":
            rows.append(_tender_source_award_row(row))
        else:
            rows.append(_tender_source_split_row(row))
    rows.sort(
        key=lambda value: (
            str(value.get("plan_publish_date") or value.get("award_date") or value.get("created_at") or ""),
            str(value.get("aggregate_id") or ""),
        ),
        reverse=True,
    )
    return {
        "success": True,
        "code": 0,
        "data": rows[:max_rows],
        **_tender_source_metadata(coverage),
    }


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


SRM_RISK_SOURCE_TABLES = {
    "srm_provider",
    "srm_provider_bu",
    "srm_category",
    "cb_contract",
    "cb_contract_milestone",
}


SRM_PROVIDER_SOURCE_TABLES = {
    "srm_provider",
    "srm_provider_bu",
    "srm_category",
    "cb_contract",
    "mu_business_unit",
}


def _srm_source_bool(payload: dict[str, Any], key: str, fallback: bool = False) -> bool:
    value = payload.get(key)
    if value is None or value == "":
        return fallback
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    return str(value).strip().lower() in {"1", "true", "yes", "y", "enabled", "启用"}


def _supplier_source_coverage(
    pool: PsqlPool,
    max_rows: int,
) -> dict[str, int]:
    return {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES))
        for table in sorted(SRM_PROVIDER_SOURCE_TABLES)
    }


def _supplier_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
    }


def _supplier_dictionary_metadata(
    coverage: dict[str, int],
    source_kind: str,
) -> dict[str, Any]:
    return {
        "source_kind": source_kind,
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _supplier_sort_order(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def supplier_source_categories(
    pool: PsqlPool,
    max_rows: int,
) -> dict[str, Any]:
    raw = _raw_source_rows(pool, "srm_category", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    rows = [
        {
            "code": str(row["payload"].get("category_code") or row["record_id"]),
            "name": str(row["payload"].get("category_name") or ""),
            "sortOrder": _supplier_sort_order(row["payload"].get("sort_order")),
            "sourceKind": "imported",
            "sourceId": row["source_id"],
        }
        for row in raw
    ]
    rows.sort(key=lambda value: (_supplier_sort_order(value["sortOrder"]), str(value["code"])))
    return {
        "success": True,
        "code": 0,
        "data": rows[:max_rows],
        **_supplier_dictionary_metadata({"srm_category": len(raw)}, "imported_or_empty"),
    }


def supplier_source_eval_results() -> dict[str, Any]:
    rows = [
        {"code": value, "name": value, "sourceKind": "definition"}
        for value in ("已评审", "合格", "不合格", "战略", "黑名单", "未定级")
    ]
    return {
        "success": True,
        "code": 0,
        "data": rows,
        **_supplier_dictionary_metadata({}, "definition"),
    }


def supplier_source_sources() -> dict[str, Any]:
    rows = [
        {"code": value, "name": value, "sourceKind": "definition"}
        for value in ("云采购", "内部收集", "外网注册", "其他")
    ]
    return {
        "success": True,
        "code": 0,
        "data": rows,
        **_supplier_dictionary_metadata({}, "definition"),
    }


def supplier_source_list(
    pool: PsqlPool,
    max_rows: int,
) -> dict[str, Any]:
    """Read the ERP SRM provider master source without local projections.

    The response follows the ERP ``GET /srm/providers`` data shape.  It is a
    read-only imported-source boundary: missing/empty source tables remain
    visible and no local supplier command state is promoted into this list.
    """

    coverage = _supplier_source_coverage(pool, max_rows)
    providers = _raw_source_rows(pool, "srm_provider", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    provider_links = _raw_source_rows(pool, "srm_provider_bu", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    categories = _raw_source_rows(pool, "srm_category", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    contracts = _raw_source_rows(pool, "cb_contract", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    category_names = {
        str(row["payload"].get("category_code") or ""): str(row["payload"].get("category_name") or "")
        for row in categories
    }
    links_by_provider: dict[str, int] = {}
    for row in provider_links:
        provider_guid = str(row["payload"].get("provider_guid") or "")
        if provider_guid:
            links_by_provider[provider_guid] = links_by_provider.get(provider_guid, 0) + 1

    result: list[dict[str, Any]] = []
    for row in providers:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        provider_guid = str(payload.get("provider_guid") or row["record_id"])
        provider_name = str(payload.get("provider_name") or "")
        short_name = str(payload.get("short_name") or "")
        contract_count = 0
        for contract in contracts:
            contract_payload = contract["payload"]
            if contract_payload.get("deleted_at"):
                continue
            contract_name = str(contract_payload.get("yf_provider_name") or "")
            if contract_name == provider_name or (
                short_name and (contract_name == short_name or short_name in contract_name)
            ):
                contract_count += 1
        category_code = str(payload.get("main_category_code") or "")
        eval_result = str(payload.get("eval_result") or "未定级")
        result.append(
            {
                "providerGuid": provider_guid,
                "providerCode": str(payload.get("provider_code") or ""),
                "providerName": provider_name,
                "shortName": short_name,
                "legalPerson": str(payload.get("legal_person") or ""),
                "registerCapital": payload.get("register_capital"),
                "businessScope": str(payload.get("business_scope") or ""),
                "mainCategory": {
                    "code": category_code,
                    "name": category_names.get(category_code, ""),
                },
                "evalResult": eval_result,
                "inspectState": str(payload.get("inspect_state") or ""),
                "auditState": str(payload.get("audit_state") or ""),
                "source": str(payload.get("source") or ""),
                "contactPerson": str(payload.get("contact_person") or ""),
                "contactPhone": str(payload.get("contact_phone") or ""),
                "enabled": _srm_source_bool(payload, "enabled", True),
                "buCount": links_by_provider.get(provider_guid, 0),
                "contractCount": contract_count,
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda item: (str(item["evalResult"]), str(item["providerCode"])), reverse=True)
    return {
        "success": True,
        "code": 0,
        "data": result[:max_rows],
        **_supplier_source_metadata(coverage),
    }


def supplier_source_detail(
    pool: PsqlPool,
    provider_guid: str,
    max_rows: int,
) -> dict[str, Any]:
    """Read one ERP provider with source BU and contract evidence."""

    if not IDENTIFIER.fullmatch(provider_guid):
        raise ValueError("invalid provider_guid")
    coverage = _supplier_source_coverage(pool, max_rows)
    providers = _raw_source_rows(pool, "srm_provider", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    provider_row: dict[str, Any] | None = None
    for row in providers:
        payload = row["payload"]
        current_guid = str(payload.get("provider_guid") or row["record_id"])
        if current_guid == provider_guid and not payload.get("deleted_at"):
            provider_row = row
            break
    if provider_row is None:
        return {
            "success": False,
            "code": 43001,
            "message": "供应商不存在",
            "data": None,
            **_supplier_source_metadata(coverage),
        }

    payload = provider_row["payload"]
    categories = _raw_source_rows(pool, "srm_category", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    category_code = str(payload.get("main_category_code") or "")
    category_name = ""
    for category in categories:
        category_payload = category["payload"]
        if str(category_payload.get("category_code") or "") == category_code:
            category_name = str(category_payload.get("category_name") or "")
            break

    provider_links = _raw_source_rows(pool, "srm_provider_bu", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    business_units = _raw_source_rows(pool, "mu_business_unit", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    units_by_guid = {
        str(row["payload"].get("bu_guid") or row["record_id"]): row["payload"]
        for row in business_units
    }
    service_bus: list[dict[str, Any]] = []
    for link in provider_links:
        link_payload = link["payload"]
        if str(link_payload.get("provider_guid") or "") != provider_guid:
            continue
        bu_guid = str(link_payload.get("bu_guid") or "")
        unit = units_by_guid.get(bu_guid, {})
        service_bus.append(
            {
                "buGuid": bu_guid,
                "buCode": str(unit.get("bu_code") or ""),
                "buName": str(unit.get("bu_name") or ""),
            }
        )

    provider_name = str(payload.get("provider_name") or "")
    short_name = str(payload.get("short_name") or "")
    contracts = _raw_source_rows(pool, "cb_contract", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    contract_rows: list[dict[str, Any]] = []
    for contract in contracts:
        contract_payload = contract["payload"]
        if contract_payload.get("deleted_at"):
            continue
        contract_name = str(contract_payload.get("yf_provider_name") or "")
        if not (
            contract_name == provider_name
            or contract_name == short_name
            or (short_name and short_name in contract_name)
        ):
            continue
        contract_rows.append(
            {
                "contractGuid": str(contract_payload.get("contract_guid") or contract["record_id"]),
                "contractCode": str(contract_payload.get("contract_code") or ""),
                "contractName": str(contract_payload.get("contract_name") or ""),
                "amount": _srm_source_number(contract_payload, "ht_amount")
                + _srm_source_number(contract_payload, "sum_alter_amount"),
                "signDate": str(contract_payload.get("sign_date") or ""),
                "htCfState": str(contract_payload.get("ht_cf_state") or ""),
            }
        )
    contract_rows.sort(key=lambda item: str(item["signDate"]), reverse=True)
    provider = {
        "providerGuid": provider_guid,
        "providerCode": str(payload.get("provider_code") or ""),
        "providerName": provider_name,
        "shortName": short_name,
        "legalPerson": str(payload.get("legal_person") or ""),
        "businessLicense": str(payload.get("business_license") or ""),
        "registerCapital": payload.get("register_capital"),
        "businessScope": str(payload.get("business_scope") or ""),
        "mainCategory": {"code": category_code, "name": category_name},
        "evalResult": str(payload.get("eval_result") or "未定级"),
        "inspectState": str(payload.get("inspect_state") or ""),
        "auditState": str(payload.get("audit_state") or ""),
        "source": str(payload.get("source") or ""),
        "contactPerson": str(payload.get("contact_person") or ""),
        "contactPhone": str(payload.get("contact_phone") or ""),
        "address": str(payload.get("address") or ""),
        "qualifications": str(payload.get("qualifications") or ""),
        "enabled": _srm_source_bool(payload, "enabled", True),
        "createdBy": str(payload.get("created_by") or ""),
        "createdAt": str(payload.get("created_at") or ""),
        "processInstanceGuid": str(payload.get("process_instance_guid") or ""),
    }
    return {
        "success": True,
        "code": 0,
        "data": {
            "provider": provider,
            "serviceBus": service_bus,
            "contracts": contract_rows[:max_rows],
        },
        **_supplier_source_metadata(coverage),
    }


def supplier_source_stats(
    pool: PsqlPool,
    max_rows: int,
) -> dict[str, Any]:
    """Read the ERP supplier statistics overview from imported source rows."""

    coverage = _supplier_source_coverage(pool, max_rows)
    providers = _raw_source_rows(pool, "srm_provider", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    categories = _raw_source_rows(pool, "srm_category", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    contracts = _raw_source_rows(pool, "cb_contract", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    visible = [
        row
        for row in providers
        if not row["payload"].get("deleted_at")
        and _srm_source_bool(row["payload"], "enabled", False)
    ]
    by_eval: dict[str, int] = {}
    by_source: dict[str, int] = {}
    by_category: dict[str, int] = {}
    for row in visible:
        payload = row["payload"]
        eval_result = str(payload.get("eval_result") or "未定级")
        source = str(payload.get("source") or "")
        category_code = str(payload.get("main_category_code") or "")
        by_eval[eval_result] = by_eval.get(eval_result, 0) + 1
        by_source[source] = by_source.get(source, 0) + 1
        by_category[category_code] = by_category.get(category_code, 0) + 1

    def contract_matches(provider_payload: dict[str, Any]) -> list[dict[str, Any]]:
        provider_name = str(provider_payload.get("provider_name") or "")
        short_name = str(provider_payload.get("short_name") or "")
        matches: list[dict[str, Any]] = []
        for row in contracts:
            payload = row["payload"]
            if payload.get("deleted_at"):
                continue
            contract_name = str(payload.get("yf_provider_name") or "")
            if contract_name == provider_name or contract_name == short_name or (
                short_name and short_name in contract_name
            ):
                matches.append(payload)
        return matches

    top_business: list[dict[str, Any]] = []
    for row in visible:
        matches = contract_matches(row["payload"])
        total_amount = sum(
            _srm_source_number(contract, "ht_amount")
            + _srm_source_number(contract, "sum_alter_amount")
            for contract in matches
        )
        top_business.append(
            {
                "name": str(row["payload"].get("provider_name") or row["record_id"]),
                "contractCount": len(matches),
                "totalAmount": total_amount,
            }
        )
    top_business.sort(key=lambda item: (-float(item["totalAmount"]), str(item["name"])))
    category_names = {
        str(row["payload"].get("category_code") or ""): str(row["payload"].get("category_name") or "")
        for row in categories
    }
    by_category_rows = []
    for row in sorted(
        categories,
        key=lambda item: (
            str(item["payload"].get("sort_order") or ""),
            str(item["payload"].get("category_code") or ""),
        ),
    ):
        category_code = str(row["payload"].get("category_code") or "")
        by_category_rows.append(
            {
                "name": category_names.get(category_code, category_code),
                "count": by_category.get(category_code, 0),
            }
        )
    result = {
        "total": len(visible),
        "byEvalResult": [
            {"name": name, "count": by_eval[name]} for name in sorted(by_eval)
        ],
        "byCategory": by_category_rows,
        "bySource": [
            {"name": name, "count": by_source[name]} for name in sorted(by_source)
        ],
        "topBusiness": top_business[:10],
    }
    return {
        "success": True,
        "code": 0,
        "data": result,
        **_supplier_source_metadata(coverage),
    }


def supplier_source_risk(
    pool: PsqlPool,
    provider_guid: str,
    max_rows: int,
) -> dict[str, Any]:
    """Calculate one ERP provider risk record without persisting source state."""

    if not IDENTIFIER.fullmatch(provider_guid):
        raise ValueError("invalid provider_guid")
    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), SRM_RISK_SOURCE_TABLES))
        for table in sorted(SRM_RISK_SOURCE_TABLES)
    }
    providers = _raw_source_rows(pool, "srm_provider", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    provider_row: dict[str, Any] | None = None
    for row in providers:
        payload = row["payload"]
        current_guid = str(payload.get("provider_guid") or row["record_id"])
        if current_guid == provider_guid and not payload.get("deleted_at"):
            provider_row = row
            break
    if provider_row is None:
        return {
            "success": False,
            "code": 43001,
            "message": "供应商不存在",
            "data": None,
            **_supplier_source_metadata(coverage),
        }
    contracts = _raw_source_rows(pool, "cb_contract", max(max_rows, 500), SRM_PROVIDER_SOURCE_TABLES)
    milestones = _raw_source_rows(
        pool, "cb_contract_milestone", max(max_rows, 500), SRM_RISK_SOURCE_TABLES,
    )
    risk = _source_supplier_risk(provider_row, contracts, milestones)
    return {
        "success": True,
        "code": 0,
        "data": {
            "providerGuid": provider_guid,
            "score": risk["score"],
            "rating": risk["rating"],
            "tags": risk["tags"],
            "riskTags": ",".join(risk["tags"]),
            "contractCount": risk["contract_count"],
            "contractTotal": risk["contract_total"],
            "overdueCount": risk["overdue_count"],
            "overdueAmount": risk["overdue_amount"],
            "sourceKind": "imported",
        },
        **_supplier_source_metadata(coverage),
    }


def _srm_source_number(payload: dict[str, Any], key: str) -> float:
    value = payload.get(key)
    if value is None or value == "":
        return 0.0
    try:
        return float(value)
    except (TypeError, ValueError) as error:
        raise ServiceError(f"invalid supplier risk numeric field: {key}") from error


def _source_supplier_risk(
    provider: dict[str, Any],
    contracts: list[dict[str, Any]],
    milestones: list[dict[str, Any]],
) -> dict[str, Any]:
    """Reproduce the ERP risk-board calculation from imported source rows.

    This deliberately operates on raw source envelopes and never falls back to
    local supplier command projections.  If the source supplier table is
    absent, the caller returns an explicit empty/source-coverage response.
    """

    payload = provider["payload"]
    provider_name = str(payload.get("provider_name") or "")
    short_name = str(payload.get("short_name") or provider_name)
    if str(payload.get("eval_result") or "") in {"黑名单", "不合格"}:
        return {
            "score": 0.0,
            "rating": "E",
            "tags": ["blacklist"],
            "contract_count": 0,
            "contract_total": 0.0,
            "overdue_count": 0,
            "overdue_amount": 0.0,
        }
    matching_contracts: list[dict[str, Any]] = []
    for row in contracts:
        contract = row["payload"]
        if contract.get("deleted_at"):
            continue
        name = str(contract.get("yf_provider_name") or "")
        if name == provider_name or (short_name and short_name in name):
            matching_contracts.append(row)
    contract_ids = {
        str(row["payload"].get("contract_guid") or row["record_id"])
        for row in matching_contracts
    }
    overdue_rows = [
        row
        for row in milestones
        if str(row["payload"].get("contract_guid") or "") in contract_ids
        and str(row["payload"].get("state") or "") == "overdue"
    ]
    contract_total = sum(
        _srm_source_number(row["payload"], "ht_amount")
        + _srm_source_number(row["payload"], "sum_alter_amount")
        for row in matching_contracts
    )
    overdue_amount = sum(_srm_source_number(row["payload"], "plan_amount") for row in overdue_rows)
    score = 70.0 + min(15.0, float(len(matching_contracts)))
    score -= min(35.0, float(len(overdue_rows)) * 5.0)
    if contract_total > 0:
        score -= min(30.0, overdue_amount / contract_total * 50.0)
    tags: list[str] = []
    if str(payload.get("inspect_state") or "") == "不合格":
        score -= 15.0
        tags.append("inspect_failed")
    if overdue_rows:
        tags.append("overdue")
    if contract_total > 50_000_000:
        tags.append("heavy_concentration")
    score = max(0.0, min(100.0, round(score, 1)))
    rating = "A" if score >= 85 else "B" if score >= 70 else "C" if score >= 55 else "D" if score >= 40 else "E"
    return {
        "score": score,
        "rating": rating,
        "tags": tags,
        "contract_count": len(matching_contracts),
        "contract_total": contract_total,
        "overdue_count": len(overdue_rows),
        "overdue_amount": overdue_amount,
    }


def supplier_risk_board_source(
    pool: PsqlPool,
    max_rows: int,
) -> dict[str, Any]:
    """Read the ERP SRM risk-board source tables without local projections."""

    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), SRM_RISK_SOURCE_TABLES))
        for table in sorted(SRM_RISK_SOURCE_TABLES)
    }
    providers = _raw_source_rows(pool, "srm_provider", max(max_rows, 500), SRM_RISK_SOURCE_TABLES)
    contracts = _raw_source_rows(pool, "cb_contract", max(max_rows, 500), SRM_RISK_SOURCE_TABLES)
    milestones = _raw_source_rows(pool, "cb_contract_milestone", max(max_rows, 500), SRM_RISK_SOURCE_TABLES)
    distribution: dict[str, int] = {}
    high_risk: list[dict[str, Any]] = []
    for provider in providers:
        payload = provider["payload"]
        if payload.get("deleted_at"):
            continue
        risk = _source_supplier_risk(provider, contracts, milestones)
        rating = str(risk["rating"])
        distribution[rating] = distribution.get(rating, 0) + 1
        if rating not in {"D", "E"}:
            continue
        high_risk.append(
            {
                "providerGuid": str(payload.get("provider_guid") or provider["record_id"]),
                "providerCode": str(payload.get("provider_code") or ""),
                "providerName": str(payload.get("provider_name") or ""),
                "shortName": str(payload.get("short_name") or ""),
                "mainCategoryCode": str(payload.get("main_category_code") or ""),
                "rating": rating,
                "riskScore": risk["score"],
                "riskTags": ",".join(risk["tags"]),
                "ratingUpdatedAt": str(payload.get("rating_updated_at") or ""),
                "contractCount": risk["contract_count"],
                "contractTotal": risk["contract_total"],
                "overdueCount": risk["overdue_count"],
                "overdueAmount": risk["overdue_amount"],
                "sourceKind": "imported",
            }
        )
    high_risk.sort(key=lambda item: (float(item["riskScore"]), str(item["providerGuid"])))
    distribution_rows = [
        {"rating": rating, "c": distribution[rating]}
        for rating in sorted(distribution)
    ]
    return {
        "success": True,
        "code": 0,
        "data": {
            "highRisk": high_risk[:max_rows],
            "distribution": distribution_rows,
        },
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [table for table, count in coverage.items() if count == 0],
        "authorizing": False,
    }


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


SALES_SOURCE_TABLES = {
    "sale_customer",
    "sale_subscription",
    "sale_contract",
    "sale_mortgage",
    "sale_refund",
    "sale_revenue",
}

SALES_SOURCE_FAMILIES = {
    "customers": ("sale_customer", "customer", "customer_guid"),
    "subscriptions": ("sale_subscription", "subscription", "sub_guid"),
    "contracts": ("sale_contract", "sales_agreement", "scontract_guid"),
    "mortgages": ("sale_mortgage", "mortgage", "mortgage_guid"),
    "refunds": ("sale_refund", "refund", "refund_guid"),
    "revenues": ("sale_revenue", "sale_revenue", "revenue_guid"),
}


def _sales_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _sales_source_amount_display(value: Any) -> str:
    if value is None or value == "":
        return "—"
    try:
        return f"¥{Decimal(str(value)):,.2f}"
    except (InvalidOperation, TypeError, ValueError):
        return "—"


def _sales_source_row(
    row: dict[str, Any],
    family: str,
) -> dict[str, Any]:
    table, aggregate_type, identity_field = SALES_SOURCE_FAMILIES[family]
    payload = dict(row["payload"])
    identity = str(
        payload.get(identity_field)
        or payload.get("subscription_guid" if family == "subscriptions" else "")
        or payload.get("contract_guid" if family == "contracts" else "")
        or row["record_id"]
    )
    payload.setdefault(identity_field, identity)
    payload.setdefault("source_id", row["source_id"])
    payload.setdefault("source_kind", "imported")
    payload.setdefault("source_table", table)
    payload["aggregate_type"] = aggregate_type
    payload["aggregate_id"] = identity
    payload["source_id"] = row["source_id"]
    payload["source_table"] = table
    if family == "customers":
        payload.setdefault("customer_id", identity)
        payload.setdefault("name", payload.get("customer_name", identity))
        payload.setdefault("contact_reference", payload.get("phone", ""))
        payload.setdefault("state", "active")
    elif family == "subscriptions":
        payload.setdefault("subscription_id", identity)
        payload.setdefault(
            "unit_reference",
            "-".join(
                value
                for value in (
                    str(payload.get("building_no") or ""),
                    str(payload.get("unit_no") or ""),
                )
                if value
            ),
        )
        payload.setdefault("state", "reserved")
    elif family == "contracts":
        payload.setdefault("agreement_id", identity)
        payload.setdefault("state", "draft")
    elif family == "mortgages":
        payload.setdefault("mortgage_id", identity)
        payload.setdefault("bank_reference", payload.get("bank_name", ""))
        payload.setdefault("state", "applying")
    elif family == "refunds":
        payload.setdefault("refund_id", identity)
        payload.setdefault("state", "requested")
    else:
        payload.setdefault("revenue_id", identity)
        payload.setdefault("status", "expected")
        payload.setdefault("state", payload.get("status", "expected"))
    amount_value = payload.get("amount")
    if family in {"subscriptions", "contracts"}:
        amount_value = payload.get("total_price", amount_value)
    elif family == "mortgages":
        amount_value = payload.get("loan_amount", amount_value)
    elif family == "refunds":
        amount_value = payload.get("refund_amount", amount_value)
    payload.setdefault("amount_display", _sales_source_amount_display(amount_value))
    return payload


def sales_source_rows(
    pool: PsqlPool,
    family: str,
    proj_guid: str | None,
    state: str | None,
    keyword: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Read one ERP sales table without promoting rows to company projections."""

    if family not in SALES_SOURCE_FAMILIES:
        raise ValueError("unsupported sales source family")
    for value, name in ((proj_guid, "proj_guid"), (state, "state")):
        if value is not None and len(value) > 128:
            raise ValueError(f"invalid {name}")
    if keyword is not None and len(keyword) > 128:
        raise ValueError("invalid keyword")
    table = SALES_SOURCE_FAMILIES[family][0]
    coverage = {
        name: len(_raw_source_rows(pool, name, max(max_rows, 500), SALES_SOURCE_TABLES))
        for name in sorted(SALES_SOURCE_TABLES)
    }
    raw = _raw_source_rows(pool, table, max(max_rows, 500), SALES_SOURCE_TABLES)
    rows: list[dict[str, Any]] = []
    for row in raw:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        if proj_guid is not None and str(payload.get("proj_guid") or "") != proj_guid:
            continue
        row_state_value = payload.get("status") if family == "revenues" else payload.get("state")
        row_state = str(row_state_value or "")
        if state is not None and row_state != state:
            continue
        if keyword is not None:
            haystack = " ".join(str(value) for value in payload.values())
            if keyword.lower() not in haystack.lower():
                continue
        rows.append(_sales_source_row(row, family))
    rows.sort(
        key=lambda value: (
            str(value.get("created_at") or value.get("receive_date") or value.get("signed_date") or ""),
            str(value.get("aggregate_id") or ""),
        ),
        reverse=True,
    )
    return {
        "success": True,
        "code": 0,
        "data": rows[:max_rows],
        **_sales_source_metadata(coverage),
    }


INVOICE_SOURCE_TABLES = {
    "invoice_in",
    "invoice_out",
    "ep_project",
    "mu_business_unit",
}


def _invoice_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _invoice_source_coverage(pool: PsqlPool, max_rows: int) -> dict[str, int]:
    return {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), INVOICE_SOURCE_TABLES))
        for table in sorted(INVOICE_SOURCE_TABLES)
    }


def _invoice_source_row(
    row: dict[str, Any],
    direction: str,
    projects: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    payload = row["payload"]
    invoice_id = _report_text(payload, "invoice_guid", row["record_id"])
    invoice_no = _report_text(payload, "invoice_no", invoice_id)
    project_id = _report_text(payload, "proj_guid")
    total = _report_float(payload, "total_amount")
    tax = _report_float(payload, "tax_amount")
    project_name = _report_text(projects.get(project_id, {}), "proj_name", project_id)
    source = {
        "invoiceGuid": invoice_id,
        "invoiceNo": invoice_no,
        "projGuid": project_id,
        "projName": project_name,
        "buGuid": _report_text(payload, "bu_guid"),
        "contractGuid": _report_text(payload, "contract_guid"),
        "providerName": _report_text(payload, "provider_name"),
        "customerName": _report_text(payload, "customer_name"),
        "scontractGuid": _report_text(payload, "scontract_guid"),
        "revenueGuid": _report_text(payload, "revenue_guid"),
        "invoiceDate": _report_text(payload, "invoice_date"),
        "totalAmount": total,
        "taxAmount": tax,
        "taxRate": _report_float(payload, "tax_rate"),
        "invoiceType": _report_text(payload, "invoice_type"),
        "state": _report_text(payload, "state"),
        "remark": _report_text(payload, "remark"),
        "direction": direction,
        "sourceKind": "imported",
        "sourceId": row["source_id"],
        # Compatibility fields let the existing Rabbita table consume the
        # source observation without treating it as a company projection.
        "aggregate_type": "invoice",
        "aggregate_id": invoice_id,
        "name": invoice_no,
        "amount_display": f"¥{total:,.2f}",
        "source_kind": "imported",
    }
    return source


def invoice_source_rows(
    pool: PsqlPool,
    direction: str,
    proj_guid: str | None,
    contract_guid: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if direction not in {"in", "out"}:
        raise ValueError("unsupported invoice direction")
    for value, label in ((proj_guid, "proj_guid"), (contract_guid, "contract_guid")):
        if value is not None and not IDENTIFIER.fullmatch(value):
            raise ValueError(f"invalid {label}")
    table = "invoice_" + direction
    raw = _raw_source_rows(pool, table, max(max_rows, 500), INVOICE_SOURCE_TABLES)
    raw_projects = _raw_source_rows(pool, "ep_project", max(max_rows, 100), INVOICE_SOURCE_TABLES)
    projects = {
        _report_text(row["payload"], "proj_guid", row["record_id"]): row["payload"]
        for row in raw_projects
    }
    rows: list[dict[str, Any]] = []
    for row in raw:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        if proj_guid is not None and _report_text(payload, "proj_guid") != proj_guid:
            continue
        if contract_guid is not None and _report_text(payload, "contract_guid") != contract_guid:
            continue
        rows.append(_invoice_source_row(row, direction, projects))
    rows.sort(
        key=lambda value: (str(value.get("invoiceDate", "")), str(value.get("invoiceGuid", ""))),
        reverse=True,
    )
    coverage = _invoice_source_coverage(pool, max_rows)
    return {"success": True, "code": 0, "data": rows[:max_rows], **_invoice_source_metadata(coverage)}


def invoice_source_tax_ledger(
    pool: PsqlPool,
    proj_guid: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if proj_guid is not None and not IDENTIFIER.fullmatch(proj_guid):
        raise ValueError("invalid proj_guid")
    grouped: dict[str, dict[str, Any]] = {}
    for direction in ("in", "out"):
        source = invoice_source_rows(pool, direction, proj_guid, None, max_rows)
        for row in source["data"]:
            period = str(row.get("invoiceDate") or "")[:7]
            if not period:
                continue
            entry = grouped.setdefault(
                period,
                {"period": period, "totalIn": 0.0, "taxIn": 0.0, "totalOut": 0.0, "taxOut": 0.0},
            )
            if direction == "in":
                entry["totalIn"] += float(row.get("totalAmount") or 0)
                entry["taxIn"] += float(row.get("taxAmount") or 0)
            else:
                entry["totalOut"] += float(row.get("totalAmount") or 0)
                entry["taxOut"] += float(row.get("taxAmount") or 0)
    rows = []
    for period, entry in grouped.items():
        entry["netTax"] = round(float(entry["taxOut"]) - float(entry["taxIn"]), 2)
        rows.append(entry)
    rows.sort(key=lambda value: str(value.get("period", "")), reverse=True)
    coverage = _invoice_source_coverage(pool, max_rows)
    return {
        "success": True,
        "code": 0,
        "data": {"rows": rows[:max_rows]},
        **_invoice_source_metadata(coverage),
    }


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


def _delivery_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def source_delivery_progress(
    pool: PsqlPool,
    project_id: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Observe the ERP ``proj_progress`` rows without mixing commands in."""

    if project_id is not None and not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    raw = _raw_delivery_rows(
        pool,
        "proj_progress",
        record_id=None,
        project_id=None,
        task_id=None,
        max_rows=max_rows,
    )
    rows = []
    for row in raw:
        value = _delivery_source_fields(row, table="proj_progress")
        if project_id is not None and value.get("project_id") != project_id:
            continue
        value.update(
            {
                "progress_guid": value.get("progress_id", ""),
                "proj_guid": value.get("project_id", ""),
                "bu_guid": "",
                "progressGuid": value.get("progress_id", ""),
                "projGuid": value.get("project_id", ""),
                "planDate": value.get("plan_date", ""),
                "planPct": value.get("plan_pct", "0"),
                "actualPct": value.get("actual_pct", "0"),
                "actualDate": value.get("actual_date", ""),
                "contractGuid": value.get("contract_id", ""),
                "milestoneGuid": value.get("milestone_id", ""),
            }
        )
        rows.append(value)
    rows.sort(key=lambda value: (str(value.get("plan_date", "")), str(value.get("progress_id", ""))))
    return {
        "success": True,
        "code": 0,
        "data": rows,
        **_delivery_source_metadata({"proj_progress": len(raw)}),
    }


def source_delivery_outputs(
    pool: PsqlPool,
    project_id: str | None,
    period: str | None,
    state: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Observe the ERP ``proj_output`` rows and preserve contract labels."""

    if project_id is not None and not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    if period is not None and len(period) > 64:
        raise ValueError("invalid period")
    if state is not None and len(state) > 64:
        raise ValueError("invalid state")
    raw = _raw_delivery_rows(
        pool,
        "proj_output",
        record_id=None,
        project_id=None,
        task_id=None,
        max_rows=max_rows,
    )
    contracts = _raw_source_rows(pool, "cb_contract", max(max_rows, 500), COST_SOURCE_TABLES)
    contract_names = {
        str(row["record_id"]): str(
            row["payload"].get("contract_name")
            or row["payload"].get("ht_name")
            or ""
        )
        for row in contracts
    }
    rows = []
    for row in raw:
        value = _delivery_source_fields(row, table="proj_output")
        if project_id is not None and value.get("project_id") != project_id:
            continue
        if period is not None and value.get("period") != period:
            continue
        if state is not None and value.get("state") != state:
            continue
        value["contract_name"] = contract_names.get(str(value.get("contract_id") or ""), "")
        value.update(
            {
                "output_guid": value.get("output_id", ""),
                "proj_guid": value.get("project_id", ""),
                "contract_guid": value.get("contract_id", ""),
                "outputGuid": value.get("output_id", ""),
                "outputCode": value.get("output_code", ""),
                "projGuid": value.get("project_id", ""),
                "contractGuid": value.get("contract_id", ""),
                "outputAmount": value.get("output_amount", "0"),
                "confirmAmount": value.get("confirm_amount", "0"),
            }
        )
        rows.append(value)
    rows.sort(key=lambda value: (str(value.get("period", "")), str(value.get("output_id", ""))), reverse=True)
    return {
        "success": True,
        "code": 0,
        "data": rows,
        **_delivery_source_metadata({"proj_output": len(raw), "cb_contract": len(contracts)}),
    }


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


BUDGET_SCOPE_SOURCE_TABLES = {
    "sys_user",
    "mu_business_unit",
    "vcb_loan_simple",
    "ep_project",
}


def _budget_scope_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _budget_scope_coverage(pool: PsqlPool, max_rows: int) -> dict[str, int]:
    return {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), BUDGET_SCOPE_SOURCE_TABLES))
        for table in sorted(BUDGET_SCOPE_SOURCE_TABLES)
    }


def budget_source_users_in_bu(
    pool: PsqlPool,
    bu_guid: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Read ERP ``GET /budget/users-in-bu`` without granting scope."""

    if bu_guid is not None and not IDENTIFIER.fullmatch(bu_guid):
        raise ValueError("invalid bu_guid")
    raw_users = _raw_source_rows(pool, "sys_user", max(max_rows, 500), BUDGET_SCOPE_SOURCE_TABLES)
    raw_units = _raw_source_rows(pool, "mu_business_unit", max(max_rows, 500), BUDGET_SCOPE_SOURCE_TABLES)
    units = {
        _report_text(row["payload"], "bu_guid", row["record_id"]): row["payload"]
        for row in raw_units
    }
    selected = units.get(bu_guid, {}) if bu_guid else {}
    selected_hierarchy = _report_text(selected, "hierarchy_code")
    allowed_units: set[str] = set()
    if bu_guid:
        for guid, payload in units.items():
            hierarchy = _report_text(payload, "hierarchy_code")
            if guid == bu_guid or (
                selected_hierarchy and hierarchy.startswith(selected_hierarchy + ".")
            ):
                allowed_units.add(guid)
    result: list[dict[str, Any]] = []
    for row in raw_users:
        payload = row["payload"]
        if not bool(payload.get("enabled", 0)):
            continue
        user_bu = _report_text(payload, "bu_guid")
        dept = _report_text(payload, "dept_guid")
        if bu_guid is None or user_bu in allowed_units or dept in allowed_units:
            result.append({
                "userId": _report_text(payload, "user_id", row["record_id"]),
                "empName": _report_text(payload, "emp_name", _report_text(payload, "user_name")),
                "deptGuid": dept,
                "buGuid": user_bu,
                "sourceKind": "imported",
                "sourceId": row["source_id"],
            })
    result.sort(key=lambda value: (str(value.get("empName", "")), str(value.get("userId", ""))))
    coverage = _budget_scope_coverage(pool, max_rows)
    metadata = _budget_scope_metadata(coverage)
    metadata["scope_applied"] = bool(bu_guid)
    metadata["scope_required"] = not bool(bu_guid)
    return {"success": True, "code": 0, "data": result[:max_rows], **metadata}


def budget_source_my_loan_balance(
    pool: PsqlPool,
    user_code: str | None,
    user_id: str | None,
    max_rows: int,
) -> dict[str, Any] | None:
    """Read ERP ``GET /budget/my-loan-balance`` for an explicit source user."""

    if user_code is not None and not IDENTIFIER.fullmatch(user_code):
        raise ValueError("invalid user_code")
    if user_id is not None and not IDENTIFIER.fullmatch(user_id):
        raise ValueError("invalid user_id")
    raw_users = _raw_source_rows(pool, "sys_user", max(max_rows, 500), BUDGET_SCOPE_SOURCE_TABLES)
    selected_id = user_id
    if user_code is not None:
        selected = next(
            (row for row in raw_users if _report_text(row["payload"], "user_code") == user_code),
            None,
        )
        if selected is None:
            return None
        selected_id = _report_text(selected["payload"], "user_id", selected["record_id"])
    raw_loans = _raw_source_rows(pool, "vcb_loan_simple", max(max_rows, 500), BUDGET_SCOPE_SOURCE_TABLES)
    rows: list[dict[str, Any]] = []
    for row in raw_loans:
        payload = row["payload"]
        if selected_id is None or _report_text(payload, "applied_by") != selected_id:
            continue
        if _report_text(payload, "apply_state") not in {"Approved", "已审核", "approved"}:
            continue
        remain = _report_float(payload, "remain_amount")
        if remain <= 0 or payload.get("deleted_at"):
            continue
        rows.append({
            "loanGuid": _report_text(payload, "loan_guid", row["record_id"]),
            "loanCode": _report_text(payload, "loan_code"),
            "subject": _report_text(payload, "subject"),
            "remainAmount": remain,
            "loanAmount": _report_float(payload, "loan_amount"),
            "applyDate": _report_text(payload, "apply_date"),
            "sourceKind": "imported",
            "sourceId": row["source_id"],
        })
    rows.sort(key=lambda value: (str(value.get("applyDate", "")), str(value.get("loanGuid", ""))))
    coverage = _budget_scope_coverage(pool, max_rows)
    metadata = _budget_scope_metadata(coverage)
    metadata["scope_applied"] = selected_id is not None
    metadata["scope_required"] = selected_id is None
    return {
        "success": True,
        "code": 0,
        "data": {"total": sum(float(row["remainAmount"]) for row in rows), "loans": rows},
        **metadata,
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


def investment_imports(
    pool: PsqlPool,
    project_id: str,
    max_rows: int,
) -> dict[str, Any]:
    """Observe imported Excel workbooks without enabling upload or parsing.

    The source list route only joins import-history rows to versions and
    users.  The controlled export currently has no ``tzsy_excel_import``
    rows, so this adapter returns an explicit empty list and coverage metadata
    instead of exposing designer imports or manufacturing workbook state.
    """

    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), INVESTMENT_IMPORT_SOURCE_TABLES))
        for table in sorted(INVESTMENT_IMPORT_SOURCE_TABLES)
    }
    versions = {
        str(row["payload"].get("version_guid") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "tzsy_version", max(max_rows, 500), INVESTMENT_IMPORT_SOURCE_TABLES)
    }
    users = {
        str(row["payload"].get("user_id") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "sys_user", max(max_rows, 500), INVESTMENT_IMPORT_SOURCE_TABLES)
    }
    result: list[dict[str, Any]] = []
    for row in _raw_source_rows(pool, "tzsy_excel_import", max(max_rows, 500), INVESTMENT_IMPORT_SOURCE_TABLES):
        payload = row["payload"]
        if str(payload.get("proj_guid") or "") != project_id:
            continue
        version_guid = str(payload.get("version_guid") or "")
        version = versions.get(version_guid, {})
        creator = users.get(str(payload.get("created_by") or ""), {})
        result.append(
            {
                "importGuid": str(payload.get("import_guid") or row["record_id"]),
                "versionGuid": version_guid,
                "versionName": str(version.get("version_name") or ""),
                "fileName": str(payload.get("file_name") or ""),
                "fileSize": payload.get("file_size"),
                "sheetCount": payload.get("sheet_count"),
                "nonEmptyCells": payload.get("non_empty_cells"),
                "formulaCount": payload.get("formula_count"),
                "crossSheetFormulaCount": payload.get("cross_sheet_formula_count"),
                "status": str(payload.get("status") or ""),
                "createdByName": str(creator.get("emp_name") or creator.get("user_name") or ""),
                "createdAt": str(payload.get("created_at") or ""),
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda item: str(item.get("createdAt") or ""), reverse=True)
    return {
        "success": True,
        "code": 0,
        "data": result[:20],
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [table for table, count in coverage.items() if count == 0],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _investment_excel_metadata(pool: PsqlPool, max_rows: int) -> tuple[dict[str, int], list[str]]:
    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), INVESTMENT_EXCEL_SOURCE_TABLES))
        for table in sorted(INVESTMENT_EXCEL_SOURCE_TABLES)
    }
    return coverage, [table for table, count in coverage.items() if count == 0]


def _investment_excel_envelope(
    data: Any,
    coverage: dict[str, int],
    missing: list[str],
) -> dict[str, Any]:
    return {
        "success": True,
        "code": 0,
        "data": data,
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": missing,
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _investment_import_source(
    pool: PsqlPool,
    import_id: str,
    max_rows: int,
) -> tuple[dict[str, Any], dict[str, int], list[str]] | None:
    if not IDENTIFIER.fullmatch(import_id):
        raise ValueError("invalid import_guid")
    coverage, missing = _investment_excel_metadata(pool, max_rows)
    imports = _raw_source_rows(pool, "tzsy_excel_import", max(max_rows, 500), INVESTMENT_EXCEL_SOURCE_TABLES)
    selected = next(
        (
            row for row in imports
            if str(row["payload"].get("import_guid") or row["record_id"]) == import_id
        ),
        None,
    )
    if selected is None:
        return None
    payload = selected["payload"]
    project_id = str(payload.get("proj_guid") or "")
    version_id = str(payload.get("version_guid") or "")
    projects = {
        str(row["payload"].get("proj_guid") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "ep_project", max(max_rows, 500), INVESTMENT_EXCEL_SOURCE_TABLES)
    }
    versions = {
        str(row["payload"].get("version_guid") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "tzsy_version", max(max_rows, 500), INVESTMENT_EXCEL_SOURCE_TABLES)
    }
    users = {
        str(row["payload"].get("user_id") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "sys_user", max(max_rows, 500), INVESTMENT_EXCEL_SOURCE_TABLES)
    }
    version = versions.get(version_id, {})
    creator = users.get(str(payload.get("created_by") or ""), {})
    sheets: list[dict[str, Any]] = []
    for row in _raw_source_rows(pool, "tzsy_excel_sheet", max(max_rows, 2000), INVESTMENT_EXCEL_SOURCE_TABLES):
        sheet = row["payload"]
        if str(sheet.get("import_guid") or "") != import_id:
            continue
        summary = sheet.get("summary_json") or sheet.get("summary")
        if isinstance(summary, str):
            try:
                summary = json.loads(summary)
            except json.JSONDecodeError:
                summary = None
        sheets.append(
            {
                "sheetGuid": str(sheet.get("sheet_guid") or row["record_id"]),
                "sheetOrder": int(sheet.get("sheet_order") or 0),
                "sheetName": str(sheet.get("sheet_name") or ""),
                "dimensionRef": str(sheet.get("dimension_ref") or ""),
                "rowCount": sheet.get("row_count"),
                "colCount": sheet.get("col_count"),
                "nonEmptyCount": sheet.get("non_empty_count"),
                "formulaCount": sheet.get("formula_count"),
                "crossSheetFormulaCount": sheet.get("cross_sheet_formula_count"),
                "mappedModule": str(sheet.get("mapped_module") or "unmapped"),
                "mappedModuleName": str(sheet.get("mapped_module_name") or ""),
                "department": str(sheet.get("department") or ""),
                "summary": summary,
                "cellsJson": sheet.get("cells_json"),
            }
        )
    sheets.sort(key=lambda value: (int(value.get("sheetOrder") or 0), str(value.get("sheetGuid") or "")))
    mapping = payload.get("mapping_json") or payload.get("mapping")
    if isinstance(mapping, str):
        try:
            mapping = json.loads(mapping)
        except json.JSONDecodeError:
            mapping = None
    data = {
        "importGuid": str(payload.get("import_guid") or selected["record_id"]),
        "projGuid": project_id,
        "projName": str(projects.get(project_id, {}).get("proj_name") or ""),
        "versionGuid": version_id,
        "versionName": str(version.get("version_name") or ""),
        "fileName": str(payload.get("file_name") or ""),
        "fileSize": payload.get("file_size"),
        "sheetCount": payload.get("sheet_count"),
        "nonEmptyCells": payload.get("non_empty_cells"),
        "formulaCount": payload.get("formula_count"),
        "crossSheetFormulaCount": payload.get("cross_sheet_formula_count"),
        "status": str(payload.get("status") or ""),
        "mapping": mapping,
        "createdByName": str(creator.get("emp_name") or creator.get("user_name") or ""),
        "createdAt": str(payload.get("created_at") or ""),
        "sheets": sheets,
    }
    return data, coverage, missing


INVESTMENT_BRIDGE_PLANS: dict[str, dict[str, Any]] = {
    "project_master": {
        "erpTargets": ["ep_project"],
        "erpSources": ["ep_project"],
        "apiEndpoints": ["GET /mdm/projects"],
        "status": "parsed",
        "gap": "Excel 项目主数据尚未回写 ep_project。",
        "nextAction": "完成抽取层和项目主数据 owner review 后再回写。",
    },
    "profit_summary": {
        "erpTargets": ["tzsy_plan_index"],
        "erpSources": ["tzsy_plan_index"],
        "apiEndpoints": ["GET /investment/projects/:projGuid/profit-summary"],
        "status": "parsed",
        "gap": "利润指标仍需逐项校准，Excel 值未自动写入。",
        "nextAction": "先完成 preview，再由 owner 批准批量 upsert。",
    },
    "unmapped": {
        "erpTargets": [],
        "erpSources": [],
        "apiEndpoints": [],
        "status": "unmapped",
        "gap": "sheet 未匹配已审计模块。",
        "nextAction": "补充映射规则并重新审核。",
    },
}


def investment_import_detail(pool: PsqlPool, import_id: str, max_rows: int) -> dict[str, Any] | None:
    source = _investment_import_source(pool, import_id, max_rows)
    if source is None:
        return None
    data, coverage, missing = source
    return _investment_excel_envelope(data, coverage, missing)


def investment_import_bridge_plan(pool: PsqlPool, import_id: str, max_rows: int) -> dict[str, Any] | None:
    source = _investment_import_source(pool, import_id, max_rows)
    if source is None:
        return None
    data, coverage, missing = source
    module_counts: dict[str, int] = {}
    sheets: list[dict[str, Any]] = []
    for sheet in data["sheets"]:
        module = str(sheet.get("mappedModule") or "unmapped")
        module_counts[module] = module_counts.get(module, 0) + 1
        plan = INVESTMENT_BRIDGE_PLANS.get(module, INVESTMENT_BRIDGE_PLANS["unmapped"])
        sheets.append(
            {
                "sheetOrder": sheet["sheetOrder"],
                "sheetName": sheet["sheetName"],
                "mappedModule": module,
                "mappedModuleName": sheet["mappedModuleName"],
                "department": sheet["department"],
                **plan,
            }
        )
    bridge_data = {
        "importGuid": data["importGuid"],
        "projGuid": data["projGuid"],
        "versionGuid": data["versionGuid"],
        "fileName": data["fileName"],
        "status": data["status"],
        "summary": {
            "sheetCount": data["sheetCount"],
            "nonEmptyCells": data["nonEmptyCells"],
            "formulaCount": data["formulaCount"],
            "crossSheetFormulaCount": data["crossSheetFormulaCount"],
            "moduleCounts": module_counts,
            "mappedSheetCount": sum(count for module, count in module_counts.items() if module != "unmapped"),
            "unmappedSheetCount": module_counts.get("unmapped", 0),
            "createdAt": data["createdAt"],
        },
        "sheets": sheets,
    }
    return _investment_excel_envelope(bridge_data, coverage, missing)


def investment_index_upsert_preview(pool: PsqlPool, import_id: str, max_rows: int) -> dict[str, Any] | None:
    source = _investment_import_source(pool, import_id, max_rows)
    if source is None:
        return None
    data, coverage, missing = source
    mapping = {
        "profit_summary": (
            ("revenue", "CO.Revenue", "可售货值", "carry_over", "万元"),
            ("cost", "CO.Cost", "成本结转", "carry_over", "万元"),
            ("grossProfit", "CO.GrossProfit", "毛利", "carry_over", "万元"),
            ("netProfit", "CO.NetProfit", "净利润", "carry_over", "万元"),
            ("irr", "CO.IRR", "项目 IRR", "carry_over", "%"),
            ("npv", "CO.NPV", "项目 NPV(8%折现)", "carry_over", "万元"),
        ),
        "tax_detail": (("taxTotal", "Tax.Total", "税费合计", "tax", "万元"),),
        "financial_cost_detail": (("finTotal", "Fin.Total", "融资总额", "financing", "万元"),),
    }
    existing = {
        str(row["payload"].get("full_code") or ""): row["payload"]
        for row in _investment_source_rows(pool, "tzsy_plan_index", max_rows)
        if str(row["payload"].get("version_guid") or "") == data["versionGuid"]
        and not row["payload"].get("deleted_at")
    }
    items: list[dict[str, Any]] = []
    sheets_with_mapping = 0
    sheets_extracted = 0
    for sheet in data["sheets"]:
        fields = mapping.get(str(sheet.get("mappedModule") or ""), ())
        if not fields:
            continue
        sheets_with_mapping += 1
        summary = sheet.get("summary") if isinstance(sheet.get("summary"), dict) else {}
        extracted = summary.get("extractedKeyValues")
        if isinstance(extracted, list):
            sheets_extracted += 1
        extracted_by_key = {
            str(value.get("fieldKey") or ""): value
            for value in extracted or []
            if isinstance(value, dict)
        }
        for field_key, full_code, index_name, dimension, unit in fields:
            old = existing.get(full_code, {})
            hit = extracted_by_key.get(field_key)
            item = {
                "sheetOrder": sheet["sheetOrder"],
                "sheetName": sheet["sheetName"],
                "mappedModule": sheet["mappedModule"],
                "mappedModuleName": sheet["mappedModuleName"],
                "fullCode": full_code,
                "indexName": index_name,
                "dimension": dimension,
                "unit": unit,
                "oldValue": old.get("index_value"),
                "existingIndexGuid": old.get("index_guid"),
                "newValue": hit.get("value") if hit else None,
                "sourceCell": hit.get("valueRef") if hit else None,
                "anchorCell": hit.get("anchorRef") if hit else None,
                "confidence": "high" if hit and hit.get("direction") == "right" else ("medium" if hit else None),
                "canUpsert": bool(hit),
                "proposedAction": "update" if hit and old else ("insert" if hit else None),
                "reason": None if hit else "未抽取到源单元格值。",
                "missingData": None if hit else "extractedKeyValues",
            }
            items.append(item)
    preview_data = {
        "importGuid": data["importGuid"],
        "projGuid": data["projGuid"],
        "versionGuid": data["versionGuid"],
        "versionName": data["versionName"],
        "versionNo": None,
        "versionIsCurrent": None,
        "fileName": data["fileName"],
        "summary": {
            "sheetsTotal": len(data["sheets"]),
            "sheetsWithMapping": sheets_with_mapping,
            "sheetsExtracted": sheets_extracted,
            "itemsTotal": len(items),
            "itemsCanUpsert": sum(1 for item in items if item["canUpsert"]),
            "itemsToInsert": sum(1 for item in items if item["proposedAction"] == "insert"),
            "itemsToUpdate": sum(1 for item in items if item["proposedAction"] == "update"),
            "itemsToSkip": sum(1 for item in items if item["proposedAction"] is None),
        },
        "items": items,
    }
    return _investment_excel_envelope(preview_data, coverage, missing)


def investment_profit_table(pool: PsqlPool, import_id: str, max_rows: int) -> dict[str, Any] | None:
    source = _investment_import_source(pool, import_id, max_rows)
    if source is None:
        return None
    data, coverage, missing = source
    grouped: dict[str, dict[str, Any]] = {}
    for row in _raw_source_rows(pool, "tzsy_profit_table", max(max_rows, 5000), INVESTMENT_EXCEL_SOURCE_TABLES):
        payload = row["payload"]
        if str(payload.get("import_guid") or "") != import_id:
            continue
        row_key = str(payload.get("row_idx") or "0")
        grouped.setdefault(row_key, {"row": int(payload.get("row_idx") or 0), "cells": {}})["cells"][
            str(payload.get("col_key") or payload.get("col_idx") or "")
        ] = {
            "text": payload.get("text_value"),
            "num": payload.get("num_value"),
            "formula": payload.get("formula"),
            "ref": payload.get("cell_ref"),
            "isHeader": bool(payload.get("is_header")),
        }
    rows = sorted(grouped.values(), key=lambda value: value["row"])
    return _investment_excel_envelope(
        {
            "importGuid": data["importGuid"],
            "projGuid": data["projGuid"],
            "versionGuid": data["versionGuid"],
            "sheetName": "利润测算总表",
            "source": "tzsy_profit_table" if rows else "empty",
            "merged": [],
            "rows": rows,
            "columnOrder": sorted({column for row in rows for column in row["cells"]}),
        },
        coverage,
        missing,
    )


def investment_plan_line_preview(pool: PsqlPool, import_id: str, max_rows: int) -> dict[str, Any] | None:
    source = _investment_import_source(pool, import_id, max_rows)
    if source is None:
        return None
    data, coverage, missing = source
    sheet_summary = []
    for sheet in data["sheets"]:
        if sheet["mappedModule"] in {"land_cost_detail", "construction_cost_detail", "design_cost_detail", "marketing_cost_detail", "admin_cost_detail", "audit_fee_detail", "financial_cost_detail", "tax_detail"}:
            sheet_summary.append(
                {
                    "sheet": sheet["sheetName"],
                    "module": sheet["mappedModule"],
                    "lines": 0,
                    "reason": "源 sheet cells_json 未导入或尚未完成安全抽取。",
                }
            )
    return _investment_excel_envelope(
        {
            "importGuid": data["importGuid"],
            "projGuid": data["projGuid"],
            "versionGuid": data["versionGuid"],
            "summary": {
                "sheetsScanned": len(data["sheets"]),
                "sheetsWithRule": len(sheet_summary),
                "linesTotal": 0,
                "amountTotal": 0.0,
            },
            "sheetSummary": sheet_summary,
            "lines": [],
        },
        coverage,
        missing,
    )


def investment_plan_lines(
    pool: PsqlPool,
    project_id: str,
    query: dict[str, str | None],
    max_rows: int,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    coverage, missing = _investment_excel_metadata(pool, max_rows)
    rows: list[dict[str, Any]] = []
    for row in _raw_source_rows(pool, "tzsy_plan_line", max(max_rows, 5000), INVESTMENT_EXCEL_SOURCE_TABLES):
        payload = row["payload"]
        if str(payload.get("proj_guid") or "") != project_id:
            continue
        checks = {
            "versionGuid": "version_guid",
            "moduleCode": "module_code",
            "sheet": "source_sheet",
            "department": "department",
            "status": "status",
        }
        if any(query.get(key) and str(payload.get(source_key) or "") != query[key] for key, source_key in checks.items()):
            continue
        keyword = query.get("keyword")
        if keyword and keyword.casefold() not in str(payload.get("subject") or "").casefold():
            continue
        rows.append(
            {
                "lineGuid": str(payload.get("line_guid") or row["record_id"]),
                "projGuid": project_id,
                "versionGuid": str(payload.get("version_guid") or ""),
                "importGuid": str(payload.get("import_guid") or ""),
                "sourceSheet": str(payload.get("source_sheet") or ""),
                "moduleCode": str(payload.get("module_code") or ""),
                "moduleName": str(payload.get("module_name") or ""),
                "subject": str(payload.get("subject") or ""),
                "planAmount": payload.get("plan_amount"),
                "planPeriod": str(payload.get("plan_period") or ""),
                "department": str(payload.get("department") or ""),
                "sourceRow": payload.get("source_row"),
                "sourceCell": str(payload.get("source_cell") or ""),
                "status": str(payload.get("status") or ""),
                "remark": str(payload.get("remark") or ""),
                "createdAt": str(payload.get("created_at") or ""),
                "updatedAt": str(payload.get("updated_at") or ""),
            }
        )
    rows.sort(key=lambda value: (value["moduleCode"], value["sourceSheet"], int(value["sourceRow"] or 0)))
    by_module: dict[str, dict[str, Any]] = {}
    amount_total = 0.0
    for row in rows:
        module = row["moduleCode"] or "unknown"
        item = by_module.setdefault(module, {"moduleCode": module, "moduleName": row["moduleName"], "count": 0, "amount": 0.0})
        item["count"] += 1
        amount = _report_float(row, "planAmount")
        item["amount"] += amount
        amount_total += amount
    for item in by_module.values():
        item["amount"] = round(item["amount"], 4)
    return _investment_excel_envelope(
        {
            "lines": rows,
            "summary": {"count": len(rows), "amountTotal": round(amount_total, 4), "byModule": list(by_module.values())},
        },
        coverage,
        missing,
    )


def investment_subject_mappings(pool: PsqlPool, project_id: str, max_rows: int) -> dict[str, Any] | None:
    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    coverage, missing = _investment_excel_metadata(pool, max_rows)
    project = next(
        (
            row["payload"] for row in _raw_source_rows(pool, "ep_project", max(max_rows, 500), INVESTMENT_EXCEL_SOURCE_TABLES)
            if str(row["payload"].get("proj_guid") or row["record_id"]) == project_id
            and not row["payload"].get("deleted_at")
        ),
        None,
    )
    if project is None:
        return None
    groups: dict[str, list[dict[str, Any]]] = {}
    for row in _raw_source_rows(pool, "tzsy_subject_mapping", max(max_rows, 5000), INVESTMENT_EXCEL_SOURCE_TABLES):
        payload = row["payload"]
        if str(payload.get("proj_guid") or "") != project_id:
            continue
        category = str(payload.get("category") or "custom")
        groups.setdefault(category, []).append(
            {
                "key": str(payload.get("param_key") or ""),
                "value": str(payload.get("param_value") or ""),
                "type": str(payload.get("value_type") or "string"),
                "description": str(payload.get("description") or ""),
            }
        )
    return _investment_excel_envelope(
        {"projGuid": project_id, "projName": str(project.get("proj_name") or ""), "groups": groups},
        coverage,
        missing,
    )


def investment_profit_cockpit(pool: PsqlPool, project_id: str, max_rows: int) -> dict[str, Any] | None:
    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    coverage, missing = _investment_excel_metadata(pool, max_rows)
    project = next(
        (
            row["payload"] for row in _raw_source_rows(pool, "ep_project", max(max_rows, 500), INVESTMENT_EXCEL_SOURCE_TABLES)
            if str(row["payload"].get("proj_guid") or row["record_id"]) == project_id
            and not row["payload"].get("deleted_at")
        ),
        None,
    )
    if project is None:
        return None
    imports = {
        str(row["payload"].get("import_guid") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "tzsy_excel_import", max(max_rows, 500), INVESTMENT_EXCEL_SOURCE_TABLES)
        if str(row["payload"].get("proj_guid") or "") == project_id
    }
    table_rows = [
        row["payload"]
        for row in _raw_source_rows(pool, "tzsy_profit_table", max(max_rows, 5000), INVESTMENT_EXCEL_SOURCE_TABLES)
        if str(row["payload"].get("import_guid") or "") in imports
    ]
    if not table_rows:
        return None
    values: dict[str, dict[str, Any]] = {}
    for row in table_rows:
        if str(row.get("col_key") or "") != "C":
            continue
        key = "R" + str(row.get("row_idx") or "")
        values[key] = {"total": row.get("num_value") or 0}
    return _investment_excel_envelope(
        {
            "projGuid": project_id,
            "projName": str(project.get("proj_name") or ""),
            "versionGuid": str(next(iter(imports.values()), {}).get("version_guid") or ""),
            "importGuid": next(iter(imports.keys()), ""),
            "source": "tzsy_profit_table",
            "values": values,
            "children": {},
        },
        coverage,
        missing,
    )


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


def investment_sensitivity(
    pool: PsqlPool,
    project_id: str,
    max_rows: int,
) -> dict[str, Any]:
    """Return the ERP sensitivity scenarios from the current source version.

    This mirrors the source route's deterministic calculation. It is an
    observation only: it does not activate a version, write an index, call an
    LLM, or authorize a valuation or accounting effect.
    """

    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    versions = [
        row["payload"]
        for row in _investment_source_rows(pool, "tzsy_version", max_rows)
        if str(row["payload"].get("proj_guid") or "") == project_id
        and not row["payload"].get("deleted_at")
    ]
    current = next(
        (row for row in versions if _dashboard_flag(row.get("is_current"))),
        None,
    )
    if current is None:
        return {
            "success": True,
            "code": 0,
            "data": {"msg": "尚无激活版本"},
            "source_kind": "imported",
            "source_coverage": {"tzsy_version": len(versions), "tzsy_plan_index": 0},
            "authorizing": False,
            "persisted": False,
            "provider_execution": False,
        }
    version_id = str(current.get("version_guid") or "")
    rows = [
        row["payload"]
        for row in _investment_source_rows(pool, "tzsy_plan_index", max_rows)
        if str(row["payload"].get("version_guid") or "") == version_id
        and not row["payload"].get("deleted_at")
    ]

    def find_value(*terms: str, default: float) -> float:
        for row in rows:
            name = str(row.get("index_name") or "")
            if any(term in name for term in terms):
                return _report_float(row, "index_value")
        return default

    sales = find_value("售价", "收入", default=0.0)
    cost = find_value("成本", default=1.0)
    tax = find_value("税", default=0.0)

    def irr(sales_value: float, cost_value: float, tax_value: float) -> float:
        if cost_value <= 0:
            return 0.0
        profit = sales_value - cost_value - tax_value
        if profit <= 0:
            return -100.0
        return round(((profit / cost_value) ** (1 / 5) - 1) * 100, 2)

    cases = [
        {"name": "基线", "irr": irr(sales, cost, tax)},
        {"name": "售价 -5%", "irr": irr(sales * 0.95, cost, tax)},
        {"name": "售价 -10%", "irr": irr(sales * 0.90, cost, tax)},
        {"name": "成本 +5%", "irr": irr(sales, cost * 1.05, tax)},
        {"name": "成本 +10%", "irr": irr(sales, cost * 1.10, tax)},
        {"name": "税费 +5%", "irr": irr(sales, cost, tax * 1.05)},
    ]
    return {
        "success": True,
        "code": 0,
        "data": {
            "base": {"sales": sales, "cost": cost, "tax": tax},
            "baseIrr": irr(sales, cost, tax),
            "cases": cases,
        },
        "source_kind": "imported",
        "source_coverage": {"tzsy_version": len(versions), "tzsy_plan_index": len(rows)},
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def admin_quality_overview(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    """Evaluate the source admin quality rules without inventing empty data."""

    rows_by_table = {
        table: _raw_source_rows(pool, table, max(max_rows, 500), ADMIN_QUALITY_SOURCE_TABLES)
        for table in sorted(ADMIN_QUALITY_SOURCE_TABLES)
    }
    coverage = {table: len(rows) for table, rows in rows_by_table.items()}
    missing_or_empty = [table for table, count in coverage.items() if count == 0]

    def payloads(table: str) -> list[dict[str, Any]]:
        return [row["payload"] for row in rows_by_table[table]]

    def quality_rule(
        code: str,
        name: str,
        source_tables: list[str],
        count: int,
    ) -> dict[str, Any]:
        unavailable = [table for table in source_tables if coverage.get(table, 0) == 0]
        if unavailable:
            return {
                "ruleCode": code,
                "rule": name,
                "count": None,
                "status": "NO_SOURCE_ROWS",
                "severity": "info",
                "sourceTables": source_tables,
                "missingSourceTables": unavailable,
                "sourceKind": "imported_or_empty",
            }
        severity = "info" if count == 0 else ("error" if count > 5 else "warning")
        return {
            "ruleCode": code,
            "rule": name,
            "count": count,
            "status": "PASS" if count == 0 else "FAIL",
            "severity": severity,
            "sourceTables": source_tables,
            "missingSourceTables": [],
            "sourceKind": "imported",
        }

    projects = payloads("ep_project")
    contracts = payloads("cb_contract")
    applies = payloads("cb_htfk_apply")
    costs = payloads("cb_cost")
    tasks = payloads("jd_task")
    loans = payloads("vcb_loan_simple")
    users = payloads("sys_user")
    payments_by_contract: dict[str, float] = {}
    for apply in applies:
        if str(apply.get("apply_state") or "") == "已审核":
            contract_id = str(apply.get("contract_guid") or "")
            payments_by_contract[contract_id] = payments_by_contract.get(contract_id, 0.0) + _report_float(
                apply, "apply_amount"
            )
    cost_projects = {
        str(cost.get("proj_guid") or "")
        for cost in costs
        if _dashboard_flag(cost.get("is_end_cost"))
    }
    rules = [
        quality_rule(
            "project_without_bu",
            "项目缺少所属公司",
            ["ep_project"],
            sum(1 for project in projects if not str(project.get("bu_guid") or "")),
        ),
        quality_rule(
            "contract_without_project",
            "合同未关联项目",
            ["cb_contract"],
            sum(1 for contract in contracts if not str(contract.get("proj_guid") or "")),
        ),
        quality_rule(
            "payment_without_contract",
            "付款申请缺少合同",
            ["cb_htfk_apply"],
            sum(1 for apply in applies if not str(apply.get("contract_guid") or "")),
        ),
        quality_rule(
            "payment_over_contract",
            "付款累计超合同总额",
            ["cb_contract", "cb_htfk_apply"],
            sum(
                1
                for contract in contracts
                if payments_by_contract.get(str(contract.get("contract_guid") or ""), 0.0)
                > _report_float(contract, "ht_amount") + _report_float(contract, "sum_alter_amount")
            ),
        ),
        quality_rule(
            "project_without_dynamic_cost",
            "在建项目无动态成本科目",
            ["ep_project", "cb_cost"],
            sum(
                1
                for project in projects
                if str(project.get("proj_status") or "") in {"planning", "development", "sales"}
                and str(project.get("proj_guid") or "") not in cost_projects
            ),
        ),
        quality_rule(
            "expense_split_mismatch",
            "报销分摊合计 ≠ 应付金额",
            ["vcb_expense", "cb_expense_split"],
            0,
        ),
        quality_rule(
            "workflow_overdue",
            "BPM 实例进行中超 7 天",
            ["wf_process_instance"],
            sum(
                1
                for row in rows_by_table["wf_process_instance"]
                if str(row["payload"].get("status") or "") == "Running"
                and (_report_date(row["payload"].get("initiated_at")) or date.max)
                < date.today() - timedelta(days=7)
            ),
        ),
        quality_rule(
            "loan_balance_inconsistent",
            "借款三态字段不一致",
            ["vcb_loan_simple"],
            sum(
                1
                for loan in loans
                if abs(
                    _report_float(loan, "remain_amount")
                    - (_report_float(loan, "loan_amount") - _report_float(loan, "balance_amount"))
                )
                > 0.01
            ),
        ),
        quality_rule(
            "task_dates_reversed",
            "任务计划完成 < 开始日期",
            ["jd_task"],
            sum(
                1
                for task in tasks
                if (_report_date(task.get("plan_end_date")) or date.max)
                < (_report_date(task.get("plan_begin_date")) or date.min)
            ),
        ),
        quality_rule(
            "supplier_duplicate_name",
            "供应商重名(SRM)",
            ["srm_provider"],
            0,
        ),
        quality_rule(
            "workflow_zombie",
            "BPM 实例僵尸(>30 天 Running)",
            ["wf_process_instance"],
            sum(
                1
                for row in rows_by_table["wf_process_instance"]
                if str(row["payload"].get("status") or "") == "Running"
                and (_report_date(row["payload"].get("initiated_at")) or date.max)
                < date.today() - timedelta(days=30)
            ),
        ),
        quality_rule(
            "user_without_bu",
            "用户缺少所属组织",
            ["sys_user"],
            sum(1 for user in users if not str(user.get("bu_guid") or "")),
        ),
    ]
    evaluated = [rule for rule in rules if rule["status"] != "NO_SOURCE_ROWS"]
    return {
        "success": True,
        "code": 0,
        "data": {
            "summary": {
                "total": sum(int(rule["count"]) for rule in evaluated),
                "passed": sum(1 for rule in evaluated if rule["status"] == "PASS"),
                "failed": sum(1 for rule in evaluated if rule["status"] == "FAIL"),
                "totalRules": len(rules),
                "evaluatedRules": len(evaluated),
                "unavailableRules": len(rules) - len(evaluated),
            },
            "rules": rules,
        },
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": missing_or_empty,
    }


def admin_rbac_users(
    pool: PsqlPool,
    keyword: str | None,
    enabled: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if keyword is not None and len(keyword) > 128:
        raise ValueError("invalid user keyword")
    if enabled not in {None, "", "0", "1"}:
        raise ValueError("enabled must be 0 or 1")
    rows_by_table = {
        table: _raw_source_rows(pool, table, max(max_rows, 500), ADMIN_RBAC_SOURCE_TABLES)
        for table in sorted(ADMIN_RBAC_SOURCE_TABLES)
    }
    coverage = {table: len(rows) for table, rows in rows_by_table.items()}
    units = {
        str(row["payload"].get("bu_guid") or row["record_id"]): row["payload"]
        for row in rows_by_table["mu_business_unit"]
    }
    filtered: list[dict[str, Any]] = []
    folded_keyword = keyword.casefold() if keyword else None
    for row in rows_by_table["sys_user"]:
        payload = row["payload"]
        user_code = str(payload.get("user_code") or "")
        emp_name = str(payload.get("emp_name") or payload.get("user_name") or "")
        is_enabled = bool(payload.get("enabled", 0))
        if folded_keyword and folded_keyword not in (user_code + " " + emp_name).casefold():
            continue
        if enabled in {"0", "1"} and is_enabled != (enabled == "1"):
            continue
        bu_guid = str(payload.get("bu_guid") or "")
        dept_guid = str(payload.get("dept_guid") or "")
        filtered.append(
            {
                "userId": str(payload.get("user_id") or row["record_id"]),
                "userCode": user_code,
                "empName": emp_name,
                "isSuperUser": bool(payload.get("is_super_user", 0)),
                "enabled": is_enabled,
                "buGuid": bu_guid,
                "buName": str(units.get(bu_guid, {}).get("bu_name") or ""),
                "deptGuid": dept_guid,
                "deptName": str(units.get(dept_guid, {}).get("bu_name") or ""),
                "roles": [],
                "rolesSourceStatus": (
                    "NO_SOURCE_ROWS"
                    if coverage.get("sys_role", 0) == 0 or coverage.get("sys_user_role", 0) == 0
                    else "NOT_MAPPED"
                ),
                "sourceKind": "imported",
            }
        )
    filtered.sort(key=lambda value: (not value["isSuperUser"], value["userCode"], value["userId"]))
    return {
        "success": True,
        "code": 0,
        "data": filtered[:max_rows],
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [table for table, count in coverage.items() if count == 0],
    }


def rbac_current_user(
    pool: PsqlPool,
    user_code: str,
    max_rows: int,
) -> dict[str, Any] | None:
    """Read the source ``GET /rbac/me`` shape without making it an authority."""

    profile = auth_current_user(pool, user_code, max_rows)
    if profile is None:
        return None
    profile_data = profile["data"]
    users = _raw_source_rows(pool, "sys_user", max(max_rows, 100), ADMIN_RBAC_SOURCE_TABLES)
    selected = next(
        (
            row
            for row in users
            if str(row["payload"].get("user_code") or "") == user_code
        ),
        None,
    )
    if selected is None:
        return None
    user_id = str(selected["payload"].get("user_id") or selected["record_id"])
    roles = _raw_source_rows(pool, "sys_role", max(max_rows, 500), ADMIN_RBAC_SOURCE_TABLES)
    assignments = _raw_source_rows(pool, "sys_user_role", max(max_rows, 500), ADMIN_RBAC_SOURCE_TABLES)
    role_by_code = {
        str(row["payload"].get("role_code") or row["record_id"]): row["payload"]
        for row in roles
    }
    role_codes: list[str] = []
    role_names: list[str] = []
    permissions: list[str] = []
    data_scope = "self"
    for assignment in assignments:
        payload = assignment["payload"]
        if str(payload.get("user_id") or "") != user_id:
            continue
        role_code = str(payload.get("role_code") or "")
        if not role_code or role_code in role_codes:
            continue
        role_codes.append(role_code)
        role = role_by_code.get(role_code, {})
        role_name = str(role.get("role_name") or "")
        if role_name:
            role_names.append(role_name)
        scope = str(role.get("data_scope") or "")
        if scope:
            data_scope = scope
        raw_permissions = role.get("permissions", [])
        if isinstance(raw_permissions, str):
            try:
                raw_permissions = json.loads(raw_permissions)
            except json.JSONDecodeError:
                raw_permissions = []
        if isinstance(raw_permissions, list):
            for permission in raw_permissions:
                value = str(permission)
                if value and value not in permissions:
                    permissions.append(value)
    coverage = {
        "sys_user": len(users),
        "sys_role": len(roles),
        "sys_user_role": len(assignments),
    }
    return {
        "success": True,
        "code": 0,
        "data": {
            "userId": profile_data["userId"],
            "userCode": profile_data["userCode"],
            "empName": profile_data["empName"],
            "buGuid": profile_data["buGuid"],
            "isSuperUser": profile_data["isSuperUser"],
            "roles": role_codes,
            "roleNames": role_names,
            "permissions": permissions,
            "dataScope": data_scope,
            "rolesSourceStatus": (
                "NO_SOURCE_ROWS"
                if coverage["sys_role"] == 0 or coverage["sys_user_role"] == 0
                else "IMPORTED"
            ),
            "sourceKind": "imported",
        },
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
    }


def auth_current_user(
    pool: PsqlPool,
    user_code: str,
    max_rows: int,
) -> dict[str, Any] | None:
    """Return the imported, non-secret profile for one source user.

    This mirrors the source ``GET /auth/me`` read without exposing password,
    login-failure, or network fields.  It is deliberately a read boundary:
    profile updates, password changes, preferences, and initiated-document
    mutations remain separate authenticated commands.
    """

    if not IDENTIFIER.fullmatch(user_code):
        raise ValueError("invalid user_code")
    users = _raw_source_rows(pool, "sys_user", max(max_rows, 100), ADMIN_RBAC_SOURCE_TABLES)
    units = {
        str(row["payload"].get("bu_guid") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "mu_business_unit", max(max_rows, 100), ADMIN_RBAC_SOURCE_TABLES)
    }
    selected = next(
        (
            row
            for row in users
            if str(row["payload"].get("user_code") or "") == user_code
        ),
        None,
    )
    if selected is None:
        return None
    payload = selected["payload"]
    bu_guid = str(payload.get("bu_guid") or "")
    dept_guid = str(payload.get("dept_guid") or "")
    return {
        "success": True,
        "code": 0,
        "data": {
            "userId": str(payload.get("user_id") or selected["record_id"]),
            "userCode": user_code,
            "userName": str(payload.get("user_name") or ""),
            "empName": str(payload.get("emp_name") or payload.get("user_name") or ""),
            "buGuid": bu_guid,
            "buName": str(units.get(bu_guid, {}).get("bu_name") or ""),
            "deptGuid": dept_guid,
            "deptName": str(units.get(dept_guid, {}).get("bu_name") or ""),
            "isSuperUser": bool(payload.get("is_super_user", 0)),
            "enabled": bool(payload.get("enabled", 0)),
            "lastLoginTime": str(payload.get("last_login_time") or ""),
            "sourceKind": "imported",
        },
        "source_kind": "imported",
        "source_coverage": {
            "sys_user": len(users),
            "mu_business_unit": len(units),
        },
    }


def auth_preferences(
    pool: PsqlPool,
    user_code: str,
    max_rows: int,
) -> dict[str, Any] | None:
    """Read source ``GET /auth/prefs`` without enabling preference writes."""

    if not IDENTIFIER.fullmatch(user_code):
        raise ValueError("invalid user_code")
    users = _raw_source_rows(pool, "sys_user", max(max_rows, 100), AUTH_PREF_SOURCE_TABLES)
    selected = next(
        (
            row
            for row in users
            if str(row["payload"].get("user_code") or "") == user_code
        ),
        None,
    )
    if selected is None:
        return None
    user_id = str(selected["payload"].get("user_id") or selected["record_id"])
    raw_preferences = _raw_source_rows(
        pool,
        "sys_user_pref",
        max(max_rows, 100),
        AUTH_PREF_SOURCE_TABLES,
    )
    values: dict[str, Any] = {}
    for row in raw_preferences:
        payload = row["payload"]
        if str(payload.get("user_id") or "") != user_id:
            continue
        key = str(payload.get("pref_key") or "")
        if not key:
            continue
        value = payload.get("pref_value")
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except json.JSONDecodeError:
                pass
        values[key] = value
    coverage = {
        "sys_user": len(users),
        "sys_user_pref": len(raw_preferences),
    }
    return {
        "success": True,
        "code": 0,
        "data": values,
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
    }


def auth_my_initiated(
    pool: PsqlPool,
    user_code: str,
    max_rows: int,
) -> dict[str, Any] | None:
    """Read the source user's initiated expense/loan/payment records.

    The source endpoint joins three tables.  Empty source tables stay empty;
    the result never falls back to the designer's sample documents.
    """

    if not IDENTIFIER.fullmatch(user_code):
        raise ValueError("invalid user_code")
    users = _raw_source_rows(pool, "sys_user", max(max_rows, 100), AUTH_SOURCE_TABLES)
    selected = next(
        (
            row
            for row in users
            if str(row["payload"].get("user_code") or "") == user_code
        ),
        None,
    )
    if selected is None:
        return None
    user_id = str(selected["payload"].get("user_id") or selected["record_id"])

    def initiated_rows(table: str, id_key: str, code_key: str, amount_key: str) -> list[dict[str, Any]]:
        rows = _raw_source_rows(pool, table, max(max_rows, 100), AUTH_SOURCE_TABLES)
        filtered = [
            row
            for row in rows
            if str(row["payload"].get("applied_by") or "") == user_id
        ]
        filtered.sort(
            key=lambda row: (
                str(row["payload"].get("apply_date") or row["payload"].get("created_at") or ""),
                str(row["payload"].get(id_key) or row["record_id"]),
            ),
            reverse=True,
        )
        result: list[dict[str, Any]] = []
        for row in filtered[:max_rows]:
            payload = row["payload"]
            result.append(
                {
                    "id": str(payload.get(id_key) or row["record_id"]),
                    "code": str(payload.get(code_key) or ""),
                    "subject": str(payload.get("subject") or ""),
                    "amount": payload.get(amount_key),
                    "state": str(payload.get("apply_state") or ""),
                    "date": str(payload.get("apply_date") or ""),
                    "biz": table,
                    "sourceKind": "imported",
                }
            )
        return result

    expenses = initiated_rows("vcb_expense", "expense_guid", "expense_code", "pay_amount")
    loans = initiated_rows("vcb_loan_simple", "loan_guid", "loan_code", "loan_amount")
    applies = initiated_rows("cb_htfk_apply", "htfk_apply_guid", "apply_code", "apply_amount")
    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 100), AUTH_SOURCE_TABLES))
        for table in sorted(AUTH_SOURCE_TABLES)
    }
    return {
        "success": True,
        "code": 0,
        "data": {
            "expenses": expenses,
            "loans": loans,
            "applies": applies,
        },
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "matched_coverage": {
            "vcb_expense": len(expenses),
            "vcb_loan_simple": len(loans),
            "cb_htfk_apply": len(applies),
        },
    }


def rbac_roles(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    """Read source ``GET /rbac/roles`` without applying role authority."""

    raw_roles = _raw_source_rows(pool, "sys_role", max(max_rows, 500), ADMIN_RBAC_SOURCE_TABLES)
    assignments = _raw_source_rows(
        pool, "sys_user_role", max(max_rows, 500), ADMIN_RBAC_SOURCE_TABLES,
    )
    users_by_id = {
        str(row["payload"].get("user_id") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "sys_user", max(max_rows, 500), ADMIN_RBAC_SOURCE_TABLES)
    }
    user_counts: dict[str, int] = {}
    for assignment in assignments:
        role_code = str(assignment["payload"].get("role_code") or "")
        user_id = str(assignment["payload"].get("user_id") or "")
        if role_code and user_id in users_by_id:
            user_counts[role_code] = user_counts.get(role_code, 0) + 1
    result: list[dict[str, Any]] = []
    for row in raw_roles:
        payload = row["payload"]
        role_code = str(payload.get("role_code") or row["record_id"])
        permissions = payload.get("permissions", [])
        if isinstance(permissions, str):
            try:
                permissions = json.loads(permissions)
            except json.JSONDecodeError:
                permissions = []
        if not isinstance(permissions, list):
            permissions = []
        result.append(
            {
                "roleCode": role_code,
                "roleName": str(payload.get("role_name") or ""),
                "description": str(payload.get("description") or ""),
                "dataScope": str(payload.get("data_scope") or "self"),
                "permissions": [str(permission) for permission in permissions],
                "isSystem": bool(payload.get("is_system", 0)),
                "userCount": user_counts.get(role_code, 0),
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda value: str(value.get("roleCode", "")))
    coverage = {
        "sys_role": len(raw_roles),
        "sys_user_role": len(assignments),
        "sys_user": len(users_by_id),
    }
    return {
        "success": True,
        "code": 0,
        "data": result[:max_rows],
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def rbac_role_detail(
    pool: PsqlPool,
    role_code: str,
    max_rows: int,
) -> dict[str, Any] | None:
    """Read source ``GET /rbac/roles/:code`` with no mutation or grants."""

    if not IDENTIFIER.fullmatch(role_code):
        raise ValueError("invalid role code")
    roles = rbac_roles(pool, max_rows)
    role = next(
        (item for item in roles["data"] if item.get("roleCode") == role_code),
        None,
    )
    if role is None:
        return None
    assignments = _raw_source_rows(
        pool, "sys_user_role", max(max_rows, 500), ADMIN_RBAC_SOURCE_TABLES,
    )
    users = {
        str(row["payload"].get("user_id") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "sys_user", max(max_rows, 500), ADMIN_RBAC_SOURCE_TABLES)
    }
    assigned_users: list[dict[str, Any]] = []
    for assignment in assignments:
        payload = assignment["payload"]
        if str(payload.get("role_code") or "") != role_code:
            continue
        user_id = str(payload.get("user_id") or "")
        user = users.get(user_id)
        if user is None:
            continue
        assigned_users.append(
            {
                "userId": user_id,
                "userCode": str(user.get("user_code") or ""),
                "empName": str(user.get("emp_name") or user.get("user_name") or ""),
                "grantedAt": str(payload.get("granted_at") or ""),
            }
        )
    assigned_users.sort(key=lambda value: str(value.get("userCode", "")))
    return {
        "success": True,
        "code": 0,
        "data": {
            "role": role,
            "users": assigned_users[:max_rows],
        },
        "source_kind": roles["source_kind"],
        "source_coverage": roles["source_coverage"],
        "missing_or_empty_source_tables": roles["missing_or_empty_source_tables"],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


RBAC_PERMISSION_CATALOG = [
    {"module": "驾驶舱", "perms": [{"code": "dashboard:read", "name": "查看驾驶舱"}]},
    {
        "module": "项目",
        "perms": [
            {"code": "project:read", "name": "查看项目"},
            {"code": "project:create", "name": "新建项目"},
            {"code": "project:update", "name": "修改项目"},
        ],
    },
    {
        "module": "合同",
        "perms": [
            {"code": "contract:read", "name": "查看合同"},
            {"code": "contract:create", "name": "新建合同"},
            {"code": "contract:approve", "name": "审批合同"},
        ],
    },
    {
        "module": "付款",
        "perms": [
            {"code": "payment:read", "name": "查看付款"},
            {"code": "payment:create", "name": "发起付款"},
            {"code": "payment:approve", "name": "审批付款"},
            {"code": "payment:pay", "name": "出纳支付"},
        ],
    },
    {
        "module": "成本",
        "perms": [
            {"code": "cost:read", "name": "查看动态成本"},
            {"code": "cost:update", "name": "调整动态成本"},
        ],
    },
    {
        "module": "报销",
        "perms": [
            {"code": "expense:read", "name": "查看报销"},
            {"code": "expense:create", "name": "发起报销"},
            {"code": "expense:approve", "name": "审批报销"},
        ],
    },
    {
        "module": "借款",
        "perms": [
            {"code": "loan:read", "name": "查看借款"},
            {"code": "loan:create", "name": "发起借款"},
            {"code": "loan:approve", "name": "审批借款"},
        ],
    },
    {
        "module": "计划",
        "perms": [
            {"code": "plan:read", "name": "查看计划"},
            {"code": "plan:create", "name": "编排任务"},
        ],
    },
    {
        "module": "投资",
        "perms": [
            {"code": "investment:read", "name": "查看投资"},
            {"code": "investment:update", "name": "调整测算"},
        ],
    },
    {"module": "报表", "perms": [{"code": "report:read", "name": "查看报表"}]},
    {
        "module": "SRM",
        "perms": [
            {"code": "srm:read", "name": "查看供应商"},
            {"code": "srm:create", "name": "新增供应商"},
            {"code": "srm:approve", "name": "供应商入库"},
        ],
    },
]


def rbac_permission_catalog() -> dict[str, Any]:
    """Return the source-defined permission catalog as non-authorizing metadata."""

    return {
        "success": True,
        "code": 0,
        "data": json.loads(json.dumps(RBAC_PERMISSION_CATALOG, ensure_ascii=False)),
        "source_kind": "definition",
        "source_coverage": {},
        "missing_or_empty_source_tables": [],
        "authorizing": False,
        "persisted": False,
    }


def admin_dict_groups(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    raw = _raw_source_rows(pool, "my_biz_param_option", max(max_rows, 100), ADMIN_SOURCE_TABLES)
    groups: dict[str, dict[str, int]] = {}
    for row in raw:
        name = str(row["payload"].get("param_name") or "")
        if not name:
            continue
        group = groups.setdefault(name, {"total": 0, "enabled": 0})
        group["total"] += 1
        if bool(row["payload"].get("enabled", 0)):
            group["enabled"] += 1
    return {
        "success": True,
        "code": 0,
        "data": [
            {"groupName": name, "total": value["total"], "enabled": value["enabled"], "sourceKind": "imported"}
            for name, value in sorted(groups.items())
        ],
        "source_kind": "imported",
        "source_coverage": {"my_biz_param_option": len(raw)},
    }


def admin_dict_options(
    pool: PsqlPool,
    group_name: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if group_name is not None and len(group_name) > 128:
        raise ValueError("invalid groupName")
    raw = _raw_source_rows(pool, "my_biz_param_option", max(max_rows, 100), ADMIN_SOURCE_TABLES)
    rows = [
        row
        for row in raw
        if group_name is None or str(row["payload"].get("param_name") or "") == group_name
    ]
    rows.sort(
        key=lambda row: (
            str(row["payload"].get("param_name") or ""),
            int(row["payload"].get("display_order") or 0),
            str(row["payload"].get("param_code") or ""),
        )
    )
    return {
        "success": True,
        "code": 0,
        "data": [
            {
                "paramGuid": str(row["payload"].get("param_guid") or row["record_id"]),
                "groupName": str(row["payload"].get("param_name") or ""),
                "code": str(row["payload"].get("param_code") or ""),
                "value": str(row["payload"].get("param_value") or ""),
                "displayOrder": int(row["payload"].get("display_order") or 0),
                "enabled": bool(row["payload"].get("enabled", 0)),
                "sourceKind": "imported",
            }
            for row in rows
        ],
        "source_kind": "imported",
        "source_coverage": {"my_biz_param_option": len(raw)},
    }


def admin_audit_logs(
    pool: PsqlPool,
    action: str | None,
    user_id: str | None,
    target_type: str | None,
    limit: int,
    offset: int,
    max_rows: int,
) -> dict[str, Any]:
    if limit < 1 or limit > 500 or offset < 0:
        raise ValueError("invalid audit pagination")
    raw = _raw_source_rows(pool, "audit_log", max(max_rows, 500), ADMIN_SOURCE_TABLES)
    users = {
        str(row["payload"].get("user_id", row["record_id"])): str(
            row["payload"].get("emp_name") or row["payload"].get("user_name") or ""
        )
        for row in _raw_source_rows(pool, "sys_user", max(max_rows, 100), ADMIN_SOURCE_TABLES)
    }
    filtered = []
    for row in raw:
        payload = row["payload"]
        if action is not None and action.casefold() not in str(payload.get("action") or "").casefold():
            continue
        if user_id is not None and str(payload.get("user_id") or "") != user_id:
            continue
        if target_type is not None and str(payload.get("target_type") or "") != target_type:
            continue
        filtered.append(row)
    filtered.sort(
        key=lambda row: (
            int(row["payload"].get("log_id") or 0),
            str(row["record_id"]),
        ),
        reverse=True,
    )
    page = filtered[offset : offset + limit]
    return {
        "success": True,
        "code": 0,
        "data": {
            "rows": [
                {
                    "logId": int(row["payload"].get("log_id") or 0),
                    "userId": str(row["payload"].get("user_id") or ""),
                    "empName": users.get(str(row["payload"].get("user_id") or ""), ""),
                    "action": str(row["payload"].get("action") or ""),
                    "targetType": str(row["payload"].get("target_type") or ""),
                    "targetId": str(row["payload"].get("target_id") or ""),
                    "ip": str(row["payload"].get("ip") or ""),
                    "createdAt": str(row["payload"].get("created_at") or ""),
                    "sourceKind": "imported",
                }
                for row in page
            ],
            "total": len(filtered),
        },
        "source_kind": "imported",
        "source_coverage": {"audit_log": len(raw)},
    }


def admin_audit_actions(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    raw = _raw_source_rows(pool, "audit_log", max(max_rows, 500), ADMIN_SOURCE_TABLES)
    counts: dict[str, int] = {}
    for row in raw:
        action = str(row["payload"].get("action") or "")
        if action:
            counts[action] = counts.get(action, 0) + 1
    actions = sorted(counts.items(), key=lambda value: (-value[1], value[0]))[:30]
    return {
        "success": True,
        "code": 0,
        "data": [{"action": action, "count": count, "sourceKind": "imported"} for action, count in actions],
        "source_kind": "imported",
        "source_coverage": {"audit_log": len(raw)},
    }


def admin_health_tables(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), ADMIN_HEALTH_SOURCE_TABLES))
        for table in sorted(ADMIN_HEALTH_SOURCE_TABLES)
    }
    rows = [
        {
            "table": table,
            "rowCount": count,
            "sourceStatus": "rows_imported" if count else "no_rows_in_export",
            "sourceKind": "imported_or_empty",
        }
        for table, count in coverage.items()
    ]
    return {
        "success": True,
        "code": 0,
        "data": rows,
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [table for table, count in coverage.items() if count == 0],
    }


def admin_health_bpm_pool(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    instance_rows = _raw_source_rows(
        pool,
        "wf_process_instance",
        max(max_rows, 500),
        ADMIN_HEALTH_SOURCE_TABLES,
    )
    definition_rows = _raw_source_rows(
        pool,
        "wf_process_def",
        max(max_rows, 100),
        ADMIN_HEALTH_SOURCE_TABLES,
    )
    process_names = {
        str(row["payload"].get("process_guid", row["record_id"])): str(
            row["payload"].get("process_name") or row["payload"].get("process_key") or ""
        )
        for row in definition_rows
    }
    by_status: dict[str, int] = {}
    by_biz_type: dict[tuple[str, str], int] = {}
    recent: list[dict[str, Any]] = []
    for row in instance_rows:
        payload = row["payload"]
        status = str(payload.get("status") or "")
        biz_type = str(payload.get("biz_type") or "")
        by_status[status] = by_status.get(status, 0) + 1
        key = (biz_type, status)
        by_biz_type[key] = by_biz_type.get(key, 0) + 1
        recent.append(
            {
                "piGuid": str(payload.get("process_instance_guid", row["record_id"])),
                "processName": process_names.get(str(payload.get("process_guid") or ""), ""),
                "bizType": biz_type,
                "bizDataGuid": str(payload.get("biz_data_guid") or ""),
                "status": status,
                "currentStepOrder": payload.get("current_step_order"),
                "initiatedAt": str(payload.get("initiated_at") or ""),
                "completedAt": str(payload.get("completed_at") or ""),
                "sourceKind": "imported",
            }
        )
    recent.sort(key=lambda value: str(value.get("initiatedAt", "")), reverse=True)
    return {
        "success": True,
        "code": 0,
        "data": {
            "byStatus": [{"status": key, "count": value} for key, value in sorted(by_status.items())],
            "byBizType": [
                {"bizType": biz_type, "status": status, "count": count}
                for (biz_type, status), count in sorted(by_biz_type.items())
            ],
            "recent": recent[:20],
        },
        "source_kind": "imported_or_empty",
        "source_coverage": {
            "wf_process_def": len(definition_rows),
            "wf_process_instance": len(instance_rows),
            "wf_step_action": len(
                _raw_source_rows(pool, "wf_step_action", max(max_rows, 500), ADMIN_HEALTH_SOURCE_TABLES)
            ),
        },
        "authorizing": False,
    }


ADMIN_DIAGNOSTIC_SOURCE_TABLES = {"sys_param", "sys_user"}


def _admin_diagnostic_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
        "secret_values_redacted": True,
    }


def _admin_diagnostic_params(pool: PsqlPool, max_rows: int) -> tuple[dict[str, str], dict[str, int]]:
    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), ADMIN_DIAGNOSTIC_SOURCE_TABLES))
        for table in sorted(ADMIN_DIAGNOSTIC_SOURCE_TABLES)
    }
    params: dict[str, str] = {}
    for row in _raw_source_rows(pool, "sys_param", max(max_rows, 500), ADMIN_DIAGNOSTIC_SOURCE_TABLES):
        payload = row["payload"]
        key = str(payload.get("pk") or payload.get("key") or payload.get("param_key") or "")
        if key:
            params[key] = str(payload.get("pv") or payload.get("value") or payload.get("param_value") or "")
    return params, coverage


def _redacted_diagnostic_params(params: dict[str, str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for key, value in sorted(params.items()):
        lowered = key.lower()
        if any(marker in lowered for marker in ("key", "pass", "secret", "token", "password")):
            result[key] = "***" if value else "(空)"
        else:
            result[key] = value
    return result


def admin_health_full(pool: PsqlPool, max_rows: int, database: str | None) -> dict[str, Any]:
    """Expose the source health shape with PostgreSQL coverage and no fake runtime metrics."""

    tables = admin_health_tables(pool, max_rows)
    bpm_pool = admin_health_bpm_pool(pool, max_rows)
    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), ADMIN_HEALTH_SOURCE_TABLES))
        for table in sorted(ADMIN_HEALTH_SOURCE_TABLES)
    }
    return {
        "success": True,
        "code": 0,
        "data": {
            "uptime": {"seconds": None, "hours": None},
            "memory": {"rssMB": None, "heapUsedMB": None, "heapTotalMB": None},
            "node": {"version": None, "platform": None},
            "db": {"sizeMB": None, "name": database},
            "tables": tables["data"],
            "workflow": bpm_pool["data"],
            "runtimeMetricsAvailable": False,
        },
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def admin_llm_status(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    """Read redacted LLM configuration without invoking a provider."""

    params, coverage = _admin_diagnostic_params(pool, max_rows)
    provider = params.get("ai.llm.provider") or "mock"
    fallback = params.get("ai.llm.fallback_providers") or ""
    global_key = params.get("ai.llm.key") or ""
    return {
        "success": True,
        "code": 0,
        "data": {
            "provider": provider,
            "fallbackList": fallback,
            "globalKeyMasked": "***" if global_key else "(未配)",
            "providers": [],
            "note": "PostgreSQL migration adapter exposes redacted configuration only; provider execution remains disabled.",
        },
        **_admin_diagnostic_metadata(coverage),
    }


def admin_ai_diag(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    """Return an explicit no-provider-execution AI diagnostic."""

    params, coverage = _admin_diagnostic_params(pool, max_rows)
    provider = params.get("ai.llm.provider") or "(未配)"
    global_key = bool(params.get("ai.llm.key"))
    provider_key = bool(params.get("ai.llm.key." + provider)) if provider != "(未配)" else False
    return {
        "success": True,
        "code": 0,
        "data": {
            "provider": provider,
            "hasGlobalKey": global_key,
            "hasProviderKey": provider_key,
            "allParams": _redacted_diagnostic_params(params),
            "pingResult": None,
            "hint": "Provider execution is disabled in the PostgreSQL migration adapter; configure a reviewed managed provider before enabling it.",
        },
        **_admin_diagnostic_metadata(coverage),
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


REPORT_TEMPLATE_SOURCE_TABLES = {
    "sys_report_template",
}


REPORT_TEMPLATE_TABLE_META = [
    {
        "name": "ep_project",
        "label": "项目",
        "columns": [
            {"field": "proj_code", "label": "项目编码"},
            {"field": "proj_name", "label": "项目名称"},
            {"field": "bu_guid", "label": "公司ID"},
            {"field": "proj_status", "label": "阶段"},
            {"field": "begin_date", "label": "开始日期"},
        ],
        "filterableTypes": {
            "proj_code": "text",
            "proj_name": "text",
            "proj_status": "enum:initiation/acquisition/planning/development/sales/delivery/settlement",
            "begin_date": "date",
        },
    },
    {
        "name": "cb_contract",
        "label": "合同",
        "columns": [
            {"field": "contract_code", "label": "合同号"},
            {"field": "contract_name", "label": "合同名"},
            {"field": "yf_provider_name", "label": "乙方"},
            {"field": "ht_amount", "label": "合同金额"},
            {"field": "sum_alter_amount", "label": "累计变更"},
            {"field": "sign_date", "label": "签订日"},
            {"field": "js_state", "label": "结算状态"},
            {"field": "r_code", "label": "R 编码"},
            {"field": "l3_code", "label": "CBS 三级"},
            {"field": "cb_state", "label": "CB 状态"},
        ],
        "filterableTypes": {
            "contract_code": "text",
            "contract_name": "text",
            "yf_provider_name": "text",
            "ht_amount": "number",
            "sign_date": "date",
            "r_code": "text",
            "l3_code": "text",
            "cb_state": "enum:draft/approving/signed/paid",
        },
    },
    {
        "name": "cb_htfk_apply",
        "label": "付款申请",
        "columns": [
            {"field": "apply_code", "label": "申请号"},
            {"field": "subject", "label": "事由"},
            {"field": "apply_amount", "label": "申请金额"},
            {"field": "apply_state", "label": "申请状态"},
            {"field": "pay_state", "label": "支付状态"},
            {"field": "apply_date", "label": "申请日"},
        ],
        "filterableTypes": {
            "apply_code": "text",
            "subject": "text",
            "apply_amount": "number",
            "apply_state": "text",
            "pay_state": "text",
            "apply_date": "date",
        },
    },
    {
        "name": "vcb_expense",
        "label": "报销",
        "columns": [
            {"field": "expense_code", "label": "报销号"},
            {"field": "subject", "label": "主题"},
            {"field": "pay_amount", "label": "应付金额"},
            {"field": "apply_state", "label": "状态"},
            {"field": "apply_date", "label": "申请日"},
        ],
        "filterableTypes": {
            "expense_code": "text",
            "subject": "text",
            "pay_amount": "number",
            "apply_state": "text",
            "apply_date": "date",
        },
    },
    {
        "name": "vcb_loan_simple",
        "label": "借款",
        "columns": [
            {"field": "loan_code", "label": "借款号"},
            {"field": "subject", "label": "主题"},
            {"field": "loan_amount", "label": "借款金额"},
            {"field": "remain_amount", "label": "剩余"},
            {"field": "apply_state", "label": "状态"},
            {"field": "apply_date", "label": "申请日"},
        ],
        "filterableTypes": {
            "loan_code": "text",
            "subject": "text",
            "loan_amount": "number",
            "apply_state": "text",
            "apply_date": "date",
        },
    },
    {
        "name": "srm_provider",
        "label": "供应商",
        "columns": [
            {"field": "provider_code", "label": "编码"},
            {"field": "provider_name", "label": "供应商"},
            {"field": "short_name", "label": "简称"},
            {"field": "main_category_code", "label": "类别"},
            {"field": "eval_result", "label": "评级"},
            {"field": "contact_person", "label": "联系人"},
        ],
        "filterableTypes": {
            "provider_code": "text",
            "provider_name": "text",
            "main_category_code": "text",
            "eval_result": "text",
        },
    },
    {
        "name": "jd_task",
        "label": "任务",
        "columns": [
            {"field": "task_code", "label": "编码"},
            {"field": "task_name", "label": "任务"},
            {"field": "task_type", "label": "类型"},
            {"field": "plan_end_date", "label": "计划完成"},
            {"field": "progress_pct", "label": "进度"},
            {"field": "status", "label": "状态"},
        ],
        "filterableTypes": {
            "task_name": "text",
            "task_type": "text",
            "plan_end_date": "date",
            "status": "text",
        },
    },
    {
        "name": "sale_revenue",
        "label": "销售回款",
        "columns": [
            {"field": "revenue_code", "label": "编码"},
            {"field": "customer_name", "label": "客户"},
            {"field": "amount", "label": "金额"},
            {"field": "receive_date", "label": "到账日"},
            {"field": "status", "label": "状态"},
            {"field": "payment_type", "label": "付款类型"},
        ],
        "filterableTypes": {
            "customer_name": "text",
            "amount": "number",
            "receive_date": "date",
            "status": "text",
        },
    },
    {
        "name": "cb_subject_dict",
        "label": "CBS 字典(v3)",
        "columns": [
            {"field": "l3_code", "label": "CBS 三级"},
            {"field": "r_code", "label": "R 编码"},
            {"field": "l2_name", "label": "大类"},
            {"field": "subject", "label": "子项"},
            {"field": "plan_amount", "label": "计划金额(万)"},
            {"field": "plan_version", "label": "版本"},
            {"field": "src", "label": "来源"},
        ],
        "filterableTypes": {
            "l3_code": "text",
            "r_code": "text",
            "l2_name": "text",
            "subject": "text",
            "plan_amount": "number",
            "plan_version": "text",
            "src": "enum:seed/manual/cloned",
        },
    },
    {
        "name": "cb_change_apply",
        "label": "合同变更(v3)",
        "columns": [
            {"field": "change_code", "label": "变更号"},
            {"field": "reason", "label": "原因"},
            {"field": "change_amount", "label": "金额"},
            {"field": "state", "label": "状态"},
            {"field": "r_code", "label": "R 编码"},
            {"field": "l3_code", "label": "CBS"},
            {"field": "apply_date", "label": "申请日"},
        ],
        "filterableTypes": {
            "change_code": "text",
            "reason": "text",
            "change_amount": "number",
            "state": "enum:estimated/approving/confirmed",
            "r_code": "text",
            "l3_code": "text",
            "apply_date": "date",
        },
    },
]


REPORT_TEMPLATE_OPERATORS = ["=", "!=", ">", ">=", "<", "<=", "like", "in"]


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


def report_template_metadata() -> dict[str, Any]:
    return {
        "success": True,
        "code": 0,
        "data": {
            "tables": REPORT_TEMPLATE_TABLE_META,
            "operators": REPORT_TEMPLATE_OPERATORS,
        },
        "source_kind": "definition",
        "source_coverage": {},
        "missing_or_empty_source_tables": [],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def report_template_rows(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), REPORT_TEMPLATE_SOURCE_TABLES))
        for table in sorted(REPORT_TEMPLATE_SOURCE_TABLES)
    }
    result: list[dict[str, Any]] = []
    for source in _raw_source_rows(
        pool, "sys_report_template", max(max_rows, 500), REPORT_TEMPLATE_SOURCE_TABLES,
    ):
        payload = source["payload"]
        def json_array(key: str, alternate: str) -> list[Any]:
            value = payload.get(key, payload.get(alternate, []))
            if isinstance(value, list):
                return value
            if isinstance(value, str):
                try:
                    decoded = json.loads(value)
                except json.JSONDecodeError:
                    decoded = []
                return decoded if isinstance(decoded, list) else []
            return []

        result.append(
            {
                "templateId": _report_text(payload, "template_id", source["record_id"]),
                "templateName": _report_text(payload, "template_name"),
                "description": _report_text(payload, "description"),
                "baseTable": _report_text(payload, "base_table", ""),
                "columns": json_array("columns", "columns_json"),
                "filters": json_array("filters", "filters_json"),
                "orderBy": _report_text(payload, "order_by", "orderBy"),
                "createdBy": _report_text(payload, "created_by", "createdBy"),
                "createdAt": _report_text(payload, "created_at", "createdAt"),
                "isShared": _notification_bool(payload, "is_shared", "isShared"),
                "isMine": False,
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda row: (str(row["createdAt"]), str(row["templateId"])), reverse=True)
    return {
        "success": True,
        "code": 0,
        "data": result[:max_rows],
        **_notification_source_metadata(coverage),
    }


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


DASHBOARD_SOURCE_TABLES = {
    "cb_contract",
    "cb_cost",
    "cb_expense_split",
    "cb_htfk_apply",
    "cb_htfkplan",
    "ep_project",
    "jd_task",
    "mu_business_unit",
    "proj_lifecycle_instance",
    "proj_lifecycle_stage",
    "tzsy_plan_index",
    "tzsy_version",
    "vcb_expense",
    "wf_process_instance",
    "cb_plan_version",
    "cb_r_master",
    "cb_subject_dict",
    "fund_plan",
    "invoice_in",
    "invoice_out",
    "proj_progress",
    "sale_contract",
    "sale_customer",
    "sale_mortgage",
    "sale_refund",
    "sale_revenue",
    "sale_subscription",
    "sys_warning",
    "tender_award",
    "tender_plan",
}

COST_DASHBOARD_SOURCE_TABLES = {
    "cb_change_apply",
    "cb_contract",
    "cb_expense_split",
    "cb_plan_version",
    "cb_r_master",
    "cb_subject_dict",
    "ep_project",
    "sale_revenue",
    "vcb_expense",
}


def _dashboard_flag(value: Any) -> bool:
    return value in {True, 1, "1", "true", "True", "TRUE"}


def dynamic_cost(
    pool: PsqlPool,
    project_id: str,
    max_rows: int,
) -> dict[str, Any]:
    """Return the source ERP five-column dynamic-cost calculation."""

    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    raw_costs = _raw_source_rows(pool, "cb_cost", max(max_rows, 500), DASHBOARD_SOURCE_TABLES)
    projects = _raw_source_rows(pool, "ep_project", max(max_rows, 100), DASHBOARD_SOURCE_TABLES)
    project_name = next(
        (
            str(row["payload"].get("proj_name") or "")
            for row in projects
            if str(row["payload"].get("proj_guid") or "") == project_id
        ),
        "",
    )
    source_rows = [
        row["payload"]
        for row in raw_costs
        if str(row["payload"].get("proj_guid") or "") == project_id
        and not row["payload"].get("deleted_at")
    ]
    source_rows.sort(
        key=lambda payload: (
            str(payload.get("cost_code") or ""),
            str(payload.get("cost_guid") or ""),
        )
    )
    items: list[dict[str, Any]] = []
    for payload in source_rows:
        target = _report_float(payload, "target_cost")
        dynamic = sum(
            _report_float(payload, key)
            for key in ("ht_alter_amount", "zt_cost", "dfs_budget", "yg_alter")
        )
        items.append(
            {
                "costGuid": str(payload.get("cost_guid") or ""),
                "costCode": str(payload.get("cost_code") or ""),
                "costName": str(payload.get("cost_name") or ""),
                "costLevel": int(payload.get("cost_level") or 0),
                "parentCostGuid": str(payload.get("parent_cost_guid") or ""),
                "isEndCost": _dashboard_flag(payload.get("is_end_cost")),
                "A_targetCost": target,
                "B_dtCost": round(dynamic, 2),
                "C_deviationPct": round((target - dynamic) / target * 100, 4) if target > 0 else None,
                "D_htAlterAmount": _report_float(payload, "ht_alter_amount"),
                "E_ztCost": _report_float(payload, "zt_cost"),
                "F_dfsBudget": _report_float(payload, "dfs_budget"),
                "G_ygAlter": _report_float(payload, "yg_alter"),
                "H_layoutSpare": round(target - dynamic, 2),
                "remarks": str(payload.get("remarks") or ""),
                "projectName": project_name,
                "sourceKind": "imported",
            }
        )
    end_rows = [item for item in items if item["isEndCost"]]
    target_total = sum(float(item["A_targetCost"]) for item in end_rows)
    dynamic_total = sum(float(item["B_dtCost"]) for item in end_rows)
    return {
        "success": True,
        "code": 0,
        "data": {
            "items": items,
            "summary": {
                "A_targetCost": round(target_total, 2),
                "B_dtCost": round(dynamic_total, 2),
                "C_deviationPct": round((target_total - dynamic_total) / target_total * 100, 4)
                if target_total > 0
                else None,
                "H_layoutSpare": round(target_total - dynamic_total, 2),
                "endCount": len(end_rows),
                "projectName": project_name,
            },
        },
        "source_kind": "imported",
        "source_coverage": {"cb_cost": len(raw_costs), "ep_project": len(projects)},
    }


def dynamic_cost_remarks(
    pool: PsqlPool,
    cost_id: str,
    max_rows: int,
) -> dict[str, Any] | None:
    """Read the source dynamic-cost remark for one imported cost subject."""

    if not IDENTIFIER.fullmatch(cost_id):
        raise ValueError("invalid cost_id")
    raw_costs = _raw_source_rows(pool, "cb_cost", max(max_rows, 500), DASHBOARD_SOURCE_TABLES)
    projects = _raw_source_rows(pool, "ep_project", max(max_rows, 100), DASHBOARD_SOURCE_TABLES)
    row = next(
        (
            item["payload"]
            for item in raw_costs
            if str(item["payload"].get("cost_guid") or item["record_id"]) == cost_id
            and not item["payload"].get("deleted_at")
        ),
        None,
    )
    if row is None:
        return None
    project_id = str(row.get("proj_guid") or "")
    project_name = next(
        (
            str(item["payload"].get("proj_name") or "")
            for item in projects
            if str(item["payload"].get("proj_guid") or "") == project_id
        ),
        "",
    )
    return {
        "success": True,
        "code": 0,
        "data": {
            "costCode": str(row.get("cost_code") or ""),
            "costName": str(row.get("cost_name") or ""),
            "remarks": str(row.get("remarks") or ""),
            "projectName": project_name,
            "sourceKind": "imported",
        },
        "source_kind": "imported",
        "source_coverage": {"cb_cost": len(raw_costs), "ep_project": len(projects)},
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def cost_milestone_check(
    pool: PsqlPool,
    milestone_id: str,
    apply_amount: float,
    max_rows: int,
) -> dict[str, Any] | None:
    """Evaluate the source early-payment warnings for one milestone."""

    if not IDENTIFIER.fullmatch(milestone_id):
        raise ValueError("invalid milestone_id")
    milestones = _raw_source_rows(pool, "cb_contract_milestone", max(max_rows, 500), COST_SOURCE_TABLES)
    tasks = _raw_source_rows(pool, "jd_task", max(max_rows, 500), COST_SOURCE_TABLES)
    row = next(
        (
            item["payload"]
            for item in milestones
            if str(item["payload"].get("milestone_guid") or item["record_id"]) == milestone_id
            and not item["payload"].get("deleted_at")
        ),
        None,
    )
    if row is None:
        return None
    today = date.today()
    warnings: list[dict[str, Any]] = []
    early_flag = False
    over_pay = False
    trigger_type = str(row.get("trigger_type") or "")
    plan_date = _report_date(row.get("plan_date"))
    if trigger_type == "time" and plan_date is not None and plan_date > today:
        early_flag = True
        warnings.append(
            {
                "level": "warn",
                "code": "early_time",
                "message": f"节点计划付款日 {plan_date.isoformat()}, 比今天早 {(plan_date - today).days} 天",
            }
        )
    if trigger_type == "progress" and row.get("trigger_value"):
        task = next(
            (
                item["payload"]
                for item in tasks
                if str(item["payload"].get("task_guid") or item["record_id"]) == str(row["trigger_value"])
            ),
            None,
        )
        if task is not None and str(task.get("status") or "") != "done":
            early_flag = True
            warnings.append(
                {
                    "level": "warn",
                    "code": "early_progress",
                    "message": f"关联任务「{task.get('task_name') or ''}」状态 {task.get('status') or ''},未完成",
                }
            )
    if trigger_type == "event" and not row.get("reached_at"):
        early_flag = True
        warnings.append(
            {"level": "warn", "code": "early_event", "message": "事件未打点(reached_at 为空)"}
        )
    plan_amount = _report_float(row, "plan_amount")
    actual_amount = _report_float(row, "actual_amount")
    if plan_amount > 0 and actual_amount + apply_amount > plan_amount + 0.01:
        over_pay = True
        exceeded = actual_amount + apply_amount - plan_amount
        warnings.append(
            {
                "level": "error",
                "code": "over_pay",
                "message": f"本节点计划 {plan_amount:.2f},已付 {actual_amount:.2f},本次 {apply_amount:.2f} 累计超付 {exceeded:.2f}",
            }
        )
    coverage = _cost_source_coverage(pool, max_rows)
    return {
        "success": True,
        "code": 0,
        "data": {
            "earlyFlag": early_flag,
            "overPay": over_pay,
            "warnings": warnings,
            "milestone": {
                "nodeName": str(row.get("node_name") or ""),
                "planAmount": plan_amount,
                "actualAmount": actual_amount,
                "state": str(row.get("state") or ""),
            },
        },
        **_cost_source_metadata(coverage),
    }


def cost_dashboard_v3(
    pool: PsqlPool,
    project_id: str,
    plan_version: str | None,
    max_rows: int,
) -> dict[str, Any] | None:
    """Return the source ``profit-actual-v2`` CBS hierarchy for cost v3.

    The source route is read-only but normally returns 404 when the selected
    project has no CBS dictionary.  The PostgreSQL adapter keeps a successful
    empty envelope instead, preserving source coverage so Rabbita can render
    the absence without inventing a hierarchy.
    """

    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    if plan_version is not None and not IDENTIFIER.fullmatch(plan_version):
        raise ValueError("invalid plan_version")
    rows = {
        table: _raw_source_rows(pool, table, max(max_rows, 500), COST_DASHBOARD_SOURCE_TABLES)
        for table in sorted(COST_DASHBOARD_SOURCE_TABLES)
    }
    coverage = {table: len(values) for table, values in rows.items()}
    project = next(
        (
            row["payload"]
            for row in rows["ep_project"]
            if str(row["payload"].get("proj_guid") or row["record_id"]) == project_id
            and not row["payload"].get("deleted_at")
        ),
        None,
    )
    if project is None:
        return None
    active_version = next(
        (
            row["payload"]
            for row in rows["cb_plan_version"]
            if not row["payload"].get("deleted_at")
            and str(row["payload"].get("proj_guid") or "") == project_id
            and _dashboard_flag(row["payload"].get("is_active"))
        ),
        None,
    )
    selected_version = plan_version or str((active_version or {}).get("plan_version") or "baseline")
    dict_rows = [
        row["payload"]
        for row in rows["cb_subject_dict"]
        if not row["payload"].get("deleted_at")
        and str(row["payload"].get("proj_guid") or "") == project_id
        and _report_text(row["payload"], "plan_version", "baseline") == selected_version
    ]
    dict_rows.sort(key=lambda payload: str(payload.get("l3_code") or ""))
    contracts = [
        row["payload"]
        for row in rows["cb_contract"]
        if not row["payload"].get("deleted_at")
        and str(row["payload"].get("proj_guid") or "") == project_id
        and _report_text(row["payload"], "r_code")
    ]
    expenses = [
        row["payload"]
        for row in rows["vcb_expense"]
        if not row["payload"].get("deleted_at")
    ]
    splits = [row["payload"] for row in rows["cb_expense_split"]]
    changes = [
        row["payload"]
        for row in rows["cb_change_apply"]
        if not row["payload"].get("deleted_at")
        and str(row["payload"].get("proj_guid") or "") == project_id
    ]

    expense_by_id = {
        str(payload.get("expense_guid") or ""): payload
        for payload in expenses
        if payload.get("expense_guid")
    }

    def leaf_compute(l3_code: str, plan_amount: Any) -> dict[str, float]:
        a = _report_float({"value": plan_amount}, "value")
        d, e, g = 0.0, 0.0, 0.0
        for payload in contracts:
            if _report_text(payload, "l3_code") != l3_code:
                continue
            amount = (
                _report_float(payload, "ht_amount")
                + _report_float(payload, "sum_alter_amount")
            ) / 10000
            if _report_text(payload, "cb_state") in {"signed", "paid"}:
                d += amount
            elif _report_text(payload, "cb_state") == "approving":
                e += amount
        for payload in splits:
            if _report_text(payload, "l3_code") != l3_code:
                continue
            expense = expense_by_id.get(_report_text(payload, "expense_guid"), {})
            amount = _report_float(payload, "amount") / 10000
            if _report_text(expense, "apply_state") in {"approved", "Approved"}:
                d += amount
            elif _report_text(expense, "apply_state") in {"approving", "Approving"}:
                e += amount
        for payload in changes:
            if _report_text(payload, "l3_code") != l3_code:
                continue
            amount = _report_float(payload, "change_amount") / 10000
            if _report_text(payload, "state") == "confirmed":
                d += amount
            elif _report_text(payload, "state") in {"estimated", "approving"}:
                g += amount
        f = max(0.0, a - d - e)
        b = d + e + f + g
        return {
            "A": round(a, 2),
            "D": round(d, 2),
            "E": round(e, 2),
            "F": round(f, 2),
            "G": round(g, 2),
            "B": round(b, 2),
            "H": round(a - b, 2),
        }

    r_names = {
        _report_text(row["payload"], "r_code"): _report_text(row["payload"], "r_name")
        for row in rows["cb_r_master"]
        if not row["payload"].get("deleted_at")
    }
    grouped: dict[str, dict[str, Any]] = {}
    for payload in dict_rows:
        r_code = _report_text(payload, "r_code")
        l2_code = _report_text(payload, "l2_code")
        r_group = grouped.setdefault(
            r_code,
            {"rCode": r_code, "rName": r_names.get(r_code, r_code), "groups": {}},
        )
        l2_group = r_group["groups"].setdefault(
            l2_code,
            {"l2Code": l2_code, "l2Name": _report_text(payload, "l2_name"), "leaves": []},
        )
        l2_group["leaves"].append(
            {
                "l3Code": _report_text(payload, "l3_code"),
                "subject": _report_text(payload, "subject"),
                **leaf_compute(_report_text(payload, "l3_code"), payload.get("plan_amount")),
            }
        )

    output_rows: list[dict[str, Any]] = []
    for r_group in grouped.values():
        totals = {key: 0.0 for key in ("A", "D", "E", "F", "G", "B", "H")}
        groups_out: list[dict[str, Any]] = []
        for l2_group in r_group["groups"].values():
            group_totals = {key: 0.0 for key in totals}
            for leaf in l2_group["leaves"]:
                for key in group_totals:
                    group_totals[key] += leaf[key]
            group_totals = {key: round(value, 2) for key, value in group_totals.items()}
            groups_out.append({**l2_group, **group_totals})
            for key in totals:
                totals[key] += group_totals[key]
        totals = {key: round(value, 2) for key, value in totals.items()}
        output_rows.append({**r_group, **totals, "groups": groups_out})

    revenue_total = sum(
        _report_float(payload, "amount")
        for payload in (
            row["payload"]
            for row in rows["sale_revenue"]
            if not row["payload"].get("deleted_at")
            and str(row["payload"].get("proj_guid") or "") == project_id
            and _report_text(row["payload"], "status") == "received"
        )
    ) / 10000
    if output_rows or revenue_total:
        output_rows.insert(
            0,
            {
                "rCode": "R6",
                "rName": r_names.get("R6", "回款额"),
                "A": 0,
                "D": round(revenue_total, 2),
                "E": 0,
                "F": 0,
                "G": 0,
                "B": round(revenue_total, 2),
                "H": 0,
                "groups": [],
            },
        )
    r0_total = sum(
        (
            _report_float(payload, "ht_amount")
            + _report_float(payload, "sum_alter_amount")
        ) / 10000
        for payload in contracts
        if _report_text(payload, "r_code") in {"", "R0"}
    )
    if r0_total:
        output_rows.append(
            {
                "rCode": "R0",
                "rName": "未归类(R0 兜底)",
                "A": 0,
                "D": round(r0_total, 2),
                "E": 0,
                "F": 0,
                "G": 0,
                "B": round(r0_total, 2),
                "H": round(-r0_total, 2),
                "groups": [],
            }
        )
    summary_rows = [row for row in output_rows if row["rCode"] not in {"R6", "R0"}]
    target_total = round(sum(float(row["A"]) for row in summary_rows), 2)
    dynamic_total = round(sum(float(row["B"]) for row in summary_rows), 2)
    return {
        "success": True,
        "code": 0,
        "data": {
            "projGuid": project_id,
            "projName": _report_text(project, "proj_name", project_id),
            "planVersion": selected_version,
            "asOf": date.today().isoformat(),
            "rows": output_rows,
            "summary": {
                "targetCost": target_total,
                "dynamicCost": dynamic_total,
                "deviationPct": round((target_total - dynamic_total) / target_total * 100, 4)
                if target_total > 0
                else None,
            },
            "counts": {
                "leaves": len(dict_rows),
                "contracts": len(contracts),
                "expenses": len(splits),
                "changes": len(changes),
            },
        },
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [table for table, count in coverage.items() if count == 0],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _dashboard_context(
    pool: PsqlPool,
    max_rows: int,
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, int], list[str]]:
    table_literals = ", ".join(
        sql_literal("legacy/raw/" + table) for table in sorted(DASHBOARD_SOURCE_TABLES)
    )
    query = f"""
    SELECT split_part(record_type, '/', 3),
           encode(convert_to(record_id, 'UTF8'), 'hex'),
           encode(convert_to(source_id, 'UTF8'), 'hex'),
           encode(convert_to(payload::text, 'UTF8'), 'hex')
    FROM (
      SELECT record_type, record_id, source_id, payload,
             row_number() OVER (PARTITION BY record_type ORDER BY record_id) AS row_number
      FROM company_record
      WHERE record_type IN ({table_literals})
    ) limited
    WHERE row_number <= {max_rows}
    ORDER BY record_type, record_id
    """
    rows = {table: [] for table in DASHBOARD_SOURCE_TABLES}
    for line in query_lines(pool, query):
        fields = line.split("|")
        if len(fields) != 4 or fields[0] not in DASHBOARD_SOURCE_TABLES:
            raise ServiceError("unexpected dashboard source row shape")
        try:
            payload = json.loads(decode_hex(fields[3]))
        except json.JSONDecodeError as error:
            raise ServiceError("invalid dashboard source row JSON") from error
        if not isinstance(payload, dict):
            raise ServiceError("dashboard source row payload is not an object")
        rows[fields[0]].append(
            {
                "record_id": decode_hex(fields[1]),
                "source_id": decode_hex(fields[2]),
                "payload": payload,
            }
        )
    coverage = {table: len(values) for table, values in rows.items()}
    missing = [table for table, count in coverage.items() if count == 0]
    return rows, coverage, missing


def _dashboard_envelope(
    data: Any,
    coverage: dict[str, int],
    missing: list[str],
) -> dict[str, Any]:
    return {
        "success": True,
        "code": 0,
        "data": data,
        "source_kind": "imported",
        "source_coverage": coverage,
        "missing_source_tables": missing,
    }


def dashboard_group_overview(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    rows, coverage, missing = _dashboard_context(pool, max_rows)
    units = [row["payload"] for row in rows["mu_business_unit"]]
    projects = [
        row["payload"]
        for row in rows["ep_project"]
        if not row["payload"].get("deleted_at")
    ]
    instances = [row["payload"] for row in rows["proj_lifecycle_instance"]]
    contracts = [row["payload"] for row in rows["cb_contract"]]
    applications = [row["payload"] for row in rows["cb_htfk_apply"]]
    costs = [
        row["payload"]
        for row in rows["cb_cost"]
        if _dashboard_flag(row["payload"].get("is_end_cost"))
    ]
    today = date.today()
    running_projects = {
        str(payload.get("proj_guid"))
        for payload in instances
        if str(payload.get("status") or "") == "in_progress" and payload.get("proj_guid")
    }
    total_contract_amount = sum(
        _report_float(payload, "ht_amount") + _report_float(payload, "sum_alter_amount")
        for payload in contracts
    )
    paid_amount = sum(
        _report_float(payload, "apply_amount")
        for payload in applications
        if str(payload.get("pay_state") or "") in {"完全支付", "部分支付"}
    )
    target_total = sum(_report_float(payload, "target_cost") for payload in costs)
    dynamic_total = sum(
        _report_float(payload, "ht_alter_amount")
        + _report_float(payload, "zt_cost")
        + _report_float(payload, "dfs_budget")
        + _report_float(payload, "yg_alter")
        for payload in costs
    )
    overdue_approvals = 0
    for row in rows["wf_process_instance"]:
        payload = row["payload"]
        initiated = _report_date(payload.get("initiated_at"))
        if str(payload.get("status") or "") == "Running" and initiated is not None:
            if (today - initiated).days > 7:
                overdue_approvals += 1
    overdue_tasks = 0
    for row in rows["jd_task"]:
        payload = row["payload"]
        planned_end = _report_date(payload.get("plan_end_date"))
        if str(payload.get("status") or "") == "overdue" or (
            str(payload.get("status") or "") != "done"
            and planned_end is not None
            and planned_end < today
        ):
            overdue_tasks += 1
    paid_ratio = paid_amount / total_contract_amount * 100 if total_contract_amount > 0 else 0
    deviation_pct = (target_total - dynamic_total) / target_total * 100 if target_total > 0 else 0
    return _dashboard_envelope(
        {
            "companyCount": sum(1 for payload in units if payload.get("bu_type") == "company"),
            "projectCount": len(projects),
            "inProgressCount": len(running_projects),
            "contractCount": len(contracts),
            "totalContractAmount": total_contract_amount,
            "paidAmount": paid_amount,
            "paidRatio": round(paid_ratio, 2),
            "cost": {
                "target": target_total,
                "dynamic": dynamic_total,
                "deviationPct": round(deviation_pct, 2),
            },
            "anomalies": {
                "overdueApprovals": overdue_approvals,
                "overdueTasks": overdue_tasks,
            },
        },
        coverage,
        missing,
    )


def dashboard_group_funnel(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    rows, coverage, missing = _dashboard_context(pool, max_rows)
    stages = sorted(
        (row["payload"] for row in rows["proj_lifecycle_stage"]),
        key=lambda payload: (_report_float(payload, "stage_order"), str(payload.get("stage_code") or "")),
    )
    grouped: dict[str, set[str]] = {}
    for row in rows["proj_lifecycle_instance"]:
        payload = row["payload"]
        if str(payload.get("status") or "") not in {"in_progress", "done"}:
            continue
        project_id = str(payload.get("proj_guid") or "")
        stage_code = str(payload.get("stage_code") or "")
        if project_id and stage_code:
            grouped.setdefault(stage_code, set()).add(project_id)
    max_count = max((len(values) for values in grouped.values()), default=0)
    data = [
        {
            "stageCode": str(payload.get("stage_code") or ""),
            "stageName": str(payload.get("stage_name") or payload.get("stage_code") or ""),
            "count": len(grouped.get(str(payload.get("stage_code") or ""), set())),
            "widthPct": (
                f"{round(len(grouped.get(str(payload.get("stage_code") or ""), set())) / max_count * 100)}%"
                if max_count > 0
                else "0%"
            ),
        }
        for payload in stages
    ]
    return _dashboard_envelope(data, coverage, missing)


def dashboard_group_top_anomalies(
    pool: PsqlPool,
    limit: int,
    max_rows: int,
) -> dict[str, Any]:
    if limit < 1 or limit > 30:
        raise ValueError("limit must be between 1 and 30")
    rows, coverage, missing = _dashboard_context(pool, max_rows)
    units = {
        str(row["payload"].get("bu_guid") or row["record_id"]): row["payload"]
        for row in rows["mu_business_unit"]
    }
    projects = [row["payload"] for row in rows["ep_project"] if not row["payload"].get("deleted_at")]
    costs_by_project: dict[str, list[dict[str, Any]]] = {}
    for row in rows["cb_cost"]:
        payload = row["payload"]
        if _dashboard_flag(payload.get("is_end_cost")):
            costs_by_project.setdefault(str(payload.get("proj_guid") or ""), []).append(payload)
    tasks_by_project: dict[str, list[dict[str, Any]]] = {}
    for row in rows["jd_task"]:
        payload = row["payload"]
        tasks_by_project.setdefault(str(payload.get("proj_guid") or ""), []).append(payload)
    today = date.today()
    ranked: list[dict[str, Any]] = []
    for project in projects:
        project_id = str(project.get("proj_guid") or "")
        project_costs = costs_by_project.get(project_id, [])
        target = sum(_report_float(payload, "target_cost") for payload in project_costs)
        dynamic = sum(
            _report_float(payload, "ht_alter_amount")
            + _report_float(payload, "zt_cost")
            + _report_float(payload, "dfs_budget")
            + _report_float(payload, "yg_alter")
            for payload in project_costs
        )
        project_tasks = tasks_by_project.get(project_id, [])
        overdue_tasks = sum(
            1
            for payload in project_tasks
            if str(payload.get("status") or "") == "overdue"
            or (
                str(payload.get("status") or "") != "done"
                and (_report_date(payload.get("plan_end_date")) or date.max) < today
            )
        )
        in_progress_nodes = sum(
            1
            for payload in project_tasks
            if str(payload.get("task_type") or "") == "key_node"
            and str(payload.get("status") or "") == "in_progress"
        )
        deviation = (target - dynamic) / target * 100 if target > 0 else 0
        risk_score = (abs(deviation) * 10 if deviation < 0 else 0) + overdue_tasks * 20
        reasons: list[str] = []
        if deviation < 0:
            reasons.append(f"成本超目标 {abs(deviation):.2f}%")
        if overdue_tasks > 0:
            reasons.append(f"{overdue_tasks} 个任务延期")
        ranked.append(
            {
                "projGuid": project_id,
                "projCode": str(project.get("proj_code") or project_id),
                "projName": str(project.get("proj_name") or project_id),
                "buName": str(units.get(str(project.get("bu_guid") or ""), {}).get("bu_name") or ""),
                "projStatus": str(project.get("proj_status") or ""),
                "targetCost": target,
                "dynamicCost": dynamic,
                "deviationPct": round(deviation, 2),
                "overdueTasks": overdue_tasks,
                "inProgressNodes": in_progress_nodes,
                "riskScore": round(risk_score),
                "reason": " / ".join(reasons) if reasons else "正常",
            }
        )
    ranked.sort(key=lambda value: (-float(value["riskScore"]), str(value["projGuid"])))
    return _dashboard_envelope(ranked[:limit], coverage, missing)


def dashboard_v2_group(
    pool: PsqlPool,
    business_unit_id: str | None,
    project_id: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Translate the source cockpit v2 read using bounded imported rows."""

    if business_unit_id is not None and not IDENTIFIER.fullmatch(business_unit_id):
        raise ValueError("invalid buGuid")
    if project_id is not None and not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid projGuid")
    rows, coverage, missing = _dashboard_context(pool, max_rows)
    projects = [
        row["payload"]
        for row in rows["ep_project"]
        if not row["payload"].get("deleted_at")
        and (project_id is None or str(row["payload"].get("proj_guid") or "") == project_id)
        and (business_unit_id is None or str(row["payload"].get("bu_guid") or "") == business_unit_id)
    ]
    project_ids = {str(project.get("proj_guid") or "") for project in projects}
    contract_rows = [
        row["payload"]
        for row in rows["cb_contract"]
        if (project_id is None or str(row["payload"].get("proj_guid") or "") in project_ids)
        and (business_unit_id is None or str(row["payload"].get("bu_guid") or "") == business_unit_id)
    ]
    contract_ids = {str(row.get("contract_guid") or "") for row in contract_rows}
    application_rows = [
        row["payload"]
        for row in rows["cb_htfk_apply"]
        if (project_id is None or str(row["payload"].get("proj_guid") or "") in project_ids)
        and (business_unit_id is None or str(row["payload"].get("bu_guid") or "") == business_unit_id)
    ]
    plan_rows = [
        row["payload"]
        for row in rows["cb_htfkplan"]
        if str(row["payload"].get("contract_guid") or "") in contract_ids
    ]
    warnings = [
        row["payload"]
        for row in rows["sys_warning"]
        if str(row["payload"].get("status") or "") == "open"
        and (project_id is None or str(row["payload"].get("proj_guid") or "") == project_id)
        and (business_unit_id is None or str(row["payload"].get("bu_guid") or "") == business_unit_id)
    ]
    processes = [
        row["payload"]
        for row in rows["wf_process_instance"]
        if str(row["payload"].get("status") or "") == "Running"
        and (business_unit_id is None or str(row["payload"].get("bu_guid") or "") == business_unit_id)
    ]
    month_series: list[str] = []
    today = date.today()
    for offset in range(-6, 4):
        month = today.month - 1 + offset
        year = today.year + month // 12
        month = month % 12 + 1
        month_series.append(f"{year:04d}-{month:02d}")
    plan_by_month: dict[str, float] = {}
    actual_by_month: dict[str, float] = {}
    for payload in plan_rows:
        month = str(payload.get("jhfk_date") or "")[:7]
        if month:
            plan_by_month[month] = plan_by_month.get(month, 0.0) + _report_float(payload, "jhfk_amount")
    for payload in application_rows:
        if str(payload.get("apply_state") or "") != "已审核":
            continue
        month = str(payload.get("apply_date") or "")[:7]
        if month:
            actual_by_month[month] = actual_by_month.get(month, 0.0) + _report_float(payload, "apply_amount")
    stage_distribution: dict[str, int] = {}
    for project in projects:
        stage = str(project.get("proj_status") or "unknown")
        stage_distribution[stage] = stage_distribution.get(stage, 0) + 1
    warning_rows = [
        {
            "warningGuid": str(payload.get("warning_guid") or ""),
            "ruleCode": str(payload.get("rule_code") or ""),
            "ruleName": str(payload.get("rule_name") or ""),
            "severity": str(payload.get("severity") or ""),
            "bizType": str(payload.get("biz_type") or ""),
            "bizDataGuid": str(payload.get("biz_data_guid") or ""),
            "title": str(payload.get("title") or ""),
            "firstDetectedAt": str(payload.get("first_detected_at") or ""),
        }
        for payload in warnings
    ]
    warning_rows.sort(
        key=lambda value: (
            {"error": 0, "warning": 1}.get(value["severity"], 2),
            value["firstDetectedAt"],
        )
    )
    target_contracts = [
        payload for payload in contract_rows
        if str(payload.get("js_state") or "") != "已结算"
    ]
    unpaid = [
        payload for payload in application_rows
        if str(payload.get("pay_state") or "") == "未支付"
        and str(payload.get("apply_state") or "") == "已审核"
    ]
    data = {
        "scope": {"buGuid": business_unit_id, "projGuid": project_id},
        "kpi": {
            "projectCount": len(projects),
            "inProgressProjects": sum(
                1 for project in projects
                if str(project.get("proj_status") or "") in {"planning", "development", "sales"}
            ),
            "contractInProgressAmount": sum(
                _report_float(payload, "ht_amount") + _report_float(payload, "sum_alter_amount")
                for payload in target_contracts
            ),
            "unpaidAmount": sum(_report_float(payload, "apply_amount") for payload in unpaid),
            "openWarnings": len(warnings),
            "runningProcesses": len(processes),
        },
        "paymentTrend": [
            {"ym": month, "plan": plan_by_month.get(month, 0.0), "actual": actual_by_month.get(month, 0.0)}
            for month in month_series
        ],
        "stageDistribution": [
            {"stage": stage, "count": count}
            for stage, count in sorted(stage_distribution.items())
        ],
        "latestWarnings": warning_rows[:5],
    }
    return {
        "success": True,
        "code": 0,
        "data": data,
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": missing,
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def dashboard_v3_group(
    pool: PsqlPool,
    business_unit_id: str | None,
    project_id: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Translate the source cockpit v3 aggregate without synthetic rows.

    The source handler is intentionally broad and tolerant of missing tables.
    This adapter keeps that response shape for the rows available in the
    PostgreSQL raw envelope, applies the same project/business-unit scope, and
    exposes missing-table coverage so an empty section is distinguishable from
    a measured zero.  It never writes, authorizes, or calls a provider.
    """

    if business_unit_id is not None and not IDENTIFIER.fullmatch(business_unit_id):
        raise ValueError("invalid buGuid")
    if project_id is not None and not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid projGuid")

    rows, coverage, missing = _dashboard_context(pool, max(max_rows, 500))

    def active(payload: dict[str, Any]) -> bool:
        return not payload.get("deleted_at")

    all_projects = [
        row["payload"]
        for row in rows["ep_project"]
        if active(row["payload"])
    ]
    projects = [
        payload
        for payload in all_projects
        if (project_id is None or str(payload.get("proj_guid") or "") == project_id)
        and (
            business_unit_id is None
            or str(payload.get("bu_guid") or "") == business_unit_id
        )
    ]
    project_ids = {str(payload.get("proj_guid") or "") for payload in projects}

    def scoped(payload: dict[str, Any]) -> bool:
        payload_project = str(payload.get("proj_guid") or "")
        payload_bu = str(payload.get("bu_guid") or "")
        if project_id is not None and payload_project != project_id:
            return False
        if business_unit_id is not None and payload_bu != business_unit_id:
            return False
        return True

    def amount(payload: dict[str, Any], key: str) -> float:
        return _report_float(payload, key)

    def wan(value: float) -> float:
        return round(value / 10000, 2)

    contracts = [
        payload
        for payload in (row["payload"] for row in rows["cb_contract"])
        if active(payload) and scoped(payload)
    ]
    applications = [
        payload
        for payload in (row["payload"] for row in rows["cb_htfk_apply"])
        if active(payload) and scoped(payload)
    ]
    contract_by_id = {
        str(payload.get("contract_guid") or ""): payload
        for payload in contracts
        if payload.get("contract_guid")
    }

    sale_contracts = [
        payload
        for payload in (row["payload"] for row in rows["sale_contract"])
        if active(payload) and scoped(payload)
    ]
    sale_contract_ids = {
        str(payload.get("scontract_guid") or payload.get("contract_guid") or "")
        for payload in sale_contracts
    }
    sale_mortgages = [
        payload
        for payload in (row["payload"] for row in rows["sale_mortgage"])
        if active(payload)
        and (
            not (project_id or business_unit_id)
            or str(payload.get("scontract_guid") or "") in sale_contract_ids
        )
    ]
    sale_refunds = [
        payload
        for payload in (row["payload"] for row in rows["sale_refund"])
        if active(payload)
        and (
            not (project_id or business_unit_id)
            or str(payload.get("scontract_guid") or "") in sale_contract_ids
        )
    ]
    sales = {
        "customers": [
            payload
            for payload in (row["payload"] for row in rows["sale_customer"])
            if active(payload) and scoped(payload)
        ],
        "subscriptions": [
            payload
            for payload in (row["payload"] for row in rows["sale_subscription"])
            if active(payload) and scoped(payload)
        ],
        "contracts": sale_contracts,
        "mortgages": sale_mortgages,
        "refunds": sale_refunds,
        "revenues": [
            payload
            for payload in (row["payload"] for row in rows["sale_revenue"])
            if active(payload) and scoped(payload)
        ],
    }

    revenue_received = sum(
        amount(payload, "amount")
        for payload in sales["revenues"]
        if str(payload.get("status") or "") == "received"
    )
    revenue_expected = sum(
        amount(payload, "amount")
        for payload in sales["revenues"]
        if str(payload.get("status") or "") == "expected"
    )
    signed_contracts = [
        payload
        for payload in contracts
        if str(payload.get("cb_state") or "") in {"signed", "paid"}
    ]
    approving_contracts = [
        payload
        for payload in contracts
        if str(payload.get("cb_state") or "") == "approving"
    ]
    unpaid_applications = [
        payload
        for payload in applications
        if str(payload.get("apply_state") or "") == "已审核"
        and str(payload.get("pay_state") or "") == "未支付"
    ]
    r0_contracts = [
        payload
        for payload in contracts
        if str(payload.get("r_code") or "") in {"", "R0"}
    ]

    fund_plans = [
        payload
        for payload in (row["payload"] for row in rows["fund_plan"])
        if active(payload) and scoped(payload)
    ]
    progress_rows = [
        payload
        for payload in (row["payload"] for row in rows["proj_progress"])
        if active(payload) and scoped(payload)
    ]
    invoice_in = [
        payload
        for payload in (row["payload"] for row in rows["invoice_in"])
        if active(payload) and scoped(payload)
    ]
    invoice_out = [
        payload
        for payload in (row["payload"] for row in rows["invoice_out"])
        if active(payload) and scoped(payload)
    ]
    tender_plans = [
        payload
        for payload in (row["payload"] for row in rows["tender_plan"])
        if active(payload) and scoped(payload)
    ]
    tender_ids = {
        str(payload.get("tender_guid") or "")
        for payload in tender_plans
        if payload.get("tender_guid")
    }
    tender_awards = [
        payload
        for payload in (row["payload"] for row in rows["tender_award"])
        if active(payload)
        and (
            not (project_id or business_unit_id)
            or str(payload.get("tender_guid") or "") in tender_ids
        )
    ]
    warnings = [
        payload
        for payload in (row["payload"] for row in rows["sys_warning"])
        if active(payload)
        and str(payload.get("status") or "") == "open"
        and scoped(payload)
    ]
    processes = [
        payload
        for payload in (row["payload"] for row in rows["wf_process_instance"])
        if active(payload)
        and str(payload.get("status") or "") == "Running"
        and (
            not (project_id or business_unit_id)
            or scoped(payload)
            or str(payload.get("proj_guid") or "") in project_ids
        )
    ]

    subject_dict = [
        payload
        for payload in (row["payload"] for row in rows["cb_subject_dict"])
        if active(payload) and scoped(payload)
    ]
    active_versions = {
        (
            str(payload.get("proj_guid") or ""),
            str(payload.get("plan_version") or ""),
        )
        for payload in (
            row["payload"] for row in rows["cb_plan_version"]
        )
        if active(payload) and _dashboard_flag(payload.get("is_active"))
    }
    subject_dict = [
        payload
        for payload in subject_dict
        if (
            str(payload.get("proj_guid") or ""),
            str(payload.get("plan_version") or ""),
        ) in active_versions
    ]
    dict_plan_sum = sum(amount(payload, "plan_amount") for payload in subject_dict)

    paid_contract_expense = sum(
        amount(payload, "apply_amount")
        for payload in applications
        if str(payload.get("pay_state") or "") in {"完全支付", "部分支付"}
    )
    expenses = [
        payload
        for payload in (row["payload"] for row in rows["vcb_expense"])
        if active(payload) and scoped(payload)
    ]
    paid_expense = sum(
        amount(payload, "pay_amount")
        for payload in expenses
        if str(payload.get("pay_state") or "") in {"完全支付", "部分支付"}
    )
    total_revenue = wan(revenue_received)
    total_expense = wan(paid_contract_expense + paid_expense)
    net_profit = round(total_revenue - total_expense, 2)
    net_profit_rate = round(net_profit / total_revenue * 100, 2) if total_revenue > 0 else 0

    r6_plan = wan(revenue_expected)
    available_cash = max(
        0.0,
        sum(amount(payload, "actual_amount") for payload in fund_plans if str(payload.get("direction") or "") == "in")
        / 10000
        - total_expense
        + r6_plan * 0.3,
    )
    avg_monthly_out = max(1.0, total_expense / 6)
    cashflow_months = round(available_cash / avg_monthly_out, 1)

    expense_splits = [
        row["payload"]
        for row in rows["cb_expense_split"]
        if active(row["payload"])
    ]
    expense_by_category_map: dict[str, float] = {}
    for payload in applications:
        if str(payload.get("pay_state") or "") not in {"完全支付", "部分支付"}:
            continue
        contract = contract_by_id.get(str(payload.get("contract_guid") or ""), {})
        code = str(contract.get("r_code") or "R0")
        expense_by_category_map[code] = expense_by_category_map.get(code, 0.0) + wan(
            amount(payload, "apply_amount")
        )
    expense_by_id = {
        str(payload.get("expense_guid") or ""): payload
        for payload in expenses
        if payload.get("expense_guid")
    }
    for split in expense_splits:
        expense = expense_by_id.get(str(split.get("expense_guid") or ""))
        if expense is None or str(expense.get("pay_state") or "") not in {"完全支付", "部分支付"}:
            continue
        code = str(split.get("r_code") or "R0")
        expense_by_category_map[code] = expense_by_category_map.get(code, 0.0) + wan(
            amount(split, "amount")
        )
    r_names = {
        str(payload.get("r_code") or ""): str(payload.get("r_name") or "")
        for payload in (
            row["payload"] for row in rows["cb_r_master"]
        )
        if active(payload)
    }
    expense_by_category = [
        {
            "rCode": code,
            "rName": r_names.get(code, code),
            "amount": round(value, 2),
        }
        for code, value in expense_by_category_map.items()
        if value > 0
    ]
    expense_by_category.sort(key=lambda value: (-value["amount"], value["rCode"]))

    units = [
        row["payload"]
        for row in rows["mu_business_unit"]
        if active(row["payload"]) and row["payload"].get("bu_type") == "company"
    ]
    expense_by_city: list[dict[str, Any]] = []
    if business_unit_id is None and project_id is None:
        for unit in units:
            unit_id = str(unit.get("bu_guid") or "")
            unit_contracts = [
                payload
                for payload in (row["payload"] for row in rows["cb_htfk_apply"])
                if active(payload) and str(payload.get("bu_guid") or "") == unit_id
                and str(payload.get("pay_state") or "") in {"完全支付", "部分支付"}
            ]
            unit_revenue = [
                payload
                for payload in sales["revenues"]
                if str(payload.get("bu_guid") or "") == unit_id
                and str(payload.get("status") or "") == "received"
            ]
            expense_by_city.append(
                {
                    "buGuid": unit_id,
                    "name": str(unit.get("bu_name") or unit_id),
                    "expense": wan(sum(amount(payload, "apply_amount") for payload in unit_contracts)),
                    "revenue": wan(sum(amount(payload, "amount") for payload in unit_revenue)),
                }
            )
        expense_by_city.sort(key=lambda value: (-value["expense"], value["buGuid"]))

    health_weights = {"profit": 40, "recover": 25, "budget": 20, "warning": 15}
    expected_revenue = r6_plan + total_revenue
    profit_target = expected_revenue * 0.25
    profit_score = min(100, net_profit / profit_target * 100) if profit_target > 0 else 50
    recover_score = (
        min(100, total_revenue / (total_revenue + r6_plan) * 100)
        if total_revenue + r6_plan > 0
        else 0
    )
    dict_sum_wan = dict_plan_sum / 10000
    signed_wan = sum(wan(amount(payload, "ht_amount") + amount(payload, "sum_alter_amount")) for payload in signed_contracts)
    approving_wan = sum(wan(amount(payload, "ht_amount") + amount(payload, "sum_alter_amount")) for payload in approving_contracts)
    budget_rate = min(2, (signed_wan + approving_wan) / dict_sum_wan) if dict_sum_wan > 0 else 0
    budget_score = 100 if budget_rate <= 0.9 else max(0, 100 - (budget_rate - 0.9) * 200)
    warning_score = max(0, 100 - len(warnings) * 10)
    health_score = round(
        health_weights["profit"] * profit_score / 100
        + health_weights["recover"] * recover_score / 100
        + health_weights["budget"] * budget_score / 100
        + health_weights["warning"] * warning_score / 100
    )
    health_breakdown = {
        "profit": {"score": round(profit_score), "weight": 40, "label": "利润达成率"},
        "recover": {"score": round(recover_score), "weight": 25, "label": "回款率"},
        "budget": {"score": round(budget_score), "weight": 20, "label": "预算执行"},
        "warning": {"score": round(warning_score), "weight": 15, "label": "风险告警"},
    }

    progress_active = [
        payload for payload in progress_rows
        if str(payload.get("state") or "") in {"pending", "in_progress"}
    ]
    progress_done = [
        payload for payload in progress_rows
        if str(payload.get("state") or "") == "completed"
    ]
    progress_average = (
        sum(amount(payload, "actual_pct") for payload in progress_active) / len(progress_active)
        if progress_active else 0
    )
    tender_active = [
        payload for payload in tender_plans
        if str(payload.get("state") or "") in {"planning", "publishing", "bidding"}
    ]
    signed_sales = [
        payload for payload in sale_contracts
        if str(payload.get("state") or "") == "signed"
    ]
    released_mortgages = [
        payload for payload in sale_mortgages
        if str(payload.get("state") or "") == "released"
    ]
    approved_refunds = [
        payload for payload in sale_refunds
        if str(payload.get("state") or "") == "approved"
    ]

    def compact_contract(payload: dict[str, Any]) -> dict[str, Any]:
        return {
            "contractCode": str(payload.get("contract_code") or ""),
            "contractName": str(payload.get("contract_name") or ""),
            "htAmount": amount(payload, "ht_amount"),
            "contractGuid": str(payload.get("contract_guid") or ""),
        }

    top_unpaid = [compact_contract(payload) for payload in signed_contracts]
    top_unpaid.sort(key=lambda value: (-float(value["htAmount"]), value["contractGuid"]))
    top_r0 = [compact_contract(payload) for payload in r0_contracts]
    top_r0.sort(key=lambda value: (-float(value["htAmount"]), value["contractGuid"]))
    top_approving = [compact_contract(payload) for payload in approving_contracts]
    top_approving.sort(key=lambda value: (-float(value["htAmount"]), value["contractGuid"]))

    used_by_l3: dict[str, float] = {}
    for payload in contracts:
        if str(payload.get("cb_state") or "") in {"signed", "paid", "approving"}:
            code = str(payload.get("l3_code") or "")
            if code:
                used_by_l3[code] = used_by_l3.get(code, 0.0) + wan(
                    amount(payload, "ht_amount") + amount(payload, "sum_alter_amount")
                )
    top_overbudget: list[dict[str, Any]] = []
    for payload in subject_dict:
        code = str(payload.get("l3_code") or "")
        plan_amount = amount(payload, "plan_amount")
        used = used_by_l3.get(code, 0.0)
        if code and plan_amount > 0 and used > plan_amount:
            top_overbudget.append(
                {
                    "l3Code": code,
                    "subject": str(payload.get("subject") or ""),
                    "planAmount": plan_amount,
                    "used": used,
                }
            )
    top_overbudget.sort(key=lambda value: (-(value["used"] - value["planAmount"]), value["l3Code"]))
    gap_by_period: dict[str, float] = {}
    for payload in fund_plans:
        period = str(payload.get("plan_period") or "")
        sign = 1 if str(payload.get("direction") or "") == "in" else -1
        gap_by_period[period] = gap_by_period.get(period, 0.0) + sign * amount(payload, "plan_amount")
    top_gap = [
        {"planPeriod": period, "net": value}
        for period, value in gap_by_period.items()
        if value < 0
    ]
    top_gap.sort(key=lambda value: (value["net"], value["planPeriod"]))

    funnel = [
        {"stage": "客户", "value": len(sales["customers"])},
        {"stage": "认筹", "value": len(sales["subscriptions"])},
        {"stage": "签约", "value": len(signed_sales)},
        {"stage": "放款", "value": len(released_mortgages)},
        {"stage": "退房", "value": -len(approved_refunds)},
    ]
    compare_sales = [
        {"name": "认筹", "value": len(sales["subscriptions"])},
        {"name": "签约", "value": len(signed_sales)},
        {"name": "放款", "value": len(released_mortgages)},
    ]
    compare_cost = [
        {"name": "A 目标", "value": dict_plan_sum},
        {"name": "D 已成", "value": signed_wan},
        {"name": "E 在途", "value": approving_wan},
    ]
    compare_fund = [
        {"name": "收入计划", "value": sum(amount(payload, "plan_amount") for payload in fund_plans if str(payload.get("direction") or "") == "in")},
        {"name": "收入实际", "value": sum(amount(payload, "actual_amount") for payload in fund_plans if str(payload.get("direction") or "") == "in")},
        {"name": "支出计划", "value": sum(amount(payload, "plan_amount") for payload in fund_plans if str(payload.get("direction") or "") == "out")},
        {"name": "支出实际", "value": sum(amount(payload, "actual_amount") for payload in fund_plans if str(payload.get("direction") or "") == "out")},
    ]

    data = {
        "scope": {
            "buGuid": business_unit_id,
            "projGuid": project_id,
            "level": "project" if project_id else "bu" if business_unit_id else "group",
        },
        "kpi": {
            "r6Received": total_revenue,
            "r6Expected": r6_plan,
            "contractSigned": signed_wan,
            "contractApproving": approving_wan,
            "dictPlanSum": round(dict_plan_sum, 2),
            "unpaidApply": wan(sum(amount(payload, "apply_amount") for payload in unpaid_applications)),
            "r0PendingCount": len(r0_contracts),
            "customerCount": len(sales["customers"]),
            "subCount": len(sales["subscriptions"]),
            "signedCount": len(signed_sales),
            "mortgageCount": len(released_mortgages),
            "mortgageAmount": wan(sum(amount(payload, "loan_amount") for payload in released_mortgages)),
            "refundCount": len(approved_refunds),
            "scontractTotal": wan(sum(amount(payload, "total_price") for payload in signed_sales)),
            "fundInPlan": sum(amount(payload, "plan_amount") for payload in fund_plans if str(payload.get("direction") or "") == "in"),
            "fundInActual": sum(amount(payload, "actual_amount") for payload in fund_plans if str(payload.get("direction") or "") == "in"),
            "fundOutPlan": sum(amount(payload, "plan_amount") for payload in fund_plans if str(payload.get("direction") or "") == "out"),
            "fundOutActual": sum(amount(payload, "actual_amount") for payload in fund_plans if str(payload.get("direction") or "") == "out"),
            "progressActive": len(progress_active),
            "progressAvgPct": round(progress_average, 1),
            "progressDone": len(progress_done),
            "invInTotal": sum(amount(payload, "total_amount") for payload in invoice_in),
            "invOutTotal": sum(amount(payload, "total_amount") for payload in invoice_out),
            "netTax": round(
                sum(amount(payload, "tax_amount") for payload in invoice_out)
                - sum(amount(payload, "tax_amount") for payload in invoice_in),
                2,
            ),
            "tenderActiveCount": len(tender_active),
            "tenderActiveAmount": wan(sum(amount(payload, "estimated_amount") for payload in tender_active)),
            "tenderAwardedAmount": wan(sum(amount(payload, "award_amount") for payload in tender_awards)),
            "openWarnings": len(warnings),
            "runningProcesses": len(processes),
            "totalRevenue": total_revenue,
            "totalExpense": total_expense,
            "netProfit": net_profit,
            "netProfitRate": net_profit_rate,
            "cashflowMonths": cashflow_months,
            "healthScore": health_score,
        },
        "healthBreakdown": health_breakdown,
        "expenseByCategory": expense_by_category,
        "expenseByCity": expense_by_city,
        "gauge": {
            "collectionRate": round(total_revenue / (total_revenue + r6_plan) * 100, 1)
            if total_revenue + r6_plan > 0
            else 0,
            "mortgageRate": round(len(released_mortgages) / len(signed_sales) * 100, 1)
            if signed_sales
            else 0,
            "payableRate": round(
                wan(sum(amount(payload, "apply_amount") for payload in unpaid_applications))
                / signed_wan
                * 100,
                1,
            )
            if signed_wan > 0
            else 0,
            "budgetUsedRate": round((signed_wan + approving_wan) / dict_sum_wan * 100, 1)
            if dict_sum_wan > 0
            else 0,
        },
        "funnel": funnel,
        "compareSales": compare_sales,
        "compareCost": compare_cost,
        "compareFund": compare_fund,
        "tops": {
            "topUnpaid": top_unpaid[:5],
            "topR0": top_r0[:5],
            "topApproving": top_approving[:5],
            "topOverbudget": top_overbudget[:5],
            "topGap": top_gap[:5],
        },
    }
    return {
        "success": True,
        "code": 0,
        "data": data,
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": missing,
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _dashboard_project_context(
    rows: dict[str, list[dict[str, Any]]],
    project_id: str,
) -> dict[str, Any] | None:
    for row in rows["ep_project"]:
        payload = row["payload"]
        if str(payload.get("proj_guid") or row["record_id"]) == project_id and not payload.get("deleted_at"):
            return payload
    return None


def dashboard_project_kpi(
    pool: PsqlPool,
    project_id: str,
    max_rows: int,
) -> dict[str, Any] | None:
    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    rows, coverage, missing = _dashboard_context(pool, max_rows)
    project = _dashboard_project_context(rows, project_id)
    if project is None:
        return None
    units = {
        str(row["payload"].get("bu_guid") or row["record_id"]): row["payload"]
        for row in rows["mu_business_unit"]
    }
    tasks = [
        row["payload"]
        for row in rows["jd_task"]
        if str(row["payload"].get("proj_guid") or "") == project_id
        and str(row["payload"].get("task_type") or "") == "key_node"
    ]
    costs = [
        row["payload"]
        for row in rows["cb_cost"]
        if str(row["payload"].get("proj_guid") or "") == project_id
        and _dashboard_flag(row["payload"].get("is_end_cost"))
    ]
    contracts = [
        row["payload"]
        for row in rows["cb_contract"]
        if str(row["payload"].get("proj_guid") or "") == project_id
    ]
    applications = [
        row["payload"]
        for row in rows["cb_htfk_apply"]
        if str(row["payload"].get("proj_guid") or "") == project_id
    ]
    today = date.today()
    overdue_nodes = sum(
        1
        for payload in tasks
        if str(payload.get("status") or "") != "done"
        and (_report_date(payload.get("plan_end_date")) or date.max) < today
    )
    avg_progress = sum(_report_float(payload, "progress_pct") for payload in tasks) / len(tasks) if tasks else 0
    target_cost = sum(_report_float(payload, "target_cost") for payload in costs)
    dynamic_cost = sum(
        _report_float(payload, "ht_alter_amount")
        + _report_float(payload, "zt_cost")
        + _report_float(payload, "dfs_budget")
        + _report_float(payload, "yg_alter")
        for payload in costs
    )
    deviation_pct = (target_cost - dynamic_cost) / target_cost * 100 if target_cost > 0 else 0
    apply_total = sum(_report_float(payload, "apply_amount") for payload in applications)
    paid_total = sum(
        _report_float(payload, "apply_amount")
        for payload in applications
        if str(payload.get("pay_state") or "") in {"完全支付", "部分支付"}
    )
    approval_instances = [row["payload"] for row in rows["wf_process_instance"]]
    apply_ids = {
        str(payload.get("htfk_apply_guid") or "")
        for payload in applications
        if payload.get("htfk_apply_guid")
    }
    expense_ids = {
        str(row["payload"].get("expense_guid") or "")
        for row in rows["vcb_expense"]
        if str(row["payload"].get("bu_guid") or "") == str(project.get("bu_guid") or "")
        and row["payload"].get("expense_guid")
    }
    approval_ids = apply_ids | expense_ids
    approval_days: list[int] = []
    overdue_approvals = 0
    for payload in approval_instances:
        if str(payload.get("biz_data_guid") or "") not in approval_ids:
            continue
        initiated = _report_date(payload.get("initiated_at"))
        completed = _report_date(payload.get("completed_at"))
        if initiated is not None and completed is not None:
            approval_days.append((completed - initiated).days)
        if str(payload.get("status") or "") == "Running" and initiated is not None and (today - initiated).days > 7:
            overdue_approvals += 1
    version = next(
        (
            row["payload"]
            for row in rows["tzsy_version"]
            if str(row["payload"].get("proj_guid") or "") == project_id
            and _dashboard_flag(row["payload"].get("is_current"))
        ),
        None,
    )
    profit = None
    if version is not None:
        version_id = str(version.get("version_guid") or "")
        values = {
            str(row["payload"].get("full_code") or ""): _report_float(row["payload"], "index_value")
            for row in rows["tzsy_plan_index"]
            if str(row["payload"].get("version_guid") or "") == version_id
        }
        profit = {
            "irr": values.get("CO.IRR"),
            "npv": values.get("CO.NPV"),
            "netProfit": values.get("CO.NetProfit"),
            "revenue": values.get("CO.Revenue"),
        }
    current_month = today.strftime("%Y-%m")
    month_plan = sum(
        _report_float(payload, "jhfk_amount")
        for payload in rows["cb_htfkplan"]
        if str(payload.get("contract_guid") or "") in {
            str(contract.get("contract_guid") or "") for contract in contracts
        }
        and str(payload.get("jhfk_date") or "")[:7] == current_month
    )
    return _dashboard_envelope(
        {
            "project": {
                "projGuid": project_id,
                "projCode": str(project.get("proj_code") or project_id),
                "projName": str(project.get("proj_name") or project_id),
                "buName": str(units.get(str(project.get("bu_guid") or ""), {}).get("bu_name") or ""),
                "projStatus": str(project.get("proj_status") or ""),
            },
            "kpi": {
                "progress": {
                    "avgProgress": round(avg_progress, 1),
                    "totalNodes": len(tasks),
                    "overdueNodes": overdue_nodes,
                    "done": sum(1 for payload in tasks if str(payload.get("status") or "") == "done"),
                    "inProgress": sum(
                        1 for payload in tasks if str(payload.get("status") or "") == "in_progress"
                    ),
                },
                "cost": {
                    "target": target_cost,
                    "dynamic": dynamic_cost,
                    "deviationPct": round(deviation_pct, 2),
                    "layoutSpare": target_cost - dynamic_cost,
                },
                "contract": {
                    "count": len(contracts),
                    "totalAmount": sum(
                        _report_float(payload, "ht_amount") + _report_float(payload, "sum_alter_amount")
                        for payload in contracts
                    ),
                },
                "payment": {
                    "count": len(applications),
                    "applyTotal": apply_total,
                    "paidTotal": paid_total,
                    "paidRatio": round(paid_total / apply_total * 100, 2) if apply_total > 0 else 0,
                },
                "cash": {"thisMonthPlan": month_plan},
                "profit": profit,
                "quality": None,
                "approval": {
                    "avgDays": round(sum(approval_days) / len(approval_days), 1) if approval_days else None,
                    "overdueCount": overdue_approvals,
                },
            },
        },
        coverage,
        missing,
    )


def dashboard_project_anomalies(
    pool: PsqlPool,
    project_id: str,
    max_rows: int,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(project_id):
        raise ValueError("invalid project_id")
    rows, coverage, missing = _dashboard_context(pool, max_rows)
    project = _dashboard_project_context(rows, project_id)
    if project is None:
        return _dashboard_envelope([], coverage, missing)
    anomalies: list[dict[str, Any]] = []
    costs = [
        row["payload"]
        for row in rows["cb_cost"]
        if str(row["payload"].get("proj_guid") or "") == project_id
        and _dashboard_flag(row["payload"].get("is_end_cost"))
    ]
    target = sum(_report_float(payload, "target_cost") for payload in costs)
    dynamic = sum(
        _report_float(payload, "ht_alter_amount")
        + _report_float(payload, "zt_cost")
        + _report_float(payload, "dfs_budget")
        + _report_float(payload, "yg_alter")
        for payload in costs
    )
    if target > 0:
        deviation = (target - dynamic) / target * 100
        if deviation < -1:
            anomalies.append(
                {
                    "severity": "error" if deviation < -5 else "warning",
                    "title": f"成本超目标 {abs(deviation):.2f}%",
                    "detail": f"目标 ¥{target:,.0f} 动态 ¥{dynamic:,.0f}",
                    "suggestion": "建议立即组织成本分析会,识别超支科目并制定纠偏措施",
                }
            )
    today = date.today()
    for row in rows["jd_task"]:
        payload = row["payload"]
        if str(payload.get("proj_guid") or "") != project_id or str(payload.get("task_type") or "") != "key_node":
            continue
        planned_end = _report_date(payload.get("plan_end_date"))
        if (
            str(payload.get("status") or "") == "overdue"
            or (
                str(payload.get("status") or "") != "done"
                and planned_end is not None
                and planned_end < today
            )
        ):
            days = (today - planned_end).days if planned_end is not None else 0
            anomalies.append(
                {
                    "severity": "error" if days > 30 else "warning",
                    "title": f"关键节点延期 {days} 天",
                    "detail": f"{payload.get('task_name') or ''}(计划 {payload.get('plan_end_date') or ''})",
                    "suggestion": "建议召集项目周会复盘进度,评估是否启动赶工预案",
                }
            )
    apply_ids = {
        str(row["payload"].get("htfk_apply_guid") or "")
        for row in rows["cb_htfk_apply"]
        if str(row["payload"].get("proj_guid") or "") == project_id
    }
    expense_ids = {
        str(row["payload"].get("expense_guid") or "")
        for row in rows["vcb_expense"]
        if str(row["payload"].get("bu_guid") or "") == str(project.get("bu_guid") or "")
        and row["payload"].get("expense_guid")
    }
    approval_ids = apply_ids | expense_ids
    overdue_approvals = 0
    today = date.today()
    for row in rows["wf_process_instance"]:
        payload = row["payload"]
        initiated = _report_date(payload.get("initiated_at"))
        if (
            str(payload.get("status") or "") == "Running"
            and str(payload.get("biz_data_guid") or "") in approval_ids
            and initiated is not None
            and (today - initiated).days > 7
        ):
            overdue_approvals += 1
    if overdue_approvals:
        anomalies.append(
            {
                "severity": "warning",
                "title": f"{overdue_approvals} 单审批超 7 天未结",
                "detail": "审批长期停滞会阻塞项目进度",
                "suggestion": "建议责任人介入催办,或评估流程节点配置合理性",
            }
        )
    return _dashboard_envelope(anomalies, coverage, missing)


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

INVESTMENT_IMPORT_SOURCE_TABLES = {
    "ep_project",
    "sys_user",
    "tzsy_version",
    "tzsy_excel_import",
}

INVESTMENT_EXCEL_SOURCE_TABLES = {
    "ep_project",
    "sys_user",
    "tzsy_version",
    "tzsy_excel_import",
    "tzsy_excel_sheet",
    "tzsy_profit_table",
    "tzsy_plan_line",
    "tzsy_subject_mapping",
}

ADMIN_SOURCE_TABLES = {
    "audit_log",
    "my_biz_param_option",
    "sys_user",
}

AUTH_SOURCE_TABLES = {
    "sys_user",
    "vcb_expense",
    "vcb_loan_simple",
    "cb_htfk_apply",
}

AUTH_PREF_SOURCE_TABLES = {
    "sys_user",
    "sys_user_pref",
}

ADMIN_QUALITY_SOURCE_TABLES = {
    "ep_project",
    "cb_contract",
    "cb_htfk_apply",
    "cb_cost",
    "vcb_expense",
    "cb_expense_split",
    "wf_process_instance",
    "vcb_loan_simple",
    "jd_task",
    "srm_provider",
    "sys_user",
}

ADMIN_RBAC_SOURCE_TABLES = {
    "sys_user",
    "mu_business_unit",
    "sys_role",
    "sys_user_role",
}

ADMIN_HEALTH_SOURCE_TABLES = {
    "mu_business_unit",
    "sys_user",
    "ep_project",
    "proj_lifecycle_stage",
    "proj_lifecycle_instance",
    "my_biz_param_option",
    "vys_proceeding",
    "wf_process_def",
    "wf_step_def",
    "wf_step_assignee",
    "wf_process_instance",
    "wf_step_action",
    "vcb_expense",
    "cb_expense_detail",
    "cb_expense_split",
    "cb_contract",
    "cb_htfkplan",
    "cb_htfk_apply",
    "cb_cost",
    "vcb_loan_simple",
    "cb_loan_offset",
    "jd_task",
    "jd_task_report",
    "tzsy_version",
    "tzsy_plan_index",
    "audit_log",
    "srm_provider",
    "srm_provider_bu",
    "srm_category",
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
    "sys_user",
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
    user_rows = _workflow_rows(pool, "sys_user", max(max_rows, 500))
    users_by_id = {
        str(row["payload"].get("user_id") or row["record_id"]): row["payload"]
        for row in user_rows
    }
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
                "user_code": str(
                    users_by_id.get(str(payload.get("assignee_user_guid", "")), {}).get("user_code") or ""
                ),
                "user_name": str(
                    users_by_id.get(str(payload.get("assignee_user_guid", "")), {}).get("emp_name") or ""
                ),
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


def _workflow_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _workflow_source_coverage(pool: PsqlPool, max_rows: int) -> dict[str, int]:
    return {
        table: len(_workflow_rows(pool, table, max(max_rows, 500)))
        for table in sorted(WORKFLOW_SOURCE_TABLES)
    }


def _workflow_resolve_user_id(
    pool: PsqlPool,
    user_id: str | None,
    user_code: str | None,
    max_rows: int,
) -> str | None:
    if user_id is not None:
        if not IDENTIFIER.fullmatch(user_id):
            raise ValueError("invalid user_id")
        return user_id
    if user_code is None:
        return None
    if not IDENTIFIER.fullmatch(user_code):
        raise ValueError("invalid user_code")
    rows = _workflow_rows(pool, "sys_user", max(max_rows, 500))
    selected = next(
        (row for row in rows if _report_text(row["payload"], "user_code") == user_code),
        None,
    )
    return _report_text(selected["payload"], "user_id", selected["record_id"]) if selected else None


def _workflow_source_context(
    pool: PsqlPool,
    max_rows: int,
) -> tuple[
    dict[str, dict[str, Any]],
    dict[str, dict[str, Any]],
    dict[str, dict[str, Any]],
    dict[str, dict[str, Any]],
    list[dict[str, Any]],
    list[dict[str, Any]],
    dict[str, dict[str, Any]],
]:
    process_rows = _workflow_rows(pool, "wf_process_def", max_rows)
    step_rows = _workflow_rows(pool, "wf_step_def", max(max_rows, 500))
    assignee_rows = _workflow_rows(pool, "wf_step_assignee", max(max_rows, 500))
    user_rows = _workflow_rows(pool, "sys_user", max(max_rows, 500))
    instance_rows = _workflow_rows(pool, "wf_process_instance", max(max_rows, 500))
    action_rows = _workflow_rows(pool, "wf_step_action", max(max_rows, 500))
    users = {
        _report_text(row["payload"], "user_id", row["record_id"]): row["payload"]
        for row in user_rows
    }
    processes = {
        _report_text(row["payload"], "process_guid", row["record_id"]): row["payload"]
        for row in process_rows
    }
    steps = {
        _report_text(row["payload"], "step_guid", row["record_id"]): row["payload"]
        for row in step_rows
    }
    assignees = {
        _report_text(row["payload"], "assignee_guid", row["record_id"]): row["payload"]
        for row in assignee_rows
    }
    return processes, steps, assignees, users, instance_rows, action_rows, {
        "process_rows": {key: value for key, value in processes.items()},
    }


def _workflow_instance_value(payload: dict[str, Any], key: str, fallback: str = "") -> str:
    return _report_text(payload, key, fallback)


def _workflow_normalized_instance(row: dict[str, Any]) -> dict[str, Any]:
    payload = row["payload"]
    return {
        "processInstanceGuid": _workflow_instance_value(payload, "process_instance_guid", row["record_id"]),
        "processGuid": _workflow_instance_value(payload, "process_guid"),
        "processName": _workflow_instance_value(payload, "process_name"),
        "processKey": _workflow_instance_value(payload, "process_key"),
        "bizType": _workflow_instance_value(payload, "biz_type"),
        "bizDataGuid": _workflow_instance_value(payload, "biz_data_guid"),
        "status": _workflow_instance_value(payload, "status"),
        "initiatorGuid": _workflow_instance_value(payload, "initiator_guid"),
        "buGuid": _workflow_instance_value(payload, "bu_guid"),
        "initiatedAt": _workflow_instance_value(payload, "initiated_at"),
        "completedAt": _workflow_instance_value(payload, "completed_at"),
        "currentStepOrder": payload.get("current_step_order", 0),
        "sourceId": row["source_id"],
    }


def _workflow_action_rows(
    action_rows: list[dict[str, Any]],
    instance_id: str | None = None,
) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for row in action_rows:
        payload = row["payload"]
        current_instance = _workflow_instance_value(payload, "process_instance_guid")
        if instance_id is not None and current_instance != instance_id:
            continue
        result.append({
            "actionGuid": _workflow_instance_value(payload, "action_guid", row["record_id"]),
            "processInstanceGuid": current_instance,
            "stepOrder": payload.get("step_order", 0),
            "stepName": _workflow_instance_value(payload, "step_name"),
            "assigneeGuid": _workflow_instance_value(payload, "assignee_guid", _workflow_instance_value(payload, "operator_guid")),
            "decision": _workflow_instance_value(payload, "decision"),
            "comment": _workflow_instance_value(payload, "comment"),
            "actionTime": _workflow_instance_value(payload, "action_time", _workflow_instance_value(payload, "created_at")),
            "sourceId": row["source_id"],
        })
    result.sort(key=lambda value: (str(value.get("actionTime", "")), str(value.get("actionGuid", ""))))
    return result


def _workflow_detail_data(
    instance: dict[str, Any],
    process: dict[str, Any],
    steps: dict[str, dict[str, Any]],
    assignees: dict[str, dict[str, Any]],
    users: dict[str, dict[str, Any]],
    actions: list[dict[str, Any]],
) -> dict[str, Any]:
    process_guid = str(instance.get("processGuid") or "")
    step_rows: list[dict[str, Any]] = []
    for step_guid, payload in steps.items():
        if _workflow_instance_value(payload, "process_guid") != process_guid:
            continue
        assigned: list[dict[str, Any]] = []
        for assignee_guid, assignee in assignees.items():
            if _workflow_instance_value(assignee, "step_guid") != step_guid:
                continue
            user_guid = _workflow_instance_value(assignee, "assignee_user_guid")
            user = users.get(user_guid, {})
            assigned.append({
                "assigneeGuid": assignee_guid,
                "userGuid": user_guid,
                "userCode": _report_text(user, "user_code"),
                "userName": _report_text(user, "emp_name", _report_text(user, "user_name", user_guid)),
                "weight": assignee.get("weight", 1),
            })
        step_rows.append({
            "stepGuid": step_guid,
            "stepOrder": payload.get("step_order", 0),
            "stepName": _workflow_instance_value(payload, "step_name"),
            "threshold": payload.get("threshold", 1),
            "stepKey": _workflow_instance_value(payload, "step_key"),
            "stepStatus": _workflow_instance_value(payload, "status"),
            "assignees": assigned,
        })
    step_rows.sort(key=lambda value: (int(value.get("stepOrder") or 0), str(value.get("stepGuid", ""))))
    initiator = users.get(str(instance.get("initiatorGuid") or ""), {})
    instance_payload = {
        "processInstanceGuid": instance.get("processInstanceGuid", ""),
        "bizType": instance.get("bizType", ""),
        "bizDataGuid": instance.get("bizDataGuid", ""),
        "status": instance.get("status", ""),
        "initiatorGuid": instance.get("initiatorGuid", ""),
        "initiatedAt": instance.get("initiatedAt", ""),
        "completedAt": instance.get("completedAt", ""),
        "currentStepOrder": instance.get("currentStepOrder", 0),
    }
    return {
        "instance": instance_payload,
        "processName": _report_text(process, "process_name", str(instance.get("processName") or instance.get("processKey") or "")),
        "initiator": {
            "userId": instance.get("initiatorGuid", ""),
            "empName": _report_text(initiator, "emp_name", _report_text(initiator, "user_name", str(instance.get("initiatorGuid") or ""))),
        },
        "steps": step_rows,
        "actions": [
            {
                **action,
                "assigneeEmpName": _report_text(users.get(str(action.get("assigneeGuid") or ""), {}), "emp_name", str(action.get("assigneeGuid") or "")),
            }
            for action in actions
        ],
    }


def workflow_source_tasks_mine(
    pool: PsqlPool,
    user_id: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if user_id is not None and not IDENTIFIER.fullmatch(user_id):
        raise ValueError("invalid user_id")
    _processes, _steps, _assignees, _users, instance_rows, action_rows, _ = _workflow_source_context(pool, max_rows)
    instances = [_workflow_normalized_instance(row) for row in instance_rows]
    actions_by_instance: dict[str, list[dict[str, Any]]] = {}
    for action in _workflow_action_rows(action_rows):
        actions_by_instance.setdefault(str(action.get("processInstanceGuid") or ""), []).append(action)
    result: list[dict[str, Any]] = []
    for instance in instances:
        if str(instance.get("status", "")) not in {"Running", "Approving", "running", "submitted"}:
            continue
        actions = actions_by_instance.get(str(instance.get("processInstanceGuid", "")), [])
        if user_id is not None and actions and not any(str(action.get("assigneeGuid")) == user_id for action in actions):
            continue
        result.append({
            "processInstanceGuid": instance["processInstanceGuid"],
            "processName": instance["processName"],
            "bizType": instance["bizType"],
            "bizDataGuid": instance["bizDataGuid"],
            "currentStep": {"stepOrder": instance["currentStepOrder"], "stepName": ""},
            "initiator": {"userId": instance["initiatorGuid"], "empName": ""},
            "initiatedAt": instance["initiatedAt"],
        })
    coverage = _workflow_source_coverage(pool, max_rows)
    metadata = _workflow_source_metadata(coverage)
    metadata["scope_applied"] = user_id is not None
    return {"success": True, "code": 0, "data": result[:max_rows], **metadata}


def workflow_source_tasks_initiated(
    pool: PsqlPool,
    user_id: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if user_id is not None and not IDENTIFIER.fullmatch(user_id):
        raise ValueError("invalid user_id")
    _processes, _steps, _assignees, _users, instance_rows, _action_rows, _ = _workflow_source_context(pool, max_rows)
    result: list[dict[str, Any]] = []
    for row in instance_rows:
        instance = _workflow_normalized_instance(row)
        if user_id is not None and instance["initiatorGuid"] != user_id:
            continue
        result.append({
            "processInstanceGuid": instance["processInstanceGuid"],
            "processName": instance["processName"],
            "bizType": instance["bizType"],
            "bizDataGuid": instance["bizDataGuid"],
            "status": instance["status"],
            "initiatedAt": instance["initiatedAt"],
            "completedAt": instance["completedAt"],
            "currentStepOrder": instance["currentStepOrder"],
        })
    coverage = _workflow_source_coverage(pool, max_rows)
    metadata = _workflow_source_metadata(coverage)
    metadata["scope_applied"] = user_id is not None
    return {"success": True, "code": 0, "data": result[:max_rows], **metadata}


def workflow_source_history(
    pool: PsqlPool,
    user_id: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if user_id is not None and not IDENTIFIER.fullmatch(user_id):
        raise ValueError("invalid user_id")
    _processes, _steps, _assignees, users, instance_rows, action_rows, _ = _workflow_source_context(pool, max_rows)
    instances = {_workflow_normalized_instance(row)["processInstanceGuid"]: _workflow_normalized_instance(row) for row in instance_rows}
    result: list[dict[str, Any]] = []
    for action in _workflow_action_rows(action_rows):
        if user_id is not None and str(action.get("assigneeGuid") or "") != user_id:
            continue
        instance = instances.get(str(action.get("processInstanceGuid") or ""), {})
        if not instance:
            continue
        result.append({
            "processInstanceGuid": instance.get("processInstanceGuid", ""),
            "processName": instance.get("processName", ""),
            "bizType": instance.get("bizType", ""),
            "bizDataGuid": instance.get("bizDataGuid", ""),
            "status": instance.get("status", ""),
            "initiatedAt": instance.get("initiatedAt", ""),
            "completedAt": instance.get("completedAt", ""),
            "currentStepOrder": instance.get("currentStepOrder", 0),
            "initiator": {"empName": _report_text(users.get(str(instance.get("initiatorGuid") or ""), {}), "emp_name")},
            "myLastActionTime": action.get("actionTime", ""),
            "myLastDecision": action.get("decision", ""),
        })
    coverage = _workflow_source_coverage(pool, max_rows)
    metadata = _workflow_source_metadata(coverage)
    metadata["scope_applied"] = user_id is not None
    return {"success": True, "code": 0, "data": result[:max_rows], **metadata}


def workflow_source_instance_detail(
    pool: PsqlPool,
    instance_id: str,
    max_rows: int,
) -> dict[str, Any] | None:
    if not IDENTIFIER.fullmatch(instance_id):
        raise ValueError("invalid process_instance_id")
    processes, steps, assignees, users, instance_rows, action_rows, _ = _workflow_source_context(pool, max_rows)
    source_row = next(
        (row for row in instance_rows if _workflow_instance_value(row["payload"], "process_instance_guid", row["record_id"]) == instance_id),
        None,
    )
    if source_row is None:
        return None
    instance = _workflow_normalized_instance(source_row)
    actions = _workflow_action_rows(action_rows, instance_id)
    process = processes.get(str(instance.get("processGuid") or ""), {})
    coverage = _workflow_source_coverage(pool, max_rows)
    return {"success": True, "code": 0, "data": _workflow_detail_data(instance, process, steps, assignees, users, actions), **_workflow_source_metadata(coverage)}


def workflow_source_instance_by_biz(
    pool: PsqlPool,
    biz_type: str,
    biz_data_guid: str,
    max_rows: int,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(biz_type) or not IDENTIFIER.fullmatch(biz_data_guid):
        raise ValueError("invalid workflow business identity")
    _processes, _steps, _assignees, _users, instance_rows, _actions, _ = _workflow_source_context(pool, max_rows)
    candidates = [
        row for row in instance_rows
        if _workflow_instance_value(row["payload"], "biz_type") == biz_type
        and _workflow_instance_value(row["payload"], "biz_data_guid") == biz_data_guid
    ]
    candidates.sort(key=lambda row: _workflow_instance_value(row["payload"], "initiated_at"), reverse=True)
    result = None
    if candidates:
        result = workflow_source_instance_detail(
            pool,
            _workflow_instance_value(candidates[0]["payload"], "process_instance_guid", candidates[0]["record_id"]),
            max_rows,
        )
        result = result.get("data") if result else None
    coverage = _workflow_source_coverage(pool, max_rows)
    return {"success": True, "code": 0, "data": result, **_workflow_source_metadata(coverage)}


LOAN_SOURCE_TABLES = {
    "vcb_loan_simple",
    "cb_loan_offset",
    "sys_user",
    "mu_business_unit",
    "ep_project",
}


CASHFLOW_SOURCE_TABLES = {
    "cb_contract",
    "cb_contract_milestone",
    "cb_htfk_apply",
    "cb_htfkplan",
    "cb_plan_version",
    "cb_subject_dict",
    "ep_project",
    "mu_business_unit",
    "sale_revenue",
    "vcb_expense",
    "vcb_loan_simple",
}


CBS_SOURCE_TABLES = {
    "cb_change_apply",
    "cb_contract",
    "cb_expense_split",
    "cb_plan_version",
    "cb_r_master",
    "cb_subject_dict",
    "vcb_expense",
    "wf_approval_rule",
}


FUND_SOURCE_TABLES = {
    "ep_project",
    "fund_dispatch",
    "fund_plan",
    "mu_business_unit",
}


WARNING_SOURCE_TABLES = {
    "cb_contract",
    "cb_cost",
    "cb_expense_split",
    "cb_htfk_apply",
    "ep_project",
    "jd_task",
    "my_biz_param_option",
    "srm_provider",
    "sys_user",
    "vcb_expense",
    "vcb_loan_simple",
    "wf_process_instance",
}


WARNING_RULE_DEFINITIONS = [
    ("W001", "项目缺少所属公司", "error", "project"),
    ("W002", "合同未关联项目", "error", "contract"),
    ("W003", "付款申请缺少合同", "error", "htfk_apply"),
    ("W004", "付款累计超合同总额", "error", "contract"),
    ("W005", "在建项目无动态成本科目", "warning", "project"),
    ("W006", "报销分摊合计 ≠ 应付金额", "error", "expense"),
    ("W007", "BPM 实例进行中超 7 天", "warning", "wf_instance"),
    ("W008", "借款三态字段不一致", "error", "loan"),
    ("W009", "任务计划完成日 < 开始日", "warning", "jd_task"),
    ("W010", "供应商重名(SRM)", "warning", "srm_provider"),
    ("W011", "BPM 僵尸(>30 天 Running)", "error", "wf_instance"),
    ("W012", "用户缺少所属组织", "warning", "sys_user"),
]


ATTACHMENT_SOURCE_TABLES = {
    "attachment",
    "sys_user",
}


MARKETING_SOURCE_TABLES = {
    "mkt_campaign",
    "mkt_placement",
    "mkt_channel",
    "mkt_material",
}


NOTIFICATION_SOURCE_TABLES = {
    "sys_message",
    "sys_warning_subscription",
    "sys_param",
    "sys_email_outbox",
    "sys_warning_digest_log",
    "sys_warning",
    "sys_user",
}


NOTIFICATION_CONFIG_KEYS = (
    "notify.webhook.url",
    "notify.webhook.kind",
    "notify.email.from",
    "notify.email.enabled",
    "notify.email.smtp.host",
    "notify.email.smtp.port",
    "notify.email.smtp.user",
    "notify.email.smtp.pass",
    "notify.email.smtp.secure",
    "ai.ocr.provider",
    "ai.ocr.http.url",
    "ai.llm.provider",
    "ai.llm.key",
    "ai.llm.model",
    "ai.llm.endpoint",
    "ai.llm.fallback_providers",
    "notify.digest.enabled",
    "notify.digest.hour",
    "notify.ticket_email.enabled",
    "notify.ticket_webhook.enabled",
)


OCR_SOURCE_TABLES = {
    "sys_param",
    "sys_user",
}

ERROR_LOG_SOURCE_TABLES = {
    "sys_error_log",
    "sys_user",
}

AI_STATS_SOURCE_TABLES = {
    "ai_draft",
    "ai_query_log",
    "ai_correction_log",
    "wf_step_action",
    "wf_process_instance",
    "sys_user",
}

AI_HUB_SOURCE_TABLES = {
    "ai_draft",
    "ai_query_log",
    "ai_correction_log",
    "ai_query_session",
    "ai_query_turn",
    "audit_log",
    "sys_user",
}

WEBHOOK_SOURCE_TABLES = {
    "sys_param",
}

WEBHOOK_PLATFORM_DEFINITIONS = (
    ("feishu", "飞书"),
    ("dingtalk", "钉钉"),
    ("wecom", "企微"),
)

OCR_PROVIDER_DEFINITIONS = (
    ("mock", "演示 Mock", False, ()),
    ("paddle", "本地 PaddleOCR", False, ()),
    ("http", "自定义 HTTP 端点", True, ("ai.ocr.http.url",)),
    (
        "baidu",
        "百度 OCR",
        True,
        ("ai.ocr.baidu.api_key", "ai.ocr.baidu.secret_key"),
    ),
    ("aliyun", "阿里云 OCR", True, ("ai.ocr.aliyun.app_code",)),
    (
        "tencent",
        "腾讯云 OCR",
        True,
        (
            "ai.ocr.tencent.secret_id",
            "ai.ocr.tencent.secret_key",
            "ai.ocr.tencent.region",
        ),
    ),
)


def _cashflow_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
    }


def _cbs_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
    }


def _fund_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
    }


def _warning_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "observed_imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
    }


def _cashflow_month(value: Any) -> str | None:
    if value is None:
        return None
    match = re.match(r"^(\d{4})[-/.]?(\d{1,2})", str(value))
    if match is None:
        return None
    return f"{match.group(1)}-{int(match.group(2)):02d}"


def _cashflow_months(months: int, start_offset: int = 0) -> list[str]:
    current = date.today().replace(day=1)
    result: list[str] = []
    for offset in range(months):
        month_index = current.month - 1 + start_offset + offset
        year = current.year + month_index // 12
        month = month_index % 12 + 1
        result.append(f"{year:04d}-{month:02d}")
    return result


def cashflow_source_forecast(
    pool: PsqlPool,
    months: int,
    bu_guid: str | None,
    proj_guid: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Reproduce the ERP cashflow forecast from imported source envelopes.

    This is intentionally a read-only projection.  Missing sales, expense, or
    financing tables remain visible in coverage metadata and contribute zero;
    no forecast row is invented to make an empty source look populated.
    """

    if months < 1 or months > 24:
        raise ValueError("months must be between 1 and 24")
    for value, label in ((bu_guid, "bu_guid"), (proj_guid, "proj_guid")):
        if value is not None and not IDENTIFIER.fullmatch(value):
            raise ValueError(f"invalid {label}")
    limit = max(max_rows, 500)
    coverage = {
        table: len(_raw_source_rows(pool, table, limit, CASHFLOW_SOURCE_TABLES))
        for table in sorted(CASHFLOW_SOURCE_TABLES)
    }
    plans = _raw_source_rows(pool, "cb_htfkplan", limit, CASHFLOW_SOURCE_TABLES)
    contracts = _raw_source_rows(pool, "cb_contract", limit, CASHFLOW_SOURCE_TABLES)
    applications = _raw_source_rows(pool, "cb_htfk_apply", limit, CASHFLOW_SOURCE_TABLES)
    expenses = _raw_source_rows(pool, "vcb_expense", limit, CASHFLOW_SOURCE_TABLES)
    loans = _raw_source_rows(pool, "vcb_loan_simple", limit, CASHFLOW_SOURCE_TABLES)
    units = {
        str(row["payload"].get("bu_guid") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "mu_business_unit", limit, CASHFLOW_SOURCE_TABLES)
    }
    projects = {
        str(row["payload"].get("proj_guid") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "ep_project", limit, CASHFLOW_SOURCE_TABLES)
    }
    contract_by_id = {
        str(row["payload"].get("contract_guid") or row["record_id"]): row["payload"]
        for row in contracts
        if not row["payload"].get("deleted_at")
    }

    def included_plan(row: dict[str, Any]) -> bool:
        payload = row["payload"]
        if payload.get("deleted_at"):
            return False
        if bu_guid is not None and str(payload.get("bu_guid") or "") != bu_guid:
            return False
        contract = contract_by_id.get(str(payload.get("contract_guid") or ""), {})
        return proj_guid is None or str(contract.get("proj_guid") or "") == proj_guid

    def included_direct(row: dict[str, Any], *, project: bool = False) -> bool:
        payload = row["payload"]
        if payload.get("deleted_at"):
            return False
        if bu_guid is not None and str(payload.get("bu_guid") or "") != bu_guid:
            return False
        return not project or proj_guid is None or str(payload.get("proj_guid") or "") == proj_guid

    selected_plans = [row for row in plans if included_plan(row)]
    selected_apps = [row for row in applications if included_direct(row, project=True)]
    selected_expenses = [row for row in expenses if included_direct(row)]
    selected_loans = [row for row in loans if included_direct(row, project=True)]
    month_list = _cashflow_months(months)
    month_set = set(month_list)
    series: dict[str, dict[str, Any]] = {
        month: {
            "ym": month,
            "planned": 0.0,
            "pending": 0.0,
            "confirmed": 0.0,
            "expense": 0.0,
            "loan": 0.0,
        }
        for month in month_list
    }
    by_bu: dict[str, float] = {}
    by_project: dict[str, float] = {}
    for row in selected_plans:
        payload = row["payload"]
        month = _cashflow_month(payload.get("jhfk_date"))
        amount = _report_float(payload, "jhfk_amount")
        if month not in month_set:
            continue
        series[month]["planned"] += amount
        bu = str(payload.get("bu_guid") or "")
        by_bu[bu] = by_bu.get(bu, 0.0) + amount
        contract = contract_by_id.get(str(payload.get("contract_guid") or ""), {})
        project = str(contract.get("proj_guid") or "")
        if project:
            by_project[project] = by_project.get(project, 0.0) + amount
    for row in selected_apps:
        payload = row["payload"]
        month = _cashflow_month(payload.get("apply_date"))
        if month not in month_set:
            continue
        state = str(payload.get("apply_state") or "")
        if state == "申请审批中":
            series[month]["pending"] += _report_float(payload, "apply_amount")
        elif state == "已审核":
            series[month]["confirmed"] += _report_float(payload, "apply_amount")
    for row in selected_expenses:
        payload = row["payload"]
        month = _cashflow_month(payload.get("apply_date"))
        if (
            month in month_set
            and str(payload.get("apply_state") or "") == "Approved"
            and str(payload.get("pay_state") or "") != "完全支付"
        ):
            series[month]["expense"] += _report_float(payload, "pay_amount")
    for row in selected_loans:
        payload = row["payload"]
        month = _cashflow_month(payload.get("apply_date"))
        amount = _report_float(payload, "remain_amount")
        if month in month_set and str(payload.get("apply_state") or "") == "Approved" and amount > 0:
            series[month]["loan"] += amount

    cumulative = 0.0
    actual_cumulative = 0.0
    rows: list[dict[str, Any]] = []
    for month in month_list:
        row = series[month]
        base_outflow = row["confirmed"] + row["pending"] + max(
            0.0, row["planned"] - row["confirmed"] - row["pending"]
        )
        total_outflow = base_outflow + row["expense"] + row["loan"]
        actual_outflow = row["confirmed"] + row["expense"] + row["loan"]
        cumulative += total_outflow
        actual_cumulative += actual_outflow
        rows.append(
            {
                **row,
                "totalOutflow": round(total_outflow, 2),
                "cumulativeOutflow": round(cumulative, 2),
                "actualOutflow": round(actual_outflow, 2),
                "actualCumulative": round(actual_cumulative, 2),
            }
        )

    def top_rows(values: dict[str, float], name_key: str) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for key, amount in sorted(values.items(), key=lambda item: (-item[1], item[0]))[:5]:
            if name_key == "buName":
                name = str(units.get(key, {}).get("bu_name") or key)
                result.append({"buGuid": key, "buName": name, "amount": round(amount, 2)})
            else:
                name = str(projects.get(key, {}).get("proj_name") or key)
                result.append({"projGuid": key, "projName": name, "amount": round(amount, 2)})
        return result

    totals = {
        "plannedTotal": round(sum(row["planned"] for row in rows), 2),
        "pendingTotal": round(sum(row["pending"] for row in rows), 2),
        "confirmedTotal": round(sum(row["confirmed"] for row in rows), 2),
        "expenseTotal": round(sum(row["expense"] for row in rows), 2),
        "loanTotal": round(sum(row["loan"] for row in rows), 2),
        "totalOutflow": round(sum(row["totalOutflow"] for row in rows), 2),
    }
    return {
        "success": True,
        "code": 0,
        "data": {
            "filters": {"months": months, "buGuid": bu_guid, "projGuid": proj_guid},
            "months": month_list,
            "series": rows,
            "totals": totals,
            "byBu": top_rows(by_bu, "buName"),
            "byProj": top_rows(by_project, "projName"),
        },
        **_cashflow_source_metadata(coverage),
    }


def _cashflow_rows_and_coverage(
    pool: PsqlPool, max_rows: int,
) -> tuple[dict[str, int], dict[str, list[dict[str, Any]]]]:
    limit = max(max_rows, 500)
    rows = {
        table: _raw_source_rows(pool, table, limit, CASHFLOW_SOURCE_TABLES)
        for table in sorted(CASHFLOW_SOURCE_TABLES)
    }
    coverage = {table: len(values) for table, values in rows.items()}
    return coverage, rows


def _cashflow_contract_map(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {
        str(row["payload"].get("contract_guid") or row["record_id"]): row["payload"]
        for row in rows
        if not row["payload"].get("deleted_at")
    }


def cashflow_source_detail(
    pool: PsqlPool,
    ym: str,
    bu_guid: str | None,
    proj_guid: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Return the source rows behind one forecast month for drill-down."""

    match = re.fullmatch(r"(\d{4})-(\d{2})", ym)
    if match is None or not 1 <= int(match.group(2)) <= 12:
        raise ValueError("ym must use YYYY-MM")
    for value, label in ((bu_guid, "bu_guid"), (proj_guid, "proj_guid")):
        if value is not None and not IDENTIFIER.fullmatch(value):
            raise ValueError(f"invalid {label}")
    coverage, rows = _cashflow_rows_and_coverage(pool, max_rows)
    contracts = _cashflow_contract_map(rows["cb_contract"])
    plans: list[dict[str, Any]] = []
    for row in rows["cb_htfkplan"]:
        payload = row["payload"]
        if payload.get("deleted_at") or _cashflow_month(payload.get("jhfk_date")) != ym:
            continue
        if bu_guid is not None and str(payload.get("bu_guid") or "") != bu_guid:
            continue
        contract = contracts.get(str(payload.get("contract_guid") or ""), {})
        if proj_guid is not None and str(contract.get("proj_guid") or "") != proj_guid:
            continue
        plans.append(
            {
                "htfk_plan_guid": _report_text(payload, "htfk_plan_guid", row["record_id"]),
                "plan_period": _report_text(payload, "plan_period"),
                "jhfk_date": _report_text(payload, "jhfk_date"),
                "jhfk_amount": _report_float(payload, "jhfk_amount"),
                "approve_state": _report_text(payload, "approve_state"),
                "contract_code": _report_text(contract, "contract_code"),
                "contract_name": _report_text(contract, "contract_name"),
                "proj_guid": _report_text(contract, "proj_guid"),
            }
        )
    applies: list[dict[str, Any]] = []
    for row in rows["cb_htfk_apply"]:
        payload = row["payload"]
        if payload.get("deleted_at") or _cashflow_month(payload.get("apply_date")) != ym:
            continue
        if bu_guid is not None and str(payload.get("bu_guid") or "") != bu_guid:
            continue
        if proj_guid is not None and str(payload.get("proj_guid") or "") != proj_guid:
            continue
        contract = contracts.get(str(payload.get("contract_guid") or ""), {})
        applies.append(
            {
                "htfk_apply_guid": _report_text(payload, "htfk_apply_guid", row["record_id"]),
                "apply_code": _report_text(payload, "apply_code"),
                "apply_date": _report_text(payload, "apply_date"),
                "apply_amount": _report_float(payload, "apply_amount"),
                "apply_state": _report_text(payload, "apply_state"),
                "pay_state": _report_text(payload, "pay_state"),
                "subject": _report_text(payload, "subject"),
                "proj_guid": _report_text(payload, "proj_guid"),
                "contract_code": _report_text(contract, "contract_code"),
                "contract_name": _report_text(contract, "contract_name"),
            }
        )
    plans.sort(key=lambda value: value["jhfk_date"])
    applies.sort(key=lambda value: value["apply_date"])
    return {
        "success": True,
        "code": 0,
        "data": {"ym": ym, "plans": plans, "applies": applies},
        **_cashflow_source_metadata(coverage),
    }


def cashflow_source_inflow(
    pool: PsqlPool,
    months: int,
    bu_guid: str | None,
    proj_guid: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if months < 1 or months > 24:
        raise ValueError("months must be between 1 and 24")
    for value, label in ((bu_guid, "bu_guid"), (proj_guid, "proj_guid")):
        if value is not None and not IDENTIFIER.fullmatch(value):
            raise ValueError(f"invalid {label}")
    coverage, rows = _cashflow_rows_and_coverage(pool, max_rows)
    month_list = _cashflow_months(months + 3, -3)
    month_set = set(month_list)
    series = {
        month: {"ym": month, "received": 0.0, "expected": 0.0, "overdue": 0.0}
        for month in month_list
    }
    today = date.today().isoformat()
    for row in rows["sale_revenue"]:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        if bu_guid is not None and str(payload.get("bu_guid") or "") != bu_guid:
            continue
        if proj_guid is not None and str(payload.get("proj_guid") or "") != proj_guid:
            continue
        month = _cashflow_month(payload.get("receive_date"))
        if month not in month_set:
            continue
        state = _report_text(payload, "status")
        if state == "expected" and _report_text(payload, "receive_date")[:10] < today:
            state = "overdue"
        if state not in {"received", "expected", "overdue"}:
            continue
        series[month][state] += _report_float(payload, "amount")
    cumulative = 0.0
    data: list[dict[str, Any]] = []
    for month in month_list:
        row = series[month]
        total = row["received"] + row["expected"] + row["overdue"]
        cumulative += total
        data.append({**row, "total": round(total, 2), "cumulative": round(cumulative, 2)})
    totals = {
        "receivedTotal": round(sum(row["received"] for row in data), 2),
        "expectedTotal": round(sum(row["expected"] for row in data), 2),
        "overdueTotal": round(sum(row["overdue"] for row in data), 2),
        "totalInflow": round(sum(row["total"] for row in data), 2),
    }
    return {
        "success": True,
        "code": 0,
        "data": {"months": month_list, "series": data, "totals": totals},
        **_cashflow_source_metadata(coverage),
    }


def cashflow_source_net(pool: PsqlPool, months: int, max_rows: int) -> dict[str, Any]:
    if months < 1 or months > 24:
        raise ValueError("months must be between 1 and 24")
    forecast = cashflow_source_forecast(pool, months, None, None, max_rows)
    coverage, rows = _cashflow_rows_and_coverage(pool, max_rows)
    month_list = _cashflow_months(months)
    revenue_by_month = {month: 0.0 for month in month_list}
    month_set = set(month_list)
    for row in rows["sale_revenue"]:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        month = _cashflow_month(payload.get("receive_date"))
        if month in month_set:
            revenue_by_month[month] += _report_float(payload, "amount")
    cumulative = 0.0
    series: list[dict[str, Any]] = []
    for row in forecast["data"]["series"]:
        outflow = row["planned"] + row["pending"]
        inflow = revenue_by_month[row["ym"]]
        net = inflow - outflow
        cumulative += net
        series.append(
            {
                "ym": row["ym"],
                "inflow": round(inflow, 2),
                "outflow": round(outflow, 2),
                "net": round(net, 2),
                "cumulativeNet": round(cumulative, 2),
            }
        )
    return {
        "success": True,
        "code": 0,
        "data": {"series": series},
        **_cashflow_source_metadata(coverage),
    }


def cashflow_source_gap_alert(
    pool: PsqlPool, horizon_days: int, max_rows: int,
) -> dict[str, Any]:
    if horizon_days < 7 or horizon_days > 365:
        raise ValueError("horizon_days must be between 7 and 365")
    coverage, rows = _cashflow_rows_and_coverage(pool, max_rows)
    today = date.today()
    end_date = today + timedelta(days=horizon_days)
    buckets: dict[str, dict[str, Any]] = {}

    def bucket(day: date) -> dict[str, Any]:
        monday = day - timedelta(days=day.weekday())
        key = monday.isoformat()
        if key not in buckets:
            buckets[key] = {"weekStart": key, "in": 0.0, "out": 0.0, "outItems": [], "inItems": []}
        return buckets[key]

    contracts = _cashflow_contract_map(rows["cb_contract"])
    for row in rows["cb_contract_milestone"]:
        payload = row["payload"]
        if payload.get("deleted_at") or _report_text(payload, "trigger_type") != "time":
            continue
        if _report_text(payload, "state") not in {"pending", "reached"}:
            continue
        day = _report_date(payload.get("plan_date"))
        if day is None or day < today or day > end_date:
            continue
        contract = contracts.get(str(payload.get("contract_guid") or ""), {})
        target = bucket(day)
        amount = _report_float(payload, "plan_amount")
        target["out"] += amount
        target["outItems"].append(
            {"subject": _report_text(contract, "contract_name"), "amount": amount, "kind": "milestone"}
        )
    for row in rows["sale_revenue"]:
        payload = row["payload"]
        if payload.get("deleted_at") or _report_text(payload, "status") != "pending":
            continue
        day = _report_date(payload.get("receive_date"))
        if day is None or day < today or day > end_date:
            continue
        target = bucket(day)
        amount = _report_float(payload, "amount")
        target["in"] += amount
        target["inItems"].append({"subject": _report_text(payload, "customer_name"), "amount": amount})
    weeks: list[dict[str, Any]] = []
    for key in sorted(buckets):
        row = buckets[key]
        gap = round(row["out"] - row["in"], 2)
        weeks.append({**row, "gap": gap, "alert": gap > 0})
    gap_weeks = [row for row in weeks if row["alert"]]
    return {
        "success": True,
        "code": 0,
        "data": {
            "weeks": weeks,
            "gapWeeks": gap_weeks,
            "totalGap": round(sum(row["gap"] for row in gap_weeks), 2),
            "horizonDays": horizon_days,
        },
        **_cashflow_source_metadata(coverage),
    }


def cashflow_source_forecast_v3(
    pool: PsqlPool, months: int, proj_guid: str, max_rows: int,
) -> dict[str, Any]:
    if months < 1 or months > 24:
        raise ValueError("months must be between 1 and 24")
    if not IDENTIFIER.fullmatch(proj_guid):
        raise ValueError("invalid proj_guid")
    coverage, rows = _cashflow_rows_and_coverage(pool, max_rows)
    month_list = _cashflow_months(months)
    month_set = set(month_list)
    versions = [
        row["payload"] for row in rows["cb_plan_version"]
        if not row["payload"].get("deleted_at")
        and str(row["payload"].get("proj_guid") or "") == proj_guid
    ]
    active = next(
        (row for row in versions if _srm_source_bool(row, "is_active")),
        versions[0] if versions else {},
    )
    plan_version = _report_text(active, "plan_version", "baseline")
    leaves = [
        row["payload"] for row in rows["cb_subject_dict"]
        if not row["payload"].get("deleted_at")
        and str(row["payload"].get("proj_guid") or "") == proj_guid
        and _report_text(row["payload"], "plan_version", "baseline") == plan_version
    ]
    contracts = [
        row["payload"] for row in rows["cb_contract"]
        if not row["payload"].get("deleted_at")
        and str(row["payload"].get("proj_guid") or "") == proj_guid
        and _report_text(row["payload"], "cb_state") in {"signed", "paid", "approving"}
    ]
    total_a = sum(_report_float(row, "plan_amount") for row in leaves)
    total_d = sum(
        (_report_float(row, "ht_amount") + _report_float(row, "sum_alter_amount")) / 10000
        for row in contracts if _report_text(row, "cb_state") in {"signed", "paid"}
    )
    total_e = sum(
        (_report_float(row, "ht_amount") + _report_float(row, "sum_alter_amount")) / 10000
        for row in contracts if _report_text(row, "cb_state") == "approving"
    )
    total_fg = sum(max(0.0, _report_float(row, "plan_amount")) for row in leaves)
    total_fg = max(0.0, total_fg - total_d - total_e) + total_d * 0.05
    revenue: dict[str, float] = {month: 0.0 for month in month_list}
    for row in rows["sale_revenue"]:
        payload = row["payload"]
        if payload.get("deleted_at") or str(payload.get("proj_guid") or "") != proj_guid:
            continue
        if _report_text(payload, "status") != "expected":
            continue
        month = _cashflow_month(payload.get("receive_date"))
        if month in month_set:
            revenue[month] += _report_float(payload, "amount") / 10000
    fg_monthly = total_fg / months
    cumulative = 0.0
    series: list[dict[str, Any]] = []
    for index, month in enumerate(month_list):
        inflow = revenue[month]
        outflow = (total_e if index == 0 else 0.0) + fg_monthly
        net = inflow - outflow
        cumulative += net
        series.append(
            {
                "ym": month,
                "inflow": round(inflow, 2),
                "outflow": round(outflow, 2),
                "net": round(net, 2),
                "cumNet": round(cumulative, 2),
                "gap": round(max(0.0, -cumulative), 2),
            }
        )
    totals = {
        "A_total": round(total_a, 2),
        "D_total": round(total_d, 2),
        "E_total": round(total_e, 2),
        "FG_total": round(total_fg, 2),
        "inflow_total": round(sum(row["inflow"] for row in series), 2),
        "outflow_total": round(sum(row["outflow"] for row in series), 2),
        "gap_total": round(sum(row["gap"] for row in series), 2),
    }
    return {
        "success": True,
        "code": 0,
        "data": {"projGuid": proj_guid, "planVersion": plan_version, "months": month_list, "series": series, "totals": totals},
        **_cashflow_source_metadata(coverage),
    }


def _cbs_rows_and_coverage(
    pool: PsqlPool, max_rows: int,
) -> tuple[dict[str, int], dict[str, list[dict[str, Any]]]]:
    limit = max(max_rows, 500)
    rows = {
        table: _raw_source_rows(pool, table, limit, CBS_SOURCE_TABLES)
        for table in sorted(CBS_SOURCE_TABLES)
    }
    return {table: len(values) for table, values in rows.items()}, rows


def _cbs_version(
    rows: list[dict[str, Any]], proj_guid: str, requested: str | None,
) -> str:
    if requested:
        return requested
    active = next(
        (
            row["payload"] for row in rows
            if not row["payload"].get("deleted_at")
            and str(row["payload"].get("proj_guid") or "") == proj_guid
            and _srm_source_bool(row["payload"], "is_active")
        ),
        None,
    )
    return _report_text(active or {}, "plan_version", "baseline")


def cbs_source_r_master(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage, rows = _cbs_rows_and_coverage(pool, max_rows)
    items = []
    for row in rows["cb_r_master"]:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        items.append(
            {
                "r_code": _report_text(payload, "r_code"),
                "r_name": _report_text(payload, "r_name"),
                "r_kind": _report_text(payload, "r_kind"),
                "formula": _report_text(payload, "formula"),
                "display_order": _report_float(payload, "display_order"),
                "is_live": _srm_source_bool(payload, "is_live", True),
            }
        )
    items.sort(key=lambda item: (item["display_order"], item["r_code"]))
    return {"success": True, "code": 0, "data": items, **_cbs_source_metadata(coverage)}


def cbs_source_dict(
    pool: PsqlPool,
    proj_guid: str,
    plan_version: str | None,
    r_code: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(proj_guid):
        raise ValueError("invalid proj_guid")
    for value, label in ((plan_version, "plan_version"), (r_code, "r_code")):
        if value is not None and not IDENTIFIER.fullmatch(value):
            raise ValueError(f"invalid {label}")
    coverage, rows = _cbs_rows_and_coverage(pool, max_rows)
    version = _cbs_version(rows["cb_plan_version"], proj_guid, plan_version)
    items = []
    for row in rows["cb_subject_dict"]:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        if str(payload.get("proj_guid") or "") != proj_guid:
            continue
        if _report_text(payload, "plan_version", "baseline") != version:
            continue
        if r_code is not None and _report_text(payload, "r_code") != r_code:
            continue
        items.append(
            {
                "dict_guid": _report_text(payload, "dict_guid", row["record_id"]),
                "l3_code": _report_text(payload, "l3_code"),
                "r_code": _report_text(payload, "r_code"),
                "l2_code": _report_text(payload, "l2_code"),
                "l2_name": _report_text(payload, "l2_name"),
                "subject": _report_text(payload, "subject"),
                "plan_amount": _report_float(payload, "plan_amount"),
                "src": _report_text(payload, "src"),
            }
        )
    items.sort(key=lambda item: item["l3_code"])
    return {
        "success": True,
        "code": 0,
        "data": {"planVersion": version, "items": items},
        **_cbs_source_metadata(coverage),
    }


def cbs_source_f_balance(
    pool: PsqlPool,
    proj_guid: str,
    l3_code: str,
    plan_version: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(proj_guid) or not IDENTIFIER.fullmatch(l3_code):
        raise ValueError("invalid CBS identifier")
    coverage, rows = _cbs_rows_and_coverage(pool, max_rows)
    version = _cbs_version(rows["cb_plan_version"], proj_guid, plan_version or "execution")
    leaf = next(
        (
            row["payload"] for row in rows["cb_subject_dict"]
            if not row["payload"].get("deleted_at")
            and str(row["payload"].get("proj_guid") or "") == proj_guid
            and _report_text(row["payload"], "plan_version", "baseline") == version
            and _report_text(row["payload"], "l3_code") == l3_code
        ),
        None,
    )
    if leaf is None:
        return {
            "success": False,
            "code": 43001,
            "message": "CBS leaf not found",
            "data": None,
            **_cbs_source_metadata(coverage),
        }
    plan_amount = _report_float(leaf, "plan_amount")
    used = 0.0
    for row in rows["cb_contract"]:
        payload = row["payload"]
        if payload.get("deleted_at") or str(payload.get("proj_guid") or "") != proj_guid:
            continue
        if _report_text(payload, "l3_code") != l3_code:
            continue
        if _report_text(payload, "cb_state") in {"signed", "paid", "approving"}:
            used += (
                _report_float(payload, "ht_amount")
                + _report_float(payload, "sum_alter_amount")
            ) / 10000
    expense_by_id = {
        str(row["payload"].get("expense_guid") or row["record_id"]): row["payload"]
        for row in rows["vcb_expense"]
        if not row["payload"].get("deleted_at")
    }
    for row in rows["cb_expense_split"]:
        payload = row["payload"]
        expense = expense_by_id.get(str(payload.get("expense_guid") or ""), {})
        if _report_text(payload, "l3_code") == l3_code and _report_text(
            expense, "apply_state"
        ) in {"approving", "approved", "Approved"}:
            used += _report_float(payload, "amount") / 10000
    return {
        "success": True,
        "code": 0,
        "data": {
            "planVersion": version,
            "l3Code": l3_code,
            "A": round(plan_amount, 2),
            "usedDplusE": round(used, 2),
            "F": round(max(0.0, plan_amount - used), 2),
        },
        **_cbs_source_metadata(coverage),
    }


def cbs_source_versions(
    pool: PsqlPool, proj_guid: str, max_rows: int,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(proj_guid):
        raise ValueError("invalid proj_guid")
    coverage, rows = _cbs_rows_and_coverage(pool, max_rows)
    result = []
    for row in rows["cb_plan_version"]:
        payload = row["payload"]
        if payload.get("deleted_at") or str(payload.get("proj_guid") or "") != proj_guid:
            continue
        result.append(
            {
                "plan_version": _report_text(payload, "plan_version"),
                "version_name": _report_text(payload, "version_name"),
                "parent_version": _report_text(payload, "parent_version"),
                "is_active": _srm_source_bool(payload, "is_active"),
                "frozen_at": _report_text(payload, "frozen_at"),
                "frozen_by": _report_text(payload, "frozen_by"),
                "created_at": _report_text(payload, "created_at"),
                "created_by": _report_text(payload, "created_by"),
            }
        )
    result.sort(key=lambda item: item["created_at"])
    return {"success": True, "code": 0, "data": result, **_cbs_source_metadata(coverage)}


def cbs_source_versions_compare(
    pool: PsqlPool,
    proj_guid: str,
    version_a: str,
    version_b: str,
    version_c: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(proj_guid):
        raise ValueError("invalid proj_guid")
    for value, label in ((version_a, "version_a"), (version_b, "version_b"), (version_c, "version_c")):
        if value is not None and not IDENTIFIER.fullmatch(value):
            raise ValueError(f"invalid {label}")
    coverage, rows = _cbs_rows_and_coverage(pool, max_rows)
    maps: list[dict[str, dict[str, Any]]] = []
    for version in (version_a, version_b, version_c):
        if version is None:
            maps.append({})
            continue
        maps.append(
            {
                _report_text(row["payload"], "l3_code"): row["payload"]
                for row in rows["cb_subject_dict"]
                if not row["payload"].get("deleted_at")
                and str(row["payload"].get("proj_guid") or "") == proj_guid
                and _report_text(row["payload"], "plan_version", "baseline") == version
            }
        )
    codes = sorted(set().union(*(set(value) for value in maps)))
    differences = []
    for code in codes:
        values = [mapping.get(code) for mapping in maps]
        amounts = [None if value is None else _report_float(value, "plan_amount") for value in values]
        if amounts[0] == amounts[1] and (version_c is None or amounts[0] == amounts[2]):
            continue
        source = next((value for value in values if value is not None), {})
        differences.append(
            {
                "l3Code": code,
                "rCode": _report_text(source, "r_code"),
                "l2Name": _report_text(source, "l2_name"),
                "subject": _report_text(source, "subject"),
                "a": amounts[0],
                "b": amounts[1],
                "c": amounts[2] if version_c is not None else None,
                "delta": round((amounts[1] or 0.0) - (amounts[0] or 0.0), 2),
            }
        )
    return {
        "success": True,
        "code": 0,
        "data": {"rows": differences},
        **_cbs_source_metadata(coverage),
    }


def cbs_source_r0_queue(
    pool: PsqlPool, proj_guid: str | None, max_rows: int,
) -> dict[str, Any]:
    if proj_guid is not None and not IDENTIFIER.fullmatch(proj_guid):
        raise ValueError("invalid proj_guid")
    coverage, rows = _cbs_rows_and_coverage(pool, max_rows)
    items = []
    for row in rows["cb_contract"]:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        if proj_guid is not None and str(payload.get("proj_guid") or "") != proj_guid:
            continue
        if _report_text(payload, "r_code") not in {"", "R0"}:
            continue
        items.append(
            {
                "refId": _report_text(payload, "contract_guid", row["record_id"]),
                "kind": "contract",
                "name": _report_text(payload, "contract_name"),
                "amount": _report_float(payload, "ht_amount"),
                "rCode": _report_text(payload, "r_code", "R0") or "R0",
                "l3Code": _report_text(payload, "l3_code"),
            }
        )
    return {
        "success": True,
        "code": 0,
        "data": {"items": items},
        **_cbs_source_metadata(coverage),
    }


def cbs_source_approval_rules(
    pool: PsqlPool, biz_type: str | None, max_rows: int,
) -> dict[str, Any]:
    if biz_type is not None and len(biz_type) > 128:
        raise ValueError("invalid biz_type")
    coverage, rows = _cbs_rows_and_coverage(pool, max_rows)
    result = []
    for row in rows["wf_approval_rule"]:
        payload = row["payload"]
        if payload.get("deleted_at") or (biz_type is not None and _report_text(payload, "biz_type") != biz_type):
            continue
        result.append(
            {
                "rule_guid": _report_text(payload, "rule_guid", row["record_id"]),
                "biz_type": _report_text(payload, "biz_type"),
                "threshold": _report_float(payload, "threshold"),
                "actor_user_id": _report_text(payload, "actor_user_id"),
                "description": _report_text(payload, "description"),
                "display_order": _report_float(payload, "display_order"),
            }
        )
    result.sort(key=lambda item: (item["biz_type"], item["threshold"]))
    return {"success": True, "code": 0, "data": result, **_cbs_source_metadata(coverage)}


def cbs_source_approval_pick(
    pool: PsqlPool, biz_type: str, amount: float, max_rows: int,
) -> dict[str, Any]:
    if not biz_type or len(biz_type) > 128:
        raise ValueError("invalid biz_type")
    coverage, rows = _cbs_rows_and_coverage(pool, max_rows)
    candidates = [
        row["payload"] for row in rows["wf_approval_rule"]
        if not row["payload"].get("deleted_at")
        and _report_text(row["payload"], "biz_type") == biz_type
        and _report_float(row["payload"], "threshold") <= amount
    ]
    selected = max(candidates, key=lambda value: _report_float(value, "threshold"), default=None)
    data = None if selected is None else {
        "actor_user_id": _report_text(selected, "actor_user_id"),
        "threshold": _report_float(selected, "threshold"),
        "description": _report_text(selected, "description"),
    }
    return {"success": True, "code": 0, "data": data, **_cbs_source_metadata(coverage)}


def cbs_source_changes(
    pool: PsqlPool, proj_guid: str | None, contract_guid: str | None, max_rows: int,
) -> dict[str, Any]:
    for value, label in ((proj_guid, "proj_guid"), (contract_guid, "contract_guid")):
        if value is not None and not IDENTIFIER.fullmatch(value):
            raise ValueError(f"invalid {label}")
    coverage, rows = _cbs_rows_and_coverage(pool, max_rows)
    contracts = _cashflow_contract_map(rows["cb_contract"])
    result = []
    for row in rows["cb_change_apply"]:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        if proj_guid is not None and str(payload.get("proj_guid") or "") != proj_guid:
            continue
        if contract_guid is not None and str(payload.get("contract_guid") or "") != contract_guid:
            continue
        contract = contracts.get(str(payload.get("contract_guid") or ""), {})
        result.append(
            {
                **payload,
                "change_guid": _report_text(payload, "change_guid", row["record_id"]),
                "contract_name": _report_text(contract, "contract_name"),
                "contract_code": _report_text(contract, "contract_code"),
            }
        )
    result.sort(key=lambda value: _report_text(value, "created_at"), reverse=True)
    return {"success": True, "code": 0, "data": result, **_cbs_source_metadata(coverage)}


def cbs_source_demo_contracts(
    pool: PsqlPool, proj_guid: str | None, max_rows: int,
) -> dict[str, Any]:
    if proj_guid is not None and not IDENTIFIER.fullmatch(proj_guid):
        raise ValueError("invalid proj_guid")
    coverage, rows = _cbs_rows_and_coverage(pool, max_rows)
    result = []
    for row in rows["cb_contract"]:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        if proj_guid is not None and str(payload.get("proj_guid") or "") != proj_guid:
            continue
        result.append(
            {
                "id": _report_text(payload, "contract_guid", row["record_id"]),
                "code": _report_text(payload, "contract_code"),
                "name": _report_text(payload, "contract_name"),
                "rCode": _report_text(payload, "r_code", "R0") or "R0",
                "l3Code": _report_text(payload, "l3_code"),
                "amount": round(_report_float(payload, "ht_amount") / 10000, 2),
                "alterAmount": round(_report_float(payload, "sum_alter_amount") / 10000, 2),
                "state": _report_text(payload, "cb_state", "draft") or "draft",
            }
        )
    result.sort(key=lambda value: value["code"], reverse=True)
    return {"success": True, "code": 0, "data": result, **_cbs_source_metadata(coverage)}


def _fund_rows_and_coverage(
    pool: PsqlPool, max_rows: int,
) -> tuple[dict[str, int], dict[str, list[dict[str, Any]]]]:
    limit = max(max_rows, 500)
    rows = {
        table: _raw_source_rows(pool, table, limit, FUND_SOURCE_TABLES)
        for table in sorted(FUND_SOURCE_TABLES)
    }
    return {table: len(values) for table, values in rows.items()}, rows


def fund_source_plans(
    pool: PsqlPool,
    proj_guid: str | None,
    period: str | None,
    direction: str | None,
    max_rows: int,
) -> dict[str, Any]:
    for value, label in ((proj_guid, "proj_guid"), (period, "period"), (direction, "direction")):
        if value is not None and (not value or len(value) > 128):
            raise ValueError(f"invalid {label}")
    if direction is not None and direction not in {"in", "out"}:
        raise ValueError("direction must be in or out")
    coverage, rows = _fund_rows_and_coverage(pool, max_rows)
    projects = {
        str(row["payload"].get("proj_guid") or row["record_id"]): row["payload"]
        for row in rows["ep_project"]
        if not row["payload"].get("deleted_at")
    }
    result = []
    for row in rows["fund_plan"]:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        if proj_guid is not None and str(payload.get("proj_guid") or "") != proj_guid:
            continue
        if period is not None and _report_text(payload, "plan_period") != period:
            continue
        if direction is not None and _report_text(payload, "direction") != direction:
            continue
        project = projects.get(str(payload.get("proj_guid") or ""), {})
        result.append(
            {
                "plan_guid": _report_text(payload, "plan_guid", row["record_id"]),
                "plan_code": _report_text(payload, "plan_code"),
                "proj_guid": _report_text(payload, "proj_guid"),
                "proj_name": _report_text(project, "proj_name"),
                "bu_guid": _report_text(payload, "bu_guid"),
                "plan_period": _report_text(payload, "plan_period"),
                "direction": _report_text(payload, "direction"),
                "category": _report_text(payload, "category"),
                "r_code": _report_text(payload, "r_code"),
                "plan_amount": _report_float(payload, "plan_amount"),
                "actual_amount": _report_float(payload, "actual_amount"),
                "remark": _report_text(payload, "remark"),
                "created_at": _report_text(payload, "created_at"),
            }
        )
    result.sort(key=lambda value: (value["plan_period"], value["direction"], value["plan_code"]))
    return {"success": True, "code": 0, "data": result, **_fund_source_metadata(coverage)}


def fund_source_gap_analysis(
    pool: PsqlPool, proj_guid: str, max_rows: int,
) -> dict[str, Any]:
    if not IDENTIFIER.fullmatch(proj_guid):
        raise ValueError("invalid proj_guid")
    coverage, rows = _fund_rows_and_coverage(pool, max_rows)
    grouped: dict[str, dict[str, float]] = {}
    for row in rows["fund_plan"]:
        payload = row["payload"]
        if payload.get("deleted_at") or str(payload.get("proj_guid") or "") != proj_guid:
            continue
        period = _report_text(payload, "plan_period")
        item = grouped.setdefault(
            period,
            {"planIn": 0.0, "actualIn": 0.0, "planOut": 0.0, "actualOut": 0.0},
        )
        if _report_text(payload, "direction") == "in":
            item["planIn"] += _report_float(payload, "plan_amount")
            item["actualIn"] += _report_float(payload, "actual_amount")
        elif _report_text(payload, "direction") == "out":
            item["planOut"] += _report_float(payload, "plan_amount")
            item["actualOut"] += _report_float(payload, "actual_amount")
    cumulative = 0.0
    series = []
    for period in sorted(grouped):
        item = grouped[period]
        net = item["planIn"] - item["planOut"]
        cumulative += net
        series.append(
            {
                "period": period,
                **{key: round(value, 2) for key, value in item.items()},
                "net": round(net, 2),
                "cumNet": round(cumulative, 2),
                "gap": round(max(0.0, -cumulative), 2),
            }
        )
    return {
        "success": True,
        "code": 0,
        "data": {"series": series},
        **_fund_source_metadata(coverage),
    }


def fund_source_dispatches(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage, rows = _fund_rows_and_coverage(pool, max_rows)
    result = []
    for row in rows["fund_dispatch"]:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        result.append(
            {
                "dispatch_guid": _report_text(payload, "dispatch_guid", row["record_id"]),
                "dispatch_code": _report_text(payload, "dispatch_code"),
                "proj_guid": _report_text(payload, "proj_guid"),
                "bu_guid": _report_text(payload, "bu_guid"),
                "from_proj": _report_text(payload, "from_proj"),
                "to_proj": _report_text(payload, "to_proj"),
                "amount": _report_float(payload, "amount"),
                "reason": _report_text(payload, "reason"),
                "dispatch_date": _report_text(payload, "dispatch_date"),
                "state": _report_text(payload, "state"),
                "created_at": _report_text(payload, "created_at"),
            }
        )
    result.sort(key=lambda value: value["created_at"], reverse=True)
    return {"success": True, "code": 0, "data": result, **_fund_source_metadata(coverage)}


def _warning_rows_and_coverage(
    pool: PsqlPool, max_rows: int,
) -> tuple[dict[str, int], dict[str, list[dict[str, Any]]]]:
    limit = max(max_rows, 500)
    rows = {
        table: _raw_source_rows(pool, table, limit, WARNING_SOURCE_TABLES)
        for table in sorted(WARNING_SOURCE_TABLES)
    }
    return {table: len(values) for table, values in rows.items()}, rows


def _warning_finding(
    code: str,
    name: str,
    severity: str,
    biz_type: str,
    data_guid: str,
    title: str,
    detail: str = "",
) -> dict[str, Any]:
    warning_guid = f"source:{code}:{data_guid}"
    return {
        "warningGuid": warning_guid,
        "ruleCode": code,
        "ruleName": name,
        "severity": severity,
        "bizType": biz_type,
        "bizDataGuid": data_guid,
        "title": title,
        "detail": detail,
        "firstDetectedAt": None,
        "lastScanAt": None,
        "resolvedAt": None,
        "resolvedBy": None,
        "resolvedNote": None,
        "status": "open",
        "sourceKind": "observed_imported",
    }


def _warning_findings(
    rows: dict[str, list[dict[str, Any]]],
) -> list[dict[str, Any]]:
    definitions = {code: (name, severity, biz_type) for code, name, severity, biz_type in WARNING_RULE_DEFINITIONS}
    findings: list[dict[str, Any]] = []
    projects = [row["payload"] for row in rows["ep_project"] if not row["payload"].get("deleted_at")]
    contracts = [row["payload"] for row in rows["cb_contract"] if not row["payload"].get("deleted_at")]
    applies = [row["payload"] for row in rows["cb_htfk_apply"] if not row["payload"].get("deleted_at")]
    costs = [row["payload"] for row in rows["cb_cost"] if not row["payload"].get("deleted_at")]
    expenses = [row["payload"] for row in rows["vcb_expense"] if not row["payload"].get("deleted_at")]
    loans = [row["payload"] for row in rows["vcb_loan_simple"] if not row["payload"].get("deleted_at")]
    tasks = [row["payload"] for row in rows["jd_task"] if not row["payload"].get("deleted_at")]
    users = [row["payload"] for row in rows["sys_user"] if not row["payload"].get("deleted_at")]
    definition = lambda code: (code, definitions[code][0], definitions[code][1], definitions[code][2])

    for payload in projects:
        if not _report_text(payload, "bu_guid"):
            code, name, severity, biz_type = definition("W001")
            project_id = _report_text(payload, "proj_guid")
            findings.append(_warning_finding(code, name, severity, biz_type, project_id, _report_text(payload, "proj_name")))
    for payload in contracts:
        contract_id = _report_text(payload, "contract_guid")
        if not _report_text(payload, "proj_guid"):
            code, name, severity, biz_type = definition("W002")
            findings.append(_warning_finding(code, name, severity, biz_type, contract_id, _report_text(payload, "contract_code") + " " + _report_text(payload, "contract_name")))
    for payload in applies:
        if not _report_text(payload, "contract_guid"):
            code, name, severity, biz_type = definition("W003")
            apply_id = _report_text(payload, "htfk_apply_guid")
            findings.append(_warning_finding(code, name, severity, biz_type, apply_id, _report_text(payload, "apply_code")))
    paid_by_contract: dict[str, float] = {}
    for payload in applies:
        if _report_text(payload, "apply_state") == "已审核":
            contract_id = _report_text(payload, "contract_guid")
            paid_by_contract[contract_id] = paid_by_contract.get(contract_id, 0.0) + _report_float(payload, "apply_amount")
    for payload in contracts:
        contract_id = _report_text(payload, "contract_guid")
        paid = paid_by_contract.get(contract_id, 0.0)
        total = _report_float(payload, "ht_amount") + _report_float(payload, "sum_alter_amount")
        if contract_id and paid > total and total >= 0:
            code, name, severity, biz_type = definition("W004")
            findings.append(_warning_finding(code, name, severity, biz_type, contract_id, _report_text(payload, "contract_code"), f"合同总额 {total} / 已付 {paid}"))
    end_cost_projects = {
        _report_text(payload, "proj_guid")
        for payload in costs
        if _srm_source_bool(payload, "is_end_cost")
    }
    for payload in projects:
        if _report_text(payload, "proj_status") in {"planning", "development", "sales"}:
            project_id = _report_text(payload, "proj_guid")
            if project_id and project_id not in end_cost_projects:
                code, name, severity, biz_type = definition("W005")
                findings.append(_warning_finding(code, name, severity, biz_type, project_id, _report_text(payload, "proj_name"), "缺少动态成本末级科目"))
    splits_by_expense: dict[str, float] = {}
    for row in rows["cb_expense_split"]:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        expense_id = _report_text(payload, "expense_guid")
        splits_by_expense[expense_id] = splits_by_expense.get(expense_id, 0.0) + _report_float(payload, "amount")
    for payload in expenses:
        expense_id = _report_text(payload, "expense_guid")
        amount = _report_float(payload, "pay_amount")
        split = splits_by_expense.get(expense_id, 0.0)
        if expense_id and abs(amount - split) > 0.5:
            code, name, severity, biz_type = definition("W006")
            findings.append(_warning_finding(code, name, severity, biz_type, expense_id, _report_text(payload, "expense_code") + " " + _report_text(payload, "subject"), f"应付 {amount} / 分摊 {split}"))
    for payload in loans:
        amount = _report_float(payload, "loan_amount")
        balance = _report_float(payload, "balance_amount")
        remain = _report_float(payload, "remain_amount")
        if abs(remain - (amount - balance)) > 0.01:
            code, name, severity, biz_type = definition("W008")
            loan_id = _report_text(payload, "loan_guid")
            findings.append(_warning_finding(code, name, severity, biz_type, loan_id, _report_text(payload, "loan_code") + " / " + _report_text(payload, "subject"), f"借 {amount} / 余 {balance} / 待还 {remain}"))
    for payload in tasks:
        begin = _report_date(payload.get("plan_begin_date"))
        end = _report_date(payload.get("plan_end_date"))
        if begin is not None and end is not None and end < begin:
            code, name, severity, biz_type = definition("W009")
            task_id = _report_text(payload, "task_guid")
            findings.append(_warning_finding(code, name, severity, biz_type, task_id, _report_text(payload, "task_code") + " " + _report_text(payload, "task_name"), f"开始 {begin.isoformat()} / 完成 {end.isoformat()}"))
    names: dict[str, list[str]] = {}
    for row in rows["srm_provider"]:
        payload = row["payload"]
        if payload.get("deleted_at"):
            continue
        name = _report_text(payload, "provider_name")
        if name:
            names.setdefault(name, []).append(_report_text(payload, "provider_guid", row["record_id"]))
    for name, identifiers in names.items():
        if len(identifiers) > 1:
            code, rule_name, severity, biz_type = definition("W010")
            findings.append(_warning_finding(code, rule_name, severity, biz_type, "__agg__" + name, f"重名 {len(identifiers)} 条: {name}"))
    for payload in users:
        if not _report_text(payload, "bu_guid"):
            code, name, severity, biz_type = definition("W012")
            user_id = _report_text(payload, "user_id")
            findings.append(_warning_finding(code, name, severity, biz_type, user_id, _report_text(payload, "user_code") + " " + _report_text(payload, "emp_name")))
    findings.sort(key=lambda item: (0 if item["severity"] == "error" else 1, item["ruleCode"], item["bizDataGuid"]))
    return findings


def warning_source_list(
    pool: PsqlPool,
    status: str | None,
    rule_code: str | None,
    severity: str | None,
    biz_type: str | None,
    max_rows: int,
) -> dict[str, Any]:
    for value, label in ((status, "status"), (rule_code, "rule_code"), (severity, "severity"), (biz_type, "biz_type")):
        if value is not None and len(value) > 128:
            raise ValueError(f"invalid {label}")
    coverage, rows = _warning_rows_and_coverage(pool, max_rows)
    findings = _warning_findings(rows)
    if status is not None and status != "all":
        findings = [item for item in findings if item["status"] == status]
    if rule_code is not None:
        findings = [item for item in findings if item["ruleCode"] == rule_code]
    if severity is not None:
        findings = [item for item in findings if item["severity"] == severity]
    if biz_type is not None:
        findings = [item for item in findings if item["bizType"] == biz_type]
    return {
        "success": True,
        "code": 0,
        "data": {"total": len(findings), "rows": findings[:max_rows]},
        **_warning_source_metadata(coverage),
    }


def warning_source_badge(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    result = warning_source_list(pool, "open", None, None, None, max_rows)
    rows = result["data"]["rows"]
    return {
        "success": True,
        "code": 0,
        "data": {
            "openTotal": result["data"]["total"],
            "top": [
                {
                    "warningGuid": row["warningGuid"],
                    "ruleCode": row["ruleCode"],
                    "ruleName": row["ruleName"],
                    "severity": row["severity"],
                    "bizType": row["bizType"],
                    "title": row["title"],
                    "firstDetectedAt": row["firstDetectedAt"],
                    "status": row["status"],
                }
                for row in rows[:10]
            ],
        },
        **{key: value for key, value in result.items() if key != "data"},
    }


def warning_source_rules(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage, rows = _warning_rows_and_coverage(pool, max_rows)
    findings = _warning_findings(rows)
    counts: dict[str, int] = {}
    for finding in findings:
        counts[finding["ruleCode"]] = counts.get(finding["ruleCode"], 0) + 1
    data = [
        {
            "ruleCode": code,
            "ruleName": name,
            "severity": severity,
            "bizType": biz_type,
            "enabled": True,
            "openCount": counts.get(code, 0),
            "custom": False,
        }
        for code, name, severity, biz_type in WARNING_RULE_DEFINITIONS
    ]
    return {"success": True, "code": 0, "data": data, **_warning_source_metadata(coverage)}


def warning_source_empty_read(pool: PsqlPool, table: str, max_rows: int) -> dict[str, Any]:
    coverage, _ = _warning_rows_and_coverage(pool, max_rows)
    data: Any = []
    if table == "scans":
        data = []
    return {"success": True, "code": 0, "data": data, **_warning_source_metadata(coverage)}


def _attachment_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    """Describe the imported attachment boundary without claiming file access."""

    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "downloadable": False,
        "binary_storage": "not_imported",
    }


def _attachment_source_coverage(pool: PsqlPool, max_rows: int) -> dict[str, int]:
    return {
        table: len(
            _raw_source_rows(pool, table, max(max_rows, 500), ATTACHMENT_SOURCE_TABLES)
        )
        for table in sorted(ATTACHMENT_SOURCE_TABLES)
    }


def _attachment_text(payload: dict[str, Any], *keys: str, fallback: str = "") -> str:
    for key in keys:
        value = payload.get(key)
        if value is not None and value != "":
            return str(value)
    return fallback


def _attachment_int(payload: dict[str, Any], *keys: str) -> int:
    value = _attachment_text(payload, *keys)
    if not value:
        return 0
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return 0


def _attachment_ai(payload: dict[str, Any]) -> dict[str, Any] | None:
    value = payload.get("ai_extracted", payload.get("aiExtracted"))
    extracted: Any = None
    if isinstance(value, dict):
        extracted = value
    elif isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            parsed = None
        if isinstance(parsed, dict):
            extracted = parsed
    status = _attachment_text(payload, "ai_status", "aiStatus")
    confidence = payload.get("ai_confidence", payload.get("aiConfidence"))
    if extracted is None and not status and confidence in (None, ""):
        return None
    return {
        "extracted": extracted or {},
        "confidence": confidence,
        "status": status or "pending",
    }


def _attachment_source_rows(
    pool: PsqlPool,
    *,
    biz_type: str | None,
    biz_guid: str | None,
    uploaded_by: str | None,
    ai_status: str | None,
    keyword: str | None,
    max_rows: int,
) -> tuple[dict[str, int], list[dict[str, Any]]]:
    coverage = _attachment_source_coverage(pool, max_rows)
    raw = _raw_source_rows(pool, "attachment", max(max_rows, 500), ATTACHMENT_SOURCE_TABLES)
    users = {
        str(row["payload"].get("user_id") or row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "sys_user", max(max_rows, 500), ATTACHMENT_SOURCE_TABLES)
    }
    rows: list[dict[str, Any]] = []
    for source in raw:
        payload = source["payload"]
        if payload.get("deleted_at") or payload.get("deletedAt"):
            continue
        current_biz_type = _attachment_text(payload, "biz_type", "bizType")
        current_biz_guid = _attachment_text(payload, "biz_guid", "bizGuid")
        current_uploaded_by = _attachment_text(payload, "uploaded_by", "uploadedBy")
        current_ai_status = _attachment_text(payload, "ai_status", "aiStatus")
        file_name = _attachment_text(payload, "file_name", "fileName")
        if biz_type and current_biz_type != biz_type:
            continue
        if biz_guid and current_biz_guid != biz_guid:
            continue
        if uploaded_by and current_uploaded_by != uploaded_by:
            continue
        if ai_status and current_ai_status != ai_status:
            continue
        if keyword and keyword.lower() not in file_name.lower():
            continue
        user = users.get(current_uploaded_by, {})
        ai = _attachment_ai(payload)
        rows.append(
            {
                "attGuid": _attachment_text(payload, "att_guid", "attGuid", fallback=source["record_id"]),
                "fileName": file_name,
                "fileSize": _attachment_int(payload, "file_size", "fileSize"),
                "mimeType": _attachment_text(payload, "mime_type", "mimeType"),
                "bizType": current_biz_type,
                "bizGuid": current_biz_guid,
                "uploadedBy": current_uploaded_by,
                "uploadedByName": _attachment_text(user, "emp_name", "empName"),
                "uploadedAt": _attachment_text(payload, "uploaded_at", "uploadedAt"),
                "ai": ai,
                "downloadAvailable": False,
                "sourceKind": "imported",
            }
        )
    rows.sort(key=lambda item: (str(item["uploadedAt"]), str(item["attGuid"])), reverse=True)
    return coverage, rows[:max_rows]


def attachment_source_list(
    pool: PsqlPool,
    biz_type: str | None,
    biz_guid: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Read attachments linked to one business aggregate, if imported."""

    coverage, rows = _attachment_source_rows(
        pool,
        biz_type=biz_type,
        biz_guid=biz_guid,
        uploaded_by=None,
        ai_status=None,
        keyword=None,
        max_rows=max_rows,
    )
    return {"success": True, "code": 0, "data": rows, **_attachment_source_metadata(coverage)}


def attachment_source_all(
    pool: PsqlPool,
    biz_type: str | None,
    uploaded_by: str | None,
    ai_status: str | None,
    keyword: str | None,
    max_rows: int,
) -> dict[str, Any]:
    """Read the ERP attachment search shape from imported envelopes."""

    coverage, rows = _attachment_source_rows(
        pool,
        biz_type=biz_type,
        biz_guid=None,
        uploaded_by=uploaded_by,
        ai_status=ai_status,
        keyword=keyword,
        max_rows=max_rows,
    )
    return {
        "success": True,
        "code": 0,
        "data": {"total": len(rows), "rows": rows},
        **_attachment_source_metadata(coverage),
    }


def attachment_source_stats(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    """Return attachment counts without exposing paths or binary content."""

    coverage, rows = _attachment_source_rows(
        pool,
        biz_type=None,
        biz_guid=None,
        uploaded_by=None,
        ai_status=None,
        keyword=None,
        max_rows=max_rows,
    )
    by_biz: dict[str, dict[str, Any]] = {}
    by_ai: dict[str, int] = {}
    for row in rows:
        biz = str(row["bizType"])
        entry = by_biz.setdefault(biz, {"bizType": biz, "count": 0, "bytes": 0})
        entry["count"] += 1
        entry["bytes"] += int(row["fileSize"])
        ai = row.get("ai") or {}
        ai_state = str(ai.get("status") or "unprocessed")
        by_ai[ai_state] = by_ai.get(ai_state, 0) + 1
    total_bytes = sum(int(row["fileSize"]) for row in rows)
    return {
        "success": True,
        "code": 0,
        "data": {
            "total": {"count": len(rows), "bytes": total_bytes},
            "byBizType": sorted(by_biz.values(), key=lambda item: (-item["count"], item["bizType"])),
            "byAiStatus": [
                {"aiStatus": status, "count": count}
                for status, count in sorted(by_ai.items())
            ],
        },
        **_attachment_source_metadata(coverage),
    }


def attachment_source_download(
    pool: PsqlPool,
    attachment_id: str,
    max_rows: int,
) -> dict[str, Any]:
    """Preserve the source download boundary without exposing a fake binary.

    The controlled export contains no attachment binary store.  A missing
    metadata row therefore keeps the source 43001 response, while a metadata
    row whose file payload is absent keeps the source 43002 response.  Neither
    case returns a fixture path or a local file.
    """

    if not IDENTIFIER.fullmatch(attachment_id):
        raise ValueError("invalid attachment_id")
    coverage = _attachment_source_coverage(pool, max_rows)
    raw = _raw_source_rows(pool, "attachment", max(max_rows, 500), ATTACHMENT_SOURCE_TABLES)
    row = next(
        (
            source
            for source in raw
            if _attachment_text(
                source["payload"], "att_guid", "attGuid", fallback=source["record_id"]
            )
            == attachment_id
            and not source["payload"].get("deleted_at")
            and not source["payload"].get("deletedAt")
        ),
        None,
    )
    metadata = _attachment_source_metadata(coverage)
    if row is None:
        return {
            "success": False,
            "code": 43001,
            "message": "附件不存在",
            **metadata,
        }
    return {
        "success": False,
        "code": 43002,
        "message": "文件二进制未导入",
        "attGuid": attachment_id,
        **metadata,
    }


def _marketing_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
    }


def _marketing_source_coverage(pool: PsqlPool, max_rows: int) -> dict[str, int]:
    return {
        table: len(
            _raw_source_rows(pool, table, max(max_rows, 500), MARKETING_SOURCE_TABLES)
        )
        for table in sorted(MARKETING_SOURCE_TABLES)
    }


def _marketing_text(payload: dict[str, Any], *keys: str, fallback: str = "") -> str:
    for key in keys:
        value = payload.get(key)
        if value is not None and value != "":
            return str(value)
    return fallback


def _marketing_number(payload: dict[str, Any], *keys: str) -> int | float:
    value = _marketing_text(payload, *keys)
    if not value:
        return 0
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0
    return int(number) if number.is_integer() else number


def marketing_source_campaigns(
    pool: PsqlPool,
    proj_guid: str | None,
    state: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if proj_guid is not None and not IDENTIFIER.fullmatch(proj_guid):
        raise ValueError("invalid proj_guid")
    if state is not None and len(state) > 64:
        raise ValueError("invalid state")
    coverage = _marketing_source_coverage(pool, max_rows)
    result: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "mkt_campaign", max(max_rows, 500), MARKETING_SOURCE_TABLES):
        payload = source["payload"]
        current_proj = _marketing_text(payload, "proj_guid", "projGuid")
        current_state = _marketing_text(payload, "state")
        if proj_guid and current_proj != proj_guid:
            continue
        if state and current_state != state:
            continue
        result.append(
            {
                "campaignGuid": _marketing_text(payload, "campaign_guid", "campaignGuid", fallback=source["record_id"]),
                "campaignCode": _marketing_text(payload, "campaign_code", "campaignCode"),
                "projGuid": current_proj,
                "buGuid": _marketing_text(payload, "bu_guid", "buGuid"),
                "name": _marketing_text(payload, "name"),
                "campaignType": _marketing_text(payload, "campaign_type", "campaignType"),
                "budget": _marketing_number(payload, "budget"),
                "actualCost": _marketing_number(payload, "actual_cost", "actualCost"),
                "startDate": _marketing_text(payload, "start_date", "startDate"),
                "endDate": _marketing_text(payload, "end_date", "endDate"),
                "state": current_state,
                "goal": _marketing_text(payload, "goal"),
                "remark": _marketing_text(payload, "remark"),
                "l3Code": _marketing_text(payload, "l3_code", "l3Code"),
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda item: (str(item["startDate"]), str(item["campaignCode"])), reverse=True)
    return {"success": True, "code": 0, "data": result[:max_rows], **_marketing_source_metadata(coverage)}


def marketing_source_placements(
    pool: PsqlPool,
    campaign_guid: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if campaign_guid is not None and not IDENTIFIER.fullmatch(campaign_guid):
        raise ValueError("invalid campaign_guid")
    coverage = _marketing_source_coverage(pool, max_rows)
    campaigns = {
        _marketing_text(row["payload"], "campaign_guid", "campaignGuid", fallback=row["record_id"]): row["payload"]
        for row in _raw_source_rows(pool, "mkt_campaign", max(max_rows, 500), MARKETING_SOURCE_TABLES)
    }
    result: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "mkt_placement", max(max_rows, 500), MARKETING_SOURCE_TABLES):
        payload = source["payload"]
        current_campaign = _marketing_text(payload, "campaign_guid", "campaignGuid")
        if campaign_guid and current_campaign != campaign_guid:
            continue
        campaign = campaigns.get(current_campaign, {})
        result.append(
            {
                "placementGuid": _marketing_text(payload, "placement_guid", "placementGuid", fallback=source["record_id"]),
                "placementCode": _marketing_text(payload, "placement_code", "placementCode"),
                "campaignGuid": current_campaign,
                "campaignName": _marketing_text(campaign, "name"),
                "channelGuid": _marketing_text(payload, "channel_guid", "channelGuid"),
                "channelName": _marketing_text(payload, "channel_name", "channelName"),
                "amount": _marketing_number(payload, "amount"),
                "placeDate": _marketing_text(payload, "place_date", "placeDate"),
                "durationDays": _marketing_number(payload, "duration_days", "durationDays"),
                "state": _marketing_text(payload, "state"),
                "impressions": _marketing_number(payload, "impressions"),
                "clicks": _marketing_number(payload, "clicks"),
                "leads": _marketing_number(payload, "leads"),
                "l3Code": _marketing_text(payload, "l3_code", "l3Code"),
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda item: (str(item["placeDate"]), str(item["placementCode"])), reverse=True)
    return {"success": True, "code": 0, "data": result[:max_rows], **_marketing_source_metadata(coverage)}


def marketing_source_channels(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = _marketing_source_coverage(pool, max_rows)
    placements = _raw_source_rows(pool, "mkt_placement", max(max_rows, 500), MARKETING_SOURCE_TABLES)
    counts: dict[str, tuple[int, int | float]] = {}
    for row in placements:
        payload = row["payload"]
        channel_guid = _marketing_text(payload, "channel_guid", "channelGuid")
        if not channel_guid:
            continue
        count, total = counts.get(channel_guid, (0, 0))
        counts[channel_guid] = (count + 1, total + _marketing_number(payload, "amount"))
    result: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "mkt_channel", max(max_rows, 500), MARKETING_SOURCE_TABLES):
        payload = source["payload"]
        guid = _marketing_text(payload, "channel_guid", "channelGuid", fallback=source["record_id"])
        count, total = counts.get(guid, (0, _marketing_number(payload, "total_cost", "totalCost")))
        result.append(
            {
                "channelGuid": guid,
                "channelCode": _marketing_text(payload, "channel_code", "channelCode"),
                "name": _marketing_text(payload, "name"),
                "channelType": _marketing_text(payload, "channel_type", "channelType"),
                "contactPerson": _marketing_text(payload, "contact_person", "contactPerson"),
                "contactPhone": _marketing_text(payload, "contact_phone", "contactPhone"),
                "state": _marketing_text(payload, "state"),
                "totalCost": total,
                "placementCount": count,
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda item: (float(item["totalCost"]), str(item["channelCode"])), reverse=True)
    return {"success": True, "code": 0, "data": result[:max_rows], **_marketing_source_metadata(coverage)}


def marketing_source_materials(
    pool: PsqlPool,
    proj_guid: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if proj_guid is not None and not IDENTIFIER.fullmatch(proj_guid):
        raise ValueError("invalid proj_guid")
    coverage = _marketing_source_coverage(pool, max_rows)
    result: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "mkt_material", max(max_rows, 500), MARKETING_SOURCE_TABLES):
        payload = source["payload"]
        current_proj = _marketing_text(payload, "proj_guid", "projGuid")
        if proj_guid and current_proj != proj_guid:
            continue
        result.append(
            {
                "materialGuid": _marketing_text(payload, "material_guid", "materialGuid", fallback=source["record_id"]),
                "materialCode": _marketing_text(payload, "material_code", "materialCode"),
                "projGuid": current_proj,
                "name": _marketing_text(payload, "name"),
                "materialType": _marketing_text(payload, "material_type", "materialType"),
                "unitCost": _marketing_number(payload, "unit_cost", "unitCost"),
                "quantity": _marketing_number(payload, "quantity"),
                "totalCost": _marketing_number(payload, "total_cost", "totalCost"),
                "usagePeriod": _marketing_text(payload, "usage_period", "usagePeriod"),
                "state": _marketing_text(payload, "state"),
                "remark": _marketing_text(payload, "remark"),
                "l3Code": _marketing_text(payload, "l3_code", "l3Code"),
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda item: (str(item["materialCode"]), str(item["materialGuid"])), reverse=True)
    return {"success": True, "code": 0, "data": result[:max_rows], **_marketing_source_metadata(coverage)}


def _notification_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _notification_source_coverage(pool: PsqlPool, max_rows: int) -> dict[str, int]:
    return {
        table: len(
            _raw_source_rows(pool, table, max(max_rows, 500), NOTIFICATION_SOURCE_TABLES)
        )
        for table in sorted(NOTIFICATION_SOURCE_TABLES)
    }


def _notification_text(payload: dict[str, Any], *keys: str, fallback: str = "") -> str:
    for key in keys:
        value = payload.get(key)
        if value is not None and value != "":
            return str(value)
    return fallback


def _notification_int(payload: dict[str, Any], *keys: str) -> int:
    value = _notification_text(payload, *keys)
    if not value:
        return 0
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return 0


def _notification_bool(payload: dict[str, Any], *keys: str, fallback: bool = False) -> bool:
    value = _notification_text(payload, *keys)
    if not value:
        return fallback
    return value.strip().lower() in {"1", "true", "yes", "y", "enabled", "启用"}


def _notification_user_id(
    pool: PsqlPool,
    user_code: str | None,
    max_rows: int,
) -> str | None:
    if user_code is None or user_code == "":
        return None
    users = _raw_source_rows(pool, "sys_user", max(max_rows, 500), NOTIFICATION_SOURCE_TABLES)
    for row in users:
        payload = row["payload"]
        current_code = _notification_text(payload, "user_code", "userCode", "login_name")
        if current_code == user_code:
            return _notification_text(payload, "user_id", "userId", fallback=row["record_id"])
    return user_code


def notification_source_messages(
    pool: PsqlPool,
    user_code: str | None,
    status: str,
    limit: int,
    offset: int,
    max_rows: int,
) -> dict[str, Any]:
    if user_code is not None and user_code != "" and not IDENTIFIER.fullmatch(user_code):
        raise ValueError("invalid user_code")
    if status not in {"all", "unread", "read"}:
        raise ValueError("invalid notification status")
    if limit < 1 or limit > 200 or offset < 0:
        raise ValueError("invalid notification pagination")
    coverage = _notification_source_coverage(pool, max_rows)
    user_id = _notification_user_id(pool, user_code, max_rows)
    result: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "sys_message", max(max_rows, 500), NOTIFICATION_SOURCE_TABLES):
        payload = source["payload"]
        current_user = _notification_text(payload, "user_id", "userId")
        is_read = _notification_bool(payload, "is_read", "isRead")
        if user_id and current_user != user_id:
            continue
        if status == "unread" and is_read:
            continue
        if status == "read" and not is_read:
            continue
        result.append(
            {
                "msgGuid": _notification_text(payload, "msg_guid", "msgGuid", fallback=source["record_id"]),
                "userId": current_user,
                "msgType": _notification_text(payload, "msg_type", "msgType"),
                "title": _notification_text(payload, "title"),
                "content": _notification_text(payload, "content"),
                "bizType": _notification_text(payload, "biz_type", "bizType"),
                "bizDataGuid": _notification_text(payload, "biz_data_guid", "bizDataGuid"),
                "severity": _notification_text(payload, "severity"),
                "createdAt": _notification_text(payload, "created_at", "createdAt"),
                "isRead": is_read,
                "readAt": _notification_text(payload, "read_at", "readAt"),
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda item: (str(item["createdAt"]), str(item["msgGuid"])), reverse=True)
    total = len(result)
    return {
        "success": True,
        "code": 0,
        "data": {"total": total, "rows": result[offset : offset + min(limit, max_rows)]},
        "user_code": user_code or "",
        **_notification_source_metadata(coverage),
    }


def notification_source_unread_count(
    pool: PsqlPool,
    user_code: str | None,
    max_rows: int,
) -> dict[str, Any]:
    result = notification_source_messages(pool, user_code, "unread", 200, 0, max_rows)
    return {
        "success": True,
        "code": 0,
        "data": {"count": result["data"]["total"]},
        "user_code": user_code or "",
        **{key: value for key, value in result.items() if key not in {"data", "user_code"}},
    }


def notification_source_subscriptions(
    pool: PsqlPool,
    user_code: str | None,
    max_rows: int,
) -> dict[str, Any]:
    coverage = _notification_source_coverage(pool, max_rows)
    user_id = _notification_user_id(pool, user_code, max_rows)
    result: list[dict[str, Any]] = []
    for source in _raw_source_rows(
        pool, "sys_warning_subscription", max(max_rows, 500), NOTIFICATION_SOURCE_TABLES,
    ):
        payload = source["payload"]
        if user_id and _notification_text(payload, "user_id", "userId") != user_id:
            continue
        result.append(
            {
                "subId": _notification_int(payload, "sub_id", "subId"),
                "userId": _notification_text(payload, "user_id", "userId"),
                "ruleCode": _notification_text(payload, "rule_code", "ruleCode"),
                "bizType": _notification_text(payload, "biz_type", "bizType"),
                "severityMin": _notification_text(payload, "severity_min", "severityMin"),
                "channels": _notification_text(payload, "channels"),
                "enabled": _notification_bool(payload, "enabled", fallback=True),
                "createdAt": _notification_text(payload, "created_at", "createdAt"),
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda item: (int(item["subId"]), str(item["createdAt"])), reverse=True)
    return {
        "success": True,
        "code": 0,
        "data": result[:max_rows],
        "user_code": user_code or "",
        **_notification_source_metadata(coverage),
    }


def notification_source_config(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = _notification_source_coverage(pool, max_rows)
    values = {key: "" for key in NOTIFICATION_CONFIG_KEYS}
    configured: list[str] = []
    for source in _raw_source_rows(pool, "sys_param", max(max_rows, 500), NOTIFICATION_SOURCE_TABLES):
        payload = source["payload"]
        key = _notification_text(payload, "pk", "key", "param_key")
        if key not in values:
            continue
        raw_value = _notification_text(payload, "pv", "value", "param_value")
        if raw_value:
            configured.append(key)
        lowered = key.lower()
        values[key] = "已配置" if any(marker in lowered for marker in ("pass", "key", "secret", "token")) and raw_value else raw_value
    return {
        "success": True,
        "code": 0,
        "data": {"values": values, "configured": sorted(set(configured)), "keys": list(NOTIFICATION_CONFIG_KEYS)},
        **_notification_source_metadata(coverage),
    }


def notification_source_email_outbox(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = _notification_source_coverage(pool, max_rows)
    result: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "sys_email_outbox", max(max_rows, 500), NOTIFICATION_SOURCE_TABLES):
        payload = source["payload"]
        result.append(
            {
                "eid": _notification_text(payload, "eid", fallback=source["record_id"]),
                "toAddr": _notification_text(payload, "to_addr", "toAddr"),
                "subject": _notification_text(payload, "subject"),
                "createdAt": _notification_text(payload, "created_at", "createdAt"),
                "sentAt": _notification_text(payload, "sent_at", "sentAt"),
                "status": _notification_text(payload, "status"),
                "error": _notification_text(payload, "error"),
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda item: (str(item["createdAt"]), str(item["eid"])), reverse=True)
    return {"success": True, "code": 0, "data": result[:max_rows], **_notification_source_metadata(coverage)}


def notification_source_digest_preview(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = _notification_source_coverage(pool, max_rows)
    warnings: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "sys_warning", max(max_rows, 500), NOTIFICATION_SOURCE_TABLES):
        payload = source["payload"]
        if _notification_text(payload, "status") not in {"", "open"}:
            continue
        warnings.append(
            {
                "warningGuid": _notification_text(payload, "warning_guid", "warningGuid", fallback=source["record_id"]),
                "ruleCode": _notification_text(payload, "rule_code", "ruleCode"),
                "title": _notification_text(payload, "title"),
                "severity": _notification_text(payload, "severity"),
                "sourceKind": "imported",
            }
        )
    return {
        "success": True,
        "code": 0,
        "data": {"total": len(warnings), "rows": warnings[:max_rows], "new": len(warnings)},
        **_notification_source_metadata(coverage),
    }


def notification_source_digest_log(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = _notification_source_coverage(pool, max_rows)
    result: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "sys_warning_digest_log", max(max_rows, 500), NOTIFICATION_SOURCE_TABLES):
        payload = source["payload"]
        result.append(
            {
                "logId": _notification_int(payload, "log_id", "logId") or source["record_id"],
                "digestDate": _notification_text(payload, "digest_date", "digestDate"),
                "triggeredAt": _notification_text(payload, "triggered_at", "triggeredAt"),
                "userCount": _notification_int(payload, "user_count", "userCount"),
                "errorCount": _notification_int(payload, "error_count", "errorCount"),
                "warningCount": _notification_int(payload, "warning_count", "warningCount"),
                "newCount": _notification_int(payload, "new_count", "newCount"),
                "triggeredBy": _notification_text(payload, "triggered_by", "triggeredBy"),
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda item: (str(item["triggeredAt"]), str(item["logId"])), reverse=True)
    return {"success": True, "code": 0, "data": result[:max_rows], **_notification_source_metadata(coverage)}


def notification_source_llm_providers(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = _notification_source_coverage(pool, max_rows)
    return {
        "success": True,
        "code": 0,
        "data": [],
        "provider_execution": False,
        **_notification_source_metadata(coverage),
    }


def _ocr_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
        "secret_values_redacted": True,
    }


def ocr_source_status(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), OCR_SOURCE_TABLES))
        for table in sorted(OCR_SOURCE_TABLES)
    }
    params = {
        str(row["payload"].get("pk") or row["payload"].get("key") or ""): str(
            row["payload"].get("pv") or row["payload"].get("value") or ""
        )
        for row in _raw_source_rows(pool, "sys_param", max(max_rows, 500), OCR_SOURCE_TABLES)
    }
    provider = params.get("ai.ocr.provider") or "mock"
    scene = params.get("ai.ocr.scene") or "auto"
    providers: list[dict[str, Any]] = []
    configured_count = 0
    for code, label, needs_key, keys in OCR_PROVIDER_DEFINITIONS:
        key_status: dict[str, str] = {}
        for key in keys:
            if params.get(key):
                key_status[key] = "已配置"
                configured_count += 1
            else:
                key_status[key] = "(未配)"
        providers.append(
            {
                "code": code,
                "label": label,
                "needsKey": needs_key,
                "current": code == provider,
                "keyStatus": key_status,
            }
        )
    return {
        "success": True,
        "code": 0,
        "data": {
            "provider": provider,
            "providers": providers,
            "scene": scene,
            "configuredKeyCount": configured_count,
            "note": "OCR 状态只读；provider 执行、远程调用和密钥写入仍需授权。",
            "sceneOptions": [
                {"code": "auto", "label": "自动(按 bizType+文件名猜)"},
                {"code": "invoice", "label": "发票识别(精确字段)"},
                {"code": "contract", "label": "合同/通用文本"},
            ],
        },
        **_ocr_source_metadata(coverage),
    }


def _error_log_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "network_fields_redacted": True,
        "stack_included": False,
    }


def error_log_source_rows(
    pool: PsqlPool,
    keyword: str | None,
    limit: int,
    max_rows: int,
) -> dict[str, Any]:
    if keyword is not None and len(keyword) > 128:
        raise ValueError("invalid error log keyword")
    if limit < 1 or limit > 500:
        raise ValueError("invalid error log limit")
    coverage = {
        table: len(
            _raw_source_rows(pool, table, max(max_rows, 500), ERROR_LOG_SOURCE_TABLES)
        )
        for table in sorted(ERROR_LOG_SOURCE_TABLES)
    }
    raw = _raw_source_rows(pool, "sys_error_log", max(max_rows, 500), ERROR_LOG_SOURCE_TABLES)
    filtered: list[dict[str, Any]] = []
    for source in raw:
        payload = source["payload"]
        path = _notification_text(payload, "path")
        message = _notification_text(payload, "error_message", "errorMessage")
        if keyword and keyword.casefold() not in (path + " " + message).casefold():
            continue
        status = _notification_int(payload, "status")
        filtered.append(
            {
                "errId": _notification_text(payload, "err_id", "errId", fallback=source["record_id"]),
                "occurredAt": _notification_text(payload, "occurred_at", "occurredAt"),
                "userId": _notification_text(payload, "user_id", "userId"),
                "method": _notification_text(payload, "method"),
                "path": path,
                "status": status,
                "errorMessage": message,
                "ip": "已脱敏" if _notification_text(payload, "ip") else "",
                "sourceKind": "imported",
            }
        )
    filtered.sort(key=lambda item: (str(item["occurredAt"]), str(item["errId"])), reverse=True)
    today_prefix = date.today().isoformat()
    today_count = sum(1 for row in filtered if str(row["occurredAt"]).startswith(today_prefix))
    five_xx_count = sum(1 for row in filtered if int(row["status"]) >= 500)
    return {
        "success": True,
        "code": 0,
        "data": {
            "total": len(filtered),
            "rows": filtered[: min(limit, max_rows)],
            "todayCount": today_count,
            "fiveXxCount": five_xx_count,
        },
        **_error_log_source_metadata(coverage),
    }


def _ai_stats_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
    }


def _ai_period_match(value: str, period: str) -> bool:
    if not value:
        return False
    try:
        value_date = date.fromisoformat(value[:10])
    except ValueError:
        return False
    age = (date.today() - value_date).days
    if period == "today":
        return age == 0
    if period == "week":
        return 0 <= age < 7
    return 0 <= age < 30


def _ai_stat_coverage(pool: PsqlPool, max_rows: int) -> dict[str, int]:
    return {
        table: len(
            _raw_source_rows(pool, table, max(max_rows, 500), AI_STATS_SOURCE_TABLES)
        )
        for table in sorted(AI_STATS_SOURCE_TABLES)
    }


def ai_stats_source_overview(
    pool: PsqlPool,
    period: str,
    max_rows: int,
) -> dict[str, Any]:
    if period not in {"today", "week", "month"}:
        period = "month"
    coverage = _ai_stat_coverage(pool, max_rows)
    drafts = [
        row["payload"]
        for row in _raw_source_rows(pool, "ai_draft", max(max_rows, 500), AI_STATS_SOURCE_TABLES)
        if str(row["payload"].get("status") or "") == "confirmed"
        and _ai_period_match(_notification_text(row["payload"], "created_at", "createdAt"), period)
    ]
    queries = [
        row["payload"]
        for row in _raw_source_rows(pool, "ai_query_log", max(max_rows, 500), AI_STATS_SOURCE_TABLES)
        if _ai_period_match(_notification_text(row["payload"], "created_at", "createdAt"), period)
    ]
    corrections = [
        row["payload"]
        for row in _raw_source_rows(
            pool, "ai_correction_log", max(max_rows, 500), AI_STATS_SOURCE_TABLES,
        )
        if _ai_period_match(_notification_text(row["payload"], "created_at", "createdAt"), period)
    ]
    skips = [
        row["payload"]
        for row in _raw_source_rows(
            pool, "wf_step_action", max(max_rows, 500), AI_STATS_SOURCE_TABLES,
        )
        if str(row["payload"].get("decision") or "") == "AUTO_SKIPPED"
        and _ai_period_match(_notification_text(row["payload"], "action_time", "actionTime"), period)
    ]
    query_success = sum(1 for row in queries if not _notification_text(row, "error"))
    durations = [
        _notification_int(row, "duration_ms", "durationMs")
        for row in queries
        if not _notification_text(row, "error")
    ]
    by_biz: dict[str, int] = {}
    by_provider: dict[str, list[float]] = {}
    for row in drafts:
        biz_type = _notification_text(row, "biz_type", "bizType", fallback="unknown")
        by_biz[biz_type] = by_biz.get(biz_type, 0) + 1
        provider = _notification_text(row, "llm_provider", "llmProvider", fallback="(none)")
        by_provider.setdefault(provider, []).append(float(row.get("confidence") or 0.0))
    corrected_fields: dict[tuple[str, str], int] = {}
    for row in corrections:
        key = (
            _notification_text(row, "biz_type", "bizType", fallback="unknown"),
            _notification_text(row, "field_name", "fieldName", fallback="unknown"),
        )
        corrected_fields[key] = corrected_fields.get(key, 0) + 1
    timeseries: dict[str, dict[str, Any]] = {}
    for row in drafts:
        key = _notification_text(row, "created_at", "createdAt")[:10]
        if not key:
            continue
        timeseries.setdefault(key, {"date": key, "intake": 0, "query": 0})["intake"] += 1
    for row in queries:
        key = _notification_text(row, "created_at", "createdAt")[:10]
        if not key:
            continue
        timeseries.setdefault(key, {"date": key, "intake": 0, "query": 0})["query"] += 1
    draft_total = len(drafts)
    query_total = len(queries)
    skip_total = len(skips)
    correction_total = len(corrections)
    saved_minutes = draft_total * 5 + query_total + skip_total * 3
    kpi = {
        "intakeTotal": draft_total,
        "queryTotal": query_total,
        "skipTotal": skip_total,
        "correctionTotal": correction_total,
        "accuracy": max(0, round(100 - correction_total * 100 / max(1, draft_total * 8))) if draft_total else 100,
        "avgConfidence": round(sum(float(row.get("confidence") or 0.0) for row in drafts) / draft_total * 100, 1) if draft_total else 0.0,
        "querySuccessRate": round(query_success / query_total * 100, 1) if query_total else 100.0,
        "avgQueryDurationMs": round(sum(durations) / len(durations)) if durations else 0,
        "savedMinutes": saved_minutes,
        "savedHours": round(saved_minutes / 60, 1),
    }
    return {
        "success": True,
        "code": 0,
        "data": {
            "period": period,
            "kpi": kpi,
            "byBizType": [
                {"bizType": key, "count": count}
                for key, count in sorted(by_biz.items(), key=lambda item: (-item[1], item[0]))
            ],
            "byProvider": [
                {
                    "provider": key,
                    "count": len(values),
                    "avgConfidence": round(sum(values) / len(values) * 100, 1),
                }
                for key, values in sorted(by_provider.items(), key=lambda item: (-len(item[1]), item[0]))
            ],
            "topCorrectedFields": [
                {"bizType": key[0], "field": key[1], "count": count}
                for key, count in sorted(corrected_fields.items(), key=lambda item: (-item[1], item[0]))[:5]
            ],
            "timeseries": [timeseries[key] for key in sorted(timeseries)],
        },
        **_ai_stats_source_metadata(coverage),
    }


def ai_stats_source_activity(pool: PsqlPool, limit: int, max_rows: int) -> dict[str, Any]:
    if limit < 1 or limit > 100:
        raise ValueError("invalid AI activity limit")
    coverage = _ai_stat_coverage(pool, max_rows)
    users = {
        _notification_text(row["payload"], "user_id", "userId", fallback=row["record_id"]): _notification_text(
            row["payload"], "emp_name", "empName", "user_name", "userName", fallback="系统"
        )
        for row in _raw_source_rows(pool, "sys_user", max(max_rows, 500), AI_STATS_SOURCE_TABLES)
    }
    items: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "ai_draft", max(max_rows, 500), AI_STATS_SOURCE_TABLES):
        payload = source["payload"]
        if str(payload.get("status") or "") != "confirmed":
            continue
        time_value = _notification_text(payload, "confirmed_at", "confirmedAt", "created_at", "createdAt")
        if not time_value:
            continue
        user = users.get(_notification_text(payload, "user_id", "userId"), "系统")
        biz_type = _notification_text(payload, "biz_type", "bizType", fallback="unknown")
        confidence = float(payload.get("confidence") or 0.0)
        items.append(
            {
                "type": "intake",
                "time": time_value,
                "icon": "intake",
                "title": "AI 起单 " + biz_type,
                "detail": "置信度 " + str(round(confidence * 100)) + "% · 由 " + user + " 确认",
                "sourceKind": "imported",
            }
        )
    for source in _raw_source_rows(pool, "ai_query_log", max(max_rows, 500), AI_STATS_SOURCE_TABLES):
        payload = source["payload"]
        time_value = _notification_text(payload, "created_at", "createdAt")
        if not time_value:
            continue
        question = _notification_text(payload, "question", fallback="AI 查询")[:60]
        error = _notification_text(payload, "error")
        detail = question + " · " + ("失败" if error else str(_notification_int(payload, "row_count", "rowCount")) + " 行")
        items.append(
            {
                "type": "query",
                "time": time_value,
                "icon": "query",
                "title": "AI 智能问答",
                "detail": detail,
                "sourceKind": "imported",
            }
        )
    for source in _raw_source_rows(pool, "wf_step_action", max(max_rows, 500), AI_STATS_SOURCE_TABLES):
        payload = source["payload"]
        if str(payload.get("decision") or "") != "AUTO_SKIPPED":
            continue
        time_value = _notification_text(payload, "action_time", "actionTime")
        if not time_value:
            continue
        items.append(
            {
                "type": "skip",
                "time": time_value,
                "icon": "skip",
                "title": "AI 自动跳过审批步",
                "detail": _notification_text(payload, "step_name", "stepName", fallback="审批步骤") + " — " + _notification_text(payload, "comment"),
                "sourceKind": "imported",
            }
        )
    items.sort(key=lambda item: (str(item["time"]), str(item["title"])), reverse=True)
    return {
        "success": True,
        "code": 0,
        "data": items[:limit],
        **_ai_stats_source_metadata(coverage),
    }


def ai_stats_source_badge(
    pool: PsqlPool,
    biz_type: str | None,
    biz_guid: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if not biz_type or not biz_guid:
        raise ValueError("bizType and bizGuid are required")
    if not IDENTIFIER.fullmatch(biz_type) or not IDENTIFIER.fullmatch(biz_guid):
        raise ValueError("invalid AI badge identifiers")
    coverage = _ai_stat_coverage(pool, max_rows)
    matches = []
    for source in _raw_source_rows(pool, "ai_draft", max(max_rows, 500), AI_STATS_SOURCE_TABLES):
        payload = source["payload"]
        if (
            str(payload.get("status") or "") == "confirmed"
            and _notification_text(payload, "biz_type", "bizType") == biz_type
            and _notification_text(payload, "result_biz_guid", "resultBizGuid") == biz_guid
        ):
            matches.append((source, payload))
    matches.sort(key=lambda item: _notification_text(item[1], "confirmed_at", "confirmedAt"), reverse=True)
    if not matches:
        data = {"byAi": False}
    else:
        source, payload = matches[0]
        fields_value = payload.get("fields")
        field_names: list[str] = []
        if isinstance(fields_value, dict):
            field_names = list(fields_value.keys())[:10]
        elif isinstance(fields_value, str):
            try:
                parsed = json.loads(fields_value)
                if isinstance(parsed, dict):
                    field_names = list(parsed.keys())[:10]
            except json.JSONDecodeError:
                pass
        data = {
            "byAi": True,
            "draftId": _notification_text(payload, "draft_id", "draftId", fallback=source["record_id"]),
            "confidence": float(payload.get("confidence") or 0.0),
            "llmProvider": _notification_text(payload, "llm_provider", "llmProvider"),
            "llmModel": _notification_text(payload, "llm_model", "llmModel"),
            "confirmedAt": _notification_text(payload, "confirmed_at", "confirmedAt"),
            "fieldsHint": field_names,
        }
    return {"success": True, "code": 0, "data": data, **_ai_stats_source_metadata(coverage)}


def _ai_hub_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
        "query_execution": False,
        "secret_values_redacted": True,
    }


def _ai_hub_coverage(pool: PsqlPool, max_rows: int) -> dict[str, int]:
    return {
        table: len(
            _raw_source_rows(pool, table, max(max_rows, 500), AI_HUB_SOURCE_TABLES)
        )
        for table in sorted(AI_HUB_SOURCE_TABLES)
    }


def _ai_hub_limit(value: int | str | None, default: int = 50, maximum: int = 500) -> int:
    if value is None or value == "":
        return default
    try:
        parsed = int(value)
    except (TypeError, ValueError) as error:
        raise ValueError("invalid AI Hub limit") from error
    if parsed < 1 or parsed > maximum:
        raise ValueError("invalid AI Hub limit")
    return parsed


def _ai_hub_user_ids(
    pool: PsqlPool,
    user_code: str | None,
    max_rows: int,
) -> set[str] | None:
    if user_code in (None, ""):
        return None
    ids = {user_code}
    for source in _raw_source_rows(pool, "sys_user", max(max_rows, 500), AI_HUB_SOURCE_TABLES):
        payload = source["payload"]
        if _notification_text(payload, "user_code", "userCode") == user_code:
            user_id = _notification_text(payload, "user_id", "userId")
            if user_id:
                ids.add(user_id)
    return ids


def _ai_hub_user_matches(payload: dict[str, Any], user_ids: set[str] | None) -> bool:
    if user_ids is None:
        return True
    return _notification_text(payload, "user_id", "userId", "user_code", "userCode") in user_ids


def _ai_hub_date_value(payload: dict[str, Any], *keys: str) -> str:
    return _notification_text(payload, *keys)


def ai_hub_corrections(
    pool: PsqlPool,
    biz_type: str | None,
    field: str | None,
    user_code: str | None,
    limit: int,
    max_rows: int,
) -> dict[str, Any]:
    if biz_type is not None and len(biz_type) > 128:
        raise ValueError("invalid AI Hub bizType")
    if field is not None and len(field) > 128:
        raise ValueError("invalid AI Hub field")
    if user_code is not None and not IDENTIFIER.fullmatch(user_code):
        raise ValueError("invalid AI Hub userCode")
    coverage = _ai_hub_coverage(pool, max_rows)
    user_ids = _ai_hub_user_ids(pool, user_code, max_rows)
    rows: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "ai_correction_log", max(max_rows, 500), AI_HUB_SOURCE_TABLES):
        payload = source["payload"]
        row_biz_type = _notification_text(payload, "biz_type", "bizType")
        row_field = _notification_text(payload, "field_name", "fieldName")
        if biz_type and row_biz_type != biz_type:
            continue
        if field and row_field != field:
            continue
        if not _ai_hub_user_matches(payload, user_ids):
            continue
        rows.append(
            {
                "cid": _notification_int(payload, "cid") or source["record_id"],
                "draftId": _notification_text(payload, "draft_id", "draftId"),
                "userId": _notification_text(payload, "user_id", "userId"),
                "bizType": row_biz_type,
                "fieldName": row_field,
                "llmValue": _notification_text(payload, "llm_value", "llmValue"),
                "userValue": _notification_text(payload, "user_value", "userValue"),
                "descriptionSnippet": _notification_text(
                    payload, "description_snippet", "descriptionSnippet"
                )[:200],
                "createdAt": _notification_text(payload, "created_at", "createdAt"),
                "sourceKind": "imported",
            }
        )
    rows.sort(key=lambda row: (str(row["createdAt"]), str(row["cid"])), reverse=True)
    return {
        "success": True,
        "code": 0,
        "data": rows[:limit],
        **_ai_hub_source_metadata(coverage),
    }


def ai_hub_correction_stats(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = _ai_hub_coverage(pool, max_rows)
    by_field: dict[tuple[str, str], int] = {}
    total = 0
    for source in _raw_source_rows(pool, "ai_correction_log", max(max_rows, 500), AI_HUB_SOURCE_TABLES):
        payload = source["payload"]
        key = (
            _notification_text(payload, "biz_type", "bizType"),
            _notification_text(payload, "field_name", "fieldName"),
        )
        by_field[key] = by_field.get(key, 0) + 1
        total += 1
    drafts = 0
    for source in _raw_source_rows(pool, "ai_draft", max(max_rows, 500), AI_HUB_SOURCE_TABLES):
        if _notification_text(source["payload"], "status") == "confirmed":
            drafts += 1
    rows = [
        {"bizType": key[0], "fieldName": key[1], "count": count}
        for key, count in sorted(by_field.items(), key=lambda item: (-item[1], item[0]))[:20]
    ]
    correction_rate = round(total / drafts, 2) if drafts else 0
    return {
        "success": True,
        "code": 0,
        "data": {
            "byField": rows,
            "total": total,
            "drafts": drafts,
            "correctionRate": correction_rate,
        },
        **_ai_hub_source_metadata(coverage),
    }


def ai_hub_drafts(
    pool: PsqlPool,
    user_code: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if user_code is not None and not IDENTIFIER.fullmatch(user_code):
        raise ValueError("invalid AI Hub userCode")
    coverage = _ai_hub_coverage(pool, max_rows)
    user_ids = _ai_hub_user_ids(pool, user_code, max_rows)
    result: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "ai_draft", max(max_rows, 500), AI_HUB_SOURCE_TABLES):
        payload = source["payload"]
        if not _ai_hub_user_matches(payload, user_ids):
            continue
        result.append(
            {
                "draftId": _notification_text(payload, "draft_id", "draftId", fallback=source["record_id"]),
                "bizType": _notification_text(payload, "biz_type", "bizType"),
                "description": _notification_text(payload, "description")[:300],
                "confidence": float(payload.get("confidence") or 0.0),
                "status": _notification_text(payload, "status"),
                "createdAt": _notification_text(payload, "created_at", "createdAt"),
                "confirmedAt": _notification_text(payload, "confirmed_at", "confirmedAt"),
                "resultBizGuid": _notification_text(payload, "result_biz_guid", "resultBizGuid"),
                "llmProvider": _notification_text(payload, "llm_provider", "llmProvider"),
                "llmModel": _notification_text(payload, "llm_model", "llmModel"),
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda row: str(row["createdAt"]), reverse=True)
    return {"success": True, "code": 0, "data": result[:30], **_ai_hub_source_metadata(coverage)}


def ai_hub_draft(
    pool: PsqlPool,
    draft_id: str,
    user_code: str | None,
    max_rows: int,
) -> dict[str, Any] | None:
    if not IDENTIFIER.fullmatch(draft_id):
        raise ValueError("invalid AI Hub draftId")
    if user_code is not None and not IDENTIFIER.fullmatch(user_code):
        raise ValueError("invalid AI Hub userCode")
    coverage = _ai_hub_coverage(pool, max_rows)
    user_ids = _ai_hub_user_ids(pool, user_code, max_rows)
    for source in _raw_source_rows(pool, "ai_draft", max(max_rows, 500), AI_HUB_SOURCE_TABLES):
        payload = source["payload"]
        candidate = _notification_text(payload, "draft_id", "draftId", fallback=source["record_id"])
        if candidate != draft_id or not _ai_hub_user_matches(payload, user_ids):
            continue
        fields_value = payload.get("fields")
        field_names: list[str] = []
        if isinstance(fields_value, dict):
            field_names = list(fields_value.keys())[:30]
        elif isinstance(fields_value, str):
            try:
                parsed = json.loads(fields_value)
                if isinstance(parsed, dict):
                    field_names = list(parsed.keys())[:30]
            except json.JSONDecodeError:
                pass
        result = {
            "draftId": candidate,
            "bizType": _notification_text(payload, "biz_type", "bizType"),
            "bizName": _notification_text(payload, "biz_name", "bizName", "biz_type", "bizType"),
            "bizFieldSpec": [],
            "description": _notification_text(payload, "description")[:300],
            "fields": {},
            "fieldsHint": field_names,
            "confidence": float(payload.get("confidence") or 0.0),
            "status": _notification_text(payload, "status"),
            "attGuid": _notification_text(payload, "att_guid", "attGuid"),
            "ocrText": "已脱敏；源服务未导入 OCR 文本",
            "llm": {
                "provider": _notification_text(payload, "llm_provider", "llmProvider"),
                "model": _notification_text(payload, "llm_model", "llmModel"),
            },
            "reasoning": "从导入历史草稿恢复；字段值已脱敏",
        }
        return {
            "success": True,
            "code": 0,
            "data": result,
            **_ai_hub_source_metadata(coverage),
        }
    return None


def ai_hub_query_log(
    pool: PsqlPool,
    user_code: str | None,
    max_rows: int,
) -> dict[str, Any]:
    if user_code is not None and not IDENTIFIER.fullmatch(user_code):
        raise ValueError("invalid AI Hub userCode")
    coverage = _ai_hub_coverage(pool, max_rows)
    user_ids = _ai_hub_user_ids(pool, user_code, max_rows)
    result: list[dict[str, Any]] = []
    for source in _raw_source_rows(pool, "ai_query_log", max(max_rows, 500), AI_HUB_SOURCE_TABLES):
        payload = source["payload"]
        if not _ai_hub_user_matches(payload, user_ids):
            continue
        result.append(
            {
                "qid": _notification_int(payload, "qid") or source["record_id"],
                "question": _notification_text(payload, "question")[:300],
                "sql": "已脱敏（源查询文本未导入）" if payload.get("sql") else None,
                "explanation": _notification_text(payload, "explanation")[:300],
                "rowCount": _notification_int(payload, "row_count", "rowCount"),
                "durationMs": _notification_int(payload, "duration_ms", "durationMs"),
                "llmProvider": _notification_text(payload, "llm_provider", "llmProvider"),
                "llmModel": _notification_text(payload, "llm_model", "llmModel"),
                "error": _notification_text(payload, "error"),
                "createdAt": _notification_text(payload, "created_at", "createdAt"),
                "sourceKind": "imported",
            }
        )
    result.sort(key=lambda row: (str(row["createdAt"]), str(row["qid"])), reverse=True)
    return {"success": True, "code": 0, "data": result[:50], **_ai_hub_source_metadata(coverage)}


def ai_hub_usage_stats(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = _ai_hub_coverage(pool, max_rows)
    audit_rows = _raw_source_rows(pool, "audit_log", max(max_rows, 500), AI_HUB_SOURCE_TABLES)
    now = date.today().isoformat()[:7]

    def month_row(payload: dict[str, Any]) -> bool:
        return _ai_hub_date_value(payload, "created_at", "createdAt")[:7] == now

    intake_month = sum(
        1
        for source in audit_rows
        if month_row(source["payload"])
        and _notification_text(source["payload"], "action") == "AI_INTAKE_CONFIRM"
    )
    query_month = sum(
        1
        for source in audit_rows
        if month_row(source["payload"])
        and _notification_text(source["payload"], "action").startswith("AI_QUERY")
    )
    session_turn_month = sum(
        1
        for source in _raw_source_rows(pool, "ai_query_turn", max(max_rows, 500), AI_HUB_SOURCE_TABLES)
        if month_row(source["payload"])
    )
    intake_total = sum(
        1
        for source in audit_rows
        if _notification_text(source["payload"], "action") == "AI_INTAKE_CONFIRM"
    )
    minutes_saved = intake_month * 5 + query_month * 3 + session_turn_month * 2
    return {
        "success": True,
        "code": 0,
        "data": {
            "monthlyTotalCalls": intake_month + query_month + session_turn_month,
            "intakeMonth": intake_month,
            "queryMonth": query_month,
            "sessionTurnMonth": session_turn_month,
            "intakeTotal": intake_total,
            "minutesSaved": minutes_saved,
        },
        **_ai_hub_source_metadata(coverage),
    }


def _webhook_source_metadata(coverage: dict[str, int]) -> dict[str, Any]:
    return {
        "source_kind": "imported_or_empty",
        "source_coverage": coverage,
        "missing_or_empty_source_tables": [
            table for table, count in coverage.items() if count == 0
        ],
        "authorizing": False,
        "persisted": False,
        "provider_execution": False,
        "secret_values_redacted": True,
        "network_fields_redacted": True,
    }


def _webhook_mask_url(value: str) -> str:
    if not value:
        return ""
    parsed = urlparse(value)
    if parsed.scheme and parsed.netloc:
        path = parsed.path or ""
        return f"{parsed.scheme}://{parsed.netloc}{path}（已脱敏）"
    return "已配置（已脱敏）"


def _webhook_mask_secret(value: str) -> str:
    if not value:
        return ""
    if len(value) <= 6:
        return "****"
    return value[:3] + "****" + value[-3:]


def webhook_source_config(pool: PsqlPool, max_rows: int) -> dict[str, Any]:
    coverage = {
        table: len(_raw_source_rows(pool, table, max(max_rows, 500), WEBHOOK_SOURCE_TABLES))
        for table in sorted(WEBHOOK_SOURCE_TABLES)
    }
    params: dict[str, str] = {}
    for source in _raw_source_rows(pool, "sys_param", max(max_rows, 500), WEBHOOK_SOURCE_TABLES):
        payload = source["payload"]
        key = _notification_text(payload, "pk", "key", "param_key")
        if key:
            params[key] = _notification_text(payload, "pv", "value", "param_value")
    data: dict[str, dict[str, Any]] = {}
    for platform, label in WEBHOOK_PLATFORM_DEFINITIONS:
        enabled = params.get(f"notify.webhook.{platform}.enabled", "")
        url = params.get(f"notify.webhook.{platform}.url", "")
        secret = params.get(f"notify.webhook.{platform}.secret", "")
        data[platform] = {
            "label": label,
            "enabled": _notification_bool({"value": enabled}, "value"),
            "url": _webhook_mask_url(url),
            "secret": _webhook_mask_secret(secret),
            "hasSecret": bool(secret),
            "urlConfigured": bool(url),
        }
    return {
        "success": True,
        "code": 0,
        "data": data,
        "note": "Webhook 配置只读；URL/密钥已脱敏，写入与 provider 投递仍需授权。",
        **_webhook_source_metadata(coverage),
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


def response_text(
    handler: BaseHTTPRequestHandler,
    status: int,
    body: str,
    content_type: str,
    origin: str | None,
    content_disposition: str | None = None,
) -> None:
    encoded = body.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", content_type)
    handler.send_header("Content-Length", str(len(encoded)))
    handler.send_header("Cache-Control", "no-store")
    if content_disposition is not None:
        handler.send_header("Content-Disposition", content_disposition)
    if origin is not None:
        handler.send_header("Access-Control-Allow-Origin", origin)
        handler.send_header("Vary", "Origin")
    handler.end_headers()
    handler.wfile.write(encoded)


def handler_factory(
    pool: PsqlPool,
    *,
    database_name: str,
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
                elif re.fullmatch(r"/api/company/import/[A-Za-z0-9_.:-]{1,128}/template", parsed.path):
                    biz_type = parsed.path.split("/")[-2]
                    template = import_template(biz_type)
                    if template is None:
                        response(
                            self,
                            400,
                            {"success": False, "code": 40001, "message": "不支持的 bizType"},
                            origin,
                        )
                    else:
                        response_text(
                            self,
                            200,
                            template,
                            "text/csv; charset=utf-8",
                            origin,
                            f"attachment; filename={biz_type}_template.csv",
                        )
                elif parsed.path == "/api/company/summary":
                    response(self, 200, summary(pool, expected_schema_version), origin)
                elif parsed.path == "/api/company/auth/me":
                    user_code = parse_qs(parsed.query).get("userCode", [""])[0]
                    result = auth_current_user(pool, user_code, max_response_rows)
                    if result is None:
                        response(self, 404, {"error": "user not found"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/auth/prefs":
                    user_code = parse_qs(parsed.query).get("userCode", [""])[0]
                    result = auth_preferences(pool, user_code, max_response_rows)
                    if result is None:
                        response(self, 404, {"error": "user not found"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/auth/my-initiated":
                    user_code = parse_qs(parsed.query).get("userCode", [""])[0]
                    result = auth_my_initiated(pool, user_code, max_response_rows)
                    if result is None:
                        response(self, 404, {"error": "user not found"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/receipts":
                    response(self, 200, {"items": receipts(pool)}, origin)
                elif parsed.path == "/api/company/projections":
                    value = parse_qs(parsed.query).get("aggregate_type", [None])[0]
                    response(self, 200, {"items": projections(pool, value, max_response_rows)}, origin)
                elif parsed.path == "/api/company/budget/expenses":
                    query = parse_qs(parsed.query)
                    result = budget_expenses(
                        pool,
                        query.get("expenseGuid", [None])[0],
                        query.get("userCode", [None])[0],
                        query.get("applyState", [None])[0],
                        max_response_rows,
                    )
                    if result is None:
                        response(self, 404, {"error": "user not found"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif re.fullmatch(r"/api/company/budget/expenses/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    query = parse_qs(parsed.query)
                    expense_id = parsed.path.rsplit("/", 1)[-1]
                    result = budget_expense_detail(
                        pool,
                        expense_id,
                        query.get("userCode", [None])[0],
                        max_response_rows,
                    )
                    if result is None:
                        response(self, 404, {"error": "user not found"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/source/cost/contracts":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        cost_source_contracts(
                            pool,
                            query.get("contractGuid", query.get("contract_id", [None]))[0],
                            query.get("buGuid", query.get("bu_guid", [None]))[0],
                            query.get("projGuid", query.get("proj_guid", [None]))[0],
                            query.get("keyword", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif re.fullmatch(r"/api/company/source/cost/contracts/[A-Za-z0-9_.:-]{1,128}/milestones", parsed.path):
                    contract_id = parsed.path.split("/")[-2]
                    detail = cost_source_contract_detail(pool, contract_id, max_response_rows)
                    if detail is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "合同不存在"}, origin)
                    else:
                        response(
                            self,
                            200,
                            {
                                **detail,
                                "data": detail["data"]["milestones"],
                            },
                            origin,
                        )
                elif re.fullmatch(r"/api/company/source/cost/contracts/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    contract_id = parsed.path.rsplit("/", 1)[-1]
                    detail = cost_source_contract_detail(pool, contract_id, max_response_rows)
                    if detail is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "合同不存在"}, origin)
                    else:
                        response(self, 200, detail, origin)
                elif parsed.path == "/api/company/source/cost/payment-applies":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        cost_source_payment_applications(
                            pool,
                            query.get("view", ["all"])[0],
                            query.get("buGuid", query.get("bu_guid", [None]))[0],
                            query.get("userId", query.get("user_id", [None]))[0],
                            max_response_rows,
                        ),
                        origin,
                    )
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
                elif re.fullmatch(
                    r"/api/company/source/tender/(tenders|awards|splits)",
                    parsed.path,
                ):
                    family = parsed.path.rsplit("/", 1)[-1]
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        tender_source_rows(
                            pool,
                            family,
                            query.get("projGuid", query.get("proj_guid", [None]))[0],
                            query.get("state", [None])[0],
                            query.get("tenderGuid", query.get("tender_guid", [None]))[0],
                            query.get(
                                "parentContractGuid",
                                query.get("parent_contract_guid", [None]),
                            )[0],
                            max_response_rows,
                        ),
                        origin,
                    )
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
                elif parsed.path == "/api/company/cashflow/forecast":
                    query = parse_qs(parsed.query)
                    months = int(query.get("months", ["6"])[0])
                    bu_guid = query.get("buGuid", [None])[0]
                    proj_guid = query.get("projGuid", [None])[0]
                    result = cashflow_source_forecast(
                        pool, months, bu_guid, proj_guid, max_response_rows,
                    )
                    response(self, 200, result, origin)
                elif parsed.path == "/api/company/cashflow/forecast-v3":
                    query = parse_qs(parsed.query)
                    months = int(query.get("months", ["6"])[0])
                    proj_guid = query.get("projGuid", [None])[0]
                    if not proj_guid:
                        raise CommandRejected("projGuid is required", 422)
                    result = cashflow_source_forecast_v3(
                        pool, months, proj_guid, max_response_rows,
                    )
                    response(self, 200, result, origin)
                elif parsed.path == "/api/company/cashflow/forecast/detail":
                    query = parse_qs(parsed.query)
                    ym = query.get("ym", [None])[0]
                    if not ym:
                        raise CommandRejected("ym is required", 422)
                    result = cashflow_source_detail(
                        pool,
                        ym,
                        query.get("buGuid", [None])[0],
                        query.get("projGuid", [None])[0],
                        max_response_rows,
                    )
                    response(self, 200, result, origin)
                elif parsed.path == "/api/company/cashflow/inflow":
                    query = parse_qs(parsed.query)
                    result = cashflow_source_inflow(
                        pool,
                        int(query.get("months", ["6"])[0]),
                        query.get("buGuid", [None])[0],
                        query.get("projGuid", [None])[0],
                        max_response_rows,
                    )
                    response(self, 200, result, origin)
                elif parsed.path == "/api/company/cashflow/net":
                    query = parse_qs(parsed.query)
                    result = cashflow_source_net(
                        pool, int(query.get("months", ["6"])[0]), max_response_rows,
                    )
                    response(self, 200, result, origin)
                elif parsed.path == "/api/company/cashflow/gap-alert":
                    query = parse_qs(parsed.query)
                    result = cashflow_source_gap_alert(
                        pool, int(query.get("horizonDays", ["90"])[0]), max_response_rows,
                    )
                    response(self, 200, result, origin)
                elif parsed.path == "/api/company/source/srm/categories":
                    response(self, 200, supplier_source_categories(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/source/srm/dict/eval-results":
                    response(self, 200, supplier_source_eval_results(), origin)
                elif parsed.path == "/api/company/source/srm/dict/sources":
                    response(self, 200, supplier_source_sources(), origin)
                elif parsed.path == "/api/company/srm/providers":
                    response(self, 200, supplier_source_list(pool, max_response_rows), origin)
                elif re.fullmatch(r"/api/company/srm/providers/[A-Za-z0-9_.:-]{1,128}/risk", parsed.path):
                    provider_guid = parsed.path.split("/")[-2]
                    risk = supplier_source_risk(pool, provider_guid, max_response_rows)
                    response(self, 200 if risk.get("success") is True else 404, risk, origin)
                elif re.fullmatch(r"/api/company/srm/providers/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    provider_guid = parsed.path.rsplit("/", 1)[-1]
                    detail = supplier_source_detail(pool, provider_guid, max_response_rows)
                    response(self, 200 if detail.get("success") is True else 404, detail, origin)
                elif parsed.path == "/api/company/srm/stats/overview":
                    response(self, 200, supplier_source_stats(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/supplier-risk-board":
                    response(self, 200, {"items": supplier_risk_board(pool, max_response_rows)}, origin)
                elif parsed.path == "/api/company/srm/risk-board":
                    response(self, 200, supplier_risk_board_source(pool, max_response_rows), origin)
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
                elif re.fullmatch(
                    r"/api/company/source/sales/(customers|subscriptions|contracts|mortgages|refunds|revenues)",
                    parsed.path,
                ):
                    family = parsed.path.rsplit("/", 1)[-1]
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        sales_source_rows(
                            pool,
                            family,
                            query.get("projGuid", query.get("proj_guid", [None]))[0],
                            query.get("state", query.get("status", [None]))[0],
                            query.get("keyword", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
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
                elif re.fullmatch(r"/api/company/source/invoice/(in|out)", parsed.path):
                    query = parse_qs(parsed.query)
                    result = invoice_source_rows(
                        pool,
                        parsed.path.rsplit("/", 1)[-1],
                        query.get("projGuid", [None])[0],
                        query.get("contractGuid", [None])[0],
                        max_response_rows,
                    )
                    response(self, 200, result, origin)
                elif parsed.path == "/api/company/source/invoice/tax-ledger":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        invoice_source_tax_ledger(
                            pool, query.get("projGuid", [None])[0], max_response_rows,
                        ),
                        origin,
                    )
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
                elif parsed.path == "/api/company/reports/templates/meta":
                    response(self, 200, report_template_metadata(), origin)
                elif parsed.path == "/api/company/reports/templates":
                    response(self, 200, report_template_rows(pool, max_response_rows), origin)
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
                elif re.fullmatch(
                    r"/api/company/source/cost/dynamic-cost/[A-Za-z0-9_.:-]{1,128}/remarks",
                    parsed.path,
                ):
                    cost_value = parsed.path.split("/")[-2]
                    result = dynamic_cost_remarks(pool, cost_value, max_response_rows)
                    if result is None:
                        response(
                            self,
                            404,
                            {"success": False, "code": 43001, "message": "科目不存在"},
                            origin,
                        )
                    else:
                        response(self, 200, result, origin)
                elif re.fullmatch(
                    r"/api/company/source/cost/milestones/[A-Za-z0-9_.:-]{1,128}/check",
                    parsed.path,
                ):
                    milestone_value = parsed.path.split("/")[-2]
                    query = parse_qs(parsed.query)
                    try:
                        apply_amount = float(query.get("applyAmount", ["0"])[0])
                    except (TypeError, ValueError) as error:
                        raise ValueError("invalid applyAmount") from error
                    result = cost_milestone_check(
                        pool, milestone_value, apply_amount, max_response_rows,
                    )
                    if result is None:
                        response(
                            self,
                            404,
                            {"success": False, "code": 43001, "message": "节点不存在"},
                            origin,
                        )
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/cost/dynamic-cost":
                    project_value = parse_qs(parsed.query).get("projGuid", [""])[0]
                    if not project_value:
                        response(self, 422, {"error": "projGuid is required"}, origin)
                    else:
                        response(self, 200, dynamic_cost(pool, project_value, max_response_rows), origin)
                elif parsed.path == "/api/company/dashboard/group/overview":
                    response(self, 200, dashboard_group_overview(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/dashboard/group/funnel":
                    response(self, 200, dashboard_group_funnel(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/dashboard/group/top-anomalies":
                    query = parse_qs(parsed.query)
                    try:
                        limit = int(query.get("limit", ["10"])[0])
                    except (TypeError, ValueError) as error:
                        raise ValueError("invalid dashboard anomaly limit") from error
                    response(
                        self,
                        200,
                        dashboard_group_top_anomalies(pool, limit, max_response_rows),
                        origin,
                    )
                elif parsed.path == "/api/company/dashboard/v2/group":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        dashboard_v2_group(
                            pool,
                            query.get("buGuid", query.get("bu_guid", [None]))[0],
                            query.get("projGuid", query.get("proj_guid", [None]))[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/dashboard/v3/group":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        dashboard_v3_group(
                            pool,
                            query.get("buGuid", query.get("bu_guid", [None]))[0],
                            query.get("projGuid", query.get("proj_guid", [None]))[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif re.fullmatch(
                    r"/api/company/dashboard/project/[A-Za-z0-9_.:-]{1,128}/(kpi|anomalies)",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    if parsed.path.endswith("/kpi"):
                        result = dashboard_project_kpi(pool, project_value, max_response_rows)
                        if result is None:
                            response(self, 404, {"error": "project not found"}, origin)
                        else:
                            response(self, 200, result, origin)
                    else:
                        response(
                            self,
                            200,
                            dashboard_project_anomalies(pool, project_value, max_response_rows),
                            origin,
                        )
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
                elif parsed.path == "/api/company/cbs/r-master":
                    response(self, 200, cbs_source_r_master(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/cbs/dict":
                    query = parse_qs(parsed.query)
                    proj_guid = query.get("projGuid", [None])[0]
                    if not proj_guid:
                        raise CommandRejected("projGuid is required", 422)
                    response(
                        self,
                        200,
                        cbs_source_dict(
                            pool,
                            proj_guid,
                            query.get("planVersion", [None])[0],
                            query.get("rCode", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/cbs/dict/f-balance":
                    query = parse_qs(parsed.query)
                    proj_guid = query.get("projGuid", [None])[0]
                    l3_code = query.get("l3Code", [None])[0]
                    if not proj_guid or not l3_code:
                        raise CommandRejected("projGuid and l3Code are required", 422)
                    result = cbs_source_f_balance(
                        pool, proj_guid, l3_code, query.get("planVersion", [None])[0], max_response_rows,
                    )
                    response(self, 200 if result.get("success") is True else 404, result, origin)
                elif parsed.path == "/api/company/cbs/versions":
                    proj_guid = parse_qs(parsed.query).get("projGuid", [None])[0]
                    if not proj_guid:
                        raise CommandRejected("projGuid is required", 422)
                    response(self, 200, cbs_source_versions(pool, proj_guid, max_response_rows), origin)
                elif parsed.path == "/api/company/cbs/versions/compare":
                    query = parse_qs(parsed.query)
                    proj_guid = query.get("projGuid", [None])[0]
                    version_a = query.get("a", [None])[0]
                    version_b = query.get("b", [None])[0]
                    if not proj_guid or not version_a or not version_b:
                        raise CommandRejected("projGuid, a, and b are required", 422)
                    response(
                        self,
                        200,
                        cbs_source_versions_compare(
                            pool,
                            proj_guid,
                            version_a,
                            version_b,
                            query.get("c", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/cbs/r0/queue":
                    proj_guid = parse_qs(parsed.query).get("projGuid", [None])[0]
                    response(self, 200, cbs_source_r0_queue(pool, proj_guid, max_response_rows), origin)
                elif parsed.path == "/api/company/cbs/approval-rules/pick":
                    query = parse_qs(parsed.query)
                    biz_type = query.get("bizType", [None])[0]
                    amount = query.get("amount", [None])[0]
                    if not biz_type or amount is None:
                        raise CommandRejected("bizType and amount are required", 422)
                    response(
                        self,
                        200,
                        cbs_source_approval_pick(pool, biz_type, float(amount), max_response_rows),
                        origin,
                    )
                elif parsed.path == "/api/company/cbs/approval-rules":
                    biz_type = parse_qs(parsed.query).get("bizType", [None])[0]
                    response(self, 200, cbs_source_approval_rules(pool, biz_type, max_response_rows), origin)
                elif parsed.path == "/api/company/cbs/changes":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        cbs_source_changes(
                            pool,
                            query.get("projGuid", [None])[0],
                            query.get("contractGuid", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/cbs/demo/contracts":
                    proj_guid = parse_qs(parsed.query).get("projGuid", [None])[0]
                    response(self, 200, cbs_source_demo_contracts(pool, proj_guid, max_response_rows), origin)
                elif parsed.path == "/api/company/fund/plans":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        fund_source_plans(
                            pool,
                            query.get("projGuid", [None])[0],
                            query.get("period", [None])[0],
                            query.get("direction", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/fund/gap-analysis":
                    proj_guid = parse_qs(parsed.query).get("projGuid", [None])[0]
                    if not proj_guid:
                        raise CommandRejected("projGuid is required", 422)
                    response(self, 200, fund_source_gap_analysis(pool, proj_guid, max_response_rows), origin)
                elif parsed.path == "/api/company/fund/dispatches":
                    response(self, 200, fund_source_dispatches(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/warning/badge":
                    response(self, 200, warning_source_badge(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/warning":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        warning_source_list(
                            pool,
                            query.get("status", ["open"])[0],
                            query.get("ruleCode", [None])[0],
                            query.get("severity", [None])[0],
                            query.get("bizType", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/warning/rules":
                    response(self, 200, warning_source_rules(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/warning/scans":
                    response(self, 200, warning_source_empty_read(pool, "scans", max_response_rows), origin)
                elif parsed.path == "/api/company/warning/custom-rules":
                    response(self, 200, warning_source_empty_read(pool, "custom-rules", max_response_rows), origin)
                elif parsed.path == "/api/company/warning/rule-templates":
                    response(self, 200, warning_source_empty_read(pool, "rule-templates", max_response_rows), origin)
                elif parsed.path == "/api/company/warning/tickets/mine":
                    response(self, 200, warning_source_empty_read(pool, "tickets", max_response_rows), origin)
                elif parsed.path == "/api/company/attachments/list":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        attachment_source_list(
                            pool,
                            query.get("bizType", [None])[0],
                            query.get("bizGuid", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif re.fullmatch(
                    r"/api/company/attachments/download/[A-Za-z0-9_.:-]{1,128}",
                    parsed.path,
                ):
                    attachment_value = parsed.path.rsplit("/", 1)[-1]
                    boundary = attachment_source_download(
                        pool, attachment_value, max_response_rows,
                    )
                    response(self, 404, boundary, origin)
                elif parsed.path == "/api/company/attachments/all" or parsed.path == "/api/company/attachments":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        attachment_source_all(
                            pool,
                            query.get("bizType", [None])[0],
                            query.get("uploadedBy", [None])[0],
                            query.get("aiStatus", [None])[0],
                            query.get("keyword", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/attachments/stats":
                    response(self, 200, attachment_source_stats(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/marketing/campaigns":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        marketing_source_campaigns(
                            pool,
                            query.get("projGuid", [None])[0],
                            query.get("state", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/marketing/placements":
                    campaign_guid = parse_qs(parsed.query).get("campaignGuid", [None])[0]
                    response(self, 200, marketing_source_placements(pool, campaign_guid, max_response_rows), origin)
                elif parsed.path == "/api/company/marketing/channels":
                    response(self, 200, marketing_source_channels(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/marketing/materials":
                    proj_guid = parse_qs(parsed.query).get("projGuid", [None])[0]
                    response(self, 200, marketing_source_materials(pool, proj_guid, max_response_rows), origin)
                elif parsed.path == "/api/company/ai-stats/overview":
                    period = parse_qs(parsed.query).get("period", ["month"])[0]
                    response(self, 200, ai_stats_source_overview(pool, period, max_response_rows), origin)
                elif parsed.path == "/api/company/ai-stats/activity":
                    query = parse_qs(parsed.query)
                    try:
                        limit = int(query.get("limit", ["30"])[0])
                    except (TypeError, ValueError) as error:
                        raise ValueError("invalid AI activity limit") from error
                    response(self, 200, ai_stats_source_activity(pool, limit, max_response_rows), origin)
                elif parsed.path == "/api/company/ai-stats/badge":
                    query = parse_qs(parsed.query)
                    biz_type = query.get("bizType", [None])[0]
                    biz_guid = query.get("bizGuid", [None])[0]
                    if not biz_type or not biz_guid:
                        raise CommandRejected("bizType and bizGuid are required", 422)
                    if not IDENTIFIER.fullmatch(biz_type) or not IDENTIFIER.fullmatch(biz_guid):
                        raise CommandRejected("invalid AI badge identifiers", 422)
                    response(
                        self,
                        200,
                        ai_stats_source_badge(pool, biz_type, biz_guid, max_response_rows),
                        origin,
                    )
                elif parsed.path == "/api/company/ai-hub/corrections":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        ai_hub_corrections(
                            pool,
                            query.get("bizType", [None])[0],
                            query.get("field", [None])[0],
                            query.get("userCode", [None])[0],
                            _ai_hub_limit(query.get("limit", [None])[0]),
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/ai-hub/correction-stats":
                    response(self, 200, ai_hub_correction_stats(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/ai-hub/drafts":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        ai_hub_drafts(pool, query.get("userCode", [None])[0], max_response_rows),
                        origin,
                    )
                elif re.fullmatch(r"/api/company/ai-hub/drafts/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    query = parse_qs(parsed.query)
                    draft_id = parsed.path.rsplit("/", 1)[-1]
                    result = ai_hub_draft(
                        pool, draft_id, query.get("userCode", [None])[0], max_response_rows,
                    )
                    if result is None:
                        response(
                            self,
                            404,
                            {"success": False, "code": 43001, "message": "草稿不存在"},
                            origin,
                        )
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/ai-hub/query-log":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        ai_hub_query_log(pool, query.get("userCode", [None])[0], max_response_rows),
                        origin,
                    )
                elif parsed.path == "/api/company/ai-hub/usage-stats":
                    response(self, 200, ai_hub_usage_stats(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/webhook/config":
                    response(self, 200, webhook_source_config(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/admin/ocr/status":
                    response(self, 200, ocr_source_status(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/admin/error-log":
                    query = parse_qs(parsed.query)
                    try:
                        limit = int(query.get("limit", ["100"])[0])
                    except (TypeError, ValueError) as error:
                        raise ValueError("invalid error log limit") from error
                    response(
                        self,
                        200,
                        error_log_source_rows(
                            pool,
                            query.get("keyword", [None])[0],
                            limit,
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/notify/messages":
                    query = parse_qs(parsed.query)
                    try:
                        limit = int(query.get("limit", ["50"])[0])
                        offset = int(query.get("offset", ["0"])[0])
                    except (TypeError, ValueError) as error:
                        raise ValueError("invalid notification pagination") from error
                    response(
                        self,
                        200,
                        notification_source_messages(
                            pool,
                            query.get("userCode", [None])[0],
                            query.get("status", ["unread"])[0],
                            limit,
                            offset,
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/notify/messages/unread-count":
                    user_code = parse_qs(parsed.query).get("userCode", [None])[0]
                    response(self, 200, notification_source_unread_count(pool, user_code, max_response_rows), origin)
                elif parsed.path == "/api/company/notify/subscriptions":
                    user_code = parse_qs(parsed.query).get("userCode", [None])[0]
                    response(self, 200, notification_source_subscriptions(pool, user_code, max_response_rows), origin)
                elif parsed.path == "/api/company/notify/config":
                    response(self, 200, notification_source_config(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/notify/email-outbox":
                    response(self, 200, notification_source_email_outbox(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/notify/digest/preview":
                    response(self, 200, notification_source_digest_preview(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/notify/digest/log":
                    response(self, 200, notification_source_digest_log(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/notify/llm-providers":
                    response(self, 200, notification_source_llm_providers(pool, max_response_rows), origin)
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
                    r"/api/company/investment/projects/[A-Za-z0-9_.:-]{1,128}/excel-imports",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    response(self, 200, investment_imports(pool, project_value, max_response_rows), origin)
                elif re.fullmatch(
                    r"/api/company/investment/excel-imports/[A-Za-z0-9_.:-]{1,128}",
                    parsed.path,
                ):
                    import_value = parsed.path.rsplit("/", 1)[-1]
                    result = investment_import_detail(pool, import_value, max_response_rows)
                    if result is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "导入记录不存在"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif re.fullmatch(
                    r"/api/company/investment/excel-imports/[A-Za-z0-9_.:-]{1,128}/bridge-plan",
                    parsed.path,
                ):
                    import_value = parsed.path.split("/")[-2]
                    result = investment_import_bridge_plan(pool, import_value, max_response_rows)
                    if result is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "导入记录不存在"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif re.fullmatch(
                    r"/api/company/investment/excel-imports/[A-Za-z0-9_.:-]{1,128}/index-upsert-preview",
                    parsed.path,
                ):
                    import_value = parsed.path.split("/")[-2]
                    result = investment_index_upsert_preview(pool, import_value, max_response_rows)
                    if result is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "导入记录不存在"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif re.fullmatch(
                    r"/api/company/investment/excel-imports/[A-Za-z0-9_.:-]{1,128}/profit-table",
                    parsed.path,
                ):
                    import_value = parsed.path.split("/")[-2]
                    result = investment_profit_table(pool, import_value, max_response_rows)
                    if result is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "导入记录不存在"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif re.fullmatch(
                    r"/api/company/investment/excel-imports/[A-Za-z0-9_.:-]{1,128}/plan-line-preview",
                    parsed.path,
                ):
                    import_value = parsed.path.split("/")[-2]
                    result = investment_plan_line_preview(pool, import_value, max_response_rows)
                    if result is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "导入记录不存在"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif re.fullmatch(
                    r"/api/company/investment/projects/[A-Za-z0-9_.:-]{1,128}/plan-lines",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        investment_plan_lines(
                            pool,
                            project_value,
                            {
                                "versionGuid": query.get("versionGuid", [None])[0],
                                "moduleCode": query.get("moduleCode", [None])[0],
                                "sheet": query.get("sheet", [None])[0],
                                "department": query.get("department", [None])[0],
                                "status": query.get("status", [None])[0],
                                "keyword": query.get("keyword", [None])[0],
                            },
                            max_response_rows,
                        ),
                        origin,
                    )
                elif re.fullmatch(
                    r"/api/company/investment/projects/[A-Za-z0-9_.:-]{1,128}/subject-mappings",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    result = investment_subject_mappings(pool, project_value, max_response_rows)
                    if result is None:
                        response(self, 404, {"success": False, "code": 41001, "message": "项目不存在"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif re.fullmatch(
                    r"/api/company/investment/projects/[A-Za-z0-9_.:-]{1,128}/profit-cockpit",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    result = investment_profit_cockpit(pool, project_value, max_response_rows)
                    if result is None:
                        response(self, 404, {"success": False, "code": 41002, "message": "该项目暂无利润测算总表数据"}, origin)
                    else:
                        response(self, 200, result, origin)
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
                    r"/api/company/investment/projects/[A-Za-z0-9_.:-]{1,128}/sensitivity",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    response(self, 200, investment_sensitivity(pool, project_value, max_response_rows), origin)
                elif re.fullmatch(
                    r"/api/company/investment/projects/[A-Za-z0-9_.:-]{1,128}/profit-actual-v2",
                    parsed.path,
                ):
                    project_value = parsed.path.split("/")[-2]
                    plan_version = parse_qs(parsed.query).get("planVersion", [None])[0]
                    result = cost_dashboard_v3(pool, project_value, plan_version, max_response_rows)
                    if result is None:
                        response(self, 404, {"error": "project not found"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/admin/dict/groups":
                    response(self, 200, admin_dict_groups(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/admin/quality/overview":
                    response(self, 200, admin_quality_overview(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/rbac/users":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        admin_rbac_users(
                            pool,
                            query.get("keyword", [None])[0],
                            query.get("enabled", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/rbac/me":
                    user_code = parse_qs(parsed.query).get("userCode", [""])[0]
                    result = rbac_current_user(pool, user_code, max_response_rows)
                    if result is None:
                        response(self, 404, {"error": "user not found"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/rbac/roles":
                    response(self, 200, rbac_roles(pool, max_response_rows), origin)
                elif re.fullmatch(r"/api/company/rbac/roles/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    result = rbac_role_detail(
                        pool, parsed.path.rsplit("/", 1)[-1], max_response_rows,
                    )
                    if result is None:
                        response(self, 404, {"error": "role not found"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/rbac/permission-catalog":
                    response(self, 200, rbac_permission_catalog(), origin)
                elif parsed.path == "/api/company/admin/dict/options":
                    group_name = parse_qs(parsed.query).get("groupName", [None])[0]
                    response(self, 200, admin_dict_options(pool, group_name, max_response_rows), origin)
                elif parsed.path == "/api/company/admin/audit/logs":
                    query = parse_qs(parsed.query)
                    try:
                        limit = int(query.get("limit", ["100"])[0])
                        offset = int(query.get("offset", ["0"])[0])
                    except (TypeError, ValueError) as error:
                        raise ValueError("invalid audit pagination") from error
                    response(
                        self,
                        200,
                        admin_audit_logs(
                            pool,
                            query.get("action", [None])[0],
                            query.get("userId", [None])[0],
                            query.get("targetType", [None])[0],
                            limit,
                            offset,
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/admin/audit/actions":
                    response(self, 200, admin_audit_actions(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/admin/health/tables":
                    response(self, 200, admin_health_tables(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/admin/health/bpm-pool":
                    response(self, 200, admin_health_bpm_pool(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/admin/health/full":
                    response(self, 200, admin_health_full(pool, max_response_rows, database_name), origin)
                elif parsed.path == "/api/company/admin/llm/status":
                    response(self, 200, admin_llm_status(pool, max_response_rows), origin)
                elif parsed.path == "/api/company/admin/ai/diag":
                    response(self, 200, admin_ai_diag(pool, max_response_rows), origin)
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
                elif parsed.path == "/api/company/source/budget/users-in-bu":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        budget_source_users_in_bu(
                            pool,
                            query.get("buGuid", query.get("bu_guid", [None]))[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/source/budget/my-loan-balance":
                    query = parse_qs(parsed.query)
                    result = budget_source_my_loan_balance(
                        pool,
                        query.get("userCode", query.get("user_code", [None]))[0],
                        query.get("userId", query.get("user_id", [None]))[0],
                        max_response_rows,
                    )
                    if result is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "用户不存在"}, origin)
                    else:
                        response(self, 200, result, origin)
                elif parsed.path == "/api/company/source/workflow/tasks/mine":
                    query = parse_qs(parsed.query)
                    user_id = _workflow_resolve_user_id(
                        pool,
                        query.get("userId", query.get("user_id", [None]))[0],
                        query.get("userCode", query.get("user_code", [None]))[0],
                        max_response_rows,
                    )
                    response(
                        self,
                        200,
                        workflow_source_tasks_mine(
                            pool,
                            user_id,
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/source/workflow/tasks/initiated":
                    query = parse_qs(parsed.query)
                    user_id = _workflow_resolve_user_id(
                        pool,
                        query.get("userId", query.get("user_id", [None]))[0],
                        query.get("userCode", query.get("user_code", [None]))[0],
                        max_response_rows,
                    )
                    response(
                        self,
                        200,
                        workflow_source_tasks_initiated(
                            pool,
                            user_id,
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/source/workflow/tasks/my-history":
                    query = parse_qs(parsed.query)
                    user_id = _workflow_resolve_user_id(
                        pool,
                        query.get("userId", query.get("user_id", [None]))[0],
                        query.get("userCode", query.get("user_code", [None]))[0],
                        max_response_rows,
                    )
                    response(
                        self,
                        200,
                        workflow_source_history(
                            pool,
                            user_id,
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/source/workflow/instances/by-biz":
                    query = parse_qs(parsed.query)
                    biz_type = query.get("bizType", query.get("biz_type", [""]))[0]
                    biz_guid = query.get("bizDataGuid", query.get("biz_data_guid", [""]))[0]
                    if not biz_type or not biz_guid:
                        raise CommandRejected("bizType / bizDataGuid 必填", 422)
                    response(self, 200, workflow_source_instance_by_biz(pool, biz_type, biz_guid, max_response_rows), origin)
                elif re.fullmatch(r"/api/company/source/workflow/instances/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    instance_id = parsed.path.rsplit("/", 1)[-1]
                    result = workflow_source_instance_detail(pool, instance_id, max_response_rows)
                    if result is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "流程实例不存在"}, origin)
                    else:
                        response(self, 200, result, origin)
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
                elif parsed.path == "/api/company/source/delivery/progress":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        source_delivery_progress(
                            pool,
                            query.get("projGuid", query.get("project_id", [None]))[0],
                            max_response_rows,
                        ),
                        origin,
                    )
                elif parsed.path == "/api/company/source/delivery/outputs":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        source_delivery_outputs(
                            pool,
                            query.get("projGuid", query.get("project_id", [None]))[0],
                            query.get("period", [None])[0],
                            query.get("state", [None])[0],
                            max_response_rows,
                        ),
                        origin,
                    )
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
                database_name=args.database,
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
