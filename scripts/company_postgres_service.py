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

The bearer token is read from an environment variable named by
``--token-env``.  The token itself is never accepted as a command-line
argument or written to logs. When ``--actor-signing-secret-env`` is supplied,
company commands also require a gateway-signed actor assertion.
"""

from __future__ import annotations

import argparse
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
        "capabilities": ["read_model", "expense_command", "contract_command", "audit_receipt"],
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
        "capabilities": ["read_model", "expense_command", "contract_command", "audit_receipt"],
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

        def do_OPTIONS(self) -> None:  # noqa: N802
            origin = self.headers.get("Origin")
            if origin not in cors_origins:
                response(self, 403, {"error": "origin not allowed"}, None)
                return
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
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
                else:
                    expense_match = re.fullmatch(
                        r"/api/company/expenses/([A-Za-z0-9_.:-]{1,128})/(submit|approve|reject|resubmit)",
                        parsed.path,
                    )
                    contract_match = re.fullmatch(
                        r"/api/company/contracts/([A-Za-z0-9_.:-]{1,128})/(submit|approve|reject|resubmit)",
                        parsed.path,
                    )
                    if expense_match is not None:
                        aggregate_id, command_type = expense_match.group(1), expense_match.group(2)
                    elif contract_match is not None:
                        command_family = "contract"
                        aggregate_id, command_type = contract_match.group(1), contract_match.group(2)
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
                else:
                    result = expense_command(
                        pool,
                        command_type=command_type,
                        expense_id=aggregate_id,
                        body=body,
                        actor_id=actor,
                        idempotency_key=idempotency_key,
                    )
                status = 201 if command_type == "create" and not result["idempotent_replay"] else 200
                response(self, status, result, origin)
            except PoolExhausted as error:
                response(self, 503, {"error": str(error)}, origin)
            except CommandRejected as error:
                response(self, error.status, {"error": str(error)}, origin)
            except (OSError, ServiceError, ValueError) as error:
                response(self, 503, {"error": str(error)}, origin)

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
