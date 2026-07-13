#!/usr/bin/env python3
"""Smoke-test the authenticated fixed-read PostgreSQL service locally."""

from __future__ import annotations

import argparse
import http.client
import json
import os
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any


class SmokeError(RuntimeError):
    pass


def request(
    port: int,
    path: str,
    *,
    token: str | None,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
    idempotency_key: str | None = None,
    forwarded_tls: bool = True,
) -> tuple[int, dict[str, Any] | None]:
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    headers: dict[str, str] = {}
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    if forwarded_tls:
        headers["X-Forwarded-Proto"] = "https"
    body = None
    if payload is not None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = str(len(body))
    if idempotency_key is not None:
        headers["Idempotency-Key"] = idempotency_key
    try:
        connection.request(method, path, body=body, headers=headers)
        result = connection.getresponse()
        body = result.read().decode("utf-8")
    except (OSError, TimeoutError) as error:
        connection.close()
        raise SmokeError(f"{method} {path} request failed: {error}") from error
    connection.close()
    try:
        payload = json.loads(body) if body else None
    except json.JSONDecodeError as error:
        raise SmokeError(f"invalid JSON response from {path}: {body}") from error
    return result.status, payload


def wait_for(port: int, deadline: float) -> None:
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise SmokeError("service did not start")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", default="moonproj")
    parser.add_argument("--port", type=int, default=4175)
    parser.add_argument("--psql", default=None)
    args = parser.parse_args()
    token = "moonproj-smoke-token"
    environment = os.environ.copy()
    environment["MOONPROJ_SERVICE_TOKEN"] = token
    command = [
        sys.executable,
        str(Path(__file__).with_name("company_postgres_service.py")),
        "--port",
        str(args.port),
        "--database",
        args.database,
        "--pool-size",
        "1",
        "--acquire-timeout",
        "1",
        "--require-forwarded-tls",
    ]
    if args.psql:
        command.extend(("--psql", args.psql))
    process = subprocess.Popen(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        wait_for(args.port, time.monotonic() + 10)
        status, payload = request(args.port, "/api/health", token=token)
        if status != 200 or payload is None or payload.get("ok") is not True:
            raise SmokeError(f"health failed: {status} {payload}")
        status, payload = request(args.port, "/api/company/summary", token=token)
        if status != 200 or payload is None or payload.get("target") != "postgresql":
            raise SmokeError(f"summary failed: {status} {payload}")
        status, payload = request(args.port, "/api/company/projections?aggregate_type=notification_outbox", token=token)
        if status != 200 or payload is None or not isinstance(payload.get("items"), list):
            raise SmokeError(f"projection query failed: {status} {payload}")
        status, _ = request(args.port, "/api/health", token=None)
        if status != 401:
            raise SmokeError(f"missing bearer token was not rejected: {status}")
        status, _ = request(args.port, "/api/health", token=token, forwarded_tls=False)
        if status != 400:
            raise SmokeError(f"missing forwarded TLS was not rejected: {status}")
        nonce = uuid.uuid4().hex[:10]
        expense_id = "EXP-SMOKE-" + nonce
        create_payload = {
            "expense_id": expense_id,
            "employee_id": "smoke-employee",
            "summary": "service command smoke",
            "amount_minor": 8560,
            "currency": "CNY",
            "project_id": "CD-HJL",
            "cost_subject": "travel",
        }
        status, payload = request(
            args.port,
            "/api/company/expenses",
            token=token,
            method="POST",
            payload=create_payload,
            idempotency_key="smoke-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("expense", {}).get("state") != "draft":
            raise SmokeError(f"expense create failed: {status} {payload}")
        status, payload = request(
            args.port,
            "/api/company/expenses",
            token=token,
            method="POST",
            payload=create_payload,
            idempotency_key="smoke-create-" + nonce,
        )
        if status != 200 or payload is None or payload.get("idempotent_replay") is not True:
            raise SmokeError(f"expense idempotency failed: {status} {payload}")
        conflicting_payload = dict(create_payload)
        conflicting_payload["summary"] = "different request"
        status, payload = request(
            args.port,
            "/api/company/expenses",
            token=token,
            method="POST",
            payload=conflicting_payload,
            idempotency_key="smoke-create-" + nonce,
        )
        if status != 409:
            raise SmokeError(f"idempotency conflict was not rejected: {status} {payload}")
        transitions = [("submit", "submitted"), ("reject", "rejected"), ("resubmit", "submitted"), ("approve", "approved")]
        for index, (command, expected_state) in enumerate(transitions):
            key = f"smoke-{command}-{nonce}"
            status, payload = request(
                args.port,
                f"/api/company/expenses/{expense_id}/{command}",
                token=token,
                method="POST",
                payload={},
                idempotency_key=key,
            )
            if status != 200 or payload is None or payload.get("expense", {}).get("state") != expected_state:
                raise SmokeError(f"expense {command} failed: {status} {payload}")
            if index == len(transitions) - 1:
                status, replay = request(
                    args.port,
                    f"/api/company/expenses/{expense_id}/{command}",
                    token=token,
                    method="POST",
                    payload={},
                    idempotency_key=key,
                )
                if status != 200 or replay is None or replay.get("idempotent_replay") is not True:
                    raise SmokeError(f"expense transition idempotency failed: {status} {replay}")
        status, payload = request(args.port, f"/api/company/expenses/{expense_id}", token=token)
        if status != 200 or payload is None or payload.get("payload", {}).get("state") != "approved":
            raise SmokeError(f"expense detail failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/expenses/{expense_id}/submit",
            token=token,
            method="POST",
            payload={},
            idempotency_key="smoke-invalid-" + nonce,
        )
        if status != 409:
            raise SmokeError(f"invalid expense transition was not rejected: {status} {payload}")
        print(json.dumps({"state": "service_verified", "expense_state": "approved", "port": args.port, "database": args.database}, sort_keys=True))
        return 0
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, SmokeError, ValueError) as error:
        print(f"PostgreSQL service smoke failed: {error}", file=sys.stderr)
        raise SystemExit(1)
