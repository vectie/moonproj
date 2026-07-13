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
        dashboard_overview_rows = dashboard_overview.get("data", {})
        dashboard_funnel_rows = dashboard_funnel.get("data", [])
        dashboard_anomaly_rows = dashboard_anomalies.get("data", [])
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
                    "report_missing_source_tables": report_missing_tables,
                    "dashboard_project_count": dashboard_overview_rows.get("projectCount"),
                    "dashboard_funnel_rows": len(dashboard_funnel_rows),
                    "dashboard_anomaly_rows": len(dashboard_anomaly_rows),
                    "dashboard_missing_source_tables": dashboard_overview.get("missing_source_tables", []),
                    "workflow_definition_count": 2,
                    "workflow_step_count": 12,
                    "business_unit_root_count": 1,
                    "business_unit_rows": 7,
                    "cost_subject_rows": 5,
                    "proceeding_rows": 3,
                    "investment_version_rows": 1,
                    "investment_index_rows": 26,
                    "investment_dimension_rows": 5,
                    "investment_profit_revenue": 18500.0,
                    "admin_dictionary_group_rows": 1,
                    "admin_dictionary_option_rows": 5,
                    "admin_quality_rule_rows": len(quality_rules),
                    "admin_quality_unavailable_rules": quality_summary.get("unavailableRules"),
                    "admin_audit_rows": 2,
                    "admin_audit_action_rows": 1,
                    "admin_health_table_rows": 29,
                    "admin_bpm_instance_rows": 0,
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
