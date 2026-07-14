#!/usr/bin/env python3
"""Smoke-test the trusted-upstream identity mode of the local gateway.

The smoke starts the authenticated PostgreSQL service and gateway with
credential-shaped values held only in the child environments. It verifies a
short-lived signed source identity, enabled-user lookup, HttpOnly session
binding, bounded expense/sales/marketing/invoice/fund/tender source-alias commands, notification subscription/message commands, and stale-
assertion rejection.
No secret value is printed.
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
        status, _headers, warning_list = request(
            args.gateway_port,
            "GET",
            "/api/company/warning?status=all",
            headers={"Cookie": cookie},
        )
        warning_rows = (warning_list or {}).get("data", {}).get("rows", [])
        if status != 200 or not isinstance(warning_list, dict) or len(warning_rows) != 1:
            raise SmokeError(f"trusted warning read failed: {status} {warning_list}")
        status, _headers, admin_dict = request(
            args.gateway_port,
            "GET",
            "/api/company/admin/dict/options?groupName=cost_subject",
            headers={"Cookie": cookie},
        )
        admin_dict_rows = (admin_dict or {}).get("data", [])
        if status != 200 or not isinstance(admin_dict, dict) or len(admin_dict_rows) != 5:
            raise SmokeError(f"trusted admin dictionary read failed: {status} {admin_dict}")
        status, _headers, admin_dict_command = request(
            args.gateway_port,
            "PATCH",
            f"/api/company/admin/dict/options/{admin_dict_rows[0].get('paramGuid')}",
            headers={"Cookie": cookie},
            payload={
                "value": "部门费用-管理费用-办公费-打印制作费",
                "idempotency_key": "admin-dict-update-rabbita-v1",
            },
        )
        if (
            status != 200
            or not isinstance(admin_dict_command, dict)
            or admin_dict_command.get("option", {}).get("paramGuid") != admin_dict_rows[0].get("paramGuid")
            or admin_dict_command.get("option", {}).get("authorizing") is not False
        ):
            raise SmokeError(f"trusted admin dictionary command failed: {status} {admin_dict_command}")
        status, _headers, admin_dict_replay = request(
            args.gateway_port,
            "PATCH",
            f"/api/company/admin/dict/options/{admin_dict_rows[0].get('paramGuid')}",
            headers={"Cookie": cookie},
            payload={
                "value": "部门费用-管理费用-办公费-打印制作费",
                "idempotency_key": "admin-dict-update-rabbita-v1",
            },
        )
        if (
            status != 200
            or not isinstance(admin_dict_replay, dict)
            or admin_dict_replay.get("idempotent_replay") is not True
        ):
            raise SmokeError(f"trusted admin dictionary replay failed: {status} {admin_dict_replay}")
        warning_guid = warning_rows[0].get("warningGuid")
        if warning_rows[0].get("status") == "open":
            status, _headers, warning_command = request(
                args.gateway_port,
                "POST",
                f"/api/company/warning/{warning_guid}/resolve",
                headers={"Cookie": cookie},
                payload={
                    "note": "warning command smoke",
                    "idempotency_key": "warning-resolve-gateway-v1",
                },
            )
            if (
                status != 200
                or not isinstance(warning_command, dict)
                or warning_command.get("warning", {}).get("state") != "resolved"
            ):
                raise SmokeError(f"trusted warning command failed: {status} {warning_command}")
        smoke_suffix = str(time.time_ns())
        report_template_body = {
            "templateName": "网关烟测合同报表",
            "description": "可信会话报表模板命令烟测",
            "baseTable": "cb_contract",
            "columns": ["contract_code", "ht_amount"],
            "filters": [{"field": "ht_amount", "op": ">", "value": 0}],
            "orderBy": "ht_amount desc",
            "isShared": False,
            "idempotency_key": "report-template-gateway-create-" + smoke_suffix,
        }
        status, _headers, report_template_create = request(
            args.gateway_port,
            "POST",
            "/api/company/reports/templates",
            headers={"Cookie": cookie},
            payload=report_template_body,
        )
        if (
            status != 201
            or not isinstance(report_template_create, dict)
            or report_template_create.get("template", {}).get("source_kind") != "command"
        ):
            raise SmokeError(f"trusted report template create failed: {status}")
        status, _headers, report_template_replay = request(
            args.gateway_port,
            "POST",
            "/api/company/reports/templates",
            headers={"Cookie": cookie},
            payload=report_template_body,
        )
        if status != 200 or not isinstance(report_template_replay, dict) or report_template_replay.get("idempotent_replay") is not True:
            raise SmokeError(f"trusted report template replay failed: {status}")
        status, _headers, report_template_run = request(
            args.gateway_port,
            "POST",
            "/api/company/reports/templates/run",
            headers={"Cookie": cookie},
            payload={
                "baseTable": "cb_contract",
                "columns": ["contract_code", "ht_amount"],
                "filters": [{"field": "ht_amount", "op": ">", "value": 0}],
                "limit": 10,
                "idempotency_key": "report-template-gateway-run-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(report_template_run, dict)
            or report_template_run.get("data", {}).get("sql_executed") is not False
            or len(report_template_run.get("data", {}).get("rows", [])) != 2
        ):
            raise SmokeError(f"trusted report template run failed: {status}")
        report_template_id = report_template_create.get("template", {}).get("template_id")
        status, _headers, report_template_delete = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/reports/templates/{report_template_id}"
            f"?idempotency_key=report-template-gateway-delete-{smoke_suffix}",
            headers={"Cookie": cookie},
        )
        if status != 200 or not isinstance(report_template_delete, dict) or report_template_delete.get("template", {}).get("state") != "deleted":
            raise SmokeError(
                f"trusted report template delete failed: {status} id={report_template_id!r} {report_template_delete}"
            )
        preference_key = "dashboard_view"
        preference_value = {"projGuid": "proj-0001", "density": "compact"}
        status, _headers, preference_set_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/source/auth/prefs/{preference_key}",
            headers={"Cookie": cookie},
            payload={
                "value": preference_value,
                "idempotency_key": "preference-gateway-set-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(preference_set_payload, dict)
            or preference_set_payload.get("source_kind") != "command"
            or preference_set_payload.get("data", {}).get("value") != preference_value
        ):
            raise SmokeError(f"trusted preference command set failed: {status}")
        status, _headers, preference_replay_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/source/auth/prefs/{preference_key}",
            headers={"Cookie": cookie},
            payload={
                "value": preference_value,
                "idempotency_key": "preference-gateway-set-" + smoke_suffix,
            },
        )
        if status != 200 or not isinstance(preference_replay_payload, dict) or preference_replay_payload.get("idempotent_replay") is not True:
            raise SmokeError(f"trusted preference command replay failed: {status}")
        status, _headers, preference_read_payload = request(
            args.gateway_port,
            "GET",
            "/api/company/auth/prefs?userCode=admin",
            headers={"Cookie": cookie},
        )
        if (
            status != 200
            or not isinstance(preference_read_payload, dict)
            or preference_read_payload.get("data", {}).get(preference_key) != preference_value
            or preference_read_payload.get("command_projection") is not True
        ):
            raise SmokeError(f"trusted preference command readback failed: {status}")
        status, _headers, preference_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/source/auth/prefs/{preference_key}",
            headers={"Cookie": cookie},
            payload={"idempotency_key": "preference-gateway-delete-" + smoke_suffix},
        )
        if status != 200 or not isinstance(preference_delete_payload, dict) or preference_delete_payload.get("data", {}).get("prefKey") != preference_key:
            raise SmokeError(f"trusted preference command delete failed: {status}")
        status, _headers, preference_deleted_read = request(
            args.gateway_port,
            "GET",
            "/api/company/auth/prefs?userCode=admin",
            headers={"Cookie": cookie},
        )
        if status != 200 or not isinstance(preference_deleted_read, dict) or preference_key in preference_deleted_read.get("data", {}):
            raise SmokeError(f"trusted preference tombstone readback failed: {status}")
        subscription_suffix = str(time.time_ns())
        subscription_body = {
            "ruleCode": "W005",
            "bizType": "project",
            "severityMin": "warning",
            "channels": ["in_app", "email"],
            "enabled": True,
            "idempotency_key": "notification-subscription-create-" + subscription_suffix,
        }
        status, _headers, subscription_create_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/source/notify/subscriptions",
            headers={"Cookie": cookie},
            payload=subscription_body,
        )
        subscription = (subscription_create_payload or {}).get("data", {}) if isinstance(subscription_create_payload, dict) else {}
        subscription_id = subscription.get("subId")
        if (
            status != 200
            or not isinstance(subscription_create_payload, dict)
            or subscription_create_payload.get("source_kind") != "command"
            or not isinstance(subscription_id, int)
            or subscription_create_payload.get("delivery_effect") is not False
        ):
            raise SmokeError(f"trusted notification subscription create failed: {status}")
        status, _headers, subscription_replay_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/source/notify/subscriptions",
            headers={"Cookie": cookie},
            payload=subscription_body,
        )
        if status != 200 or not isinstance(subscription_replay_payload, dict) or subscription_replay_payload.get("idempotent_replay") is not True:
            raise SmokeError(f"trusted notification subscription replay failed: {status}")
        status, _headers, subscription_read_payload = request(
            args.gateway_port,
            "GET",
            "/api/company/notify/subscriptions?userCode=admin",
            headers={"Cookie": cookie},
        )
        subscription_rows = (subscription_read_payload or {}).get("data", []) if isinstance(subscription_read_payload, dict) else []
        if (
            status != 200
            or not isinstance(subscription_rows, list)
            or not any(row.get("subId") == subscription_id and row.get("sourceKind") == "command" for row in subscription_rows if isinstance(row, dict))
            or not isinstance(subscription_read_payload, dict)
            or subscription_read_payload.get("command_projection") is not True
        ):
            raise SmokeError(f"trusted notification subscription readback failed: {status}")
        status, _headers, subscription_update_payload = request(
            args.gateway_port,
            "PATCH",
            f"/api/company/source/notify/subscriptions/{subscription_id}",
            headers={"Cookie": cookie},
            payload={
                "enabled": False,
                "channels": ["in_app"],
                "idempotency_key": "notification-subscription-update-" + subscription_suffix,
            },
        )
        updated_subscription = (subscription_update_payload or {}).get("data", {}) if isinstance(subscription_update_payload, dict) else {}
        if (
            status != 200
            or updated_subscription.get("subId") != subscription_id
            or updated_subscription.get("enabled") is not False
            or updated_subscription.get("channels") != "in_app"
        ):
            raise SmokeError(f"trusted notification subscription update failed: {status}")
        status, _headers, subscription_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/source/notify/subscriptions/{subscription_id}",
            headers={"Cookie": cookie},
            payload={"idempotency_key": "notification-subscription-delete-" + subscription_suffix},
        )
        if status != 200 or not isinstance(subscription_delete_payload, dict) or subscription_delete_payload.get("data", {}).get("subId") != subscription_id:
            raise SmokeError(f"trusted notification subscription delete failed: {status}")
        status, _headers, subscription_deleted_read = request(
            args.gateway_port,
            "GET",
            "/api/company/notify/subscriptions?userCode=admin",
            headers={"Cookie": cookie},
        )
        subscription_rows = (subscription_deleted_read or {}).get("data", []) if isinstance(subscription_deleted_read, dict) else []
        if status != 200 or any(row.get("subId") == subscription_id for row in subscription_rows if isinstance(row, dict)):
            raise SmokeError(f"trusted notification subscription tombstone readback failed: {status}")
        message_suffix = str(time.time_ns())
        message_guid = "missing-msg-0001"
        status, _headers, message_read_payload = request(
            args.gateway_port,
            "POST",
            f"/api/company/source/notify/messages/{message_guid}/read",
            headers={"Cookie": cookie},
            payload={"idempotency_key": "notification-message-read-" + message_suffix},
        )
        if (
            status != 200
            or not isinstance(message_read_payload, dict)
            or message_read_payload.get("data", {}).get("msgGuid") != message_guid
            or message_read_payload.get("data", {}).get("isRead") is not True
            or message_read_payload.get("delivery_effect") is not False
        ):
            raise SmokeError(f"trusted notification message read failed: {status}")
        status, _headers, message_read_replay_payload = request(
            args.gateway_port,
            "POST",
            f"/api/company/source/notify/messages/{message_guid}/read",
            headers={"Cookie": cookie},
            payload={"idempotency_key": "notification-message-read-" + message_suffix},
        )
        if status != 200 or not isinstance(message_read_replay_payload, dict) or message_read_replay_payload.get("idempotent_replay") is not True:
            raise SmokeError(f"trusted notification message replay failed: {status}")
        status, _headers, message_read_all_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/source/notify/messages/read-all",
            headers={"Cookie": cookie},
            payload={"idempotency_key": "notification-message-read-all-" + message_suffix},
        )
        if (
            status != 200
            or not isinstance(message_read_all_payload, dict)
            or message_read_all_payload.get("data", {}).get("readAll") is not True
            or message_read_all_payload.get("data", {}).get("count") != 0
        ):
            raise SmokeError(f"trusted notification read-all failed: {status}")
        status, _headers, message_read_all_readback = request(
            args.gateway_port,
            "GET",
            "/api/company/notify/messages?userCode=admin&status=unread",
            headers={"Cookie": cookie},
        )
        if status != 200 or not isinstance(message_read_all_readback, dict) or message_read_all_readback.get("data", {}).get("rows") != [] or message_read_all_readback.get("command_projection") is not True:
            raise SmokeError(f"trusted notification message read-state readback failed: {status}")
        status, _headers, budget_check_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/budget-check",
            headers={"Cookie": cookie},
            payload={"splits": [{"costSubjectCode": "CB-101", "amount": 8560}]},
        )
        if (
            status != 200
            or not isinstance(budget_check_payload, dict)
            or len(budget_check_payload.get("data", [])) != 1
            or budget_check_payload.get("data", [])[0].get("matched") is not True
            or budget_check_payload.get("authorizing") is not False
            or budget_check_payload.get("budget_consumption") is not False
        ):
            raise SmokeError(f"trusted budget check preview failed: {status}")
        expense_id = "EXP-GW-SMOKE-" + smoke_suffix
        expense_payload = {
            "expense_id": expense_id,
            "employee_id": user_code,
            "summary": "gateway expense command smoke",
            "amount_minor": 8560,
            "currency": "CNY",
            "project_id": "proj-0001",
            "cost_subject": "travel",
            "idempotency_key": "expense-gateway-create-" + smoke_suffix,
        }
        status, _headers, expense_create_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/expenses",
            headers={"Cookie": cookie},
            payload=expense_payload,
        )
        if (
            status != 201
            or not isinstance(expense_create_payload, dict)
            or expense_create_payload.get("expense", {}).get("state") != "draft"
        ):
            raise SmokeError(f"trusted expense command create failed: {status}")
        status, _headers, expense_update_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/expenses/{expense_id}",
            headers={"Cookie": cookie},
            payload={
                "subject": "gateway expense command smoke updated",
                "idempotency_key": "expense-gateway-update-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(expense_update_payload, dict)
            or expense_update_payload.get("expense", {}).get("state") != "draft"
        ):
            raise SmokeError(f"trusted expense command update failed: {status}")
        expense_transitions = [
            ("submit-for-approval", "submitted"),
            ("reject", "rejected"),
            ("resubmit", "submitted"),
            ("approve", "approved"),
        ]
        for command, expected_state in expense_transitions:
            status, _headers, expense_transition_payload = request(
                args.gateway_port,
                "POST",
                f"/api/company/expenses/{expense_id}/{command}",
                headers={"Cookie": cookie},
                payload={"idempotency_key": f"expense-gateway-{command}-{smoke_suffix}"},
            )
            if (
                status != 200
                or not isinstance(expense_transition_payload, dict)
                or expense_transition_payload.get("expense", {}).get("state") != expected_state
            ):
                raise SmokeError(f"trusted expense command {command} failed: {status}")
        void_expense_id = "EXP-GW-VOID-SMOKE-" + smoke_suffix
        status, _headers, void_create_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/expenses",
            headers={"Cookie": cookie},
            payload={
                **expense_payload,
                "expense_id": void_expense_id,
                "idempotency_key": "expense-gateway-void-create-" + smoke_suffix,
            },
        )
        if status != 201 or not isinstance(void_create_payload, dict):
            raise SmokeError(f"trusted expense void fixture create failed: {status}")
        status, _headers, void_payload = request(
            args.gateway_port,
            "POST",
            f"/api/company/expenses/{void_expense_id}/void",
            headers={"Cookie": cookie},
            payload={
                "reason": "gateway expense void smoke",
                "idempotency_key": "expense-gateway-void-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(void_payload, dict)
            or void_payload.get("expense", {}).get("state") != "voided"
        ):
            raise SmokeError(f"trusted expense command void failed: {status}")
        sales_customer_id = "CUS-GW-SMOKE-" + smoke_suffix
        sales_customer_payload = {
            "customer_id": sales_customer_id,
            "principal_id": "co-gateway-sales-smoke",
            "scope": "project:proj-0001",
            "customer_code": sales_customer_id,
            "name": "gateway sales command smoke",
            "contact_reference": "contact:gateway-sales",
            "idempotency_key": "sales-gateway-create-" + smoke_suffix,
        }
        status, _headers, sales_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/sales/customers",
            headers={"Cookie": cookie},
            payload=sales_customer_payload,
        )
        if (
            status != 201
            or not isinstance(sales_payload, dict)
            or sales_payload.get("customer", {}).get("state") != "active"
        ):
            raise SmokeError(f"trusted sales command forwarding failed: {status}")
        status, _headers, sales_replay_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/sales/customers",
            headers={"Cookie": cookie},
            payload=sales_customer_payload,
        )
        if (
            status != 200
            or not isinstance(sales_replay_payload, dict)
            or sales_replay_payload.get("idempotent_replay") is not True
        ):
            raise SmokeError(f"trusted sales command replay failed: {status}")
        status, _headers, sales_update_payload = request(
            args.gateway_port,
            "POST",
            f"/api/company/sales/customers/{sales_customer_id}/update",
            headers={"Cookie": cookie},
            payload={
                "name": "gateway sales command smoke updated",
                "idempotency_key": "sales-gateway-update-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(sales_update_payload, dict)
            or sales_update_payload.get("customer", {}).get("state") != "active"
        ):
            raise SmokeError(f"trusted sales command update failed: {status}")
        status, _headers, sales_block_payload = request(
            args.gateway_port,
            "POST",
            f"/api/company/sales/customers/{sales_customer_id}/block",
            headers={"Cookie": cookie},
            payload={"idempotency_key": "sales-gateway-block-" + smoke_suffix},
        )
        if (
            status != 200
            or not isinstance(sales_block_payload, dict)
            or sales_block_payload.get("customer", {}).get("state") != "blocked"
        ):
            raise SmokeError(f"trusted sales command block failed: {status}")
        status, _headers, sales_archive_payload = request(
            args.gateway_port,
            "POST",
            f"/api/company/sales/customers/{sales_customer_id}/archive",
            headers={"Cookie": cookie},
            payload={"idempotency_key": "sales-gateway-archive-" + smoke_suffix},
        )
        if (
            status != 200
            or not isinstance(sales_archive_payload, dict)
            or sales_archive_payload.get("customer", {}).get("state") != "archived"
        ):
            raise SmokeError(f"trusted sales command archive failed: {status}")
        sales_revenue_id = "REV-GW-SMOKE-" + smoke_suffix
        sales_revenue_principal = "co-gateway-sales-revenue"
        sales_revenue_scope = "project:proj-0001"

        def sales_revenue_authority(command_type: str, max_amount_minor: int = 0) -> dict[str, Any]:
            return {
                "active": True,
                "principal_id": sales_revenue_principal,
                "actor_id": user_code,
                "capability": "sales:revenue:" + command_type,
                "scope": sales_revenue_scope,
                "max_amount_minor": max_amount_minor,
            }

        status, _headers, sales_revenue_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/sales/revenues",
            headers={"Cookie": cookie},
            payload={
                "revenue_id": sales_revenue_id,
                "revenue_code": "SR-GW-SMOKE-" + smoke_suffix,
                "proj_guid": "proj-0001",
                "customer_name": "gateway sales revenue smoke",
                "amount_minor": 123450,
                "receive_date": "2026-07-14",
                "status": "expected",
                "principal_id": sales_revenue_principal,
                "scope": sales_revenue_scope,
                "authority": sales_revenue_authority("create", 150000),
                "idempotency_key": "sales-revenue-gateway-create-" + smoke_suffix,
            },
        )
        if (
            status != 201
            or not isinstance(sales_revenue_payload, dict)
            or sales_revenue_payload.get("revenue", {}).get("state") != "expected"
        ):
            raise SmokeError(f"trusted sales revenue create failed: {status}")
        status, _headers, sales_revenue_update_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/sales/revenues/{sales_revenue_id}",
            headers={"Cookie": cookie},
            payload={
                "customer_name": "gateway sales revenue smoke updated",
                "principal_id": sales_revenue_principal,
                "scope": sales_revenue_scope,
                "authority": sales_revenue_authority("update"),
                "idempotency_key": "sales-revenue-gateway-update-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(sales_revenue_update_payload, dict)
            or sales_revenue_update_payload.get("revenue", {}).get("state") != "expected"
        ):
            raise SmokeError(f"trusted sales revenue update failed: {status}")
        status, _headers, sales_revenue_confirm_payload = request(
            args.gateway_port,
            "POST",
            f"/api/company/sales/revenues/{sales_revenue_id}/confirm-received",
            headers={"Cookie": cookie},
            payload={
                "principal_id": sales_revenue_principal,
                "scope": sales_revenue_scope,
                "authority": sales_revenue_authority("confirm_received"),
                "idempotency_key": "sales-revenue-gateway-confirm-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(sales_revenue_confirm_payload, dict)
            or sales_revenue_confirm_payload.get("revenue", {}).get("state") != "received"
        ):
            raise SmokeError(f"trusted sales revenue confirm failed: {status}")
        status, _headers, sales_revenue_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/sales/revenues/{sales_revenue_id}",
            headers={"Cookie": cookie},
            payload={
                "principal_id": sales_revenue_principal,
                "scope": sales_revenue_scope,
                "authority": sales_revenue_authority("delete"),
                "idempotency_key": "sales-revenue-gateway-delete-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(sales_revenue_delete_payload, dict)
            or sales_revenue_delete_payload.get("revenue", {}).get("state") != "deleted"
        ):
            raise SmokeError(f"trusted sales revenue delete failed: {status}")
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
        invoice_id = "INV-GW-SMOKE-" + smoke_suffix
        invoice_principal = "co-gateway-invoice-smoke"
        invoice_scope = "project:proj-0001"
        status, _headers, invoice_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/source/invoice/out",
            headers={"Cookie": cookie},
            payload={
                "invoiceGuid": invoice_id,
                "invoiceNo": "INV-GW-SMOKE-" + smoke_suffix,
                "projGuid": "proj-0001",
                "customerName": "gateway invoice smoke",
                "invoiceDate": "2026-07-14",
                "totalAmount": "5.00",
                "taxRate": "0.06",
                "principal_id": invoice_principal,
                "scope": invoice_scope,
                "authority": {
                    "active": True,
                    "principal_id": invoice_principal,
                    "actor_id": user_code,
                    "capability": "invoice:out:create",
                    "scope": invoice_scope,
                    "max_amount_minor": 500,
                },
                "idempotency_key": "invoice-gateway-create-" + smoke_suffix,
            },
        )
        if (
            status != 201
            or not isinstance(invoice_payload, dict)
            or invoice_payload.get("invoice", {}).get("state") != "issued"
        ):
            raise SmokeError(f"trusted invoice command forwarding failed: {status}")
        status, _headers, invoice_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/source/invoice/out/{invoice_id}",
            headers={"Cookie": cookie},
            payload={
                "principal_id": invoice_principal,
                "scope": invoice_scope,
                "authority": {
                    "active": True,
                    "principal_id": invoice_principal,
                    "actor_id": user_code,
                    "capability": "invoice:out:delete",
                    "scope": invoice_scope,
                    "max_amount_minor": 0,
                },
                "idempotency_key": "invoice-gateway-delete-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(invoice_delete_payload, dict)
            or invoice_delete_payload.get("invoice", {}).get("state") != "deleted"
        ):
            raise SmokeError(f"trusted invoice command delete failed: {status}")
        fund_plan_id = "FP-GW-SMOKE-" + smoke_suffix
        fund_plan_create = {
            "plan_id": fund_plan_id,
            "plan_code": "FP-GW-CODE-" + smoke_suffix,
            "project_id": "proj-0001",
            "plan_period": "2026-08",
            "direction": "out",
            "category": "construction",
            "plan_amount_minor": 1200000,
            "authority": {
                "active": True,
                "principal_id": "co-gateway-fund-smoke",
                "actor_id": user_code,
                "capability": "fund:plan:create",
                "scope": "project:proj-0001",
                "max_amount_minor": 1200000,
            },
            "idempotency_key": "fund-gateway-plan-create-" + smoke_suffix,
        }
        status, _headers, fund_plan_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/fund/plans",
            headers={"Cookie": cookie},
            payload=fund_plan_create,
        )
        if status != 201 or not isinstance(fund_plan_payload, dict) or fund_plan_payload.get("plan", {}).get("state") != "planned":
            raise SmokeError(f"trusted fund plan create failed: {status}")
        status, _headers, fund_plan_update_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/fund/plans/{fund_plan_id}",
            headers={"Cookie": cookie},
            payload={
                "remark": "gateway fund update smoke",
                "idempotency_key": "fund-gateway-plan-update-" + smoke_suffix,
            },
        )
        if status != 200 or not isinstance(fund_plan_update_payload, dict) or fund_plan_update_payload.get("plan", {}).get("state") != "updated":
            raise SmokeError(f"trusted fund plan update failed: {status}")
        status, _headers, fund_plan_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/fund/plans/{fund_plan_id}",
            headers={"Cookie": cookie},
            payload={
                "reason": "gateway fund delete smoke",
                "idempotency_key": "fund-gateway-plan-delete-" + smoke_suffix,
            },
        )
        if status != 200 or not isinstance(fund_plan_delete_payload, dict) or fund_plan_delete_payload.get("plan", {}).get("state") != "deleted":
            raise SmokeError(f"trusted fund plan delete failed: {status}")
        fund_dispatch_id = "FD-GW-SMOKE-" + smoke_suffix
        status, _headers, fund_dispatch_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/fund/dispatches",
            headers={"Cookie": cookie},
            payload={
                "dispatch_id": fund_dispatch_id,
                "dispatch_code": "FD-GW-CODE-" + smoke_suffix,
                "project_id": "proj-0001",
                "from_project_id": "proj-0002",
                "to_project_id": "proj-0001",
                "amount_minor": 500000,
                "reason": "gateway fund dispatch smoke",
                "authority": {
                    "active": True,
                    "principal_id": "co-gateway-fund-smoke",
                    "actor_id": user_code,
                    "capability": "fund:dispatch:create",
                    "scope": "project:proj-0001",
                    "max_amount_minor": 500000,
                },
                "idempotency_key": "fund-gateway-dispatch-create-" + smoke_suffix,
            },
        )
        if status != 201 or not isinstance(fund_dispatch_payload, dict) or fund_dispatch_payload.get("dispatch", {}).get("state") != "pending":
            raise SmokeError(f"trusted fund dispatch create failed: {status}")
        status, _headers, fund_dispatch_approve_payload = request(
            args.gateway_port,
            "POST",
            f"/api/company/fund/dispatches/{fund_dispatch_id}/approve",
            headers={"Cookie": cookie},
            payload={
                "authority": {
                    "active": True,
                    "principal_id": "co-gateway-fund-smoke",
                    "actor_id": user_code,
                    "capability": "fund:dispatch:approve",
                    "scope": "project:proj-0001",
                    "max_amount_minor": 500000,
                },
                "idempotency_key": "fund-gateway-dispatch-approve-" + smoke_suffix,
            },
        )
        if status != 200 or not isinstance(fund_dispatch_approve_payload, dict) or fund_dispatch_approve_payload.get("dispatch", {}).get("state") != "approved" or fund_dispatch_approve_payload.get("dispatch", {}).get("cash_effect") is not False:
            raise SmokeError(f"trusted fund dispatch approval failed: {status}")
        plan_task_id = "PT-GW-SMOKE-" + smoke_suffix
        plan_task_authority = {
            "active": True,
            "principal_id": "co-gateway-plan-smoke",
            "actor_id": user_code,
            "capability": "project:task:create",
            "scope": "project:proj-0001",
        }
        status, _headers, plan_task_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/plan/tasks",
            headers={"Cookie": cookie},
            payload={
                "task_id": plan_task_id,
                "task_code": "PT-GW-CODE-" + smoke_suffix,
                "task_name": "gateway project-plan task smoke",
                "project_id": "proj-0001",
                "task_type": "task",
                "plan_begin_date": "2026-08-01",
                "plan_end_date": "2026-08-15",
                "authority": plan_task_authority,
                "idempotency_key": "plan-task-gateway-create-" + smoke_suffix,
            },
        )
        if status != 201 or not isinstance(plan_task_payload, dict) or plan_task_payload.get("task", {}).get("state") != "pending":
            raise SmokeError(f"trusted project-plan task create failed: {status}")
        status, _headers, plan_task_update_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/plan/tasks/{plan_task_id}",
            headers={"Cookie": cookie},
            payload={
                "taskName": "updated gateway project-plan task smoke",
                "authority": {
                    **plan_task_authority,
                    "capability": "project:task:update",
                },
                "idempotency_key": "plan-task-gateway-update-" + smoke_suffix,
            },
        )
        if status != 200 or not isinstance(plan_task_update_payload, dict) or plan_task_update_payload.get("task", {}).get("state") != "pending":
            raise SmokeError(f"trusted project-plan task update failed: {status}")
        status, _headers, plan_task_report_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/plan/tasks/task-001/report",
            headers={"Cookie": cookie},
            payload={
                "project_id": "proj-0001",
                "progress_pct": 20,
                "report_date": "2026-08-05",
                "summary": "gateway project-plan report smoke",
                "evidence_ids": ["plan-task-gateway-evidence"],
                "idempotency_key": "plan-task-gateway-report-" + smoke_suffix,
            },
        )
        if status != 200 or not isinstance(plan_task_report_payload, dict) or plan_task_report_payload.get("task_report", {}).get("state") != "observed":
            raise SmokeError(f"trusted project-plan task report failed: {status}")
        status, _headers, plan_task_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/plan/tasks/{plan_task_id}",
            headers={"Cookie": cookie},
            payload={
                "reason": "gateway project-plan task smoke cleanup",
                "authority": {
                    **plan_task_authority,
                    "capability": "project:task:delete",
                },
                "idempotency_key": "plan-task-gateway-delete-" + smoke_suffix,
            },
        )
        if status != 200 or not isinstance(plan_task_delete_payload, dict) or plan_task_delete_payload.get("task", {}).get("state") != "deleted":
            raise SmokeError(f"trusted project-plan task delete failed: {status}")
        delivery_progress_id = "PROG-GW-DELETE-SMOKE-" + smoke_suffix
        delivery_progress_payload = {
            "progress_id": delivery_progress_id,
            "project_id": "proj-0001",
            "principal_id": "co-gateway-delivery-smoke",
            "project_scope": "project:proj-0001",
            "stage": "gateway delivery delete smoke",
            "plan_pct": 10,
            "completed_value_minor": 1,
            "currency": "CNY",
            "evidence_ids": ["gateway-delivery-delete-evidence"],
            "idempotency_key": "delivery-gateway-delete-create-" + smoke_suffix,
        }
        status, _headers, delivery_progress_payload_result = request(
            args.gateway_port,
            "POST",
            "/api/company/delivery/progress",
            headers={"Cookie": cookie},
            payload=delivery_progress_payload,
        )
        if status != 201 or not isinstance(delivery_progress_payload_result, dict) or delivery_progress_payload_result.get("progress", {}).get("state") != "draft":
            raise SmokeError(f"trusted delivery progress create failed: {status}")
        status, _headers, delivery_progress_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/delivery/progress/{delivery_progress_id}",
            headers={"Cookie": cookie},
            payload={
                "reason": "gateway delivery delete smoke",
                "idempotency_key": "delivery-gateway-delete-" + smoke_suffix,
            },
        )
        if status != 200 or not isinstance(delivery_progress_delete_payload, dict) or delivery_progress_delete_payload.get("progress", {}).get("state") != "deleted":
            raise SmokeError(f"trusted delivery progress delete failed: {status}")
        source_contract_id = "CT-GW-SOURCE-SMOKE-" + smoke_suffix
        source_contract_payload = {
            "contractGuid": source_contract_id,
            "contractCode": "HT-GW-SOURCE-SMOKE-" + smoke_suffix,
            "contractName": "gateway source contract alias smoke",
            "buGuid": "bu-tjgs-0001",
            "buName": "成都和锦里事业部",
            "projGuid": "CD-HJL",
            "projName": "成都和锦里",
            "yfProviderName": "gateway source supplier",
            "htAmount": "45678.00",
            "rCode": "R-GW-SOURCE",
            "l3Code": "L3-GW-SOURCE",
            "signDate": "2026-07-14",
            "idempotency_key": "source-contract-gateway-create-" + smoke_suffix,
        }
        status, _headers, source_contract_create_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/source/cost/contracts",
            headers={"Cookie": cookie},
            payload=source_contract_payload,
        )
        if (
            status != 201
            or not isinstance(source_contract_create_payload, dict)
            or source_contract_create_payload.get("contract", {}).get("state") != "draft"
            or source_contract_create_payload.get("contract", {}).get("sourceKind") != "command"
            or source_contract_create_payload.get("contract", {}).get("buGuid") != "bu-tjgs-0001"
        ):
            raise SmokeError(f"trusted source contract setup failed: {status}")
        status, _headers, source_contract_update_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/source/cost/contracts/{source_contract_id}",
            headers={"Cookie": cookie},
            payload={
                "contractName": "gateway source contract alias updated",
                "htAmount": "45678.00",
                "idempotency_key": "source-contract-gateway-update-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_contract_update_payload, dict)
            or source_contract_update_payload.get("contract", {}).get("state") != "draft"
            or source_contract_update_payload.get("data", {}).get("contractGuid") != source_contract_id
        ):
            raise SmokeError(f"trusted source contract alias update failed: {status}")
        status, _headers, source_milestone_create_payload = request(
            args.gateway_port,
            "POST",
            f"/api/company/source/cost/contracts/{source_contract_id}/milestones",
            headers={"Cookie": cookie},
            payload={
                "nodeName": "gateway source milestone alias smoke",
                "triggerType": "event",
                "planPct": "10.00",
                "idempotency_key": "source-milestone-gateway-create-" + smoke_suffix,
            },
        )
        if (
            status != 201
            or not isinstance(source_milestone_create_payload, dict)
            or not source_milestone_create_payload.get("data", {}).get("milestoneGuid")
        ):
            raise SmokeError(f"trusted source milestone alias create failed: {status}")
        source_milestone_guid = source_milestone_create_payload["data"]["milestoneGuid"]
        status, _headers, source_milestone_update_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/source/cost/milestones/{source_milestone_guid}",
            headers={"Cookie": cookie},
            payload={
                "nodeName": "gateway source milestone alias updated",
                "idempotency_key": "source-milestone-gateway-update-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_milestone_update_payload, dict)
            or source_milestone_update_payload.get("data", {}).get("milestoneGuid") != source_milestone_guid
        ):
            raise SmokeError(f"trusted source milestone alias update failed: {status}")
        status, _headers, source_milestone_trigger_payload = request(
            args.gateway_port,
            "POST",
            f"/api/company/source/cost/milestones/{source_milestone_guid}/trigger-event",
            headers={"Cookie": cookie},
            payload={"idempotency_key": "source-milestone-gateway-trigger-" + smoke_suffix},
        )
        if (
            status != 200
            or not isinstance(source_milestone_trigger_payload, dict)
            or source_milestone_trigger_payload.get("milestone", {}).get("state") != "reached"
        ):
            raise SmokeError(f"trusted source milestone trigger failed: {status}")
        status, _headers, source_milestone_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/source/cost/milestones/{source_milestone_guid}",
            headers={"Cookie": cookie},
            payload={
                "reason": "gateway source milestone alias smoke void",
                "idempotency_key": "source-milestone-gateway-delete-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_milestone_delete_payload, dict)
            or source_milestone_delete_payload.get("milestone", {}).get("state") != "deleted"
        ):
            raise SmokeError(f"trusted source milestone alias delete failed: {status}")
        status, _headers, source_contract_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/source/cost/contracts/{source_contract_id}",
            headers={"Cookie": cookie},
            payload={
                "reason": "gateway source contract alias smoke void",
                "idempotency_key": "source-contract-gateway-delete-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_contract_delete_payload, dict)
            or source_contract_delete_payload.get("contract", {}).get("state") != "deleted"
        ):
            raise SmokeError(f"trusted source contract alias delete failed: {status}")
        source_project_id = "PRJ-GW-SOURCE-" + smoke_suffix
        source_project_code = "PRJ-GW-CODE-" + smoke_suffix
        status, _headers, source_project_create_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/source/mdm/projects",
            headers={"Cookie": cookie},
            payload={
                "projGuid": source_project_id,
                "projCode": source_project_code,
                "projName": "gateway source project alias smoke",
                "projShortName": "gateway project",
                "buGuid": "bu-tjgs-0001",
                "buName": "天津公司",
                "levelCode": "001",
                "beginDate": "2026-07-14",
                "projStatus": "initiation",
                "idempotency_key": "source-project-gateway-create-" + smoke_suffix,
            },
        )
        if (
            status != 201
            or not isinstance(source_project_create_payload, dict)
            or source_project_create_payload.get("project", {}).get("projGuid") != source_project_id
            or source_project_create_payload.get("project", {}).get("sourceKind") != "command"
        ):
            raise SmokeError(f"trusted source project alias create failed: {status}")
        status, _headers, source_project_update_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/source/mdm/projects/{source_project_id}",
            headers={"Cookie": cookie},
            payload={
                "projName": "gateway source project alias updated",
                "projStatus": "planning",
                "idempotency_key": "source-project-gateway-update-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_project_update_payload, dict)
            or source_project_update_payload.get("project", {}).get("projName") != "gateway source project alias updated"
        ):
            raise SmokeError(f"trusted source project alias update failed: {status}")
        status, _headers, source_project_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/source/mdm/projects/{source_project_id}",
            headers={"Cookie": cookie},
            payload={
                "reason": "gateway source project alias smoke",
                "idempotency_key": "source-project-gateway-delete-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_project_delete_payload, dict)
            or source_project_delete_payload.get("project", {}).get("projCode") != source_project_code
            or source_project_delete_payload.get("project", {}).get("sourceKind") != "command"
        ):
            raise SmokeError(f"trusted source project alias delete failed: {status}")
        source_cost_code = "SRC-GW-COST-" + smoke_suffix
        source_cost_payload = {
            "projGuid": "proj-0001",
            "costCode": source_cost_code,
            "costName": "gateway source dynamic-cost alias smoke",
            "targetCost": "2000.00",
            "htAlterAmount": "200.00",
            "ztCost": "10.00",
            "remarks": "gateway source dynamic-cost alias",
            "idempotency_key": "source-dynamic-gateway-create-" + smoke_suffix,
        }
        status, _headers, source_cost_create_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/cost/dynamic-cost",
            headers={"Cookie": cookie},
            payload=source_cost_payload,
        )
        if (
            status != 201
            or not isinstance(source_cost_create_payload, dict)
            or source_cost_create_payload.get("data", {}).get("costCode") != source_cost_code
        ):
            raise SmokeError(f"trusted source dynamic-cost alias create failed: {status}")
        source_cost_guid = source_cost_create_payload.get("data", {}).get("costGuid")
        if not isinstance(source_cost_guid, str) or not source_cost_guid:
            raise SmokeError("trusted source dynamic-cost alias id missing")
        status, _headers, source_cost_update_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/source/cost/dynamic-cost/{source_cost_guid}",
            headers={"Cookie": cookie},
            payload={
                "costName": "gateway source dynamic-cost alias updated",
                "targetCost": "2100.00",
                "idempotency_key": "source-dynamic-gateway-update-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_cost_update_payload, dict)
            or source_cost_update_payload.get("dynamic_cost", {}).get("state") != "active"
        ):
            raise SmokeError(f"trusted source dynamic-cost alias update failed: {status}")
        status, _headers, source_cost_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/source/cost/dynamic-cost/{source_cost_guid}",
            headers={"Cookie": cookie},
            payload={
                "reason": "gateway source dynamic-cost alias smoke void",
                "idempotency_key": "source-dynamic-gateway-delete-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_cost_delete_payload, dict)
            or source_cost_delete_payload.get("dynamic_cost", {}).get("state") != "deleted"
        ):
            raise SmokeError(f"trusted source dynamic-cost alias delete failed: {status}")
        source_tender_payload = {
            "projGuid": "CD-HJL",
            "tenderName": "gateway source tender alias smoke",
            "category": "construction",
            "estimatedAmount": "23456.78",
            "planPublishDate": "2026-07-14",
            "remark": "gateway source tender alias",
            "idempotency_key": "source-tender-gateway-create-" + smoke_suffix,
        }
        status, _headers, source_tender_create_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/source/tender/tenders",
            headers={"Cookie": cookie},
            payload=source_tender_payload,
        )
        if (
            status != 201
            or not isinstance(source_tender_create_payload, dict)
            or source_tender_create_payload.get("success") is not True
            or not source_tender_create_payload.get("data", {}).get("tenderGuid")
            or source_tender_create_payload.get("source_kind") != "command"
        ):
            raise SmokeError(f"trusted source tender alias failed: {status}")
        source_tender_guid = source_tender_create_payload["data"]["tenderGuid"]
        status, _headers, source_tender_replay_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/source/tender/tenders",
            headers={"Cookie": cookie},
            payload=source_tender_payload,
        )
        if status != 200 or not isinstance(source_tender_replay_payload, dict) or source_tender_replay_payload.get("idempotent_replay") is not True:
            raise SmokeError(f"trusted source tender alias replay failed: {status}")
        status, _headers, source_tender_read_payload = request(
            args.gateway_port,
            "GET",
            "/api/company/source/tender/tenders?projGuid=CD-HJL",
            headers={"Cookie": cookie},
        )
        if (
            status != 200
            or not isinstance(source_tender_read_payload, dict)
            or not any(
                isinstance(row, dict)
                and row.get("tender_guid") == source_tender_guid
                and row.get("source_kind") == "command"
                for row in source_tender_read_payload.get("data", [])
            )
        ):
            raise SmokeError(f"trusted source tender alias readback failed: {status}")
        status, _headers, source_tender_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/source/tender/tenders/{source_tender_guid}",
            headers={"Cookie": cookie},
            payload={
                "reason": "gateway source tender tombstone smoke",
                "idempotency_key": "source-tender-gateway-delete-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_tender_delete_payload, dict)
            or source_tender_delete_payload.get("success") is not True
            or source_tender_delete_payload.get("tender", {}).get("state") != "deleted"
        ):
            raise SmokeError(f"trusted source tender delete alias failed: {status}")
        status, _headers, source_tender_read_after_delete_payload = request(
            args.gateway_port,
            "GET",
            "/api/company/source/tender/tenders?projGuid=CD-HJL",
            headers={"Cookie": cookie},
        )
        if (
            status != 200
            or not isinstance(source_tender_read_after_delete_payload, dict)
            or any(
                isinstance(row, dict)
                and row.get("tender_guid") == source_tender_guid
                for row in source_tender_read_after_delete_payload.get("data", [])
            )
        ):
            raise SmokeError(f"trusted source tender delete alias readback failed: {status}")
        source_supplier_id = "SUP-GW-SOURCE-" + smoke_suffix
        source_supplier_payload = {
            "providerGuid": source_supplier_id,
            "providerCode": "GYS-GW-SOURCE-" + smoke_suffix,
            "providerName": "gateway source supplier smoke",
            "mainCategoryCode": "construction",
            "businessScope": "gateway source supplier scope",
            "principal_id": "admin",
            "scope": "project:CD-HJL",
            "idempotency_key": "source-supplier-gateway-create-" + smoke_suffix,
        }
        status, _headers, source_supplier_create_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/source/srm/providers",
            headers={"Cookie": cookie},
            payload=source_supplier_payload,
        )
        if (
            status != 201
            or not isinstance(source_supplier_create_payload, dict)
            or source_supplier_create_payload.get("data", {}).get("providerGuid") != source_supplier_id
            or source_supplier_create_payload.get("provider", {}).get("sourceKind") != "command"
        ):
            raise SmokeError(f"trusted source supplier alias failed: {status} {source_supplier_create_payload}")
        status, _headers, source_supplier_check_sign_payload = request(
            args.gateway_port,
            "GET",
            f"/api/company/srm/providers/{source_supplier_id}/check-sign",
            headers={"Cookie": cookie},
        )
        check_sign_data = (
            source_supplier_check_sign_payload.get("data", {})
            if isinstance(source_supplier_check_sign_payload, dict)
            else {}
        )
        if (
            status != 200
            or not isinstance(source_supplier_check_sign_payload, dict)
            or source_supplier_check_sign_payload.get("decision") != "derived_command_preview"
            or source_supplier_check_sign_payload.get("authorizing") is not False
            or source_supplier_check_sign_payload.get("provider_execution") is not False
            or check_sign_data.get("sourceKind") != "command"
            or check_sign_data.get("allow") is not True
        ):
            raise SmokeError(
                f"trusted source supplier check-sign preview failed: {status} "
                f"{source_supplier_check_sign_payload}"
            )
        status, _headers, source_supplier_patch_payload = request(
            args.gateway_port,
            "PATCH",
            f"/api/company/source/srm/providers/{source_supplier_id}",
            headers={"Cookie": cookie},
            payload={
                "providerName": "gateway source supplier updated",
                "idempotency_key": "source-supplier-gateway-patch-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_supplier_patch_payload, dict)
            or source_supplier_patch_payload.get("provider", {}).get("providerName") != "gateway source supplier updated"
        ):
            raise SmokeError(f"trusted source supplier PATCH alias failed: {status}")
        status, _headers, source_supplier_put_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/source/srm/providers/{source_supplier_id}",
            headers={"Cookie": cookie},
            payload={
                "businessScope": "gateway source supplier updated scope",
                "idempotency_key": "source-supplier-gateway-put-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_supplier_put_payload, dict)
            or source_supplier_put_payload.get("provider", {}).get("sourceKind") != "command"
            or source_supplier_put_payload.get("provider", {}).get("businessScope") != "gateway source supplier updated scope"
        ):
            raise SmokeError(f"trusted source supplier PUT alias failed: {status}")
        status, _headers, source_supplier_read_payload = request(
            args.gateway_port,
            "GET",
            "/api/company/srm/providers",
            headers={"Cookie": cookie},
        )
        if (
            status != 200
            or not isinstance(source_supplier_read_payload, dict)
            or not any(
                isinstance(row, dict)
                and row.get("providerGuid") == source_supplier_id
                and row.get("sourceKind") == "command"
                for row in source_supplier_read_payload.get("data", [])
            )
        ):
            raise SmokeError(f"trusted source supplier readback failed: {status}")
        status, _headers, source_supplier_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/source/srm/providers/{source_supplier_id}",
            headers={"Cookie": cookie},
            payload={
                "reason": "gateway source supplier alias smoke void",
                "idempotency_key": "source-supplier-gateway-delete-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_supplier_delete_payload, dict)
            or source_supplier_delete_payload.get("provider", {}).get("auditState") != "voided"
        ):
            raise SmokeError(f"trusted source supplier delete alias failed: {status} {source_supplier_delete_payload}")
        source_split_payload = {
            "parentContractGuid": "ht-tj-001",
            "splitName": "gateway source split alias smoke",
            "splitAmount": "3456.78",
            "splitPct": "12.50",
            "scope": "project:CD-HJL",
            "idempotency_key": "source-split-gateway-create-" + smoke_suffix,
        }
        status, _headers, source_split_create_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/source/tender/splits",
            headers={"Cookie": cookie},
            payload=source_split_payload,
        )
        if status != 201 or not isinstance(source_split_create_payload, dict) or not source_split_create_payload.get("data", {}).get("splitGuid"):
            raise SmokeError(f"trusted source split alias failed: {status}")
        source_split_guid = source_split_create_payload["data"]["splitGuid"]
        status, _headers, source_split_read_payload = request(
            args.gateway_port,
            "GET",
            "/api/company/source/tender/splits?parentContractGuid=ht-tj-001",
            headers={"Cookie": cookie},
        )
        if (
            status != 200
            or not isinstance(source_split_read_payload, dict)
            or not any(
                isinstance(row, dict)
                and row.get("split_guid") == source_split_guid
                and row.get("source_kind") == "command"
                for row in source_split_read_payload.get("data", [])
            )
        ):
            raise SmokeError(f"trusted source split alias readback failed: {status}")
        source_payment_code = "FK-GW-SOURCE-SMOKE-" + smoke_suffix
        source_payment_payload = {
            "applyCode": source_payment_code,
            "contractGuid": "ht-tj-001",
            "subject": "gateway source payment alias smoke",
            "applyAmount": "2345.67",
            "applyTypeCode": "WORK_PROGRESS",
            "idempotency_key": "source-payment-gateway-create-" + smoke_suffix,
        }
        status, _headers, source_payment_create_payload = request(
            args.gateway_port,
            "POST",
            "/api/company/source/cost/payment-applies",
            headers={"Cookie": cookie},
            payload=source_payment_payload,
        )
        if (
            status != 201
            or not isinstance(source_payment_create_payload, dict)
            or source_payment_create_payload.get("success") is not True
            or source_payment_create_payload.get("data", {}).get("applyCode") != source_payment_code
            or source_payment_create_payload.get("payment_application", {}).get("state") != "submitted"
        ):
            raise SmokeError(f"trusted source payment alias create failed: {status}")
        source_payment_guid = source_payment_create_payload.get("data", {}).get("htfkApplyGuid")
        if not isinstance(source_payment_guid, str) or not source_payment_guid:
            raise SmokeError("trusted source payment alias id missing")
        status, _headers, source_payment_update_payload = request(
            args.gateway_port,
            "PUT",
            f"/api/company/source/cost/payment-applies/{source_payment_guid}",
            headers={"Cookie": cookie},
            payload={
                "subject": "gateway source payment alias updated",
                "applyAmount": "2345.67",
                "applyTypeCode": "PURCHASE",
                "idempotency_key": "source-payment-gateway-update-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_payment_update_payload, dict)
            or source_payment_update_payload.get("data", {}).get("applyCode") != source_payment_code
            or source_payment_update_payload.get("payment_application", {}).get("state") != "submitted"
        ):
            raise SmokeError(f"trusted source payment alias update failed: {status}")
        status, _headers, source_payment_delete_payload = request(
            args.gateway_port,
            "DELETE",
            f"/api/company/source/cost/payment-applies/{source_payment_guid}",
            headers={"Cookie": cookie},
            payload={
                "reason": "gateway source payment alias smoke void",
                "idempotency_key": "source-payment-gateway-delete-" + smoke_suffix,
            },
        )
        if (
            status != 200
            or not isinstance(source_payment_delete_payload, dict)
            or source_payment_delete_payload.get("data", {}).get("applyCode") != source_payment_code
            or source_payment_delete_payload.get("payment_application", {}).get("state") != "voided"
        ):
            raise SmokeError(f"trusted source payment alias delete failed: {status}")
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
