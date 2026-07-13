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
        status, payload = request(args.port, "/api/company/tenders", token=token)
        if status != 200 or payload is None or not isinstance(payload.get("items"), list):
            raise SmokeError(f"tender read failed: {status} {payload}")
        status, payload = request(args.port, "/api/company/suppliers", token=token)
        if status != 200 or payload is None or not isinstance(payload.get("items"), list):
            raise SmokeError(f"supplier read failed: {status} {payload}")
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
        contract_id = "CT-SMOKE-" + nonce
        contract_payload = {
            "contract_id": contract_id,
            "contract_code": "HT-SMOKE-" + nonce,
            "contract_name": "service command smoke contract",
            "project_id": "CD-HJL",
            "project_name": "成都和锦里",
            "supplier_id": "smoke-supplier",
            "supplier_name": "smoke supplier",
            "sign_date": "2026-07-13",
            "amount_minor": 1234500,
            "currency": "CNY",
        }
        status, payload = request(
            args.port,
            "/api/company/contracts",
            token=token,
            method="POST",
            payload=contract_payload,
            idempotency_key="contract-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("contract", {}).get("state") != "draft":
            raise SmokeError(f"contract create failed: {status} {payload}")
        status, payload = request(
            args.port,
            "/api/company/contracts",
            token=token,
            method="POST",
            payload=contract_payload,
            idempotency_key="contract-create-" + nonce,
        )
        if status != 200 or payload is None or payload.get("idempotent_replay") is not True:
            raise SmokeError(f"contract idempotency failed: {status} {payload}")
        transitions = [
            ("submit", "submitted"),
            ("reject", "rejected"),
            ("resubmit", "submitted"),
            ("approve", "approved"),
        ]
        for command, expected_state in transitions:
            status, payload = request(
                args.port,
                f"/api/company/contracts/{contract_id}/{command}",
                token=token,
                method="POST",
                payload={},
                idempotency_key=f"contract-{command}-{nonce}",
            )
            if status != 200 or payload is None or payload.get("contract", {}).get("state") != expected_state:
                raise SmokeError(f"contract {command} failed: {status} {payload}")
        status, payload = request(args.port, f"/api/company/contracts/{contract_id}", token=token)
        if status != 200 or payload is None or payload.get("state") != "approved":
            raise SmokeError(f"contract detail failed: {status} {payload}")
        apply_id = "PAY-SMOKE-" + nonce
        payment_payload = {
            "apply_id": apply_id,
            "apply_code": "FK-SMOKE-" + nonce,
            "contract_id": "ht-tj-001",
            "plan_id": "plan-tj-001-2",
            "subject": "service command smoke payment application",
            "amount_minor": 10000000,
            "currency": "CNY",
            "apply_type_code": "WORK_PROGRESS",
        }
        status, payload = request(
            args.port,
            "/api/company/payment-applies",
            token=token,
            method="POST",
            payload=payment_payload,
            idempotency_key="payment-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("payment_application", {}).get("state") != "draft":
            raise SmokeError(f"payment application create failed: {status} {payload}")
        status, payload = request(
            args.port,
            "/api/company/payment-applies",
            token=token,
            method="POST",
            payload=payment_payload,
            idempotency_key="payment-create-" + nonce,
        )
        if status != 200 or payload is None or payload.get("idempotent_replay") is not True:
            raise SmokeError(f"payment application idempotency failed: {status} {payload}")
        status, payload = request(
            args.port,
            "/api/company/payment-applies/eligibility?plan_id=plan-tj-001-2&amount_minor=10000000",
            token=token,
        )
        if status != 200 or payload is None or payload.get("early_flag") is not True or payload.get("over_pay") is not False:
            raise SmokeError(f"payment eligibility failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/payment-applies/{apply_id}/submit",
            token=token,
            method="POST",
            payload={},
            idempotency_key=f"payment-submit-{nonce}",
        )
        if status != 200 or payload is None or payload.get("payment_application", {}).get("state") != "submitted":
            raise SmokeError(f"payment application submit failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/payment-applies/{apply_id}/update",
            token=token,
            method="POST",
            payload={
                "subject": "service command smoke payment application updated",
                "amount_minor": 11000000,
                "apply_type_code": "PURCHASE",
            },
            idempotency_key=f"payment-update-{nonce}",
        )
        if status != 200 or payload is None or payload.get("payment_application", {}).get("state") != "submitted":
            raise SmokeError(f"payment application update failed: {status} {payload}")
        payment_transitions = [
            ("reject", "rejected"),
            ("resubmit", "submitted"),
            ("approve", "approved"),
        ]
        for command, expected_state in payment_transitions:
            status, payload = request(
                args.port,
                f"/api/company/payment-applies/{apply_id}/{command}",
                token=token,
                method="POST",
                payload={},
                idempotency_key=f"payment-{command}-{nonce}",
            )
            if (
                status != 200
                or payload is None
                or payload.get("payment_application", {}).get("state") != expected_state
            ):
                raise SmokeError(f"payment application {command} failed: {status} {payload}")
        status, payload = request(args.port, f"/api/company/payment-applies/{apply_id}", token=token)
        if status != 200 or payload is None or payload.get("operation_state") != "approved":
            raise SmokeError(f"payment application detail failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/payment-applies/{apply_id}/void",
            token=token,
            method="POST",
            payload={"reason": "service control smoke void"},
            idempotency_key=f"payment-void-{nonce}",
        )
        if status != 200 or payload is None or payload.get("payment_application", {}).get("state") != "voided":
            raise SmokeError(f"payment application void failed: {status} {payload}")
        status, payload = request(args.port, f"/api/company/payment-applies/{apply_id}", token=token)
        if status != 200 or payload is None or payload.get("operation_state") != "voided":
            raise SmokeError(f"payment application void detail failed: {status} {payload}")
        tender_id = "TD-SMOKE-" + nonce
        tender_payload = {
            "tender_id": tender_id,
            "project_scope": "project:CD-HJL",
            "name": "service command smoke tender",
            "category": "construction",
            "estimated_amount_minor": 1200000,
            "currency": "CNY",
        }
        status, payload = request(
            args.port,
            "/api/company/tenders",
            token=token,
            method="POST",
            payload=tender_payload,
            idempotency_key="tender-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("tender", {}).get("state") != "planning":
            raise SmokeError(f"tender create failed: {status} {payload}")
        status, payload = request(
            args.port,
            "/api/company/tenders",
            token=token,
            method="POST",
            payload=tender_payload,
            idempotency_key="tender-create-" + nonce,
        )
        if status != 200 or payload is None or payload.get("idempotent_replay") is not True:
            raise SmokeError(f"tender idempotency failed: {status} {payload}")
        status, payload = request(args.port, f"/api/company/tenders/{tender_id}", token=token)
        if status != 200 or payload is None or payload.get("state") != "planning":
            raise SmokeError(f"tender detail failed: {status} {payload}")
        for command, expected_state in (("publish", "publishing"), ("open_bidding", "bidding"), ("cancel", "cancelled")):
            status, payload = request(
                args.port,
                f"/api/company/tenders/{tender_id}/{command}",
                token=token,
                method="POST",
                payload={},
                idempotency_key=f"tender-{command}-{nonce}",
            )
            if status != 200 or payload is None or payload.get("tender", {}).get("state") != expected_state:
                raise SmokeError(f"tender {command} failed: {status} {payload}")
        status, payload = request(args.port, f"/api/company/tenders/{tender_id}", token=token)
        if status != 200 or payload is None or payload.get("state") != "cancelled":
            raise SmokeError(f"tender cancelled detail failed: {status} {payload}")
        print(
            json.dumps(
                {
                    "state": "service_verified",
                    "expense_state": "approved",
                    "contract_state": "approved",
                    "payment_application_approval_state": "approved",
                    "payment_application_state": "voided",
                    "payment_eligibility": "early_payment_flagged",
                    "tender_state": "cancelled",
                    "port": args.port,
                    "database": args.database,
                },
                sort_keys=True,
            )
        )
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
