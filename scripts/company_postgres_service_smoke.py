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
from datetime import date
from pathlib import Path
from typing import Any


class SmokeError(RuntimeError):
    pass


def tree_count(nodes: list[dict[str, Any]]) -> int:
    return sum(1 + tree_count(node.get("children", [])) for node in nodes)


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
    # A cold/replaced psql session may consume the service's ten-second query
    # budget before the first bounded dashboard read is available.  Keep the
    # smoke client above that budget so it verifies the service response rather
    # than failing while the server is still completing its work.
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
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


def request_text(
    port: int,
    path: str,
    *,
    token: str | None,
    forwarded_tls: bool = True,
) -> tuple[int, dict[str, str], str]:
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
    headers: dict[str, str] = {}
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    if forwarded_tls:
        headers["X-Forwarded-Proto"] = "https"
    try:
        connection.request("GET", path, headers=headers)
        result = connection.getresponse()
        body = result.read().decode("utf-8")
        response_headers = {key.lower(): value for key, value in result.getheaders()}
    except (OSError, TimeoutError) as error:
        connection.close()
        raise SmokeError(f"GET {path} request failed: {error}") from error
    connection.close()
    return result.status, response_headers, body


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
        status, headers, body = request_text(args.port, "/api/company/import/project/template", token=token)
        if (
            status != 200
            or headers.get("content-type") != "text/csv; charset=utf-8"
            or headers.get("content-disposition") != "attachment; filename=project_template.csv"
            or body != "\ufeffprojCode,projName,projShortName,buCode,projStatus,beginDate\n"
        ):
            raise SmokeError(f"project import template failed: {status} {headers} {body!r}")
        status, headers, body = request_text(args.port, "/api/company/import/unsupported/template", token=token)
        if status != 400 or "不支持的 bizType" not in body:
            raise SmokeError(f"unsupported import template failed: {status} {body!r}")
        status, payload = request(args.port, "/api/company/summary", token=token)
        if (
            status != 200
            or payload is None
            or payload.get("target") != "postgresql"
            or "ai_analytics_read" not in payload.get("capabilities", [])
            or "ai_hub_read" not in payload.get("capabilities", [])
            or "webhook_config_read" not in payload.get("capabilities", [])
            or "report_template_read" not in payload.get("capabilities", [])
        ):
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
        status, supplier_source_payload = request(args.port, "/api/company/srm/providers", token=token)
        supplier_source_data = (supplier_source_payload or {}).get("data")
        if (
            status != 200
            or supplier_source_payload is None
            or supplier_source_data != []
            or supplier_source_payload.get("source_coverage", {}).get("cb_contract") != 2
            or supplier_source_payload.get("source_coverage", {}).get("srm_provider") != 0
            or "srm_provider" not in supplier_source_payload.get("missing_or_empty_source_tables", [])
            or "srm_category" not in supplier_source_payload.get("missing_or_empty_source_tables", [])
            or supplier_source_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source supplier list read failed: {status} {supplier_source_payload}")
        status, supplier_detail_payload = request(
            args.port, "/api/company/srm/providers/SUP-00018", token=token,
        )
        if (
            status != 404
            or supplier_detail_payload is None
            or supplier_detail_payload.get("data") is not None
            or supplier_detail_payload.get("source_coverage", {}).get("srm_provider") != 0
            or supplier_detail_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source supplier detail read failed: {status} {supplier_detail_payload}")
        supplier_detail_status = status
        status, supplier_detail_risk_payload = request(
            args.port, "/api/company/srm/providers/SUP-00018/risk", token=token,
        )
        if (
            status != 404
            or supplier_detail_risk_payload is None
            or supplier_detail_risk_payload.get("data") is not None
            or supplier_detail_risk_payload.get("source_coverage", {}).get("srm_provider") != 0
            or supplier_detail_risk_payload.get("source_coverage", {}).get("cb_contract_milestone") != 0
            or "cb_contract_milestone" not in supplier_detail_risk_payload.get("missing_or_empty_source_tables", [])
            or supplier_detail_risk_payload.get("authorizing") is not False
        ):
            raise SmokeError(
                f"source supplier detail risk read failed: {status} {supplier_detail_risk_payload}"
            )
        supplier_detail_risk_status = status
        status, supplier_stats_payload = request(
            args.port, "/api/company/srm/stats/overview", token=token,
        )
        supplier_stats_data = (supplier_stats_payload or {}).get("data", {})
        if (
            status != 200
            or supplier_stats_payload is None
            or supplier_stats_data.get("total") != 0
            or supplier_stats_data.get("byEvalResult") != []
            or supplier_stats_payload.get("source_coverage", {}).get("cb_contract") != 2
            or supplier_stats_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source supplier stats read failed: {status} {supplier_stats_payload}")
        status, attachment_all_payload = request(
            args.port, "/api/company/attachments/all", token=token,
        )
        attachment_all_data = (attachment_all_payload or {}).get("data", {})
        if (
            status != 200
            or attachment_all_payload is None
            or attachment_all_data.get("total") != 0
            or attachment_all_data.get("rows") != []
            or attachment_all_payload.get("source_coverage", {}).get("attachment") != 0
            or attachment_all_payload.get("source_coverage", {}).get("sys_user") != 5
            or "attachment" not in attachment_all_payload.get("missing_or_empty_source_tables", [])
            or attachment_all_payload.get("authorizing") is not False
            or attachment_all_payload.get("downloadable") is not False
            or attachment_all_payload.get("binary_storage") != "not_imported"
        ):
            raise SmokeError(f"source attachment all read failed: {status} {attachment_all_payload}")
        status, attachment_list_payload = request(
            args.port,
            "/api/company/attachments/list?bizType=contract&bizGuid=ht-tj-001",
            token=token,
        )
        if (
            status != 200
            or attachment_list_payload is None
            or attachment_list_payload.get("data") != []
            or attachment_list_payload.get("source_coverage", {}).get("attachment") != 0
            or attachment_list_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source attachment list read failed: {status} {attachment_list_payload}")
        status, attachment_stats_payload = request(
            args.port, "/api/company/attachments/stats", token=token,
        )
        attachment_stats_data = (attachment_stats_payload or {}).get("data", {})
        if (
            status != 200
            or attachment_stats_payload is None
            or attachment_stats_data.get("total") != {"count": 0, "bytes": 0}
            or attachment_stats_data.get("byBizType") != []
            or attachment_stats_data.get("byAiStatus") != []
            or attachment_stats_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source attachment stats read failed: {status} {attachment_stats_payload}")
        status, attachment_download_payload = request(
            args.port, "/api/company/attachments/download/no-attachment", token=token,
        )
        if (
            status != 404
            or attachment_download_payload is None
            or attachment_download_payload.get("code") != 43001
            or attachment_download_payload.get("binary_storage") != "not_imported"
            or attachment_download_payload.get("downloadable") is not False
            or attachment_download_payload.get("authorizing") is not False
        ):
            raise SmokeError(
                f"source attachment download boundary failed: {status} {attachment_download_payload}"
            )
        marketing_payloads: dict[str, dict[str, Any]] = {}
        for marketing_path in (
            "/api/company/marketing/campaigns?projGuid=proj-0001",
            "/api/company/marketing/placements",
            "/api/company/marketing/channels",
            "/api/company/marketing/materials?projGuid=proj-0001",
        ):
            status, marketing_payload = request(args.port, marketing_path, token=token)
            if (
                status != 200
                or marketing_payload is None
                or marketing_payload.get("data") != []
                or marketing_payload.get("source_coverage", {}).get("mkt_campaign") != 0
                or marketing_payload.get("source_coverage", {}).get("mkt_placement") != 0
                or marketing_payload.get("source_coverage", {}).get("mkt_channel") != 0
                or marketing_payload.get("source_coverage", {}).get("mkt_material") != 0
                or marketing_payload.get("authorizing") is not False
            ):
                raise SmokeError(f"source marketing read failed: {marketing_path}: {status} {marketing_payload}")
            marketing_payloads[marketing_path] = marketing_payload
        status, ai_overview_payload = request(
            args.port,
            "/api/company/ai-stats/overview?period=month",
            token=token,
        )
        ai_overview_data = (ai_overview_payload or {}).get("data", {})
        ai_kpi = ai_overview_data.get("kpi", {})
        if (
            status != 200
            or ai_overview_payload is None
            or ai_kpi.get("intakeTotal") != 0
            or ai_kpi.get("queryTotal") != 0
            or ai_kpi.get("skipTotal") != 0
            or ai_overview_payload.get("source_coverage", {}).get("ai_draft") != 0
            or ai_overview_payload.get("source_coverage", {}).get("ai_query_log") != 0
            or ai_overview_payload.get("authorizing") is not False
            or ai_overview_payload.get("provider_execution") is not False
        ):
            raise SmokeError(f"source AI overview read failed: {status} {ai_overview_payload}")
        status, ai_activity_payload = request(
            args.port,
            "/api/company/ai-stats/activity?limit=30",
            token=token,
        )
        if (
            status != 200
            or ai_activity_payload is None
            or ai_activity_payload.get("data") != []
            or ai_activity_payload.get("source_coverage", {}).get("ai_draft") != 0
            or ai_activity_payload.get("provider_execution") is not False
        ):
            raise SmokeError(f"source AI activity read failed: {status} {ai_activity_payload}")
        status, ai_badge_payload = request(
            args.port,
            "/api/company/ai-stats/badge?bizType=contract&bizGuid=HT-CD-260701",
            token=token,
        )
        if (
            status != 200
            or ai_badge_payload is None
            or ai_badge_payload.get("data", {}).get("byAi") is not False
            or ai_badge_payload.get("source_coverage", {}).get("ai_draft") != 0
            or ai_badge_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source AI badge read failed: {status} {ai_badge_payload}")
        status, ai_hub_usage_payload = request(
            args.port, "/api/company/ai-hub/usage-stats", token=token,
        )
        ai_hub_usage_data = (ai_hub_usage_payload or {}).get("data", {})
        if (
            status != 200
            or ai_hub_usage_payload is None
            or ai_hub_usage_data.get("monthlyTotalCalls") != 0
            or ai_hub_usage_data.get("minutesSaved") != 0
            or ai_hub_usage_data.get("intakeTotal") != 0
            or ai_hub_usage_payload.get("source_coverage", {}).get("ai_draft") != 0
            or ai_hub_usage_payload.get("source_coverage", {}).get("ai_query_turn") != 0
            or ai_hub_usage_payload.get("authorizing") is not False
            or ai_hub_usage_payload.get("provider_execution") is not False
            or ai_hub_usage_payload.get("query_execution") is not False
        ):
            raise SmokeError(f"source AI Hub usage read failed: {status} {ai_hub_usage_payload}")
        status, ai_hub_drafts_payload = request(
            args.port, "/api/company/ai-hub/drafts?userCode=admin", token=token,
        )
        if (
            status != 200
            or ai_hub_drafts_payload is None
            or ai_hub_drafts_payload.get("data") != []
            or ai_hub_drafts_payload.get("source_coverage", {}).get("ai_draft") != 0
            or ai_hub_drafts_payload.get("authorizing") is not False
            or ai_hub_drafts_payload.get("persisted") is not False
        ):
            raise SmokeError(f"source AI Hub drafts read failed: {status} {ai_hub_drafts_payload}")
        status, ai_hub_draft_detail_payload = request(
            args.port,
            "/api/company/ai-hub/drafts/missing-draft?userCode=admin",
            token=token,
        )
        if (
            status != 404
            or ai_hub_draft_detail_payload is None
            or ai_hub_draft_detail_payload.get("success") is not False
            or ai_hub_draft_detail_payload.get("code") != 43001
        ):
            raise SmokeError(
                f"source AI Hub draft detail read failed: {status} {ai_hub_draft_detail_payload}"
            )
        ai_hub_draft_detail_status = status
        status, ai_hub_query_payload = request(
            args.port, "/api/company/ai-hub/query-log?userCode=admin", token=token,
        )
        if (
            status != 200
            or ai_hub_query_payload is None
            or ai_hub_query_payload.get("data") != []
            or ai_hub_query_payload.get("source_coverage", {}).get("ai_query_log") != 0
            or ai_hub_query_payload.get("provider_execution") is not False
            or ai_hub_query_payload.get("query_execution") is not False
        ):
            raise SmokeError(f"source AI Hub query log read failed: {status} {ai_hub_query_payload}")
        status, ai_hub_correction_payload = request(
            args.port, "/api/company/ai-hub/correction-stats", token=token,
        )
        ai_hub_correction_data = (ai_hub_correction_payload or {}).get("data", {})
        if (
            status != 200
            or ai_hub_correction_payload is None
            or ai_hub_correction_data.get("byField") != []
            or ai_hub_correction_data.get("total") != 0
            or ai_hub_correction_data.get("drafts") != 0
            or ai_hub_correction_data.get("correctionRate") != 0
            or ai_hub_correction_payload.get("source_coverage", {}).get("ai_correction_log") != 0
            or ai_hub_correction_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source AI Hub correction stats read failed: {status} {ai_hub_correction_payload}")
        status, ai_hub_correction_rows_payload = request(
            args.port, "/api/company/ai-hub/corrections?limit=50", token=token,
        )
        if (
            status != 200
            or ai_hub_correction_rows_payload is None
            or ai_hub_correction_rows_payload.get("data") != []
            or ai_hub_correction_rows_payload.get("source_coverage", {}).get("ai_correction_log") != 0
            or ai_hub_correction_rows_payload.get("provider_execution") is not False
        ):
            raise SmokeError(
                f"source AI Hub corrections read failed: {status} {ai_hub_correction_rows_payload}"
            )
        status, webhook_payload = request(
            args.port,
            "/api/company/webhook/config",
            token=token,
        )
        webhook_data = (webhook_payload or {}).get("data", {})
        if (
            status != 200
            or webhook_payload is None
            or sorted(webhook_data) != ["dingtalk", "feishu", "wecom"]
            or any(webhook_data[platform].get("enabled") is not False for platform in webhook_data)
            or any(webhook_data[platform].get("hasSecret") is not False for platform in webhook_data)
            or webhook_payload.get("source_coverage", {}).get("sys_param") != 0
            or webhook_payload.get("secret_values_redacted") is not True
            or webhook_payload.get("provider_execution") is not False
        ):
            raise SmokeError(f"source webhook config read failed: {status} {webhook_payload}")
        status, notification_messages_payload = request(
            args.port,
            "/api/company/notify/messages?userCode=admin&status=unread",
            token=token,
        )
        notification_messages_data = (notification_messages_payload or {}).get("data", {})
        if (
            status != 200
            or notification_messages_payload is None
            or notification_messages_data.get("total") != 0
            or notification_messages_data.get("rows") != []
            or notification_messages_payload.get("source_coverage", {}).get("sys_message") != 0
            or notification_messages_payload.get("source_coverage", {}).get("sys_user") != 5
            or notification_messages_payload.get("authorizing") is not False
            or notification_messages_payload.get("persisted") is not False
        ):
            raise SmokeError(f"source notification message read failed: {status} {notification_messages_payload}")
        status, notification_unread_payload = request(
            args.port,
            "/api/company/notify/messages/unread-count?userCode=admin",
            token=token,
        )
        if (
            status != 200
            or notification_unread_payload is None
            or notification_unread_payload.get("data", {}).get("count") != 0
            or notification_unread_payload.get("source_coverage", {}).get("sys_message") != 0
            or notification_unread_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source notification unread read failed: {status} {notification_unread_payload}")
        status, notification_subscriptions_payload = request(
            args.port,
            "/api/company/notify/subscriptions?userCode=admin",
            token=token,
        )
        if (
            status != 200
            or notification_subscriptions_payload is None
            or notification_subscriptions_payload.get("data") != []
            or notification_subscriptions_payload.get("source_coverage", {}).get("sys_warning_subscription") != 0
            or notification_subscriptions_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source notification subscription read failed: {status} {notification_subscriptions_payload}")
        status, notification_config_payload = request(
            args.port, "/api/company/notify/config", token=token,
        )
        notification_config_data = (notification_config_payload or {}).get("data", {})
        if (
            status != 200
            or notification_config_payload is None
            or notification_config_data.get("configured") != []
            or notification_config_payload.get("source_coverage", {}).get("sys_param") != 0
            or notification_config_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source notification config read failed: {status} {notification_config_payload}")
        notification_read_payloads: dict[str, dict[str, Any]] = {}
        for notification_path in (
            "/api/company/notify/email-outbox",
            "/api/company/notify/digest/preview",
            "/api/company/notify/digest/log",
            "/api/company/notify/llm-providers",
        ):
            status, notification_payload = request(args.port, notification_path, token=token)
            if (
                status != 200
                or notification_payload is None
                or notification_payload.get("source_coverage", {}).get("sys_user") != 5
                or notification_payload.get("authorizing") is not False
                or notification_payload.get("provider_execution") is not False
            ):
                raise SmokeError(f"source notification read failed: {notification_path}: {status} {notification_payload}")
            if notification_path != "/api/company/notify/digest/preview" and notification_payload.get("data") != []:
                raise SmokeError(f"source notification empty read failed: {notification_path}: {notification_payload}")
            if notification_path == "/api/company/notify/digest/preview" and notification_payload.get("data", {}).get("total") != 0:
                raise SmokeError(f"source notification digest preview failed: {notification_path}: {notification_payload}")
            notification_read_payloads[notification_path] = notification_payload
        status, ocr_status_payload = request(
            args.port,
            "/api/company/admin/ocr/status",
            token=token,
        )
        ocr_data = (ocr_status_payload or {}).get("data", {})
        if (
            status != 200
            or ocr_status_payload is None
            or ocr_data.get("provider") != "mock"
            or len(ocr_data.get("providers", [])) != 6
            or ocr_status_payload.get("source_coverage", {}).get("sys_param") != 0
            or ocr_status_payload.get("provider_execution") is not False
            or ocr_status_payload.get("secret_values_redacted") is not True
        ):
            raise SmokeError(f"source OCR status read failed: {status} {ocr_status_payload}")
        status, error_log_payload = request(
            args.port,
            "/api/company/admin/error-log?limit=100",
            token=token,
        )
        error_log_data = (error_log_payload or {}).get("data", {})
        if (
            status != 200
            or error_log_payload is None
            or error_log_data.get("total") != 0
            or error_log_data.get("rows") != []
            or error_log_payload.get("source_coverage", {}).get("sys_error_log") != 0
            or error_log_payload.get("network_fields_redacted") is not True
            or error_log_payload.get("stack_included") is not False
        ):
            raise SmokeError(f"source error log read failed: {status} {error_log_payload}")
        status, cashflow_payload = request(
            args.port,
            "/api/company/cashflow/forecast?months=6&projGuid=proj-0001",
            token=token,
        )
        cashflow_data = (cashflow_payload or {}).get("data", {})
        if (
            status != 200
            or cashflow_payload is None
            or len(cashflow_data.get("series", [])) != 6
            or cashflow_payload.get("source_coverage", {}).get("cb_htfkplan") != 4
            or cashflow_payload.get("source_coverage", {}).get("cb_htfk_apply") != 3
            or cashflow_payload.get("source_coverage", {}).get("cb_contract") != 2
            or cashflow_payload.get("source_coverage", {}).get("vcb_expense") != 0
            or cashflow_payload.get("source_coverage", {}).get("sale_revenue") != 0
            or cashflow_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source cashflow forecast read failed: {status} {cashflow_payload}")
        detail_month = f"{date.today().year:04d}-{date.today().month + 1:02d}"
        if date.today().month == 12:
            detail_month = f"{date.today().year + 1:04d}-01"
        status, cashflow_detail_payload = request(
            args.port,
            f"/api/company/cashflow/forecast/detail?ym={detail_month}&projGuid=proj-0001",
            token=token,
        )
        cashflow_detail_data = (cashflow_detail_payload or {}).get("data", {})
        if (
            status != 200
            or cashflow_detail_payload is None
            or cashflow_detail_data.get("ym") != detail_month
            or not isinstance(cashflow_detail_data.get("plans"), list)
            or cashflow_detail_payload.get("source_coverage", {}).get("cb_htfkplan") != 4
            or cashflow_detail_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source cashflow detail read failed: {status} {cashflow_detail_payload}")
        status, cashflow_inflow_payload = request(
            args.port,
            "/api/company/cashflow/inflow?months=6&projGuid=proj-0001",
            token=token,
        )
        cashflow_inflow_data = (cashflow_inflow_payload or {}).get("data", {})
        if (
            status != 200
            or cashflow_inflow_payload is None
            or len(cashflow_inflow_data.get("series", [])) != 9
            or cashflow_inflow_data.get("totals", {}).get("totalInflow") != 0.0
            or cashflow_inflow_payload.get("source_coverage", {}).get("sale_revenue") != 0
            or cashflow_inflow_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source cashflow inflow read failed: {status} {cashflow_inflow_payload}")
        status, cashflow_net_payload = request(
            args.port, "/api/company/cashflow/net?months=6", token=token,
        )
        cashflow_net_data = (cashflow_net_payload or {}).get("data", {})
        if (
            status != 200
            or cashflow_net_payload is None
            or len(cashflow_net_data.get("series", [])) != 6
            or cashflow_net_payload.get("source_coverage", {}).get("cb_htfkplan") != 4
            or cashflow_net_payload.get("source_coverage", {}).get("sale_revenue") != 0
            or cashflow_net_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source cashflow net read failed: {status} {cashflow_net_payload}")
        status, cashflow_gap_payload = request(
            args.port, "/api/company/cashflow/gap-alert?horizonDays=90", token=token,
        )
        cashflow_gap_data = (cashflow_gap_payload or {}).get("data", {})
        if (
            status != 200
            or cashflow_gap_payload is None
            or cashflow_gap_data.get("gapWeeks") != []
            or cashflow_gap_payload.get("source_coverage", {}).get("cb_contract_milestone") != 0
            or cashflow_gap_payload.get("source_coverage", {}).get("sale_revenue") != 0
            or cashflow_gap_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source cashflow gap read failed: {status} {cashflow_gap_payload}")
        status, cashflow_v3_payload = request(
            args.port,
            "/api/company/cashflow/forecast-v3?months=6&projGuid=proj-0001",
            token=token,
        )
        cashflow_v3_data = (cashflow_v3_payload or {}).get("data", {})
        if (
            status != 200
            or cashflow_v3_payload is None
            or len(cashflow_v3_data.get("series", [])) != 6
            or cashflow_v3_data.get("totals", {}).get("gap_total") != 0.0
            or cashflow_v3_payload.get("source_coverage", {}).get("cb_plan_version") != 0
            or cashflow_v3_payload.get("source_coverage", {}).get("cb_subject_dict") != 0
            or cashflow_v3_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source cashflow v3 read failed: {status} {cashflow_v3_payload}")
        status, cbs_master_payload = request(args.port, "/api/company/cbs/r-master", token=token)
        if (
            status != 200
            or cbs_master_payload is None
            or cbs_master_payload.get("data") != []
            or cbs_master_payload.get("source_coverage", {}).get("cb_r_master") != 0
            or cbs_master_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source CBS R master read failed: {status} {cbs_master_payload}")
        status, cbs_dict_payload = request(
            args.port,
            "/api/company/cbs/dict?projGuid=proj-0001",
            token=token,
        )
        cbs_dict_data = (cbs_dict_payload or {}).get("data", {})
        if (
            status != 200
            or cbs_dict_payload is None
            or cbs_dict_data.get("planVersion") != "baseline"
            or cbs_dict_data.get("items") != []
            or cbs_dict_payload.get("source_coverage", {}).get("cb_subject_dict") != 0
            or cbs_dict_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source CBS dict read failed: {status} {cbs_dict_payload}")
        status, cbs_f_balance_payload = request(
            args.port,
            "/api/company/cbs/dict/f-balance?projGuid=proj-0001&l3Code=03.01.01",
            token=token,
        )
        if (
            status != 404
            or cbs_f_balance_payload is None
            or cbs_f_balance_payload.get("data") is not None
            or cbs_f_balance_payload.get("source_coverage", {}).get("cb_subject_dict") != 0
            or cbs_f_balance_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source CBS F balance read failed: {status} {cbs_f_balance_payload}")
        status, cbs_versions_payload = request(
            args.port,
            "/api/company/cbs/versions?projGuid=proj-0001",
            token=token,
        )
        if (
            status != 200
            or cbs_versions_payload is None
            or cbs_versions_payload.get("data") != []
            or cbs_versions_payload.get("source_coverage", {}).get("cb_plan_version") != 0
            or cbs_versions_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source CBS versions read failed: {status} {cbs_versions_payload}")
        status, cbs_compare_payload = request(
            args.port,
            "/api/company/cbs/versions/compare?projGuid=proj-0001&a=baseline&b=execution",
            token=token,
        )
        if (
            status != 200
            or cbs_compare_payload is None
            or cbs_compare_payload.get("data", {}).get("rows") != []
            or cbs_compare_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source CBS version compare read failed: {status} {cbs_compare_payload}")
        status, cbs_r0_payload = request(
            args.port, "/api/company/cbs/r0/queue?projGuid=proj-0001", token=token,
        )
        if (
            status != 200
            or cbs_r0_payload is None
            or len(cbs_r0_payload.get("data", {}).get("items", [])) != 2
            or cbs_r0_payload.get("source_coverage", {}).get("cb_contract") != 2
            or cbs_r0_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source CBS R0 queue read failed: {status} {cbs_r0_payload}")
        status, cbs_rules_payload = request(
            args.port, "/api/company/cbs/approval-rules", token=token,
        )
        if (
            status != 200
            or cbs_rules_payload is None
            or cbs_rules_payload.get("data") != []
            or cbs_rules_payload.get("source_coverage", {}).get("wf_approval_rule") != 0
            or cbs_rules_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source CBS approval-rules read failed: {status} {cbs_rules_payload}")
        status, cbs_pick_payload = request(
            args.port,
            "/api/company/cbs/approval-rules/pick?bizType=Contract&amount=100000",
            token=token,
        )
        if (
            status != 200
            or cbs_pick_payload is None
            or cbs_pick_payload.get("data") is not None
            or cbs_pick_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source CBS approval pick read failed: {status} {cbs_pick_payload}")
        status, cbs_changes_payload = request(
            args.port, "/api/company/cbs/changes?projGuid=proj-0001", token=token,
        )
        if (
            status != 200
            or cbs_changes_payload is None
            or cbs_changes_payload.get("data") != []
            or cbs_changes_payload.get("source_coverage", {}).get("cb_change_apply") != 0
            or cbs_changes_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source CBS changes read failed: {status} {cbs_changes_payload}")
        status, cbs_demo_contracts_payload = request(
            args.port, "/api/company/cbs/demo/contracts?projGuid=proj-0001", token=token,
        )
        if (
            status != 200
            or cbs_demo_contracts_payload is None
            or len(cbs_demo_contracts_payload.get("data", [])) != 2
            or cbs_demo_contracts_payload.get("authorizing") is not False
        ):
            raise SmokeError(
                f"source CBS contract read failed: {status} {cbs_demo_contracts_payload}"
            )
        status, fund_plans_payload = request(
            args.port,
            "/api/company/fund/plans?projGuid=proj-0001",
            token=token,
        )
        if (
            status != 200
            or fund_plans_payload is None
            or fund_plans_payload.get("data") != []
            or fund_plans_payload.get("source_coverage", {}).get("fund_plan") != 0
            or fund_plans_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source fund plans read failed: {status} {fund_plans_payload}")
        status, fund_gap_payload = request(
            args.port,
            "/api/company/fund/gap-analysis?projGuid=proj-0001",
            token=token,
        )
        if (
            status != 200
            or fund_gap_payload is None
            or fund_gap_payload.get("data", {}).get("series") != []
            or fund_gap_payload.get("source_coverage", {}).get("fund_plan") != 0
            or fund_gap_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source fund gap read failed: {status} {fund_gap_payload}")
        status, fund_dispatch_payload = request(
            args.port, "/api/company/fund/dispatches", token=token,
        )
        if (
            status != 200
            or fund_dispatch_payload is None
            or fund_dispatch_payload.get("data") != []
            or fund_dispatch_payload.get("source_coverage", {}).get("fund_dispatch") != 0
            or fund_dispatch_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source fund dispatch read failed: {status} {fund_dispatch_payload}")
        status, warning_badge_payload = request(
            args.port, "/api/company/warning/badge", token=token,
        )
        warning_badge_data = (warning_badge_payload or {}).get("data", {})
        if (
            status != 200
            or warning_badge_payload is None
            or warning_badge_data.get("openTotal") != 1
            or len(warning_badge_data.get("top", [])) != 1
            or warning_badge_data.get("top", [{}])[0].get("ruleCode") != "W005"
            or warning_badge_payload.get("persisted") is not False
            or warning_badge_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source warning badge read failed: {status} {warning_badge_payload}")
        status, warning_list_payload = request(
            args.port, "/api/company/warning?status=open", token=token,
        )
        warning_list_data = (warning_list_payload or {}).get("data", {})
        if (
            status != 200
            or warning_list_payload is None
            or warning_list_data.get("total") != 1
            or warning_list_data.get("rows", [{}])[0].get("ruleCode") != "W005"
            or warning_list_payload.get("source_coverage", {}).get("ep_project") != 2
            or warning_list_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source warning list read failed: {status} {warning_list_payload}")
        status, warning_rules_payload = request(
            args.port, "/api/company/warning/rules", token=token,
        )
        warning_rules_data = warning_rules_payload or {}
        if (
            status != 200
            or warning_rules_payload is None
            or len(warning_rules_data.get("data", [])) != 12
            or next((row for row in warning_rules_data["data"] if row.get("ruleCode") == "W005"), {}).get("openCount") != 1
            or warning_rules_payload.get("persisted") is not False
        ):
            raise SmokeError(f"source warning rules read failed: {status} {warning_rules_payload}")
        warning_empty_payloads = []
        for warning_path in (
            "/api/company/warning/scans",
            "/api/company/warning/custom-rules",
            "/api/company/warning/rule-templates",
            "/api/company/warning/tickets/mine",
        ):
            status, warning_empty_payload = request(args.port, warning_path, token=token)
            if (
                status != 200
                or warning_empty_payload is None
                or warning_empty_payload.get("data") != []
                or warning_empty_payload.get("persisted") is not False
                or warning_empty_payload.get("authorizing") is not False
            ):
                raise SmokeError(f"source warning empty read failed: {warning_path}: {status} {warning_empty_payload}")
            warning_empty_payloads.append(warning_empty_payload)
        status, supplier_risk_payload = request(args.port, "/api/company/srm/risk-board", token=token)
        supplier_risk_data = (supplier_risk_payload or {}).get("data", {})
        if (
            status != 200
            or supplier_risk_payload is None
            or supplier_risk_data.get("highRisk") != []
            or supplier_risk_data.get("distribution") != []
            or supplier_risk_payload.get("source_coverage", {}).get("cb_contract") != 2
            or "srm_provider" not in supplier_risk_payload.get("missing_or_empty_source_tables", [])
            or "srm_category" not in supplier_risk_payload.get("missing_or_empty_source_tables", [])
            or "cb_contract_milestone" not in supplier_risk_payload.get("missing_or_empty_source_tables", [])
            or supplier_risk_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"source supplier risk read failed: {status} {supplier_risk_payload}")
        status, payload = request(args.port, "/api/company/reports/overview", token=token)
        if (
            status != 200
            or payload is None
            or not isinstance(payload.get("cost_summary", {}).get("rows"), list)
            or not isinstance(payload.get("contract_payment_ledger"), list)
            or not isinstance(payload.get("source_coverage"), dict)
        ):
            raise SmokeError(f"report overview read failed: {status} {payload}")
        report_cost_rows = len(payload["cost_summary"]["rows"])
        report_contract_rows = len(payload["contract_payment_ledger"])
        report_missing_tables = payload.get("missing_source_tables", [])
        status, report_meta_payload = request(
            args.port,
            "/api/company/reports/templates/meta",
            token=token,
        )
        report_meta_data = (report_meta_payload or {}).get("data", {})
        if (
            status != 200
            or report_meta_payload is None
            or len(report_meta_data.get("tables", [])) != 10
            or report_meta_data.get("operators") != ["=", "!=", ">", ">=", "<", "<=", "like", "in"]
            or report_meta_payload.get("source_kind") != "definition"
            or report_meta_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"report template metadata read failed: {status} {report_meta_payload}")
        status, report_templates_payload = request(
            args.port,
            "/api/company/reports/templates",
            token=token,
        )
        if (
            status != 200
            or report_templates_payload is None
            or report_templates_payload.get("data") != []
            or report_templates_payload.get("source_coverage", {}).get("sys_report_template") != 0
            or report_templates_payload.get("persisted") is not False
            or report_templates_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"report template list read failed: {status} {report_templates_payload}")
        report_template_rows = len(report_templates_payload.get("data", []))
        status, dashboard_overview = request(
            args.port,
            "/api/company/dashboard/group/overview",
            token=token,
        )
        if (
            status != 200
            or dashboard_overview is None
            or dashboard_overview.get("data", {}).get("projectCount") != 2
            or dashboard_overview.get("data", {}).get("contractCount") != 2
            or dashboard_overview.get("data", {}).get("paidAmount") != 5640000.0
            or dashboard_overview.get("source_coverage", {}).get("ep_project") != 2
            or dashboard_overview.get("source_coverage", {}).get("cb_cost") != 7
            or "sale_revenue" not in dashboard_overview.get("missing_source_tables", [])
        ):
            raise SmokeError(f"dashboard overview read failed: {status} {dashboard_overview}")
        status, dashboard_funnel = request(
            args.port,
            "/api/company/dashboard/group/funnel",
            token=token,
        )
        if (
            status != 200
            or dashboard_funnel is None
            or len(dashboard_funnel.get("data", [])) != 7
            or dashboard_funnel.get("data", [])[0].get("stageCode") != "initiation"
            or dashboard_funnel.get("data", [])[0].get("count") != 2
        ):
            raise SmokeError(f"dashboard funnel read failed: {status} {dashboard_funnel}")
        status, dashboard_anomalies = request(
            args.port,
            "/api/company/dashboard/group/top-anomalies?limit=2",
            token=token,
        )
        if (
            status != 200
            or dashboard_anomalies is None
            or len(dashboard_anomalies.get("data", [])) != 2
            or dashboard_anomalies.get("data", [])[0].get("projGuid") not in {"proj-0001", "proj-0002"}
        ):
            raise SmokeError(f"dashboard anomaly read failed: {status} {dashboard_anomalies}")
        status, dashboard_kpi = request(
            args.port,
            "/api/company/dashboard/project/proj-0001/kpi",
            token=token,
        )
        if (
            status != 200
            or dashboard_kpi is None
            or dashboard_kpi.get("data", {}).get("project", {}).get("projGuid") != "proj-0001"
            or dashboard_kpi.get("data", {}).get("kpi", {}).get("progress", {}).get("totalNodes") != 5
            or dashboard_kpi.get("data", {}).get("kpi", {}).get("contract", {}).get("count") != 2
            or dashboard_kpi.get("data", {}).get("kpi", {}).get("payment", {}).get("paidTotal") != 5640000.0
        ):
            raise SmokeError(f"dashboard project KPI read failed: {status} {dashboard_kpi}")
        status, dashboard_project_anomalies = request(
            args.port,
            "/api/company/dashboard/project/proj-0001/anomalies",
            token=token,
        )
        if (
            status != 200
            or dashboard_project_anomalies is None
           or not isinstance(dashboard_project_anomalies.get("data"), list)
            or len(dashboard_project_anomalies.get("data", [])) != 1
            or dashboard_project_anomalies.get("data", [])[0].get("severity") != "warning"
            or "成本超目标" not in dashboard_project_anomalies.get("data", [])[0].get("title", "")
           or "sale_revenue" not in dashboard_project_anomalies.get("missing_source_tables", [])
        ):
            raise SmokeError(
                f"dashboard project anomaly read failed: {status} {dashboard_project_anomalies}"
            )
        status, dashboard_v2_payload = request(
            args.port,
            "/api/company/dashboard/v2/group?projGuid=proj-0001",
            token=token,
        )
        dashboard_v2_data = (dashboard_v2_payload or {}).get("data", {})
        if (
            status != 200
            or dashboard_v2_payload is None
            or dashboard_v2_data.get("scope", {}).get("projGuid") != "proj-0001"
            or dashboard_v2_data.get("kpi", {}).get("projectCount") != 1
            or dashboard_v2_data.get("kpi", {}).get("contractInProgressAmount") != 25050000.0
            or not isinstance(dashboard_v2_data.get("paymentTrend"), list)
            or dashboard_v2_payload.get("source_coverage", {}).get("ep_project") != 2
            or dashboard_v2_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"dashboard v2 read failed: {status} {dashboard_v2_payload}")
        status, dashboard_v3_payload = request(
            args.port,
            "/api/company/dashboard/v3/group?projGuid=proj-0001",
            token=token,
        )
        dashboard_v3_data = (dashboard_v3_payload or {}).get("data", {})
        if (
            status != 200
            or dashboard_v3_payload is None
            or dashboard_v3_data.get("scope", {}).get("projGuid") != "proj-0001"
            or dashboard_v3_data.get("kpi", {}).get("customerCount") != 0
            or dashboard_v3_data.get("kpi", {}).get("totalExpense") != 564.0
            or not isinstance(dashboard_v3_data.get("tops"), dict)
            or dashboard_v3_payload.get("source_coverage", {}).get("ep_project") != 2
            or "sale_revenue" not in dashboard_v3_payload.get("missing_or_empty_source_tables", [])
            or dashboard_v3_payload.get("authorizing") is not False
            or dashboard_v3_payload.get("persisted") is not False
        ):
            raise SmokeError(f"dashboard v3 read failed: {status} {dashboard_v3_payload}")
        status, dashboard_v3_bu_payload = request(
            args.port,
            "/api/company/dashboard/v3/group?buGuid=bu-tjgs-0001",
            token=token,
        )
        dashboard_v3_bu_data = (dashboard_v3_bu_payload or {}).get("data", {})
        if (
            status != 200
            or dashboard_v3_bu_payload is None
            or dashboard_v3_bu_data.get("scope", {}).get("buGuid") != "bu-tjgs-0001"
            or dashboard_v3_bu_data.get("scope", {}).get("level") != "bu"
            or dashboard_v3_bu_data.get("kpi", {}).get("totalExpense") != 564.0
            or dashboard_v3_bu_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"dashboard v3 BU scope failed: {status} {dashboard_v3_bu_payload}")
        status, dashboard_v3_group_payload = request(
            args.port, "/api/company/dashboard/v3/group", token=token,
        )
        dashboard_v3_group_data = (dashboard_v3_group_payload or {}).get("data", {})
        if (
            status != 200
            or dashboard_v3_group_payload is None
            or dashboard_v3_group_data.get("scope", {}).get("level") != "group"
            or dashboard_v3_group_data.get("kpi", {}).get("totalExpense") != 564.0
            or len(dashboard_v3_group_data.get("expenseByCity", [])) != 2
            or dashboard_v3_group_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"dashboard v3 group scope failed: {status} {dashboard_v3_group_payload}")
        dashboard_overview_rows = dashboard_overview.get("data", {})
        dashboard_funnel_rows = dashboard_funnel.get("data", [])
        dashboard_anomaly_rows = dashboard_anomalies.get("data", [])
        dashboard_v2_rows = dashboard_v2_data
        dashboard_v3_rows = dashboard_v3_data
        status, payload = request(args.port, "/api/company/workflow/process-defs", token=token)
        if (
            status != 200
            or payload is None
            or not isinstance(payload.get("items"), list)
            or payload.get("source_coverage", {}).get("wf_process_def") != 2
            or payload.get("source_coverage", {}).get("wf_step_def") != 12
            or payload.get("source_coverage", {}).get("wf_step_assignee") != 6
            or payload.get("instances_available") != 0
            or payload.get("actions_available") != 0
        ):
            raise SmokeError(f"workflow definition read failed: {status} {payload}")
        if len(payload["items"]) != 2:
            raise SmokeError(f"workflow definition count failed: {payload}")
        workflow_assignees = [
            assignee
            for process in payload["items"]
            for step in process.get("steps", [])
            for assignee in step.get("assignees", [])
        ]
        if (
            len(workflow_assignees) != 6
            or next(
                (row for row in workflow_assignees if row.get("user_guid") == "user-lmj-0001"),
                {},
            ).get("user_name")
            != "李明津"
            or payload.get("source_coverage", {}).get("sys_user") != 5
        ):
            raise SmokeError(f"workflow assignee identity read failed: {payload}")
        status, workflow_preview = request(
            args.port,
            "/api/company/workflow/process-defs/loan-approval/preview",
            token=token,
        )
        if (
            status != 200
            or workflow_preview is None
            or workflow_preview.get("process_key") != "loan-approval"
            or len(workflow_preview.get("steps", [])) != 5
            or workflow_preview.get("instances_available") != 0
            or workflow_preview.get("actions_available") != 0
        ):
            raise SmokeError(f"workflow preview read failed: {status} {workflow_preview}")
        status, business_units_payload = request(
            args.port,
            "/api/company/business-units/tree",
            token=token,
        )
        if (
            status != 200
            or business_units_payload is None
            or not isinstance(business_units_payload.get("data"), list)
            or len(business_units_payload["data"]) != 1
            or tree_count(business_units_payload["data"]) != 7
            or len(business_units_payload["data"][0].get("children", [])) != 2
            or business_units_payload.get("source_coverage", {}).get("mu_business_unit") != 7
        ):
            raise SmokeError(f"business-unit tree read failed: {status} {business_units_payload}")
        status, cost_subject_payload = request(
            args.port,
            "/api/company/budget/dict/cost-subjects",
            token=token,
        )
        if (
            status != 200
            or cost_subject_payload is None
            or len(cost_subject_payload.get("data", [])) != 5
            or cost_subject_payload.get("data", [])[0].get("code") != "CS-DYZZF"
            or cost_subject_payload.get("source_coverage", {}).get("my_biz_param_option") != 5
        ):
            raise SmokeError(f"cost-subject dictionary read failed: {status} {cost_subject_payload}")
        status, proceedings_payload = request(
            args.port,
            "/api/company/budget/proceedings",
            token=token,
        )
        if (
            status != 200
            or proceedings_payload is None
            or len(proceedings_payload.get("data", [])) != 3
            or proceedings_payload.get("data", [])[0].get("code") != "BGFCQYY"
            or proceedings_payload.get("source_coverage", {}).get("vys_proceeding") != 3
        ):
            raise SmokeError(f"proceedings dictionary read failed: {status} {proceedings_payload}")
        status, investment_versions_payload = request(
            args.port,
            "/api/company/investment/projects/proj-0001/versions",
            token=token,
        )
        if (
            status != 200
            or investment_versions_payload is None
            or len(investment_versions_payload.get("data", [])) != 1
            or investment_versions_payload.get("data", [])[0].get("versionGuid") != "tzsy-ver-tjhjy-v1"
            or investment_versions_payload.get("data", [])[0].get("isCurrent") is not True
        ):
            raise SmokeError(f"investment version read failed: {status} {investment_versions_payload}")
        status, investment_imports_payload = request(
            args.port,
            "/api/company/investment/projects/proj-0001/excel-imports",
            token=token,
        )
        if (
            status != 200
            or investment_imports_payload is None
            or investment_imports_payload.get("data") != []
            or investment_imports_payload.get("source_coverage", {}).get("tzsy_excel_import") != 0
            or "tzsy_excel_import" not in investment_imports_payload.get("missing_or_empty_source_tables", [])
            or investment_imports_payload.get("authorizing") is not False
            or investment_imports_payload.get("persisted") is not False
        ):
            raise SmokeError(f"investment import history read failed: {status} {investment_imports_payload}")
        investment_import_detail_statuses = {}
        for investment_import_path in (
            "/api/company/investment/excel-imports/no-import",
            "/api/company/investment/excel-imports/no-import/bridge-plan",
            "/api/company/investment/excel-imports/no-import/index-upsert-preview",
            "/api/company/investment/excel-imports/no-import/profit-table",
            "/api/company/investment/excel-imports/no-import/plan-line-preview",
        ):
            status, investment_import_detail_payload = request(
                args.port, investment_import_path, token=token,
            )
            if status != 404 or investment_import_detail_payload is None:
                raise SmokeError(
                    f"investment import detail boundary failed: {investment_import_path}: "
                    f"{status} {investment_import_detail_payload}"
                )
            investment_import_detail_statuses[investment_import_path] = status
        status, investment_plan_lines_payload = request(
            args.port,
            "/api/company/investment/projects/proj-0001/plan-lines",
            token=token,
        )
        if (
            status != 200
            or investment_plan_lines_payload is None
            or investment_plan_lines_payload.get("data", {}).get("lines") != []
            or investment_plan_lines_payload.get("source_coverage", {}).get("tzsy_plan_line") != 0
            or investment_plan_lines_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"investment plan-line read failed: {status} {investment_plan_lines_payload}")
        status, investment_mappings_payload = request(
            args.port,
            "/api/company/investment/projects/proj-0001/subject-mappings",
            token=token,
        )
        if (
            status != 200
            or investment_mappings_payload is None
            or investment_mappings_payload.get("data", {}).get("groups") != {}
            or investment_mappings_payload.get("source_coverage", {}).get("tzsy_subject_mapping") != 0
            or investment_mappings_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"investment subject mapping read failed: {status} {investment_mappings_payload}")
        status, investment_cockpit_payload = request(
            args.port,
            "/api/company/investment/projects/proj-0001/profit-cockpit",
            token=token,
        )
        if status != 404 or investment_cockpit_payload is None or investment_cockpit_payload.get("code") != 41002:
            raise SmokeError(f"investment cockpit boundary failed: {status} {investment_cockpit_payload}")
        status, investment_indices_payload = request(
            args.port,
            "/api/company/investment/versions/tzsy-ver-tjhjy-v1/indices",
            token=token,
        )
        if (
            status != 200
            or investment_indices_payload is None
            or len(investment_indices_payload.get("data", [])) != 5
            or sum(len(group.get("items", [])) for group in investment_indices_payload["data"]) != 26
            or investment_indices_payload.get("source_coverage", {}).get("tzsy_plan_index") != 26
        ):
            raise SmokeError(f"investment index read failed: {status} {investment_indices_payload}")
        status, investment_profit_payload = request(
            args.port,
            "/api/company/investment/projects/proj-0001/profit-summary",
            token=token,
        )
        if (
            status != 200
            or investment_profit_payload is None
            or investment_profit_payload.get("data", {}).get("revenue") != 18500.0
            or investment_profit_payload.get("data", {}).get("netProfit") != 2890.0
            or investment_profit_payload.get("data", {}).get("irr") != 14.8
        ):
            raise SmokeError(f"investment profit summary read failed: {status} {investment_profit_payload}")
        status, investment_dimensions_payload = request(
            args.port,
            "/api/company/investment/meta/dimensions",
            token=token,
        )
        if (
            status != 200
            or investment_dimensions_payload is None
            or len(investment_dimensions_payload.get("data", [])) != 5
            or investment_dimensions_payload.get("data", [])[0].get("code") != "key_point"
        ):
            raise SmokeError(f"investment dimension read failed: {status} {investment_dimensions_payload}")
        status, dynamic_cost_payload = request(
            args.port,
            "/api/company/cost/dynamic-cost?projGuid=proj-0001",
            token=token,
        )
        dynamic_cost_data = (dynamic_cost_payload or {}).get("data", {})
        dynamic_cost_summary = dynamic_cost_data.get("summary", {})
        if (
            status != 200
            or dynamic_cost_payload is None
            or len(dynamic_cost_data.get("items", [])) != 7
            or dynamic_cost_summary.get("endCount") != 6
            or dynamic_cost_summary.get("A_targetCost") != 35900000.0
            or dynamic_cost_summary.get("B_dtCost") != 36350000.0
            or dynamic_cost_summary.get("C_deviationPct") != -1.2535
            or dynamic_cost_payload.get("source_coverage", {}).get("cb_cost") != 7
        ):
            raise SmokeError(f"dynamic cost read failed: {status} {dynamic_cost_payload}")
        status, cost_dashboard_payload = request(
            args.port,
            "/api/company/investment/projects/proj-0001/profit-actual-v2?planVersion=baseline",
            token=token,
        )
        cost_dashboard_data = (cost_dashboard_payload or {}).get("data", {})
        if (
            status != 200
            or cost_dashboard_payload is None
            or cost_dashboard_data.get("rows") != []
            or cost_dashboard_data.get("summary", {}).get("targetCost") != 0
            or cost_dashboard_data.get("counts", {}).get("leaves") != 0
            or cost_dashboard_payload.get("source_coverage", {}).get("cb_subject_dict") != 0
            or cost_dashboard_payload.get("source_coverage", {}).get("cb_plan_version") != 0
            or "cb_subject_dict" not in cost_dashboard_payload.get("missing_or_empty_source_tables", [])
        ):
            raise SmokeError(f"cost dashboard source read failed: {status} {cost_dashboard_payload}")
        status, admin_groups_payload = request(
            args.port,
            "/api/company/admin/dict/groups",
            token=token,
        )
        if (
            status != 200
            or admin_groups_payload is None
            or len(admin_groups_payload.get("data", [])) != 1
            or admin_groups_payload.get("data", [])[0].get("groupName") != "cost_subject"
            or admin_groups_payload.get("data", [])[0].get("enabled") != 5
        ):
            raise SmokeError(f"admin dictionary groups read failed: {status} {admin_groups_payload}")
        status, admin_health_full_payload = request(
            args.port,
            "/api/company/admin/health/full",
            token=token,
        )
        admin_health_full_data = (admin_health_full_payload or {}).get("data", {})
        if (
            status != 200
            or admin_health_full_payload is None
            or admin_health_full_data.get("runtimeMetricsAvailable") is not False
            or len(admin_health_full_data.get("tables", [])) != 29
            or admin_health_full_data.get("db", {}).get("name") != args.database
            or admin_health_full_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"admin full health read failed: {status} {admin_health_full_payload}")
        status, admin_llm_payload = request(
            args.port,
            "/api/company/admin/llm/status",
            token=token,
        )
        if (
            status != 200
            or admin_llm_payload is None
            or admin_llm_payload.get("data", {}).get("provider") != "mock"
            or admin_llm_payload.get("data", {}).get("providers") != []
            or admin_llm_payload.get("provider_execution") is not False
            or admin_llm_payload.get("secret_values_redacted") is not True
        ):
            raise SmokeError(f"admin LLM status read failed: {status} {admin_llm_payload}")
        status, admin_ai_diag_payload = request(
            args.port,
            "/api/company/admin/ai/diag",
            token=token,
        )
        if (
            status != 200
            or admin_ai_diag_payload is None
            or admin_ai_diag_payload.get("data", {}).get("pingResult") is not None
            or admin_ai_diag_payload.get("provider_execution") is not False
            or admin_ai_diag_payload.get("secret_values_redacted") is not True
        ):
            raise SmokeError(f"admin AI diagnostic read failed: {status} {admin_ai_diag_payload}")
        status, admin_quality_payload = request(
            args.port,
            "/api/company/admin/quality/overview",
            token=token,
        )
        quality_summary = (admin_quality_payload or {}).get("data", {}).get("summary", {})
        quality_rules = (admin_quality_payload or {}).get("data", {}).get("rules", [])
        if (
            status != 200
            or admin_quality_payload is None
            or quality_summary.get("totalRules") != 12
            or quality_summary.get("evaluatedRules") != 8
            or quality_summary.get("unavailableRules") != 4
            or quality_summary.get("failed") != 1
            or len(quality_rules) != 12
            or next((row for row in quality_rules if row.get("ruleCode") == "project_without_dynamic_cost"), {}).get("count") != 1
            or next((row for row in quality_rules if row.get("ruleCode") == "supplier_duplicate_name"), {}).get("status") != "NO_SOURCE_ROWS"
            or "srm_provider" not in admin_quality_payload.get("missing_or_empty_source_tables", [])
        ):
            raise SmokeError(f"admin quality overview read failed: {status} {admin_quality_payload}")
        status, users_payload = request(
            args.port,
            "/api/company/rbac/users",
            token=token,
        )
        user_rows = (users_payload or {}).get("data", [])
        if (
            status != 200
            or users_payload is None
            or len(user_rows) != 5
            or user_rows[0].get("userCode") != "admin"
            or user_rows[0].get("isSuperUser") is not True
            or user_rows[0].get("rolesSourceStatus") != "NO_SOURCE_ROWS"
            or users_payload.get("source_coverage", {}).get("sys_user") != 5
            or users_payload.get("source_coverage", {}).get("mu_business_unit") != 7
            or "sys_role" not in users_payload.get("missing_or_empty_source_tables", [])
        ):
            raise SmokeError(f"RBAC user roster read failed: {status} {users_payload}")
        status, profile_payload = request(
            args.port,
            "/api/company/auth/me?userCode=admin",
            token=token,
        )
        profile_data = (profile_payload or {}).get("data", {})
        if (
            status != 200
            or profile_payload is None
            or profile_data.get("userId") != "user-admin-0001"
            or profile_data.get("userCode") != "admin"
            or profile_data.get("buName") != "和泓置地总部"
            or profile_data.get("deptName") != "和泓置地总部"
            or profile_data.get("isSuperUser") is not True
            or profile_data.get("sourceKind") != "imported"
            or profile_payload.get("source_coverage", {}).get("sys_user") != 5
            or profile_payload.get("source_coverage", {}).get("mu_business_unit") != 7
        ):
            raise SmokeError(f"auth profile read failed: {status} {profile_payload}")
        status, prefs_payload = request(
            args.port,
            "/api/company/auth/prefs?userCode=admin",
            token=token,
        )
        if (
            status != 200
            or prefs_payload is None
            or prefs_payload.get("data") != {}
            or prefs_payload.get("source_coverage", {}).get("sys_user") != 5
            or prefs_payload.get("source_coverage", {}).get("sys_user_pref") != 0
            or "sys_user_pref" not in prefs_payload.get("missing_or_empty_source_tables", [])
            or prefs_payload.get("authorizing") is not False
            or prefs_payload.get("persisted") is not False
        ):
            raise SmokeError(f"auth preference read failed: {status} {prefs_payload}")
        status, rbac_me_payload = request(
            args.port,
            "/api/company/rbac/me?userCode=admin",
            token=token,
        )
        rbac_me_data = (rbac_me_payload or {}).get("data", {})
        if (
            status != 200
            or rbac_me_payload is None
            or rbac_me_data.get("userId") != "user-admin-0001"
            or rbac_me_data.get("userCode") != "admin"
            or rbac_me_data.get("roles") != []
            or rbac_me_data.get("permissions") != []
            or rbac_me_data.get("rolesSourceStatus") != "NO_SOURCE_ROWS"
            or rbac_me_payload.get("source_coverage", {}).get("sys_user") != 5
            or rbac_me_payload.get("source_coverage", {}).get("sys_role") != 0
            or rbac_me_payload.get("source_coverage", {}).get("sys_user_role") != 0
            or rbac_me_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"RBAC current-user read failed: {status} {rbac_me_payload}")
        status, rbac_roles_payload = request(
            args.port,
            "/api/company/rbac/roles",
            token=token,
        )
        if (
            status != 200
            or rbac_roles_payload is None
            or rbac_roles_payload.get("data") != []
            or rbac_roles_payload.get("source_coverage", {}).get("sys_role") != 0
            or rbac_roles_payload.get("source_coverage", {}).get("sys_user_role") != 0
            or rbac_roles_payload.get("source_coverage", {}).get("sys_user") != 5
            or "sys_role" not in rbac_roles_payload.get("missing_or_empty_source_tables", [])
            or rbac_roles_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"RBAC role list read failed: {status} {rbac_roles_payload}")
        status, missing_role_payload = request(
            args.port,
            "/api/company/rbac/roles/missing-role",
            token=token,
        )
        if status != 404 or missing_role_payload is None or missing_role_payload.get("error") != "role not found":
            raise SmokeError(f"missing RBAC role should be 404: {status} {missing_role_payload}")
        status, permission_catalog_payload = request(
            args.port,
            "/api/company/rbac/permission-catalog",
            token=token,
        )
        permission_catalog = (permission_catalog_payload or {}).get("data", [])
        if (
            status != 200
            or permission_catalog_payload is None
            or len(permission_catalog) != 11
            or permission_catalog[0].get("module") != "驾驶舱"
            or permission_catalog_payload.get("source_kind") != "definition"
            or permission_catalog_payload.get("authorizing") is not False
            or permission_catalog_payload.get("persisted") is not False
        ):
            raise SmokeError(f"RBAC permission catalog read failed: {status} {permission_catalog_payload}")
        status, missing_profile_payload = request(
            args.port,
            "/api/company/auth/me?userCode=missing-user",
            token=token,
        )
        if status != 404 or missing_profile_payload is None or missing_profile_payload.get("error") != "user not found":
            raise SmokeError(f"missing auth profile should be 404: {status} {missing_profile_payload}")
        status, initiated_payload = request(
            args.port,
            "/api/company/auth/my-initiated?userCode=limingjin",
            token=token,
        )
        initiated_data = (initiated_payload or {}).get("data", {})
        if (
            status != 200
            or initiated_payload is None
            or len(initiated_data.get("expenses", [])) != 0
            or len(initiated_data.get("loans", [])) != 1
            or len(initiated_data.get("applies", [])) != 3
            or initiated_data.get("loans", [])[0].get("code") != "JK202604200001"
            or initiated_payload.get("source_coverage", {}).get("vcb_expense") != 0
            or initiated_payload.get("source_coverage", {}).get("vcb_loan_simple") != 1
            or initiated_payload.get("source_coverage", {}).get("cb_htfk_apply") != 3
        ):
            raise SmokeError(f"auth initiated read failed: {status} {initiated_payload}")
        status, expense_source_payload = request(
            args.port,
            "/api/company/budget/expenses?userCode=admin",
            token=token,
        )
        expense_source_data = (expense_source_payload or {}).get("data", [])
        if (
            status != 200
            or expense_source_payload is None
            or len(expense_source_data) != 0
            or expense_source_payload.get("source_coverage", {}).get("vcb_expense") != 0
            or "vcb_expense" not in expense_source_payload.get("missing_or_empty_source_tables", [])
        ):
            raise SmokeError(f"source expense read failed: {status} {expense_source_payload}")
        status, expense_detail_payload = request(
            args.port,
            "/api/company/budget/expenses/EXP-260712-008?userCode=admin",
            token=token,
        )
        expense_detail_data = (expense_detail_payload or {}).get("data", {})
        if (
            status != 200
            or expense_detail_payload is None
            or expense_detail_data.get("expense") is not None
            or expense_detail_data.get("details") != []
            or expense_detail_data.get("splits") != []
            or expense_detail_payload.get("source_coverage", {}).get("vcb_expense") != 0
            or expense_detail_payload.get("source_coverage", {}).get("cb_expense_detail") != 0
            or expense_detail_payload.get("source_coverage", {}).get("cb_expense_split") != 0
        ):
            raise SmokeError(f"source expense detail read failed: {status} {expense_detail_payload}")
        status, admin_options_payload = request(
            args.port,
            "/api/company/admin/dict/options?groupName=cost_subject",
            token=token,
        )
        if (
            status != 200
            or admin_options_payload is None
            or len(admin_options_payload.get("data", [])) != 5
            or admin_options_payload.get("data", [])[0].get("paramGuid") != "1"
        ):
            raise SmokeError(f"admin dictionary options read failed: {status} {admin_options_payload}")
        status, audit_logs_payload = request(
            args.port,
            "/api/company/admin/audit/logs?limit=10",
            token=token,
        )
        if (
            status != 200
            or audit_logs_payload is None
            or audit_logs_payload.get("data", {}).get("total") != 2
            or len(audit_logs_payload.get("data", {}).get("rows", [])) != 2
            or audit_logs_payload.get("data", {}).get("rows", [])[0].get("logId") != 2
        ):
            raise SmokeError(f"admin audit log read failed: {status} {audit_logs_payload}")
        status, audit_actions_payload = request(
            args.port,
            "/api/company/admin/audit/actions",
            token=token,
        )
        if (
            status != 200
            or audit_actions_payload is None
            or not audit_actions_payload.get("data")
            or audit_actions_payload.get("data", [])[0].get("action") != "login"
            or audit_actions_payload.get("data", [])[0].get("count") != 2
        ):
            raise SmokeError(f"admin audit actions read failed: {status} {audit_actions_payload}")
        status, health_tables_payload = request(
            args.port,
            "/api/company/admin/health/tables",
            token=token,
        )
        if (
            status != 200
            or health_tables_payload is None
            or len(health_tables_payload.get("data", [])) != 29
            or health_tables_payload.get("source_coverage", {}).get("mu_business_unit") != 7
            or health_tables_payload.get("source_coverage", {}).get("wf_process_instance") != 0
            or "srm_provider" not in health_tables_payload.get("missing_or_empty_source_tables", [])
        ):
            raise SmokeError(f"admin health tables read failed: {status} {health_tables_payload}")
        status, health_bpm_payload = request(
            args.port,
            "/api/company/admin/health/bpm-pool",
            token=token,
        )
        if (
            status != 200
            or health_bpm_payload is None
            or health_bpm_payload.get("data", {}).get("byStatus")
            or health_bpm_payload.get("data", {}).get("recent")
            or health_bpm_payload.get("source_coverage", {}).get("wf_process_instance") != 0
            or health_bpm_payload.get("authorizing") is not False
        ):
            raise SmokeError(f"admin BPM health read failed: {status} {health_bpm_payload}")
        status, project_payload = request(args.port, "/api/company/projects", token=token)
        if (
            status != 200
            or project_payload is None
            or len(project_payload.get("items", [])) != 2
            or project_payload.get("source_coverage", {}).get("ep_project") != 2
            or project_payload.get("source_coverage", {}).get("proj_lifecycle_instance") != 14
            or project_payload.get("source_coverage", {}).get("jd_task") != 9
            or project_payload.get("source_coverage", {}).get("jd_task_report") != 1
        ):
            raise SmokeError(f"project read failed: {status} {project_payload}")
        status, project_detail = request(args.port, "/api/company/projects/proj-0001", token=token)
        if (
            status != 200
            or project_detail is None
            or project_detail.get("project_id") != "proj-0001"
            or len(project_detail.get("lifecycle", [])) != 7
            or len(project_detail.get("tasks", [])) != 7
            or len(project_detail.get("reports", [])) != 1
        ):
            raise SmokeError(f"project detail read failed: {status} {project_detail}")
        status, lifecycle_payload = request(
            args.port,
            "/api/company/projects/proj-0001/lifecycle",
            token=token,
        )
        if (
            status != 200
            or lifecycle_payload is None
            or lifecycle_payload.get("data", {}).get("project", {}).get("projGuid") != "proj-0001"
            or len(lifecycle_payload.get("data", {}).get("stages", [])) != 7
            or lifecycle_payload.get("data", {}).get("stages", [])[0].get("stageCode") != "initiation"
        ):
            raise SmokeError(f"project lifecycle read failed: {status} {lifecycle_payload}")
        status, plan_tasks_payload = request(
            args.port,
            "/api/company/projects/proj-0001/tasks",
            token=token,
        )
        if (
            status != 200
            or plan_tasks_payload is None
            or not isinstance(plan_tasks_payload.get("data"), list)
            or len(plan_tasks_payload["data"]) != 7
            or plan_tasks_payload.get("source_coverage", {}).get("jd_task") != 7
            or plan_tasks_payload["data"][0].get("taskGuid") != "task-001"
        ):
            raise SmokeError(f"project plan task list read failed: {status} {plan_tasks_payload}")
        status, plan_task_detail_payload = request(
            args.port,
            "/api/company/tasks/task-003",
            token=token,
        )
        if (
            status != 200
            or plan_task_detail_payload is None
            or plan_task_detail_payload.get("data", {}).get("task", {}).get("taskGuid") != "task-003"
            or len(plan_task_detail_payload.get("data", {}).get("reports", [])) != 1
            or plan_task_detail_payload.get("source_coverage", {}).get("jd_task_report") != 1
        ):
            raise SmokeError(f"project plan task detail read failed: {status} {plan_task_detail_payload}")
        status, plan_summary_payload = request(
            args.port,
            "/api/company/projects/proj-0001/plan-summary",
            token=token,
        )
        if (
            status != 200
            or plan_summary_payload is None
            or plan_summary_payload.get("data", {}).get("summary", {}).get("total") != 5
            or plan_summary_payload.get("data", {}).get("summary", {}).get("done") != 2
            or len(plan_summary_payload.get("data", {}).get("upcoming", [])) != 3
        ):
            raise SmokeError(f"project plan summary read failed: {status} {plan_summary_payload}")
        status, delay_payload = request(
            args.port,
            "/api/company/tasks/task-003/delay-impact?delayDays=10",
            token=token,
        )
        if (
            status != 200
            or delay_payload is None
            or delay_payload.get("data", {}).get("source", {}).get("delayDays") != 10
            or delay_payload.get("data", {}).get("source", {}).get("newEnd") != "2026-12-25"
            or delay_payload.get("data", {}).get("impactCount") != 2
        ):
            raise SmokeError(f"project task delay-impact read failed: {status} {delay_payload}")
        status, payload = request(args.port, "/api/company/loans", token=token)
        if status != 200 or payload is None or not isinstance(payload.get("items"), list):
            raise SmokeError(f"loan read failed: {status} {payload}")
        loan_rows = len(payload["items"])
        if loan_rows:
            loan_id = payload["items"][0].get("loan_id", "")
            status, detail = request(args.port, f"/api/company/loans/{loan_id}", token=token)
            if status != 200 or detail is None or not isinstance(detail.get("offsets"), list):
                raise SmokeError(f"loan detail failed: {status} {detail}")
        nonce = uuid.uuid4().hex[:10]
        loan_actor = environment.get("MOONPROJ_ACTOR_ID", "service-operator")
        loan_id = "LOAN-SMOKE-" + nonce
        loan_payload = {
            "loan_id": loan_id,
            "loan_code": "JK-SMOKE-" + nonce,
            "subject": "service employee-loan command smoke",
            "employee_id": "employee-smoke",
            "principal_id": "co-smoke",
            "scope": "employee:employee-smoke",
            "currency": "CNY",
            "amount_minor": 800000,
            "apply_dept_guid": "bu-smoke",
            "apply_date": "2026-07-13",
            "pay_unit": "smoke account",
            "proj_guid": "proj-0001",
            "evidence_ids": ["evidence-loan-smoke-" + nonce],
            "authority": {
                "active": True,
                "principal_id": "co-smoke",
                "actor_id": loan_actor,
                "capability": "advance:create",
                "scope": "employee:employee-smoke",
                "max_amount_minor": 800000,
            },
        }
        status, payload = request(
            args.port,
            "/api/company/loans",
            token=token,
            method="POST",
            payload=loan_payload,
            idempotency_key="loan-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("loan", {}).get("state") != "Draft":
            raise SmokeError(f"loan create failed: {status} {payload}")
        status, payload = request(
            args.port,
            "/api/company/loans",
            token=token,
            method="POST",
            payload=loan_payload,
            idempotency_key="loan-create-" + nonce,
        )
        if status != 200 or payload is None or payload.get("idempotent_replay") is not True:
            raise SmokeError(f"loan idempotency failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/loans/{loan_id}/submit-for-approval",
            token=token,
            method="POST",
            payload={},
            idempotency_key="loan-submit-" + nonce,
        )
        if status != 200 or payload is None or payload.get("loan", {}).get("state") != "Approving":
            raise SmokeError(f"loan submit failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/loans/{loan_id}/offset",
            token=token,
            method="POST",
            payload={
                "offset_amount_minor": 100000,
                "offset_date": "2026-07-13",
                "authority": {
                    "active": True,
                    "principal_id": "co-smoke",
                    "actor_id": loan_actor,
                    "capability": "advance:offset",
                    "scope": "employee:employee-smoke",
                    "max_amount_minor": 100000,
                },
            },
            idempotency_key="loan-offset-before-approval-" + nonce,
        )
        if status != 409:
            raise SmokeError(f"loan offset state guard failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/loans/{loan_id}/sync-from-workflow",
            token=token,
            method="POST",
            payload={},
            idempotency_key="loan-sync-" + nonce,
        )
        if status != 409:
            raise SmokeError(f"loan workflow gate failed: {status} {payload}")
        draft_loan_id = "LOAN-SMOKE-DRAFT-" + nonce
        draft_payload = dict(loan_payload)
        draft_payload.update({"loan_id": draft_loan_id, "loan_code": "JK-SMOKE-DRAFT-" + nonce})
        status, payload = request(
            args.port,
            "/api/company/loans",
            token=token,
            method="POST",
            payload=draft_payload,
            idempotency_key="loan-draft-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("loan", {}).get("state") != "Draft":
            raise SmokeError(f"draft loan create failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/loans/{draft_loan_id}",
            token=token,
            method="PUT",
            payload={"subject": "updated employee-loan smoke"},
            idempotency_key="loan-update-" + nonce,
        )
        if status != 200 or payload is None or payload.get("loan", {}).get("state") != "Draft":
            raise SmokeError(f"loan update failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/loans/{draft_loan_id}",
            token=token,
            method="DELETE",
            payload={"reason": "service control smoke void"},
            idempotency_key="loan-void-" + nonce,
        )
        if status != 200 or payload is None or payload.get("loan", {}).get("state") != "Voided":
            raise SmokeError(f"loan void failed: {status} {payload}")
        status, _ = request(args.port, "/api/health", token=None)
        if status != 401:
            raise SmokeError(f"missing bearer token was not rejected: {status}")
        status, _ = request(args.port, "/api/health", token=token, forwarded_tls=False)
        if status != 400:
            raise SmokeError(f"missing forwarded TLS was not rejected: {status}")
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
        supplier_id = "SUP-SMOKE-" + nonce
        supplier_payload = {
            "supplier_id": supplier_id,
            "principal_id": "co-smoke",
            "scope": "project:CD-HJL",
            "supplier_code": "SUP-SMOKE-" + nonce,
            "name": "service command smoke supplier",
            "category_code": "construction",
        }
        status, payload = request(
            args.port,
            "/api/company/suppliers",
            token=token,
            method="POST",
            payload=supplier_payload,
            idempotency_key="supplier-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("supplier", {}).get("state") != "draft":
            raise SmokeError(f"supplier create failed: {status} {payload}")
        status, payload = request(
            args.port,
            "/api/company/suppliers",
            token=token,
            method="POST",
            payload=supplier_payload,
            idempotency_key="supplier-create-" + nonce,
        )
        if status != 200 or payload is None or payload.get("idempotent_replay") is not True:
            raise SmokeError(f"supplier idempotency failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/suppliers/{supplier_id}/update",
            token=token,
            method="POST",
            payload={"name": "service command smoke supplier updated"},
            idempotency_key="supplier-update-" + nonce,
        )
        if status != 200 or payload is None or payload.get("supplier", {}).get("state") != "draft":
            raise SmokeError(f"supplier update failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/suppliers/{supplier_id}/submit_review",
            token=token,
            method="POST",
            payload={},
            idempotency_key="supplier-submit-" + nonce,
        )
        if status != 200 or payload is None or payload.get("supplier", {}).get("state") != "pending_review":
            raise SmokeError(f"supplier submit review failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/suppliers/{supplier_id}/review",
            token=token,
            method="POST",
            payload={"evaluation": "qualified"},
            idempotency_key="supplier-review-" + nonce,
        )
        if (
            status != 200
            or payload is None
            or payload.get("supplier", {}).get("state") != "active"
            or payload.get("supplier", {}).get("evaluation") != "qualified"
        ):
            raise SmokeError(f"supplier review failed: {status} {payload}")
        status, payload = request(args.port, f"/api/company/suppliers/{supplier_id}", token=token)
        if status != 200 or payload is None or payload.get("state") != "active":
            raise SmokeError(f"supplier detail failed: {status} {payload}")
        status, payload = request(args.port, f"/api/company/suppliers/{supplier_id}/risk", token=token)
        if status != 200 or payload is None or payload.get("rating") != "B":
            raise SmokeError(f"supplier risk failed: {status} {payload}")
        blocked_supplier_id = "SUP-SMOKE-BLOCKED-" + nonce
        blocked_payload = {
            "supplier_id": blocked_supplier_id,
            "principal_id": "co-smoke",
            "scope": "project:CD-HJL",
            "supplier_code": "SUP-BLOCKED-" + nonce,
            "name": "service command smoke blocked supplier",
            "category_code": "construction",
        }
        status, payload = request(
            args.port,
            "/api/company/suppliers",
            token=token,
            method="POST",
            payload=blocked_payload,
            idempotency_key="supplier-blocked-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("supplier", {}).get("state") != "draft":
            raise SmokeError(f"blocked supplier create failed: {status} {payload}")
        for command, expected_state, body in (
            ("submit_review", "pending_review", {}),
            ("review", "suspended", {"evaluation": "unqualified"}),
            ("blacklist", "blacklisted", {}),
            ("void", "voided", {}),
        ):
            status, payload = request(
                args.port,
                f"/api/company/suppliers/{blocked_supplier_id}/{command}",
                token=token,
                method="POST",
                payload=body,
                idempotency_key=f"supplier-blocked-{command}-" + nonce,
            )
            if status != 200 or payload is None or payload.get("supplier", {}).get("state") != expected_state:
                raise SmokeError(f"blocked supplier {command} failed: {status} {payload}")
        status, payload = request(args.port, f"/api/company/suppliers/{blocked_supplier_id}/risk", token=token)
        if status != 200 or payload is None or payload.get("rating") != "E":
            raise SmokeError(f"blocked supplier risk failed: {status} {payload}")
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
            "bids": [{"supplier_id": supplier_id, "amount_minor": 1050000}],
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
        for command, expected_state in (("publish", "publishing"), ("open_bidding", "bidding")):
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
        status, payload = request(
            args.port,
            f"/api/company/tenders/{tender_id}/award",
            token=token,
            method="POST",
            payload={"awarded_supplier_id": supplier_id, "awarded_amount_minor": 1050000},
            idempotency_key="tender-award-" + nonce,
        )
        if status != 200 or payload is None or payload.get("tender", {}).get("state") != "awarded":
            raise SmokeError(f"tender award failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/tenders/{tender_id}/award",
            token=token,
            method="POST",
            payload={"awarded_supplier_id": supplier_id, "awarded_amount_minor": 1050000},
            idempotency_key="tender-award-" + nonce,
        )
        if status != 200 or payload is None or payload.get("idempotent_replay") is not True:
            raise SmokeError(f"tender award idempotency failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/tenders/{tender_id}/complete",
            token=token,
            method="POST",
            payload={},
            idempotency_key="tender-complete-" + nonce,
        )
        if status != 200 or payload is None or payload.get("tender", {}).get("state") != "completed":
            raise SmokeError(f"tender complete failed: {status} {payload}")
        status, payload = request(args.port, f"/api/company/tenders/{tender_id}", token=token)
        if status != 200 or payload is None or payload.get("state") != "completed":
            raise SmokeError(f"tender completed detail failed: {status} {payload}")
        split_id = "SPLIT-SMOKE-" + nonce
        split_payload = {
            "split_id": split_id,
            "parent_contract_id": contract_id,
            "split_name": "service command smoke split",
            "split_amount_minor": 123450,
            "split_pct_bps": 1000,
            "scope": "project:CD-HJL",
        }
        status, payload = request(
            args.port,
            "/api/company/tender-splits",
            token=token,
            method="POST",
            payload=split_payload,
            idempotency_key="split-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("split", {}).get("state") != "planned":
            raise SmokeError(f"contract split create failed: {status} {payload}")
        status, payload = request(
            args.port,
            "/api/company/tender-splits",
            token=token,
            method="POST",
            payload=split_payload,
            idempotency_key="split-create-" + nonce,
        )
        if status != 200 or payload is None or payload.get("idempotent_replay") is not True:
            raise SmokeError(f"contract split idempotency failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/tender-splits/{split_id}",
            token=token,
        )
        if status != 200 or payload is None or payload.get("state") != "planned":
            raise SmokeError(f"contract split detail failed: {status} {payload}")
        sales_customer_id = "CUS-SMOKE-" + nonce
        sales_customer_payload = {
            "customer_id": sales_customer_id,
            "principal_id": "co-smoke",
            "scope": "project:CD-HJL",
            "customer_code": sales_customer_id,
            "name": "service sales smoke customer",
            "contact_reference": "contact:smoke",
        }
        status, payload = request(
            args.port,
            "/api/company/sales/customers",
            token=token,
            method="POST",
            payload=sales_customer_payload,
            idempotency_key="sales-customer-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("customer", {}).get("state") != "active":
            raise SmokeError(f"sales customer create failed: {status} {payload}")
        status, payload = request(
            args.port,
            "/api/company/sales/customers",
            token=token,
            method="POST",
            payload=sales_customer_payload,
            idempotency_key="sales-customer-create-" + nonce,
        )
        if status != 200 or payload is None or payload.get("idempotent_replay") is not True:
            raise SmokeError(f"sales customer idempotency failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/sales/customers/{sales_customer_id}/update",
            token=token,
            method="POST",
            payload={"name": "service sales smoke customer updated"},
            idempotency_key="sales-customer-update-" + nonce,
        )
        if status != 200 or payload is None or payload.get("customer", {}).get("state") != "active":
            raise SmokeError(f"sales customer update failed: {status} {payload}")
        subscription_id = "SUB-SMOKE-" + nonce
        subscription_payload = {
            "subscription_id": subscription_id,
            "customer_id": sales_customer_id,
            "principal_id": "co-smoke",
            "scope": "project:CD-HJL",
            "unit_reference": "building-1/unit-1",
            "amount_minor": 1000000,
            "currency": "CNY",
        }
        status, payload = request(
            args.port,
            "/api/company/sales/subscriptions",
            token=token,
            method="POST",
            payload=subscription_payload,
            idempotency_key="sales-subscription-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("subscription", {}).get("state") != "reserved":
            raise SmokeError(f"sales subscription create failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/sales/subscriptions/{subscription_id}/convert",
            token=token,
            method="POST",
            payload={},
            idempotency_key="sales-subscription-convert-" + nonce,
        )
        if status != 200 or payload is None or payload.get("subscription", {}).get("state") != "converted":
            raise SmokeError(f"sales subscription convert failed: {status} {payload}")
        agreement_id = "AGR-SMOKE-" + nonce
        agreement_payload = {
            "agreement_id": agreement_id,
            "subscription_id": subscription_id,
            "customer_id": sales_customer_id,
            "principal_id": "co-smoke",
            "scope": "project:CD-HJL",
            "amount_minor": 1000000,
            "currency": "CNY",
        }
        status, payload = request(
            args.port,
            "/api/company/sales/contracts",
            token=token,
            method="POST",
            payload=agreement_payload,
            idempotency_key="sales-agreement-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("contract", {}).get("state") != "signed":
            raise SmokeError(f"sales agreement create failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/sales/contracts/{agreement_id}/fulfill",
            token=token,
            method="POST",
            payload={},
            idempotency_key="sales-agreement-fulfill-" + nonce,
        )
        if status != 200 or payload is None or payload.get("contract", {}).get("state") != "fulfilled":
            raise SmokeError(f"sales agreement fulfill failed: {status} {payload}")
        receivable_id = "REC-SMOKE-" + nonce
        status, payload = request(
            args.port,
            f"/api/company/sales/contracts/{agreement_id}/open_receivable",
            token=token,
            method="POST",
            payload={
                "receivable_id": receivable_id,
                "customer_id": sales_customer_id,
                "principal_id": "co-smoke",
                "scope": "project:CD-HJL",
                "amount_minor": 1000000,
                "currency": "CNY",
            },
            idempotency_key="sales-receivable-open-" + nonce,
        )
        if status != 201 or payload is None or payload.get("receivable", {}).get("state") != "open":
            raise SmokeError(f"sales receivable open failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/sales/contracts/{agreement_id}/open_receivable",
            token=token,
            method="POST",
            payload={
                "receivable_id": receivable_id,
                "customer_id": sales_customer_id,
                "principal_id": "co-smoke",
                "scope": "project:CD-HJL",
                "amount_minor": 1000000,
                "currency": "CNY",
            },
            idempotency_key="sales-receivable-open-" + nonce,
        )
        if status != 200 or payload is None or payload.get("idempotent_replay") is not True:
            raise SmokeError(f"sales receivable idempotency failed: {status} {payload}")
        mortgage_id = "MTG-SMOKE-" + nonce
        mortgage_payload = {
            "mortgage_id": mortgage_id,
            "contract_id": agreement_id,
            "customer_id": sales_customer_id,
            "principal_id": "co-smoke",
            "scope": "project:CD-HJL",
            "bank_reference": "bank:smoke",
            "loan_amount_minor": 800000,
            "annual_rate_bps": 485,
        }
        status, payload = request(
            args.port,
            "/api/company/sales/mortgages",
            token=token,
            method="POST",
            payload=mortgage_payload,
            idempotency_key="sales-mortgage-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("mortgage", {}).get("state") != "applying":
            raise SmokeError(f"sales mortgage create failed: {status} {payload}")
        for command, expected_state in (("approve", "approved"), ("release", "released")):
            status, payload = request(
                args.port,
                f"/api/company/sales/mortgages/{mortgage_id}/{command}",
                token=token,
                method="POST",
                payload={},
                idempotency_key=f"sales-mortgage-{command}-" + nonce,
            )
            if status != 200 or payload is None or payload.get("mortgage", {}).get("state") != expected_state:
                raise SmokeError(f"sales mortgage {command} failed: {status} {payload}")
        refund_id = "RF-SMOKE-" + nonce
        status, payload = request(
            args.port,
            "/api/company/sales/refunds",
            token=token,
            method="POST",
            payload={
                "refund_id": refund_id,
                "contract_id": agreement_id,
                "customer_id": sales_customer_id,
                "principal_id": "co-smoke",
                "scope": "project:CD-HJL",
                "reason": "service sales smoke adjustment",
                "amount_minor": 50000,
                "currency": "CNY",
            },
            idempotency_key="sales-refund-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("refund", {}).get("state") != "requested":
            raise SmokeError(f"sales refund create failed: {status} {payload}")
        for command, expected_state in (("approve", "approved"), ("pay", "paid")):
            status, payload = request(
                args.port,
                f"/api/company/sales/refunds/{refund_id}/{command}",
                token=token,
                method="POST",
                payload={},
                idempotency_key=f"sales-refund-{command}-" + nonce,
            )
            if status != 200 or payload is None or payload.get("refund", {}).get("state") != expected_state:
                raise SmokeError(f"sales refund {command} failed: {status} {payload}")
        status, payload = request(args.port, f"/api/company/receivables/{receivable_id}", token=token)
        if status != 200 or payload is None or payload.get("state") != "open":
            raise SmokeError(f"sales receivable detail failed: {status} {payload}")
        status, payload = request(
            args.port,
            "/api/company/delivery/overview?project_id=proj-0001",
            token=token,
        )
        if (
            status != 200
            or payload is None
            or not isinstance(payload.get("tasks"), list)
            or not isinstance(payload.get("reports"), list)
            or not payload.get("tasks")
        ):
            raise SmokeError(f"delivery overview read failed: {status} {payload}")
        delivery_progress_id = "PROG-SMOKE-" + nonce
        delivery_progress_payload = {
            "progress_id": delivery_progress_id,
            "project_id": "proj-0001",
            "principal_id": "co-smoke",
            "project_scope": "project:proj-0001",
            "stage": "主体结构",
            "plan_pct": 70,
            "completed_value_minor": 125000,
            "currency": "CNY",
            "evidence_ids": ["evidence:delivery-progress:" + nonce],
            "remark": "service delivery progress smoke",
        }
        status, payload = request(
            args.port,
            "/api/company/delivery/progress",
            token=token,
            method="POST",
            payload=delivery_progress_payload,
            idempotency_key="delivery-progress-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("progress", {}).get("state") != "draft":
            raise SmokeError(f"delivery progress create failed: {status} {payload}")
        status, payload = request(
            args.port,
            "/api/company/delivery/progress",
            token=token,
            method="POST",
            payload=delivery_progress_payload,
            idempotency_key="delivery-progress-create-" + nonce,
        )
        if status != 200 or payload is None or payload.get("idempotent_replay") is not True:
            raise SmokeError(f"delivery progress idempotency failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/delivery/progress/{delivery_progress_id}/report",
            token=token,
            method="POST",
            payload={
                "progress_pct": 55,
                "actual_date": "2026-07-13",
                "evidence_ids": ["evidence:delivery-report:" + nonce],
                "remark": "service delivery report smoke",
            },
            idempotency_key="delivery-progress-report-" + nonce,
        )
        if status != 200 or payload is None or payload.get("progress", {}).get("state") != "submitted":
            raise SmokeError(f"delivery progress report failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/delivery/progress/{delivery_progress_id}/accept",
            token=token,
            method="POST",
            payload={
                "acceptance_id": "accept-delivery-" + nonce,
                "acceptance_evidence_ids": ["evidence:delivery-accept:" + nonce],
            },
            idempotency_key="delivery-progress-accept-" + nonce,
        )
        if status != 200 or payload is None or payload.get("progress", {}).get("state") != "accepted":
            raise SmokeError(f"delivery progress accept failed: {status} {payload}")
        delivery_output_id = "OUT-SMOKE-" + nonce
        output_payload = {
            "output_id": delivery_output_id,
            "project_id": "proj-0001",
            "contract_id": "ht-tj-001",
            "period": "2026-07",
            "output_amount": "125000",
            "evidence_ids": ["evidence:delivery-output:" + nonce],
            "remark": "service output smoke",
        }
        status, payload = request(
            args.port,
            "/api/company/delivery/outputs",
            token=token,
            method="POST",
            payload=output_payload,
            idempotency_key="delivery-output-create-" + nonce,
        )
        if status != 201 or payload is None or payload.get("output", {}).get("state") != "reported":
            raise SmokeError(f"delivery output create failed: {status} {payload}")
        status, payload = request(
            args.port,
            f"/api/company/delivery/outputs/{delivery_output_id}/confirm",
            token=token,
            method="POST",
            payload={
                "confirm_amount": "125000",
                "confirmed_at": "2026-07-13",
                "evidence_ids": ["evidence:delivery-output-confirm:" + nonce],
            },
            idempotency_key="delivery-output-confirm-" + nonce,
        )
        if status != 200 or payload is None or payload.get("output", {}).get("state") != "confirmed":
            raise SmokeError(f"delivery output confirm failed: {status} {payload}")
        task_report_id = "TASK-REPORT-SMOKE-" + nonce
        status, payload = request(
            args.port,
            "/api/company/delivery/tasks/task-003/report",
            token=token,
            method="POST",
            payload={
                "report_id": task_report_id,
                "task_id": "task-003",
                "project_id": "proj-0001",
                "progress_pct": 70,
                "report_date": "2026-07-13",
                "summary": "service task report smoke",
                "evidence_ids": ["evidence:task-report:" + nonce],
            },
            idempotency_key="delivery-task-report-" + nonce,
        )
        if status != 201 or payload is None or payload.get("task_report", {}).get("state") != "observed":
            raise SmokeError(f"delivery task report failed: {status} {payload}")
        print(
            json.dumps(
                {
                    "state": "service_verified",
                    "expense_state": "approved",
                    "contract_state": "approved",
                    "payment_application_approval_state": "approved",
                    "payment_application_state": "voided",
                    "payment_eligibility": "early_payment_flagged",
                    "tender_state": "completed",
                    "supplier_state": "active",
                    "supplier_risk": "B",
                    "split_state": "planned",
                    "sales_customer_state": "active",
                    "sales_subscription_state": "converted",
                    "sales_contract_state": "fulfilled",
                    "receivable_state": "open",
                    "mortgage_state": "released",
                    "refund_state": "paid",
                    "delivery_progress_state": "accepted",
                    "delivery_output_state": "confirmed",
                    "delivery_task_report_state": "observed",
                    "report_cost_rows": report_cost_rows,
                    "report_contract_rows": report_contract_rows,
                    "report_template_meta_tables": len(report_meta_data.get("tables", [])),
                    "report_template_rows": report_template_rows,
                    "report_missing_source_tables": report_missing_tables,
                    "dashboard_project_count": dashboard_overview_rows.get("projectCount"),
                    "dashboard_v2_project_count": dashboard_v2_rows.get("kpi", {}).get("projectCount"),
                    "dashboard_v2_contract_in_progress": dashboard_v2_rows.get("kpi", {}).get("contractInProgressAmount"),
                    "dashboard_v3_customer_count": dashboard_v3_rows.get("kpi", {}).get("customerCount"),
                    "dashboard_v3_total_expense": dashboard_v3_rows.get("kpi", {}).get("totalExpense"),
                    "dashboard_v3_missing_source_tables": len(
                        dashboard_v3_payload.get("missing_or_empty_source_tables", [])
                    ),
                    "dashboard_funnel_rows": len(dashboard_funnel_rows),
                    "dashboard_anomaly_rows": len(dashboard_anomaly_rows),
                    "dashboard_missing_source_tables": dashboard_overview.get("missing_source_tables", []),
                    "workflow_definition_count": 2,
                    "workflow_step_count": 12,
                    "workflow_assignee_rows": len(workflow_assignees),
                    "business_unit_root_count": 1,
                    "business_unit_rows": 7,
                    "cost_subject_rows": 5,
                    "proceeding_rows": 3,
                    "investment_version_rows": 1,
                    "investment_import_rows": len(investment_imports_payload.get("data", [])),
                    "investment_import_detail_boundary_rows": len(investment_import_detail_statuses),
                    "investment_plan_line_rows": len(investment_plan_lines_payload.get("data", {}).get("lines", [])),
                    "investment_subject_mapping_groups": len(investment_mappings_payload.get("data", {}).get("groups", {})),
                    "investment_index_rows": 26,
                    "investment_dimension_rows": 5,
                    "investment_profit_revenue": 18500.0,
                    "dynamic_cost_rows": len(dynamic_cost_data.get("items", [])),
                    "dynamic_cost_end_rows": dynamic_cost_summary.get("endCount"),
                    "dynamic_cost_target": dynamic_cost_summary.get("A_targetCost"),
                    "dynamic_cost_total": dynamic_cost_summary.get("B_dtCost"),
                    "dynamic_cost_deviation": dynamic_cost_summary.get("C_deviationPct"),
                    "cost_dashboard_rows": len(cost_dashboard_data.get("rows", [])),
                    "cost_dashboard_source_cb_subject_dict_rows": cost_dashboard_payload.get("source_coverage", {}).get("cb_subject_dict"),
                    "cost_dashboard_source_cb_plan_version_rows": cost_dashboard_payload.get("source_coverage", {}).get("cb_plan_version"),
                    "admin_dictionary_group_rows": 1,
                    "admin_dictionary_option_rows": 5,
                    "admin_quality_rule_rows": len(quality_rules),
                    "admin_quality_unavailable_rules": quality_summary.get("unavailableRules"),
                    "rbac_user_rows": len(user_rows),
                    "rbac_role_source_status": user_rows[0].get("rolesSourceStatus"),
                    "profile_user_code": profile_data.get("userCode"),
                    "profile_source_kind": profile_data.get("sourceKind"),
                    "profile_preference_rows": len((prefs_payload or {}).get("data", {})),
                    "rbac_me_roles": len(rbac_me_data.get("roles", [])),
                    "rbac_me_role_source_status": rbac_me_data.get("rolesSourceStatus"),
                    "rbac_role_rows": len((rbac_roles_payload or {}).get("data", [])),
                    "rbac_permission_module_rows": len(permission_catalog),
                    "profile_initiated_expenses": len(initiated_data.get("expenses", [])),
                    "profile_initiated_loans": len(initiated_data.get("loans", [])),
                    "profile_initiated_applies": len(initiated_data.get("applies", [])),
                    "expense_source_rows": len(expense_source_data),
                    "expense_source_vcb_expense_rows": expense_source_payload.get("source_coverage", {}).get("vcb_expense"),
                    "expense_detail_source_expense": expense_detail_data.get("expense"),
                    "expense_detail_rows": len(expense_detail_data.get("details", [])),
                    "expense_split_rows": len(expense_detail_data.get("splits", [])),
                    "expense_detail_source_vcb_expense_rows": expense_detail_payload.get("source_coverage", {}).get("vcb_expense"),
                    "supplier_source_rows": len(supplier_source_data or []),
                    "supplier_source_provider_rows": supplier_source_payload.get("source_coverage", {}).get("srm_provider"),
                    "supplier_detail_source_status": supplier_detail_status,
                    "supplier_detail_risk_source_status": supplier_detail_risk_status,
                    "supplier_stats_total": supplier_stats_data.get("total"),
                    "supplier_stats_contract_rows": supplier_stats_payload.get("source_coverage", {}).get("cb_contract"),
                    "attachment_rows": attachment_all_data.get("total"),
                    "attachment_source_rows": attachment_all_payload.get("source_coverage", {}).get("attachment"),
                    "attachment_total_bytes": attachment_stats_data.get("total", {}).get("bytes"),
                    "attachment_binary_storage": attachment_all_payload.get("binary_storage"),
                    "attachment_download_status": attachment_download_payload.get("code"),
                    "marketing_campaign_rows": len(marketing_payloads["/api/company/marketing/campaigns?projGuid=proj-0001"].get("data", [])),
                    "marketing_placement_rows": len(marketing_payloads["/api/company/marketing/placements"].get("data", [])),
                    "marketing_channel_rows": len(marketing_payloads["/api/company/marketing/channels"].get("data", [])),
                    "marketing_material_rows": len(marketing_payloads["/api/company/marketing/materials?projGuid=proj-0001"].get("data", [])),
                    "ai_intake_rows": ai_kpi.get("intakeTotal"),
                    "ai_query_rows": ai_kpi.get("queryTotal"),
                    "ai_skip_rows": ai_kpi.get("skipTotal"),
                    "ai_activity_rows": len(ai_activity_payload.get("data", [])),
                    "ai_badge_by_ai": ai_badge_payload.get("data", {}).get("byAi"),
                    "ai_hub_monthly_calls": ai_hub_usage_data.get("monthlyTotalCalls"),
                    "ai_hub_minutes_saved": ai_hub_usage_data.get("minutesSaved"),
                    "ai_hub_intake_total": ai_hub_usage_data.get("intakeTotal"),
                    "ai_hub_draft_rows": len(ai_hub_drafts_payload.get("data", [])),
                    "ai_hub_draft_detail_status": ai_hub_draft_detail_status,
                    "ai_hub_query_rows": len(ai_hub_query_payload.get("data", [])),
                    "ai_hub_correction_rows": len(ai_hub_correction_rows_payload.get("data", [])),
                    "webhook_platform_rows": len(webhook_data),
                    "webhook_configured_platforms": sum(
                        1 for platform in webhook_data.values() if platform.get("urlConfigured")
                    ),
                    "notification_message_rows": notification_messages_data.get("total"),
                    "notification_unread_count": notification_unread_payload.get("data", {}).get("count"),
                    "notification_subscription_rows": len(notification_subscriptions_payload.get("data", [])),
                    "notification_configured_keys": len(notification_config_data.get("configured", [])),
                    "notification_outbox_rows": len(notification_read_payloads["/api/company/notify/email-outbox"].get("data", [])),
                    "notification_digest_rows": len(notification_read_payloads["/api/company/notify/digest/log"].get("data", [])),
                    "ocr_provider": ocr_data.get("provider"),
                    "ocr_provider_rows": len(ocr_data.get("providers", [])),
                    "ocr_configured_keys": ocr_data.get("configuredKeyCount"),
                    "error_log_rows": error_log_data.get("total"),
                    "error_log_today_rows": error_log_data.get("todayCount"),
                    "error_log_5xx_rows": error_log_data.get("fiveXxCount"),
                    "cashflow_series_rows": len(cashflow_data.get("series", [])),
                    "cashflow_planned_total": cashflow_data.get("totals", {}).get("plannedTotal"),
                    "cashflow_missing_source_tables": len(cashflow_payload.get("missing_or_empty_source_tables", [])),
                    "cashflow_detail_plan_rows": len(cashflow_detail_data.get("plans", [])),
                    "cashflow_inflow_series_rows": len(cashflow_inflow_data.get("series", [])),
                    "cashflow_net_series_rows": len(cashflow_net_data.get("series", [])),
                    "cashflow_gap_week_rows": len(cashflow_gap_data.get("gapWeeks", [])),
                    "cashflow_v3_series_rows": len(cashflow_v3_data.get("series", [])),
                    "cbs_r0_queue_rows": len(cbs_r0_payload.get("data", {}).get("items", [])),
                    "cbs_contract_rows": len(cbs_demo_contracts_payload.get("data", [])),
                    "cbs_dict_rows": len(cbs_dict_data.get("items", [])),
                    "fund_plan_rows": len(fund_plans_payload.get("data", [])),
                    "fund_gap_series_rows": len(fund_gap_payload.get("data", {}).get("series", [])),
                    "fund_dispatch_rows": len(fund_dispatch_payload.get("data", [])),
                    "warning_open_rows": warning_badge_data.get("openTotal"),
                    "warning_rule_rows": len(warning_rules_data.get("data", [])),
                    "supplier_risk_source_high_rows": len(supplier_risk_data.get("highRisk", [])),
                    "supplier_risk_source_provider_rows": supplier_risk_payload.get("source_coverage", {}).get("srm_provider"),
                    "admin_audit_rows": 2,
                    "admin_audit_action_rows": 1,
                    "admin_health_table_rows": 29,
                    "admin_bpm_instance_rows": 0,
                    "admin_full_health_tables": len(admin_health_full_data.get("tables", [])),
                    "admin_llm_provider": admin_llm_payload.get("data", {}).get("provider"),
                    "admin_ai_diag_provider": admin_ai_diag_payload.get("data", {}).get("provider"),
                    "workflow_instance_rows": 0,
                    "workflow_action_rows": 0,
                    "project_count": 2,
                    "project_lifecycle_rows": 14,
                    "project_task_rows": 9,
                    "project_task_report_rows": 1,
                    "plan_task_rows": 7,
                    "plan_task_report_rows": 1,
                    "plan_key_node_total": 5,
                    "project_lifecycle_stage_rows": 7,
                    "project_delay_impact_rows": 2,
                    "loan_rows": loan_rows,
                    "loan_command_state": "Voided",
                    "loan_workflow_gate": "rejected_until_source_rows",
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
