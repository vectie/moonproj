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
from pathlib import Path
from typing import Any


class SmokeError(RuntimeError):
    pass


def request(port: int, path: str, *, token: str | None, forwarded_tls: bool = True) -> tuple[int, dict[str, Any] | None]:
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    headers: dict[str, str] = {}
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    if forwarded_tls:
        headers["X-Forwarded-Proto"] = "https"
    connection.request("GET", path, headers=headers)
    result = connection.getresponse()
    body = result.read().decode("utf-8")
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
        connection = http.client.HTTPConnection("127.0.0.1", args.port, timeout=5)
        connection.request("POST", "/api/company/summary")
        status = connection.getresponse().status
        connection.close()
        if status != 405:
            raise SmokeError(f"mutation method was not rejected: {status}")
        print(json.dumps({"state": "service_verified", "port": args.port, "database": args.database}, sort_keys=True))
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
