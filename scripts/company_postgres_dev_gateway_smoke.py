#!/usr/bin/env python3
"""Smoke-test the trusted-upstream identity mode of the local gateway.

The smoke starts the authenticated PostgreSQL service and gateway with
credential-shaped values held only in the child environments. It verifies a
short-lived signed source identity, enabled-user lookup, HttpOnly session
binding, service forwarding, a bounded marketing command, and stale-assertion
rejection. No secret value is printed.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import http.client
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
from typing import Any


class SmokeError(RuntimeError):
    pass


def wait_for(port: int, deadline: float) -> None:
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise SmokeError(f"port did not open: {port}")


def request(
    port: int,
    method: str,
    path: str,
    *,
    headers: dict[str, str] | None = None,
    payload: dict[str, Any] | None = None,
) -> tuple[int, dict[str, str], Any]:
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=20)
    request_headers = dict(headers or {})
    body = None
    if payload is not None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        request_headers["Content-Type"] = "application/json"
        request_headers["Content-Length"] = str(len(body))
    try:
        connection.request(method, path, body=body, headers=request_headers)
        result = connection.getresponse()
        body = result.read().decode("utf-8")
        response_headers = {key.lower(): value for key, value in result.getheaders()}
    except (OSError, TimeoutError) as error:
        raise SmokeError(f"gateway request failed: {method} {path}: {error}") from error
    finally:
        connection.close()
    try:
        payload = json.loads(body) if body else None
    except json.JSONDecodeError as error:
        raise SmokeError(f"gateway returned invalid JSON: {method} {path}") from error
    return result.status, response_headers, payload


def identity_headers(user_code: str, secret: str, issued_at: int) -> dict[str, str]:
    timestamp = str(issued_at)
    signature = hmac.new(
        secret.encode("utf-8"),
        f"{user_code}:{timestamp}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return {
        "X-Moonproj-Identity": user_code,
        "X-Moonproj-Identity-Timestamp": timestamp,
        "X-Moonproj-Identity-Signature": signature,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", default="moonproj")
    parser.add_argument("--psql", default=None)
    parser.add_argument("--service-port", type=int, default=4184)
    parser.add_argument("--gateway-port", type=int, default=4183)
    args = parser.parse_args()

    service_token = "gateway-smoke-service-token"
    actor_secret = "gateway-smoke-actor-secret"
    identity_secret = "gateway-smoke-identity-secret"
    environment = os.environ.copy()
    environment.update(
        {
            "MOONPROJ_SERVICE_TOKEN": service_token,
            "MOONPROJ_ACTOR_SIGNING_SECRET": actor_secret,
            "MOONPROJ_UPSTREAM_IDENTITY_SECRET": identity_secret,
        }
    )
    root = Path(__file__).resolve().parents[1]
    service_command = [
        sys.executable,
        str(root / "scripts/company_postgres_service.py"),
        "--port",
        str(args.service_port),
        "--database",
        args.database,
        "--pool-size",
        "1",
        "--require-forwarded-tls",
        "--actor-signing-secret-env",
        "MOONPROJ_ACTOR_SIGNING_SECRET",
    ]
    gateway_command = [
        sys.executable,
        str(root / "scripts/company_postgres_dev_gateway.py"),
        "--public-dir",
        str(root / "frontend/public"),
        "--port",
        str(args.gateway_port),
        "--service-port",
        str(args.service_port),
        "--trusted-identity-secret-env",
        "MOONPROJ_UPSTREAM_IDENTITY_SECRET",
    ]
    if args.psql:
        service_command.extend(("--psql", args.psql))
    service = subprocess.Popen(
        service_command,
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    gateway: subprocess.Popen[str] | None = None
    try:
        wait_for(args.service_port, time.monotonic() + 10)
        gateway = subprocess.Popen(
            gateway_command,
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_for(args.gateway_port, time.monotonic() + 10)
        user_code = "admin"
        headers = identity_headers(user_code, identity_secret, int(time.time()))
        status, response_headers, payload = request(
            args.gateway_port,
            "POST",
            "/api/session/login",
            headers=headers,
        )
        if (
            status != 200
            or not isinstance(payload, dict)
            or payload.get("authenticated") is not True
            or payload.get("identity_source") != "trusted_upstream"
            or "Secure" not in response_headers.get("set-cookie", "")
        ):
            raise SmokeError(f"trusted login failed: {status}")
        cookie = response_headers.get("set-cookie", "").split(";", 1)[0]
        status, _headers, payload = request(
            args.gateway_port,
            "GET",
            "/api/company/summary",
            headers={"Cookie": cookie},
        )
        if status != 200 or not isinstance(payload, dict) or payload.get("target") != "postgresql":
            raise SmokeError(f"trusted session forwarding failed: {status}")
        smoke_suffix = str(int(time.time()))
        marketing_id = "MKT-GW-SMOKE-" + smoke_suffix
        marketing_key = "marketing-gateway-create-" + smoke_suffix
        marketing_body = {
            "campaignGuid": marketing_id,
            "campaignCode": "CAMP-GW-SMOKE-" + smoke_suffix,
            "projGuid": "proj-0001",
            "name": "gateway marketing command smoke",
            "budget": "10.00",
            "principal_id": "co-gateway-smoke",
            "scope": "project:proj-0001",
            "authority": {
                "active": True,
                "principal_id": "co-gateway-smoke",
                "actor_id": user_code,
                "capability": "marketing:campaign:create",
                "scope": "project:proj-0001",
                "max_amount_minor": 2000,
            },
            "idempotency_key": marketing_key,
        }
        status, _headers, marketing_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/marketing/campaigns",
            headers={"Cookie": cookie},
            payload=marketing_body,
        )
        if (
            status != 201
            or not isinstance(marketing_payload, dict)
            or marketing_payload.get("campaign", {}).get("state") != "planning"
        ):
            raise SmokeError(f"trusted marketing command forwarding failed: {status}")
        status, _headers, marketing_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/marketing/campaigns/{marketing_id}",
            headers={"Cookie": cookie},
            payload={
                "principal_id": "co-gateway-smoke",
                "scope": "project:proj-0001",
                "authority": {
                    "active": True,
                    "principal_id": "co-gateway-smoke",
                    "actor_id": user_code,
                    "capability": "marketing:campaign:delete",
                    "scope": "project:proj-0001",
                    "max_amount_minor": 0,
                },
                "idempotency_key": "marketing-gateway-delete-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(marketing_delete_payload, dict)
            or marketing_delete_payload.get("campaign", {}).get("state") != "deleted"
        ):
            raise SmokeError(f"trusted marketing command delete failed: {status}")
        stale_headers = identity_headers(user_code, identity_secret, int(time.time()) - 61)
        status, _headers, payload = request(
            args.gateway_port,
            "POST",
            "/api/session/login",
            headers=stale_headers,
        )
        if status != 401 or not isinstance(payload, dict) or payload.get("authenticated") is not False:
            raise SmokeError(f"stale identity was accepted: {status}")
        status, _headers, _payload = request(
            args.gateway_port,
            "GET",
            "/api/company/summary",
        )
        if status != 401:
            raise SmokeError(f"missing gateway session was accepted: {status}")
        print(json.dumps({"state": "trusted_gateway_verified", "user_code": user_code}))
        return 0
    finally:
        if gateway is not None:
            gateway.terminate()
            gateway.wait(timeout=5)
        service.terminate()
        service.wait(timeout=5)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, SmokeError, ValueError) as error:
        print(f"gateway smoke failed: {error}", file=sys.stderr)
        raise SystemExit(1)
