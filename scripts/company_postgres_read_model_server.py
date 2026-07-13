#!/usr/bin/env python3
"""Serve a read-only PostgreSQL company projection API for local development.

This is a deliberately small adapter for the Rabbita browser surface.  It
exposes only fixed read-model queries; it never accepts arbitrary SQL and has
no mutation endpoints.  It covers company, procurement/supplier-risk, sales/receivables,
source sales/receivables,
reviewed invoice, delivery/project-progress, dashboard v1, core-report and
report-builder metadata/template,
employee-loan, dynamic-cost, source contract/payment, invoice/tax-ledger,
budget scope/loan balance, workflow instance observation, investment,
admin-quality, attachment metadata,
non-secret profile, AI analytics, AI Hub observation, and webhook configuration
reads.
OCR status and error-log metadata reads redact secrets, IP addresses, and
stacks; they never execute a provider or expose a mutation path.
Production authentication, pooling, TLS,
observability and command APIs remain deployment gates.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from company_postgres_target_apply import PostgresTargetError, run_psql, sql_literal
from company_postgres_service import (
    auth_current_user as service_auth_current_user,
    auth_my_initiated as service_auth_my_initiated,
    budget_expenses as service_budget_expenses,
    budget_expense_detail as service_budget_expense_detail,
    budget_source_users_in_bu as service_budget_source_users_in_bu,
    budget_source_my_loan_balance as service_budget_source_my_loan_balance,
    contracts as service_contracts,
    contract_milestones as service_contract_milestones,
    cost_source_contracts as service_cost_source_contracts,
    cost_source_contract_detail as service_cost_source_contract_detail,
    cost_source_payment_applications as service_cost_source_payment_applications,
    invoice_source_rows as service_invoice_source_rows,
    invoice_source_tax_ledger as service_invoice_source_tax_ledger,
    cashflow_source_forecast as service_cashflow_source_forecast,
    cashflow_source_forecast_v3 as service_cashflow_source_forecast_v3,
    cashflow_source_detail as service_cashflow_source_detail,
    cashflow_source_inflow as service_cashflow_source_inflow,
    cashflow_source_net as service_cashflow_source_net,
    cashflow_source_gap_alert as service_cashflow_source_gap_alert,
    cbs_source_r_master as service_cbs_source_r_master,
    cbs_source_dict as service_cbs_source_dict,
    cbs_source_f_balance as service_cbs_source_f_balance,
    cbs_source_versions as service_cbs_source_versions,
    cbs_source_versions_compare as service_cbs_source_versions_compare,
    cbs_source_r0_queue as service_cbs_source_r0_queue,
    cbs_source_approval_rules as service_cbs_source_approval_rules,
    cbs_source_approval_pick as service_cbs_source_approval_pick,
    cbs_source_changes as service_cbs_source_changes,
    cbs_source_demo_contracts as service_cbs_source_demo_contracts,
    fund_source_plans as service_fund_source_plans,
    fund_source_gap_analysis as service_fund_source_gap_analysis,
    fund_source_dispatches as service_fund_source_dispatches,
    warning_source_badge as service_warning_source_badge,
    warning_source_list as service_warning_source_list,
    warning_source_rules as service_warning_source_rules,
    warning_source_empty_read as service_warning_source_empty_read,
    attachment_source_list as service_attachment_source_list,
    attachment_source_all as service_attachment_source_all,
    attachment_source_stats as service_attachment_source_stats,
    marketing_source_campaigns as service_marketing_source_campaigns,
    marketing_source_placements as service_marketing_source_placements,
    marketing_source_channels as service_marketing_source_channels,
    marketing_source_materials as service_marketing_source_materials,
    notification_source_messages as service_notification_source_messages,
    notification_source_unread_count as service_notification_source_unread_count,
    notification_source_subscriptions as service_notification_source_subscriptions,
    notification_source_config as service_notification_source_config,
    notification_source_email_outbox as service_notification_source_email_outbox,
    notification_source_digest_preview as service_notification_source_digest_preview,
    notification_source_digest_log as service_notification_source_digest_log,
    notification_source_llm_providers as service_notification_source_llm_providers,
    ocr_source_status as service_ocr_source_status,
    error_log_source_rows as service_error_log_source_rows,
    ai_stats_source_overview as service_ai_stats_source_overview,
    ai_stats_source_activity as service_ai_stats_source_activity,
    ai_stats_source_badge as service_ai_stats_source_badge,
    ai_hub_corrections as service_ai_hub_corrections,
    ai_hub_correction_stats as service_ai_hub_correction_stats,
    ai_hub_drafts as service_ai_hub_drafts,
    ai_hub_draft as service_ai_hub_draft,
    ai_hub_query_log as service_ai_hub_query_log,
    ai_hub_usage_stats as service_ai_hub_usage_stats,
    webhook_source_config as service_webhook_source_config,
    payment_applications as service_payment_applications,
    payment_application_eligibility as service_payment_application_eligibility,
    suppliers as service_suppliers,
    supplier_source_list as service_supplier_source_list,
    supplier_source_detail as service_supplier_source_detail,
    supplier_source_stats as service_supplier_source_stats,
    supplier_source_risk as service_supplier_source_risk,
    supplier_risk as service_supplier_risk,
    supplier_risk_board as service_supplier_risk_board,
    supplier_risk_board_source as service_supplier_risk_board_source,
    tenders as service_tenders,
    contract_splits as service_contract_splits,
    sales_rows as service_sales_rows,
    sales_source_rows as service_sales_source_rows,
    delivery_progress as service_delivery_progress,
    delivery_outputs as service_delivery_outputs,
    source_delivery_progress as service_source_delivery_progress,
    source_delivery_outputs as service_source_delivery_outputs,
    delivery_tasks as service_delivery_tasks,
    delivery_task_reports as service_delivery_task_reports,
    delivery_plan_summary as service_delivery_plan_summary,
    delivery_overview as service_delivery_overview,
    report_cost_summary as service_report_cost_summary,
    report_contract_payment_ledger as service_report_contract_payment_ledger,
    report_supplier_analysis as service_report_supplier_analysis,
    report_approval_efficiency as service_report_approval_efficiency,
    report_project_stage_matrix as service_report_project_stage_matrix,
    report_template_metadata as service_report_template_metadata,
    report_template_rows as service_report_template_rows,
    reports_overview as service_reports_overview,
    dashboard_group_overview as service_dashboard_group_overview,
    dashboard_group_funnel as service_dashboard_group_funnel,
    dashboard_group_top_anomalies as service_dashboard_group_top_anomalies,
    dashboard_project_kpi as service_dashboard_project_kpi,
    dashboard_project_anomalies as service_dashboard_project_anomalies,
    dynamic_cost as service_dynamic_cost,
    investment_versions as service_investment_versions,
    investment_indices as service_investment_indices,
    investment_profit_summary as service_investment_profit_summary,
    cost_dashboard_v3 as service_cost_dashboard_v3,
    admin_quality_overview as service_admin_quality_overview,
    admin_rbac_users as service_admin_rbac_users,
    admin_dict_groups as service_admin_dict_groups,
    admin_dict_options as service_admin_dict_options,
    admin_audit_logs as service_admin_audit_logs,
    admin_audit_actions as service_admin_audit_actions,
    admin_health_tables as service_admin_health_tables,
    admin_health_bpm_pool as service_admin_health_bpm_pool,
    workflow_source_tasks_mine as service_workflow_source_tasks_mine,
    workflow_source_tasks_initiated as service_workflow_source_tasks_initiated,
    workflow_source_history as service_workflow_source_history,
    workflow_source_instance_by_biz as service_workflow_source_instance_by_biz,
    workflow_source_instance_detail as service_workflow_source_instance_detail,
    _workflow_resolve_user_id as service_workflow_resolve_user_id,
    loans as service_loans,
)


IDENTIFIER = re.compile(r"^[A-Za-z0-9_.:-]{1,128}$")


def query_lines(args: argparse.Namespace, sql: str) -> list[str]:
    output = run_psql(args, "\n".join(line.strip() for line in sql.splitlines() if line.strip()))
    return [line for line in output.splitlines() if line]


def summary(args: argparse.Namespace) -> dict[str, Any]:
    lines = query_lines(
        args,
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
        raise PostgresTargetError("unexpected company summary shape")
    raw, projections, links, receipts, schema_version = [int(value) for value in lines[0].split("|")]
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


def auth_current_user(args: argparse.Namespace, user_code: str) -> dict[str, Any] | None:
    return service_auth_current_user(_ReadModelPool(args), user_code, 500)


def auth_my_initiated(args: argparse.Namespace, user_code: str) -> dict[str, Any] | None:
    return service_auth_my_initiated(_ReadModelPool(args), user_code, 500)


def budget_expenses(
    args: argparse.Namespace,
    expense_id: str | None,
    user_code: str | None,
    apply_state: str | None,
) -> dict[str, Any] | None:
    return service_budget_expenses(_ReadModelPool(args), expense_id, user_code, apply_state, 500)


def budget_expense_detail(
    args: argparse.Namespace,
    expense_id: str,
    user_code: str | None,
) -> dict[str, Any] | None:
    return service_budget_expense_detail(_ReadModelPool(args), expense_id, user_code, 500)


def budget_source_users_in_bu(args: argparse.Namespace, bu_guid: str | None) -> dict[str, Any]:
    return service_budget_source_users_in_bu(_ReadModelPool(args), bu_guid, 500)


def budget_source_my_loan_balance(
    args: argparse.Namespace,
    user_code: str | None,
    user_id: str | None,
) -> dict[str, Any] | None:
    return service_budget_source_my_loan_balance(_ReadModelPool(args), user_code, user_id, 500)


def receipts(args: argparse.Namespace) -> list[dict[str, Any]]:
    lines = query_lines(
        args,
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
            raise PostgresTargetError("unexpected company receipt shape")
        try:
            decoded = [base64.b16decode(field, casefold=True).decode("utf-8") for field in fields[:2]]
            mapping = base64.b16decode(fields[3], casefold=True).decode("utf-8")
            state = base64.b16decode(fields[4], casefold=True).decode("utf-8")
            applied_hash = base64.b16decode(fields[5], casefold=True).decode("utf-8")
        except (ValueError, UnicodeDecodeError) as error:
            raise PostgresTargetError("invalid company receipt encoding") from error
        result.append(
            {
                "run_id": decoded[0],
                "source_snapshot_id": decoded[1],
                "target_schema_version": int(fields[2]),
                "mapping_version": mapping,
                "state": state,
                "applied_hash": applied_hash,
            }
        )
    return result


def projections(args: argparse.Namespace, aggregate_type: str | None) -> list[dict[str, Any]]:
    clause = ""
    if aggregate_type is not None:
        if not IDENTIFIER.fullmatch(aggregate_type):
            raise ValueError("invalid aggregate_type")
        clause = f"WHERE aggregate_type = {sql_literal(aggregate_type)}"
    lines = query_lines(
        args,
        f"""
        SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'),
               encode(convert_to(aggregate_id, 'UTF8'), 'hex'),
               revision::text,
               encode(convert_to(payload::text, 'UTF8'), 'hex'),
               encode(convert_to(source_event_id, 'UTF8'), 'hex')
        FROM company_aggregate_projection
        {clause}
        ORDER BY aggregate_type, aggregate_id, revision
        LIMIT 500
        """,
    )
    result: list[dict[str, Any]] = []
    for line in lines:
        fields = line.split("|")
        if len(fields) != 5:
            raise PostgresTargetError("unexpected company projection shape")
        try:
            aggregate = base64.b16decode(fields[0], casefold=True).decode("utf-8")
            aggregate_id = base64.b16decode(fields[1], casefold=True).decode("utf-8")
            payload = json.loads(base64.b16decode(fields[3], casefold=True).decode("utf-8"))
            source_event = base64.b16decode(fields[4], casefold=True).decode("utf-8")
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise PostgresTargetError("invalid company projection encoding") from error
        result.append(
            {
                "aggregate_type": aggregate,
                "aggregate_id": aggregate_id,
                "revision": int(fields[2]),
                "payload": payload,
                "source_event_id": source_event,
            }
        )
    return result


class _ReadModelPool:
    """Adapt the fixed psql query runner to the bounded service read helpers."""

    def __init__(self, args: argparse.Namespace):
        self.args = args

    def execute(self, sql: str) -> list[str]:
        output = run_psql(self.args, sql)
        return [line for line in output.splitlines() if line]

    def execute_read(self, sql: str) -> list[str]:
        return self.execute(sql)


def contracts(args: argparse.Namespace, contract_id: str | None) -> list[dict[str, Any]]:
    pool = _ReadModelPool(args)
    return service_contracts(pool, contract_id, 500)


def contract_detail(args: argparse.Namespace, contract_id: str) -> dict[str, Any] | None:
    pool = _ReadModelPool(args)
    items = service_contracts(pool, contract_id, 500)
    if not items:
        return None
    result = dict(items[0])
    result["milestones"] = service_contract_milestones(pool, contract_id, 500)
    return result


def cost_source_contracts(
    args: argparse.Namespace,
    contract_id: str | None,
    bu_guid: str | None,
    proj_guid: str | None,
    keyword: str | None,
) -> dict[str, Any]:
    return service_cost_source_contracts(
        _ReadModelPool(args), contract_id, bu_guid, proj_guid, keyword, 500,
    )


def cost_source_contract_detail(args: argparse.Namespace, contract_id: str) -> dict[str, Any] | None:
    return service_cost_source_contract_detail(_ReadModelPool(args), contract_id, 500)


def cost_source_payment_applications(
    args: argparse.Namespace,
    view: str,
    bu_guid: str | None,
    user_id: str | None,
) -> dict[str, Any]:
    return service_cost_source_payment_applications(_ReadModelPool(args), view, bu_guid, user_id, 500)


def workflow_source_tasks_mine(
    args: argparse.Namespace,
    user_id: str | None,
    user_code: str | None,
) -> dict[str, Any]:
    pool = _ReadModelPool(args)
    return service_workflow_source_tasks_mine(
        pool,
        service_workflow_resolve_user_id(pool, user_id, user_code, 500),
        500,
    )


def workflow_source_tasks_initiated(
    args: argparse.Namespace,
    user_id: str | None,
    user_code: str | None,
) -> dict[str, Any]:
    pool = _ReadModelPool(args)
    return service_workflow_source_tasks_initiated(
        pool,
        service_workflow_resolve_user_id(pool, user_id, user_code, 500),
        500,
    )


def workflow_source_history(
    args: argparse.Namespace,
    user_id: str | None,
    user_code: str | None,
) -> dict[str, Any]:
    pool = _ReadModelPool(args)
    return service_workflow_source_history(
        pool,
        service_workflow_resolve_user_id(pool, user_id, user_code, 500),
        500,
    )


def workflow_source_instance_by_biz(
    args: argparse.Namespace,
    biz_type: str,
    biz_data_guid: str,
) -> dict[str, Any]:
    return service_workflow_source_instance_by_biz(_ReadModelPool(args), biz_type, biz_data_guid, 500)


def workflow_source_instance_detail(args: argparse.Namespace, instance_id: str) -> dict[str, Any] | None:
    return service_workflow_source_instance_detail(_ReadModelPool(args), instance_id, 500)


def payment_applications(
    args: argparse.Namespace,
    apply_id: str | None,
    view: str,
) -> list[dict[str, Any]]:
    pool = _ReadModelPool(args)
    return service_payment_applications(pool, apply_id, view, 500)


def payment_application_eligibility(
    args: argparse.Namespace,
    plan_id: str,
    amount_minor: int,
) -> dict[str, Any] | None:
    pool = _ReadModelPool(args)
    return service_payment_application_eligibility(pool, plan_id, amount_minor)


def tenders(args: argparse.Namespace, tender_id: str | None) -> list[dict[str, Any]]:
    pool = _ReadModelPool(args)
    return service_tenders(pool, tender_id, 500)


def suppliers(args: argparse.Namespace, supplier_id: str | None) -> list[dict[str, Any]]:
    pool = _ReadModelPool(args)
    return service_suppliers(pool, supplier_id, 500)


def cashflow_source_forecast(
    args: argparse.Namespace,
    months: int,
    bu_guid: str | None,
    proj_guid: str | None,
) -> dict[str, Any]:
    return service_cashflow_source_forecast(
        _ReadModelPool(args), months, bu_guid, proj_guid, 500,
    )


def cashflow_source_forecast_v3(args: argparse.Namespace, months: int, proj_guid: str) -> dict[str, Any]:
    return service_cashflow_source_forecast_v3(_ReadModelPool(args), months, proj_guid, 500)


def cashflow_source_detail(
    args: argparse.Namespace, ym: str, bu_guid: str | None, proj_guid: str | None,
) -> dict[str, Any]:
    return service_cashflow_source_detail(_ReadModelPool(args), ym, bu_guid, proj_guid, 500)


def cashflow_source_inflow(
    args: argparse.Namespace, months: int, bu_guid: str | None, proj_guid: str | None,
) -> dict[str, Any]:
    return service_cashflow_source_inflow(_ReadModelPool(args), months, bu_guid, proj_guid, 500)


def cashflow_source_net(args: argparse.Namespace, months: int) -> dict[str, Any]:
    return service_cashflow_source_net(_ReadModelPool(args), months, 500)


def cashflow_source_gap_alert(args: argparse.Namespace, horizon_days: int) -> dict[str, Any]:
    return service_cashflow_source_gap_alert(_ReadModelPool(args), horizon_days, 500)


def cbs_source_r_master(args: argparse.Namespace) -> dict[str, Any]:
    return service_cbs_source_r_master(_ReadModelPool(args), 500)


def cbs_source_dict(
    args: argparse.Namespace, proj_guid: str, plan_version: str | None, r_code: str | None,
) -> dict[str, Any]:
    return service_cbs_source_dict(_ReadModelPool(args), proj_guid, plan_version, r_code, 500)


def cbs_source_f_balance(
    args: argparse.Namespace, proj_guid: str, l3_code: str, plan_version: str | None,
) -> dict[str, Any]:
    return service_cbs_source_f_balance(_ReadModelPool(args), proj_guid, l3_code, plan_version, 500)


def cbs_source_versions(args: argparse.Namespace, proj_guid: str) -> dict[str, Any]:
    return service_cbs_source_versions(_ReadModelPool(args), proj_guid, 500)


def cbs_source_versions_compare(
    args: argparse.Namespace, proj_guid: str, version_a: str, version_b: str, version_c: str | None,
) -> dict[str, Any]:
    return service_cbs_source_versions_compare(
        _ReadModelPool(args), proj_guid, version_a, version_b, version_c, 500,
    )


def cbs_source_r0_queue(args: argparse.Namespace, proj_guid: str | None) -> dict[str, Any]:
    return service_cbs_source_r0_queue(_ReadModelPool(args), proj_guid, 500)


def cbs_source_approval_rules(args: argparse.Namespace, biz_type: str | None) -> dict[str, Any]:
    return service_cbs_source_approval_rules(_ReadModelPool(args), biz_type, 500)


def cbs_source_approval_pick(args: argparse.Namespace, biz_type: str, amount: float) -> dict[str, Any]:
    return service_cbs_source_approval_pick(_ReadModelPool(args), biz_type, amount, 500)


def cbs_source_changes(
    args: argparse.Namespace, proj_guid: str | None, contract_guid: str | None,
) -> dict[str, Any]:
    return service_cbs_source_changes(_ReadModelPool(args), proj_guid, contract_guid, 500)


def cbs_source_demo_contracts(args: argparse.Namespace, proj_guid: str | None) -> dict[str, Any]:
    return service_cbs_source_demo_contracts(_ReadModelPool(args), proj_guid, 500)


def fund_source_plans(
    args: argparse.Namespace,
    proj_guid: str | None,
    period: str | None,
    direction: str | None,
) -> dict[str, Any]:
    return service_fund_source_plans(_ReadModelPool(args), proj_guid, period, direction, 500)


def fund_source_gap_analysis(args: argparse.Namespace, proj_guid: str) -> dict[str, Any]:
    return service_fund_source_gap_analysis(_ReadModelPool(args), proj_guid, 500)


def fund_source_dispatches(args: argparse.Namespace) -> dict[str, Any]:
    return service_fund_source_dispatches(_ReadModelPool(args), 500)


def warning_source_badge(args: argparse.Namespace) -> dict[str, Any]:
    return service_warning_source_badge(_ReadModelPool(args), 500)


def warning_source_list(
    args: argparse.Namespace,
    status: str | None,
    rule_code: str | None,
    severity: str | None,
    biz_type: str | None,
) -> dict[str, Any]:
    return service_warning_source_list(_ReadModelPool(args), status, rule_code, severity, biz_type, 500)


def warning_source_rules(args: argparse.Namespace) -> dict[str, Any]:
    return service_warning_source_rules(_ReadModelPool(args), 500)


def warning_source_empty_read(args: argparse.Namespace, table: str) -> dict[str, Any]:
    return service_warning_source_empty_read(_ReadModelPool(args), table, 500)


def attachment_source_list(
    args: argparse.Namespace,
    biz_type: str | None,
    biz_guid: str | None,
) -> dict[str, Any]:
    return service_attachment_source_list(_ReadModelPool(args), biz_type, biz_guid, 500)


def attachment_source_all(
    args: argparse.Namespace,
    biz_type: str | None,
    uploaded_by: str | None,
    ai_status: str | None,
    keyword: str | None,
) -> dict[str, Any]:
    return service_attachment_source_all(
        _ReadModelPool(args), biz_type, uploaded_by, ai_status, keyword, 500,
    )


def attachment_source_stats(args: argparse.Namespace) -> dict[str, Any]:
    return service_attachment_source_stats(_ReadModelPool(args), 500)


def marketing_source_campaigns(
    args: argparse.Namespace,
    proj_guid: str | None,
    state: str | None,
) -> dict[str, Any]:
    return service_marketing_source_campaigns(_ReadModelPool(args), proj_guid, state, 500)


def marketing_source_placements(
    args: argparse.Namespace,
    campaign_guid: str | None,
) -> dict[str, Any]:
    return service_marketing_source_placements(_ReadModelPool(args), campaign_guid, 500)


def marketing_source_channels(args: argparse.Namespace) -> dict[str, Any]:
    return service_marketing_source_channels(_ReadModelPool(args), 500)


def marketing_source_materials(
    args: argparse.Namespace,
    proj_guid: str | None,
) -> dict[str, Any]:
    return service_marketing_source_materials(_ReadModelPool(args), proj_guid, 500)


def notification_source_messages(
    args: argparse.Namespace,
    user_code: str | None,
    status: str,
    limit: int,
    offset: int,
) -> dict[str, Any]:
    return service_notification_source_messages(
        _ReadModelPool(args), user_code, status, limit, offset, 500,
    )


def notification_source_unread_count(args: argparse.Namespace, user_code: str | None) -> dict[str, Any]:
    return service_notification_source_unread_count(_ReadModelPool(args), user_code, 500)


def notification_source_subscriptions(args: argparse.Namespace, user_code: str | None) -> dict[str, Any]:
    return service_notification_source_subscriptions(_ReadModelPool(args), user_code, 500)


def notification_source_config(args: argparse.Namespace) -> dict[str, Any]:
    return service_notification_source_config(_ReadModelPool(args), 500)


def notification_source_email_outbox(args: argparse.Namespace) -> dict[str, Any]:
    return service_notification_source_email_outbox(_ReadModelPool(args), 500)


def notification_source_digest_preview(args: argparse.Namespace) -> dict[str, Any]:
    return service_notification_source_digest_preview(_ReadModelPool(args), 500)


def notification_source_digest_log(args: argparse.Namespace) -> dict[str, Any]:
    return service_notification_source_digest_log(_ReadModelPool(args), 500)


def notification_source_llm_providers(args: argparse.Namespace) -> dict[str, Any]:
    return service_notification_source_llm_providers(_ReadModelPool(args), 500)


def ocr_source_status(args: argparse.Namespace) -> dict[str, Any]:
    return service_ocr_source_status(_ReadModelPool(args), 500)


def error_log_source_rows(
    args: argparse.Namespace,
    keyword: str | None,
    limit: int,
) -> dict[str, Any]:
    return service_error_log_source_rows(_ReadModelPool(args), keyword, limit, 500)


def ai_stats_source_overview(args: argparse.Namespace, period: str) -> dict[str, Any]:
    return service_ai_stats_source_overview(_ReadModelPool(args), period, 500)


def ai_stats_source_activity(args: argparse.Namespace, limit: int) -> dict[str, Any]:
    return service_ai_stats_source_activity(_ReadModelPool(args), limit, 500)


def ai_stats_source_badge(
    args: argparse.Namespace,
    biz_type: str | None,
    biz_guid: str | None,
) -> dict[str, Any]:
    return service_ai_stats_source_badge(_ReadModelPool(args), biz_type, biz_guid, 500)


def ai_hub_corrections(
    args: argparse.Namespace,
    biz_type: str | None,
    field: str | None,
    user_code: str | None,
    limit: int,
) -> dict[str, Any]:
    return service_ai_hub_corrections(
        _ReadModelPool(args), biz_type, field, user_code, limit, 500,
    )


def ai_hub_correction_stats(args: argparse.Namespace) -> dict[str, Any]:
    return service_ai_hub_correction_stats(_ReadModelPool(args), 500)


def ai_hub_drafts(args: argparse.Namespace, user_code: str | None) -> dict[str, Any]:
    return service_ai_hub_drafts(_ReadModelPool(args), user_code, 500)


def ai_hub_draft(
    args: argparse.Namespace,
    draft_id: str,
    user_code: str | None,
) -> dict[str, Any] | None:
    return service_ai_hub_draft(_ReadModelPool(args), draft_id, user_code, 500)


def ai_hub_query_log(args: argparse.Namespace, user_code: str | None) -> dict[str, Any]:
    return service_ai_hub_query_log(_ReadModelPool(args), user_code, 500)


def ai_hub_usage_stats(args: argparse.Namespace) -> dict[str, Any]:
    return service_ai_hub_usage_stats(_ReadModelPool(args), 500)


def webhook_source_config(args: argparse.Namespace) -> dict[str, Any]:
    return service_webhook_source_config(_ReadModelPool(args), 500)


def supplier_source_list(args: argparse.Namespace) -> dict[str, Any]:
    return service_supplier_source_list(_ReadModelPool(args), 500)


def supplier_source_detail(args: argparse.Namespace, provider_guid: str) -> dict[str, Any]:
    return service_supplier_source_detail(_ReadModelPool(args), provider_guid, 500)


def supplier_source_stats(args: argparse.Namespace) -> dict[str, Any]:
    return service_supplier_source_stats(_ReadModelPool(args), 500)


def supplier_source_risk(args: argparse.Namespace, provider_guid: str) -> dict[str, Any]:
    return service_supplier_source_risk(_ReadModelPool(args), provider_guid, 500)


def supplier_risk(args: argparse.Namespace, supplier_id: str) -> dict[str, Any] | None:
    return service_supplier_risk(_ReadModelPool(args), supplier_id)


def supplier_risk_board(args: argparse.Namespace) -> list[dict[str, Any]]:
    return service_supplier_risk_board(_ReadModelPool(args), 500)


def supplier_risk_board_source(args: argparse.Namespace) -> dict[str, Any]:
    return service_supplier_risk_board_source(_ReadModelPool(args), 500)


def contract_splits(
    args: argparse.Namespace,
    split_id: str | None,
    parent_contract_id: str | None,
) -> list[dict[str, Any]]:
    return service_contract_splits(_ReadModelPool(args), split_id, parent_contract_id, 500)


def sales_rows(args: argparse.Namespace, family: str, aggregate_id: str | None) -> list[dict[str, Any]]:
    return service_sales_rows(_ReadModelPool(args), family, aggregate_id, 500)


def sales_source_rows(
    args: argparse.Namespace,
    family: str,
    proj_guid: str | None,
    state: str | None,
    keyword: str | None,
) -> dict[str, Any]:
    return service_sales_source_rows(
        _ReadModelPool(args), family, proj_guid, state, keyword, 500
    )


def invoice_source_rows(
    args: argparse.Namespace,
    direction: str,
    proj_guid: str | None,
    contract_guid: str | None,
) -> dict[str, Any]:
    return service_invoice_source_rows(
        _ReadModelPool(args), direction, proj_guid, contract_guid, 500
    )


def invoice_source_tax_ledger(
    args: argparse.Namespace,
    proj_guid: str | None,
) -> dict[str, Any]:
    return service_invoice_source_tax_ledger(_ReadModelPool(args), proj_guid, 500)


def delivery_progress(
    args: argparse.Namespace,
    progress_id: str | None,
    project_id: str | None,
) -> list[dict[str, Any]]:
    return service_delivery_progress(_ReadModelPool(args), progress_id, project_id, 500)


def delivery_outputs(
    args: argparse.Namespace,
    output_id: str | None,
    project_id: str | None,
) -> list[dict[str, Any]]:
    return service_delivery_outputs(_ReadModelPool(args), output_id, project_id, 500)


def source_delivery_progress(
    args: argparse.Namespace,
    project_id: str | None,
) -> dict[str, Any]:
    return service_source_delivery_progress(_ReadModelPool(args), project_id, 500)


def source_delivery_outputs(
    args: argparse.Namespace,
    project_id: str | None,
    period: str | None,
    state: str | None,
) -> dict[str, Any]:
    return service_source_delivery_outputs(_ReadModelPool(args), project_id, period, state, 500)


def delivery_tasks(
    args: argparse.Namespace,
    task_id: str | None,
    project_id: str | None,
) -> list[dict[str, Any]]:
    return service_delivery_tasks(_ReadModelPool(args), task_id, project_id, 500)


def delivery_task_reports(
    args: argparse.Namespace,
    report_id: str | None,
    task_id: str | None,
) -> list[dict[str, Any]]:
    return service_delivery_task_reports(_ReadModelPool(args), report_id, task_id, 500)


def delivery_plan_summary(args: argparse.Namespace, project_id: str) -> dict[str, Any]:
    return service_delivery_plan_summary(_ReadModelPool(args), project_id, 500)


def delivery_overview(args: argparse.Namespace, project_id: str) -> dict[str, Any]:
    return service_delivery_overview(_ReadModelPool(args), project_id, 500)


def report_cost_summary(args: argparse.Namespace) -> dict[str, Any]:
    return service_report_cost_summary(_ReadModelPool(args), 500)


def report_contract_payment_ledger(args: argparse.Namespace) -> list[dict[str, Any]]:
    return service_report_contract_payment_ledger(_ReadModelPool(args), 500)


def report_supplier_analysis(args: argparse.Namespace) -> list[dict[str, Any]]:
    return service_report_supplier_analysis(_ReadModelPool(args), 500)


def report_approval_efficiency(args: argparse.Namespace) -> dict[str, Any]:
    return service_report_approval_efficiency(_ReadModelPool(args), 500)


def report_project_stage_matrix(args: argparse.Namespace) -> dict[str, Any]:
    return service_report_project_stage_matrix(_ReadModelPool(args), 500)


def report_template_metadata(args: argparse.Namespace) -> dict[str, Any]:
    return service_report_template_metadata()


def report_template_rows(args: argparse.Namespace) -> dict[str, Any]:
    return service_report_template_rows(_ReadModelPool(args), 500)


def reports_overview(args: argparse.Namespace) -> dict[str, Any]:
    return service_reports_overview(_ReadModelPool(args), 500)


def dashboard_group_overview(args: argparse.Namespace) -> dict[str, Any]:
    return service_dashboard_group_overview(_ReadModelPool(args), 500)


def dashboard_group_funnel(args: argparse.Namespace) -> dict[str, Any]:
    return service_dashboard_group_funnel(_ReadModelPool(args), 500)


def dashboard_group_top_anomalies(args: argparse.Namespace, limit: int) -> dict[str, Any]:
    return service_dashboard_group_top_anomalies(_ReadModelPool(args), limit, 500)


def dashboard_project_kpi(args: argparse.Namespace, project_id: str) -> dict[str, Any] | None:
    return service_dashboard_project_kpi(_ReadModelPool(args), project_id, 500)


def dashboard_project_anomalies(args: argparse.Namespace, project_id: str) -> dict[str, Any]:
    return service_dashboard_project_anomalies(_ReadModelPool(args), project_id, 500)


def dynamic_cost(args: argparse.Namespace, project_id: str) -> dict[str, Any]:
    return service_dynamic_cost(_ReadModelPool(args), project_id, 500)


def cost_dashboard_v3(
    args: argparse.Namespace,
    project_id: str,
    plan_version: str | None,
) -> dict[str, Any] | None:
    return service_cost_dashboard_v3(_ReadModelPool(args), project_id, plan_version, 500)


def investment_versions(args: argparse.Namespace, project_id: str) -> dict[str, Any]:
    return service_investment_versions(_ReadModelPool(args), project_id, 500)


def investment_indices(
    args: argparse.Namespace,
    version_id: str,
    dimension: str | None,
) -> dict[str, Any]:
    return service_investment_indices(_ReadModelPool(args), version_id, dimension, 500)


def investment_profit_summary(args: argparse.Namespace, project_id: str) -> dict[str, Any]:
    return service_investment_profit_summary(_ReadModelPool(args), project_id, 500)


def admin_quality_overview(args: argparse.Namespace) -> dict[str, Any]:
    return service_admin_quality_overview(_ReadModelPool(args), 500)


def admin_rbac_users(
    args: argparse.Namespace,
    keyword: str | None,
    enabled: str | None,
) -> dict[str, Any]:
    return service_admin_rbac_users(_ReadModelPool(args), keyword, enabled, 500)


def admin_dict_groups(args: argparse.Namespace) -> dict[str, Any]:
    return service_admin_dict_groups(_ReadModelPool(args), 500)


def admin_dict_options(args: argparse.Namespace, group_name: str | None) -> dict[str, Any]:
    return service_admin_dict_options(_ReadModelPool(args), group_name, 500)


def admin_audit_logs(
    args: argparse.Namespace,
    action: str | None,
    user_id: str | None,
    target_type: str | None,
    limit: int,
    offset: int,
) -> dict[str, Any]:
    return service_admin_audit_logs(
        _ReadModelPool(args), action, user_id, target_type, limit, offset, 500
    )


def admin_audit_actions(args: argparse.Namespace) -> dict[str, Any]:
    return service_admin_audit_actions(_ReadModelPool(args), 500)


def admin_health_tables(args: argparse.Namespace) -> dict[str, Any]:
    return service_admin_health_tables(_ReadModelPool(args), 500)


def admin_health_bpm_pool(args: argparse.Namespace) -> dict[str, Any]:
    return service_admin_health_bpm_pool(_ReadModelPool(args), 500)


def loans(
    args: argparse.Namespace,
    loan_id: str | None,
    apply_state: str | None,
) -> list[dict[str, Any]]:
    return service_loans(_ReadModelPool(args), loan_id, apply_state, 500)


def response(handler: BaseHTTPRequestHandler, status: int, payload: Any) -> None:
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.end_headers()
    handler.wfile.write(body)


def handler_factory(args: argparse.Namespace, public_dir: Path | None):
    from functools import partial
    from http.server import SimpleHTTPRequestHandler

    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, request, client_address, server):
            super().__init__(request, client_address, server, directory=str(public_dir) if public_dir else None)

        def do_OPTIONS(self) -> None:  # noqa: N802
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.end_headers()

        def do_GET(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            try:
                if parsed.path == "/api/session":
                    response(self, 200, {"authenticated": True, "adapter": "read_only"})
                    return
                if parsed.path == "/api/health":
                    response(self, 200, {"ok": True, "target": "postgresql", "read_only": True})
                    return
                if parsed.path == "/api/company/summary":
                    response(self, 200, summary(args))
                    return
                if parsed.path == "/api/company/auth/me":
                    user_code = parse_qs(parsed.query).get("userCode", [""])[0]
                    result = auth_current_user(args, user_code)
                    if result is None:
                        response(self, 404, {"error": "user not found"})
                    else:
                        response(self, 200, result)
                    return
                if parsed.path == "/api/company/auth/my-initiated":
                    user_code = parse_qs(parsed.query).get("userCode", [""])[0]
                    result = auth_my_initiated(args, user_code)
                    if result is None:
                        response(self, 404, {"error": "user not found"})
                    else:
                        response(self, 200, result)
                    return
                if parsed.path == "/api/company/receipts":
                    response(self, 200, {"items": receipts(args)})
                    return
                if parsed.path == "/api/company/projections":
                    value = parse_qs(parsed.query).get("aggregate_type", [None])[0]
                    response(self, 200, {"items": projections(args, value)})
                    return
                if parsed.path == "/api/company/budget/expenses":
                    query = parse_qs(parsed.query)
                    result = budget_expenses(
                        args,
                        query.get("expenseGuid", [None])[0],
                        query.get("userCode", [None])[0],
                        query.get("applyState", [None])[0],
                    )
                    if result is None:
                        response(self, 404, {"error": "user not found"})
                    else:
                        response(self, 200, result)
                    return
                if re.fullmatch(r"/api/company/budget/expenses/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    query = parse_qs(parsed.query)
                    result = budget_expense_detail(
                        args,
                        parsed.path.rsplit("/", 1)[-1],
                        query.get("userCode", [None])[0],
                    )
                    if result is None:
                        response(self, 404, {"error": "user not found"})
                    else:
                        response(self, 200, result)
                    return
                if parsed.path == "/api/company/source/budget/users-in-bu":
                    query = parse_qs(parsed.query)
                    response(self, 200, budget_source_users_in_bu(args, query.get("buGuid", query.get("bu_guid", [None]))[0]))
                    return
                if parsed.path == "/api/company/source/budget/my-loan-balance":
                    query = parse_qs(parsed.query)
                    result = budget_source_my_loan_balance(
                        args,
                        query.get("userCode", query.get("user_code", [None]))[0],
                        query.get("userId", query.get("user_id", [None]))[0],
                    )
                    if result is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "用户不存在"})
                    else:
                        response(self, 200, result)
                    return
                if parsed.path == "/api/company/source/cost/contracts":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        cost_source_contracts(
                            args,
                            query.get("contractGuid", query.get("contract_id", [None]))[0],
                            query.get("buGuid", query.get("bu_guid", [None]))[0],
                            query.get("projGuid", query.get("proj_guid", [None]))[0],
                            query.get("keyword", [None])[0],
                        ),
                    )
                    return
                if re.fullmatch(r"/api/company/source/cost/contracts/[A-Za-z0-9_.:-]{1,128}/milestones", parsed.path):
                    contract_id = parsed.path.split("/")[-2]
                    detail = cost_source_contract_detail(args, contract_id)
                    if detail is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "合同不存在"})
                    else:
                        response(self, 200, {**detail, "data": detail["data"]["milestones"]})
                    return
                if re.fullmatch(r"/api/company/source/cost/contracts/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    contract_id = parsed.path.rsplit("/", 1)[-1]
                    detail = cost_source_contract_detail(args, contract_id)
                    if detail is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "合同不存在"})
                    else:
                        response(self, 200, detail)
                    return
                if parsed.path == "/api/company/source/cost/payment-applies":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        cost_source_payment_applications(
                            args,
                            query.get("view", ["all"])[0],
                            query.get("buGuid", query.get("bu_guid", [None]))[0],
                            query.get("userId", query.get("user_id", [None]))[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/contracts":
                    value = parse_qs(parsed.query).get("contract_id", [None])[0]
                    response(self, 200, {"items": contracts(args, value)})
                    return
                if re.fullmatch(r"/api/company/contracts/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    contract_id = parsed.path.rsplit("/", 1)[-1]
                    result = contract_detail(args, contract_id)
                    if result is None:
                        response(self, 404, {"error": "contract not found"})
                    else:
                        response(self, 200, result)
                    return
                if parsed.path == "/api/company/payment-applies":
                    query = parse_qs(parsed.query)
                    apply_id = query.get("apply_id", [None])[0]
                    view = query.get("view", ["all"])[0]
                    response(self, 200, {"items": payment_applications(args, apply_id, view)})
                    return
                if parsed.path == "/api/company/payment-applies/eligibility":
                    query = parse_qs(parsed.query)
                    plan_id = query.get("plan_id", [""])[0]
                    amount_minor = int(query.get("amount_minor", ["0"])[0])
                    result = payment_application_eligibility(args, plan_id, amount_minor)
                    if result is None:
                        response(self, 404, {"error": "payment plan not found"})
                    else:
                        response(self, 200, result)
                    return
                if parsed.path == "/api/company/tenders":
                    tender_id = parse_qs(parsed.query).get("tender_id", [None])[0]
                    response(self, 200, {"items": tenders(args, tender_id)})
                    return
                if re.fullmatch(r"/api/company/tenders/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    tender_id = parsed.path.rsplit("/", 1)[-1]
                    rows = tenders(args, tender_id)
                    if not rows:
                        response(self, 404, {"error": "tender not found"})
                    else:
                        response(self, 200, rows[0])
                    return
                if parsed.path == "/api/company/suppliers":
                    supplier_id = parse_qs(parsed.query).get("supplier_id", [None])[0]
                    response(self, 200, {"items": suppliers(args, supplier_id)})
                    return
                if parsed.path == "/api/company/cashflow/forecast":
                    query = parse_qs(parsed.query)
                    months = int(query.get("months", ["6"])[0])
                    bu_guid = query.get("buGuid", [None])[0]
                    proj_guid = query.get("projGuid", [None])[0]
                    response(self, 200, cashflow_source_forecast(args, months, bu_guid, proj_guid))
                    return
                if parsed.path == "/api/company/cashflow/forecast-v3":
                    query = parse_qs(parsed.query)
                    months = int(query.get("months", ["6"])[0])
                    proj_guid = query.get("projGuid", [None])[0]
                    if not proj_guid:
                        response(self, 422, {"error": "projGuid is required"})
                    else:
                        response(self, 200, cashflow_source_forecast_v3(args, months, proj_guid))
                    return
                if parsed.path == "/api/company/cashflow/forecast/detail":
                    query = parse_qs(parsed.query)
                    ym = query.get("ym", [None])[0]
                    if not ym:
                        response(self, 422, {"error": "ym is required"})
                    else:
                        response(
                            self,
                            200,
                            cashflow_source_detail(
                                args, ym, query.get("buGuid", [None])[0], query.get("projGuid", [None])[0],
                            ),
                        )
                    return
                if parsed.path == "/api/company/cashflow/inflow":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        cashflow_source_inflow(
                            args,
                            int(query.get("months", ["6"])[0]),
                            query.get("buGuid", [None])[0],
                            query.get("projGuid", [None])[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/cashflow/net":
                    months = int(parse_qs(parsed.query).get("months", ["6"])[0])
                    response(self, 200, cashflow_source_net(args, months))
                    return
                if parsed.path == "/api/company/cashflow/gap-alert":
                    horizon_days = int(parse_qs(parsed.query).get("horizonDays", ["90"])[0])
                    response(self, 200, cashflow_source_gap_alert(args, horizon_days))
                    return
                if parsed.path == "/api/company/cbs/r-master":
                    response(self, 200, cbs_source_r_master(args))
                    return
                if parsed.path == "/api/company/cbs/dict":
                    query = parse_qs(parsed.query)
                    proj_guid = query.get("projGuid", [None])[0]
                    if not proj_guid:
                        response(self, 422, {"error": "projGuid is required"})
                    else:
                        response(
                            self,
                            200,
                            cbs_source_dict(
                                args,
                                proj_guid,
                                query.get("planVersion", [None])[0],
                                query.get("rCode", [None])[0],
                            ),
                        )
                    return
                if parsed.path == "/api/company/cbs/dict/f-balance":
                    query = parse_qs(parsed.query)
                    proj_guid = query.get("projGuid", [None])[0]
                    l3_code = query.get("l3Code", [None])[0]
                    if not proj_guid or not l3_code:
                        response(self, 422, {"error": "projGuid and l3Code are required"})
                    else:
                        result = cbs_source_f_balance(
                            args, proj_guid, l3_code, query.get("planVersion", [None])[0],
                        )
                        response(self, 200 if result.get("success") is True else 404, result)
                    return
                if parsed.path == "/api/company/cbs/versions":
                    proj_guid = parse_qs(parsed.query).get("projGuid", [None])[0]
                    if not proj_guid:
                        response(self, 422, {"error": "projGuid is required"})
                    else:
                        response(self, 200, cbs_source_versions(args, proj_guid))
                    return
                if parsed.path == "/api/company/cbs/versions/compare":
                    query = parse_qs(parsed.query)
                    proj_guid = query.get("projGuid", [None])[0]
                    version_a = query.get("a", [None])[0]
                    version_b = query.get("b", [None])[0]
                    if not proj_guid or not version_a or not version_b:
                        response(self, 422, {"error": "projGuid, a, and b are required"})
                    else:
                        response(
                            self,
                            200,
                            cbs_source_versions_compare(
                                args, proj_guid, version_a, version_b, query.get("c", [None])[0],
                            ),
                        )
                    return
                if parsed.path == "/api/company/cbs/r0/queue":
                    proj_guid = parse_qs(parsed.query).get("projGuid", [None])[0]
                    response(self, 200, cbs_source_r0_queue(args, proj_guid))
                    return
                if parsed.path == "/api/company/cbs/approval-rules/pick":
                    query = parse_qs(parsed.query)
                    biz_type = query.get("bizType", [None])[0]
                    amount = query.get("amount", [None])[0]
                    if not biz_type or amount is None:
                        response(self, 422, {"error": "bizType and amount are required"})
                    else:
                        response(self, 200, cbs_source_approval_pick(args, biz_type, float(amount)))
                    return
                if parsed.path == "/api/company/cbs/approval-rules":
                    biz_type = parse_qs(parsed.query).get("bizType", [None])[0]
                    response(self, 200, cbs_source_approval_rules(args, biz_type))
                    return
                if parsed.path == "/api/company/cbs/changes":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        cbs_source_changes(
                            args, query.get("projGuid", [None])[0], query.get("contractGuid", [None])[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/cbs/demo/contracts":
                    proj_guid = parse_qs(parsed.query).get("projGuid", [None])[0]
                    response(self, 200, cbs_source_demo_contracts(args, proj_guid))
                    return
                if parsed.path == "/api/company/fund/plans":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        fund_source_plans(
                            args,
                            query.get("projGuid", [None])[0],
                            query.get("period", [None])[0],
                            query.get("direction", [None])[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/fund/gap-analysis":
                    proj_guid = parse_qs(parsed.query).get("projGuid", [None])[0]
                    if not proj_guid:
                        response(self, 422, {"error": "projGuid is required"})
                    else:
                        response(self, 200, fund_source_gap_analysis(args, proj_guid))
                    return
                if parsed.path == "/api/company/fund/dispatches":
                    response(self, 200, fund_source_dispatches(args))
                    return
                if parsed.path == "/api/company/warning/badge":
                    response(self, 200, warning_source_badge(args))
                    return
                if parsed.path == "/api/company/warning":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        warning_source_list(
                            args,
                            query.get("status", ["open"])[0],
                            query.get("ruleCode", [None])[0],
                            query.get("severity", [None])[0],
                            query.get("bizType", [None])[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/warning/rules":
                    response(self, 200, warning_source_rules(args))
                    return
                if parsed.path == "/api/company/warning/scans":
                    response(self, 200, warning_source_empty_read(args, "scans"))
                    return
                if parsed.path == "/api/company/warning/custom-rules":
                    response(self, 200, warning_source_empty_read(args, "custom-rules"))
                    return
                if parsed.path == "/api/company/warning/rule-templates":
                    response(self, 200, warning_source_empty_read(args, "rule-templates"))
                    return
                if parsed.path == "/api/company/warning/tickets/mine":
                    response(self, 200, warning_source_empty_read(args, "tickets"))
                    return
                if parsed.path == "/api/company/attachments/list":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        attachment_source_list(
                            args,
                            query.get("bizType", [None])[0],
                            query.get("bizGuid", [None])[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/attachments/all" or parsed.path == "/api/company/attachments":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        attachment_source_all(
                            args,
                            query.get("bizType", [None])[0],
                            query.get("uploadedBy", [None])[0],
                            query.get("aiStatus", [None])[0],
                            query.get("keyword", [None])[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/attachments/stats":
                    response(self, 200, attachment_source_stats(args))
                    return
                if parsed.path == "/api/company/marketing/campaigns":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        marketing_source_campaigns(
                            args,
                            query.get("projGuid", [None])[0],
                            query.get("state", [None])[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/marketing/placements":
                    campaign_guid = parse_qs(parsed.query).get("campaignGuid", [None])[0]
                    response(self, 200, marketing_source_placements(args, campaign_guid))
                    return
                if parsed.path == "/api/company/marketing/channels":
                    response(self, 200, marketing_source_channels(args))
                    return
                if parsed.path == "/api/company/marketing/materials":
                    proj_guid = parse_qs(parsed.query).get("projGuid", [None])[0]
                    response(self, 200, marketing_source_materials(args, proj_guid))
                    return
                if parsed.path == "/api/company/ai-stats/overview":
                    period = parse_qs(parsed.query).get("period", ["month"])[0]
                    response(self, 200, ai_stats_source_overview(args, period))
                    return
                if parsed.path == "/api/company/ai-stats/activity":
                    query = parse_qs(parsed.query)
                    try:
                        limit = int(query.get("limit", ["30"])[0])
                    except (TypeError, ValueError):
                        response(self, 422, {"error": "invalid AI activity limit"})
                    else:
                        if limit < 1 or limit > 100:
                            response(self, 422, {"error": "invalid AI activity limit"})
                        else:
                            response(self, 200, ai_stats_source_activity(args, limit))
                    return
                if parsed.path == "/api/company/ai-stats/badge":
                    query = parse_qs(parsed.query)
                    biz_type = query.get("bizType", [None])[0]
                    biz_guid = query.get("bizGuid", [None])[0]
                    if not biz_type or not biz_guid:
                        response(self, 422, {"error": "bizType and bizGuid are required"})
                    elif not IDENTIFIER.fullmatch(biz_type) or not IDENTIFIER.fullmatch(biz_guid):
                        response(self, 422, {"error": "invalid AI badge identifiers"})
                    else:
                        response(self, 200, ai_stats_source_badge(args, biz_type, biz_guid))
                    return
                if parsed.path == "/api/company/ai-hub/corrections":
                    query = parse_qs(parsed.query)
                    try:
                        limit = int(query.get("limit", ["50"])[0])
                    except (TypeError, ValueError):
                        response(self, 422, {"error": "invalid AI Hub limit"})
                    else:
                        if limit < 1 or limit > 500:
                            response(self, 422, {"error": "invalid AI Hub limit"})
                        else:
                            response(
                                self,
                                200,
                                ai_hub_corrections(
                                    args,
                                    query.get("bizType", [None])[0],
                                    query.get("field", [None])[0],
                                    query.get("userCode", [None])[0],
                                    limit,
                                ),
                            )
                    return
                if parsed.path == "/api/company/ai-hub/correction-stats":
                    response(self, 200, ai_hub_correction_stats(args))
                    return
                if parsed.path == "/api/company/ai-hub/drafts":
                    query = parse_qs(parsed.query)
                    response(self, 200, ai_hub_drafts(args, query.get("userCode", [None])[0]))
                    return
                ai_hub_draft_match = re.fullmatch(
                    r"/api/company/ai-hub/drafts/([A-Za-z0-9_.:-]{1,128})",
                    parsed.path,
                )
                if ai_hub_draft_match is not None:
                    query = parse_qs(parsed.query)
                    result = ai_hub_draft(
                        args,
                        ai_hub_draft_match.group(1),
                        query.get("userCode", [None])[0],
                    )
                    if result is None:
                        response(
                            self,
                            404,
                            {"success": False, "code": 43001, "message": "草稿不存在"},
                        )
                    else:
                        response(self, 200, result)
                    return
                if parsed.path == "/api/company/ai-hub/query-log":
                    query = parse_qs(parsed.query)
                    response(self, 200, ai_hub_query_log(args, query.get("userCode", [None])[0]))
                    return
                if parsed.path == "/api/company/ai-hub/usage-stats":
                    response(self, 200, ai_hub_usage_stats(args))
                    return
                if parsed.path == "/api/company/webhook/config":
                    response(self, 200, webhook_source_config(args))
                    return
                if parsed.path == "/api/company/admin/ocr/status":
                    response(self, 200, ocr_source_status(args))
                    return
                if parsed.path == "/api/company/admin/error-log":
                    query = parse_qs(parsed.query)
                    try:
                        limit = int(query.get("limit", ["100"])[0])
                    except (TypeError, ValueError):
                        response(self, 422, {"error": "invalid error log limit"})
                    else:
                        if limit < 1 or limit > 500:
                            response(self, 422, {"error": "invalid error log limit"})
                        elif len(query.get("keyword", [""])[0]) > 128:
                            response(self, 422, {"error": "invalid error log keyword"})
                        else:
                            response(
                                self,
                                200,
                                error_log_source_rows(
                                    args,
                                    query.get("keyword", [None])[0],
                                    limit,
                                ),
                            )
                    return
                if parsed.path == "/api/company/notify/messages":
                    query = parse_qs(parsed.query)
                    try:
                        limit = int(query.get("limit", ["50"])[0])
                        offset = int(query.get("offset", ["0"])[0])
                    except (TypeError, ValueError):
                        response(self, 422, {"error": "invalid notification pagination"})
                    else:
                        response(
                            self,
                            200,
                            notification_source_messages(
                                args,
                                query.get("userCode", [None])[0],
                                query.get("status", ["unread"])[0],
                                limit,
                                offset,
                            ),
                        )
                    return
                if parsed.path == "/api/company/notify/messages/unread-count":
                    user_code = parse_qs(parsed.query).get("userCode", [None])[0]
                    response(self, 200, notification_source_unread_count(args, user_code))
                    return
                if parsed.path == "/api/company/notify/subscriptions":
                    user_code = parse_qs(parsed.query).get("userCode", [None])[0]
                    response(self, 200, notification_source_subscriptions(args, user_code))
                    return
                if parsed.path == "/api/company/notify/config":
                    response(self, 200, notification_source_config(args))
                    return
                if parsed.path == "/api/company/notify/email-outbox":
                    response(self, 200, notification_source_email_outbox(args))
                    return
                if parsed.path == "/api/company/notify/digest/preview":
                    response(self, 200, notification_source_digest_preview(args))
                    return
                if parsed.path == "/api/company/notify/digest/log":
                    response(self, 200, notification_source_digest_log(args))
                    return
                if parsed.path == "/api/company/notify/llm-providers":
                    response(self, 200, notification_source_llm_providers(args))
                    return
                if parsed.path == "/api/company/source/workflow/tasks/mine":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        workflow_source_tasks_mine(
                            args,
                            query.get("userId", query.get("user_id", [None]))[0],
                            query.get("userCode", query.get("user_code", [None]))[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/source/workflow/tasks/initiated":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        workflow_source_tasks_initiated(
                            args,
                            query.get("userId", query.get("user_id", [None]))[0],
                            query.get("userCode", query.get("user_code", [None]))[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/source/workflow/tasks/my-history":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        workflow_source_history(
                            args,
                            query.get("userId", query.get("user_id", [None]))[0],
                            query.get("userCode", query.get("user_code", [None]))[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/source/workflow/instances/by-biz":
                    query = parse_qs(parsed.query)
                    biz_type = query.get("bizType", query.get("biz_type", [""]))[0]
                    biz_guid = query.get("bizDataGuid", query.get("biz_data_guid", [""]))[0]
                    if not biz_type or not biz_guid:
                        response(self, 422, {"success": False, "code": 40001, "message": "bizType / bizDataGuid 必填"})
                    else:
                        response(self, 200, workflow_source_instance_by_biz(args, biz_type, biz_guid))
                    return
                workflow_instance_match = re.fullmatch(
                    r"/api/company/source/workflow/instances/([A-Za-z0-9_.:-]{1,128})",
                    parsed.path,
                )
                if workflow_instance_match is not None:
                    result = workflow_source_instance_detail(args, workflow_instance_match.group(1))
                    if result is None:
                        response(self, 404, {"success": False, "code": 43001, "message": "流程实例不存在"})
                    else:
                        response(self, 200, result)
                    return
                if parsed.path == "/api/company/srm/providers":
                    response(self, 200, supplier_source_list(args))
                    return
                if re.fullmatch(r"/api/company/srm/providers/[A-Za-z0-9_.:-]{1,128}/risk", parsed.path):
                    provider_guid = parsed.path.split("/")[-2]
                    risk = supplier_source_risk(args, provider_guid)
                    response(self, 200 if risk.get("success") is True else 404, risk)
                    return
                if re.fullmatch(r"/api/company/srm/providers/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    provider_guid = parsed.path.rsplit("/", 1)[-1]
                    detail = supplier_source_detail(args, provider_guid)
                    response(self, 200 if detail.get("success") is True else 404, detail)
                    return
                if parsed.path == "/api/company/srm/stats/overview":
                    response(self, 200, supplier_source_stats(args))
                    return
                if parsed.path == "/api/company/supplier-risk-board":
                    response(self, 200, {"items": supplier_risk_board(args)})
                    return
                if parsed.path == "/api/company/srm/risk-board":
                    response(self, 200, supplier_risk_board_source(args))
                    return
                if re.fullmatch(r"/api/company/suppliers/[A-Za-z0-9_.:-]{1,128}/risk", parsed.path):
                    supplier_id = parsed.path.split("/")[-2]
                    result = supplier_risk(args, supplier_id)
                    if result is None:
                        response(self, 404, {"error": "supplier not found"})
                    else:
                        response(self, 200, result)
                    return
                if re.fullmatch(r"/api/company/suppliers/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    supplier_id = parsed.path.rsplit("/", 1)[-1]
                    rows = suppliers(args, supplier_id)
                    if not rows:
                        response(self, 404, {"error": "supplier not found"})
                    else:
                        response(self, 200, rows[0])
                    return
                if parsed.path == "/api/company/tender-splits":
                    parent_contract_id = parse_qs(parsed.query).get("parent_contract_id", [None])[0]
                    response(self, 200, {"items": contract_splits(args, None, parent_contract_id)})
                    return
                if re.fullmatch(r"/api/company/tender-splits/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    split_id = parsed.path.rsplit("/", 1)[-1]
                    rows = contract_splits(args, split_id, None)
                    if not rows:
                        response(self, 404, {"error": "contract split not found"})
                    else:
                        response(self, 200, rows[0])
                    return
                if re.fullmatch(r"/api/company/payment-applies/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    apply_id = parsed.path.rsplit("/", 1)[-1]
                    rows = payment_applications(args, apply_id, "all")
                    if not rows:
                        response(self, 404, {"error": "payment application not found"})
                    else:
                        response(self, 200, rows[0])
                    return
                sales_match = re.fullmatch(
                    r"/api/company/sales/(customers|subscriptions|contracts|mortgages|refunds|revenues)(?:/([A-Za-z0-9_.:-]{1,128}))?",
                    parsed.path,
                )
                if sales_match is not None:
                    family, aggregate_id = sales_match.group(1), sales_match.group(2)
                    rows = sales_rows(args, family, aggregate_id)
                    if aggregate_id is None:
                        response(self, 200, {"items": rows})
                    elif not rows:
                        response(self, 404, {"error": f"sales {family[:-1]} not found"})
                    else:
                        response(self, 200, rows[0])
                    return
                receivable_match = re.fullmatch(
                    r"/api/company/receivables(?:/([A-Za-z0-9_.:-]{1,128}))?",
                    parsed.path,
                )
                if receivable_match is not None:
                    aggregate_id = receivable_match.group(1)
                    rows = sales_rows(args, "receivables", aggregate_id)
                    if aggregate_id is None:
                        response(self, 200, {"items": rows})
                    elif not rows:
                        response(self, 404, {"error": "receivable not found"})
                    else:
                        response(self, 200, rows[0])
                    return
                source_invoice_match = re.fullmatch(
                    r"/api/company/source/invoice/(in|out)",
                    parsed.path,
                )
                if source_invoice_match is not None:
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        invoice_source_rows(
                            args,
                            source_invoice_match.group(1),
                            query.get("projGuid", [None])[0],
                            query.get("contractGuid", [None])[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/source/invoice/tax-ledger":
                    proj_guid = parse_qs(parsed.query).get("projGuid", [None])[0]
                    response(self, 200, invoice_source_tax_ledger(args, proj_guid))
                    return
                invoice_match = re.fullmatch(
                    r"/api/company/invoices(?:/([A-Za-z0-9_.:-]{1,128}))?",
                    parsed.path,
                )
                if invoice_match is not None:
                    aggregate_id = invoice_match.group(1)
                    rows = sales_rows(args, "invoices", aggregate_id)
                    if aggregate_id is None:
                        response(self, 200, {"items": rows})
                    elif not rows:
                        response(self, 404, {"error": "invoice not found"})
                    else:
                        response(self, 200, rows[0])
                    return
                if parsed.path == "/api/company/reports/overview":
                    response(self, 200, reports_overview(args))
                    return
                if parsed.path == "/api/company/reports/templates/meta":
                    response(self, 200, report_template_metadata(args))
                    return
                if parsed.path == "/api/company/reports/templates":
                    response(self, 200, report_template_rows(args))
                    return
                if parsed.path == "/api/company/reports/cost-summary":
                    response(self, 200, report_cost_summary(args))
                    return
                if parsed.path == "/api/company/reports/contract-payment-ledger":
                    response(self, 200, report_contract_payment_ledger(args))
                    return
                if parsed.path == "/api/company/reports/supplier-analysis":
                    response(self, 200, report_supplier_analysis(args))
                    return
                if parsed.path == "/api/company/reports/approval-efficiency":
                    response(self, 200, report_approval_efficiency(args))
                    return
                if parsed.path == "/api/company/reports/project-stage-matrix":
                    response(self, 200, report_project_stage_matrix(args))
                    return
                if parsed.path == "/api/company/admin/quality/overview":
                    response(self, 200, admin_quality_overview(args))
                    return
                dynamic_cost_match = re.fullmatch(
                    r"/api/company/cost/dynamic-cost",
                    parsed.path,
                )
                if dynamic_cost_match is not None:
                    project_id = parse_qs(parsed.query).get("projGuid", [""])[0]
                    if not project_id:
                        response(self, 422, {"error": "projGuid is required"})
                    else:
                        response(self, 200, dynamic_cost(args, project_id))
                    return
                investment_versions_match = re.fullmatch(
                    r"/api/company/investment/projects/([A-Za-z0-9_.:-]{1,128})/versions",
                    parsed.path,
                )
                if investment_versions_match is not None:
                    response(self, 200, investment_versions(args, investment_versions_match.group(1)))
                    return
                investment_indices_match = re.fullmatch(
                    r"/api/company/investment/versions/([A-Za-z0-9_.:-]{1,128})/indices",
                    parsed.path,
                )
                if investment_indices_match is not None:
                    dimension = parse_qs(parsed.query).get("dimension", [None])[0]
                    response(
                        self,
                        200,
                        investment_indices(args, investment_indices_match.group(1), dimension),
                    )
                    return
                if re.fullmatch(
                    r"/api/company/source/sales/(customers|subscriptions|contracts|mortgages|refunds|revenues)",
                    parsed.path,
                ):
                    family = parsed.path.rsplit("/", 1)[-1]
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        sales_source_rows(
                            args,
                            family,
                            query.get("projGuid", query.get("proj_guid", [None]))[0],
                            query.get("state", query.get("status", [None]))[0],
                            query.get("keyword", [None])[0],
                        ),
                    )
                    return
                investment_profit_match = re.fullmatch(
                    r"/api/company/investment/projects/([A-Za-z0-9_.:-]{1,128})/profit-summary",
                    parsed.path,
                )
                if investment_profit_match is not None:
                    response(self, 200, investment_profit_summary(args, investment_profit_match.group(1)))
                    return
                cost_dashboard_match = re.fullmatch(
                    r"/api/company/investment/projects/([A-Za-z0-9_.:-]{1,128})/profit-actual-v2",
                    parsed.path,
                )
                if cost_dashboard_match is not None:
                    plan_version = parse_qs(parsed.query).get("planVersion", [None])[0]
                    result = cost_dashboard_v3(args, cost_dashboard_match.group(1), plan_version)
                    if result is None:
                        response(self, 404, {"error": "project not found"})
                    else:
                        response(self, 200, result)
                    return
                if parsed.path == "/api/company/rbac/users":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        admin_rbac_users(
                            args,
                            query.get("keyword", [None])[0],
                            query.get("enabled", [None])[0],
                        ),
                    )
                    return
                if parsed.path == "/api/company/admin/dict/groups":
                    response(self, 200, admin_dict_groups(args))
                    return
                if parsed.path == "/api/company/admin/dict/options":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        admin_dict_options(args, query.get("groupName", [None])[0]),
                    )
                    return
                if parsed.path == "/api/company/admin/audit/logs":
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
                            args,
                            query.get("action", [None])[0],
                            query.get("userId", [None])[0],
                            query.get("targetType", [None])[0],
                            limit,
                            offset,
                        ),
                    )
                    return
                if parsed.path == "/api/company/admin/audit/actions":
                    response(self, 200, admin_audit_actions(args))
                    return
                if parsed.path == "/api/company/admin/health/tables":
                    response(self, 200, admin_health_tables(args))
                    return
                if parsed.path == "/api/company/admin/health/bpm-pool":
                    response(self, 200, admin_health_bpm_pool(args))
                    return
                if parsed.path == "/api/company/dashboard/group/overview":
                    response(self, 200, dashboard_group_overview(args))
                    return
                if parsed.path == "/api/company/dashboard/group/funnel":
                    response(self, 200, dashboard_group_funnel(args))
                    return
                if parsed.path == "/api/company/dashboard/group/top-anomalies":
                    query = parse_qs(parsed.query)
                    try:
                        limit = int(query.get("limit", ["10"])[0])
                    except (TypeError, ValueError) as error:
                        raise ValueError("invalid dashboard anomaly limit") from error
                    response(self, 200, dashboard_group_top_anomalies(args, limit))
                    return
                dashboard_match = re.fullmatch(
                    r"/api/company/dashboard/project/([A-Za-z0-9_.:-]{1,128})/(kpi|anomalies)",
                    parsed.path,
                )
                if dashboard_match is not None:
                    project_id, family = dashboard_match.group(1), dashboard_match.group(2)
                    if family == "kpi":
                        result = dashboard_project_kpi(args, project_id)
                        if result is None:
                            response(self, 404, {"error": "project not found"})
                        else:
                            response(self, 200, result)
                    else:
                        response(self, 200, dashboard_project_anomalies(args, project_id))
                    return
                if parsed.path == "/api/company/loans":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        {
                            "items": loans(
                                args,
                                query.get("loan_id", [None])[0],
                                query.get("apply_state", [None])[0],
                            )
                        },
                    )
                    return
                if re.fullmatch(r"/api/company/loans/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    loan_id = parsed.path.rsplit("/", 1)[-1]
                    rows = loans(args, loan_id, None)
                    if not rows:
                        response(self, 404, {"error": "loan not found"})
                    else:
                        response(self, 200, {"loan": rows[0], "offsets": rows[0].get("offsets", [])})
                    return
                if parsed.path == "/api/company/delivery/progress":
                    query = parse_qs(parsed.query)
                    rows = delivery_progress(
                        args,
                        query.get("progress_id", [None])[0],
                        query.get("project_id", [None])[0],
                    )
                    response(self, 200, {"items": rows})
                    return
                if parsed.path == "/api/company/source/delivery/progress":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        source_delivery_progress(args, query.get("projGuid", query.get("project_id", [None]))[0]),
                    )
                    return
                if re.fullmatch(r"/api/company/delivery/progress/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    progress_id = parsed.path.rsplit("/", 1)[-1]
                    rows = delivery_progress(args, progress_id, None)
                    if not rows:
                        response(self, 404, {"error": "delivery progress not found"})
                    else:
                        response(self, 200, rows[0])
                    return
                if parsed.path == "/api/company/delivery/outputs":
                    query = parse_qs(parsed.query)
                    rows = delivery_outputs(
                        args,
                        query.get("output_id", [None])[0],
                        query.get("project_id", [None])[0],
                    )
                    response(self, 200, {"items": rows})
                    return
                if parsed.path == "/api/company/source/delivery/outputs":
                    query = parse_qs(parsed.query)
                    response(
                        self,
                        200,
                        source_delivery_outputs(
                            args,
                            query.get("projGuid", query.get("project_id", [None]))[0],
                            query.get("period", [None])[0],
                            query.get("state", [None])[0],
                        ),
                    )
                    return
                if re.fullmatch(r"/api/company/delivery/outputs/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    output_id = parsed.path.rsplit("/", 1)[-1]
                    rows = delivery_outputs(args, output_id, None)
                    if not rows:
                        response(self, 404, {"error": "delivery output not found"})
                    else:
                        response(self, 200, rows[0])
                    return
                if parsed.path == "/api/company/delivery/tasks":
                    query = parse_qs(parsed.query)
                    rows = delivery_tasks(
                        args,
                        query.get("task_id", [None])[0],
                        query.get("project_id", [None])[0],
                    )
                    response(self, 200, {"items": rows})
                    return
                if re.fullmatch(r"/api/company/delivery/tasks/[A-Za-z0-9_.:-]{1,128}", parsed.path):
                    task_id = parsed.path.rsplit("/", 1)[-1]
                    rows = delivery_tasks(args, task_id, None)
                    if not rows:
                        response(self, 404, {"error": "delivery task not found"})
                    else:
                        response(
                            self,
                            200,
                            {"task": rows[0], "reports": delivery_task_reports(args, None, task_id)},
                        )
                    return
                if parsed.path == "/api/company/delivery/task-reports":
                    query = parse_qs(parsed.query)
                    rows = delivery_task_reports(
                        args,
                        query.get("report_id", [None])[0],
                        query.get("task_id", [None])[0],
                    )
                    response(self, 200, {"items": rows})
                    return
                if parsed.path == "/api/company/delivery/plan-summary":
                    project_id = parse_qs(parsed.query).get("project_id", [""])[0]
                    if not project_id:
                        response(self, 422, {"error": "project_id is required"})
                    else:
                        response(self, 200, delivery_plan_summary(args, project_id))
                    return
                if parsed.path == "/api/company/delivery/overview":
                    project_id = parse_qs(parsed.query).get("project_id", [""])[0]
                    if not project_id:
                        response(self, 422, {"error": "project_id is required"})
                    else:
                        response(self, 200, delivery_overview(args, project_id))
                    return
                if parsed.path.startswith("/api/"):
                    response(self, 404, {"error": "unknown read-model endpoint"})
                    return
                if public_dir is None:
                    response(self, 404, {"error": "static public directory is not configured"})
                    return
                super().do_GET()
            except (OSError, PostgresTargetError, ValueError) as error:
                response(self, 500, {"error": str(error)})

        def do_POST(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path == "/api/session/login":
                response(self, 200, {"authenticated": True, "adapter": "read_only"})
                return
            if parsed.path == "/api/session/logout":
                response(self, 200, {"authenticated": False, "adapter": "read_only"})
                return
            response(self, 404, {"error": "read-model adapter is read-only"})

        def log_message(self, format: str, *values: object) -> None:
            sys.stderr.write("company-read-model: " + (format % values) + "\n")

    return Handler


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public-dir", type=Path, default=None)
    parser.add_argument("--host", dest="http_host", default="127.0.0.1")
    parser.add_argument("--port", dest="http_port", type=int, default=4173)
    parser.add_argument("--psql", default=None)
    parser.add_argument("--pg-host", default=os.environ.get("PGHOST", "/tmp"))
    parser.add_argument("--pg-port", default=os.environ.get("PGPORT", "5432"))
    parser.add_argument("--pg-user", default=os.environ.get("PGUSER", "moonproj"))
    parser.add_argument("--database", default=os.environ.get("PGDATABASE", "moonproj"))
    args = parser.parse_args()
    # Reuse the PostgreSQL adapter's argument names so the same credential
    # environment and psql binary selection apply to every read-model query.
    args.host, args.port, args.user = args.pg_host, args.pg_port, args.pg_user
    if args.public_dir is not None and not args.public_dir.is_dir():
        parser.error(f"public directory does not exist: {args.public_dir}")
    server = ThreadingHTTPServer((args.http_host, args.http_port), handler_factory(args, args.public_dir))
    print(f"company read model listening on http://{args.http_host}:{args.http_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
