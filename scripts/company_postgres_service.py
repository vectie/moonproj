#!/usr/bin/env python3
"""Run the authenticated, fixed-read PostgreSQL company service.

The rehearsal adapters and the browser read-model server intentionally use one
``psql`` process per query.  This service keeps bounded, reusable PostgreSQL
sessions behind a fixed HTTP read surface so the service contract can be
exercised without introducing a third-party runtime dependency.  The managed
deployment still owns TLS termination, token issuance, observability sinks,
and provider-level capacity controls.

Only these GET endpoints exist:

* ``/api/health``
* ``/api/company/summary``
* ``/api/company/receipts``
* ``/api/company/projections?aggregate_type=<optional>``

The bearer token is read from an environment variable named by
``--token-env``.  The token itself is never accepted as a command-line
argument or written to logs.
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
        "read_only": True,
        "schema_version": schema_version,
        "raw_records": raw,
        "aggregate_projections": projections,
        "accounting_links": links,
        "receipts": receipts,
    }


def health(pool: PsqlPool, expected_schema_version: int) -> dict[str, Any]:
    summary(pool, expected_schema_version)
    return {"ok": True, "target": "postgresql", "read_only": True, "schema_version": expected_schema_version}


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

        def do_OPTIONS(self) -> None:  # noqa: N802
            origin = self.headers.get("Origin")
            if origin not in cors_origins:
                response(self, 403, {"error": "origin not allowed"}, None)
                return
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
            self.send_header("Vary", "Origin")
            self.end_headers()

        def do_GET(self) -> None:  # noqa: N802
            origin = self._origin()
            if origin == "":
                response(self, 403, {"error": "origin not allowed"}, None)
                return
            if not self._tls_ok():
                response(self, 400, {"error": "forwarded TLS is required"}, origin)
                return
            if not self._authorized():
                self.send_response(401)
                self.send_header("WWW-Authenticate", "Bearer")
                self.end_headers()
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
                elif parsed.path.startswith("/api/"):
                    response(self, 404, {"error": "unknown read-model endpoint"}, origin)
                else:
                    response(self, 404, {"error": "not found"}, origin)
            except PoolExhausted as error:
                response(self, 503, {"error": str(error)}, origin)
            except (OSError, ServiceError, ValueError) as error:
                response(self, 503, {"error": str(error)}, origin)

        def do_POST(self) -> None:  # noqa: N802
            response(self, 405, {"error": "mutation endpoints are disabled"}, self._origin() or None)

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
