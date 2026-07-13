#!/usr/bin/env python3
"""Build a source-to-Rabbita UI and API parity matrix.

The ERP route inventory answers *which server handlers exist*.  This report
answers the next migration question: for every source browser route, which
Rabbita view is mounted, whether it is a real/read-model/fixture surface, and
which source API module still needs a connected command/read workflow.

The report is intentionally evidence-oriented.  A mounted page is not marked
functional merely because it renders: the generic summary/read-model adapter
is not dashboard parity; the bounded dashboard v1 reads are now explicitly
identified, while the local expense/contract/payment-application/
tender/supplier/supplier-provider/supplier-risk/sales read verticals are explicitly identified, including the
delivery/project-progress runtime, non-authorizing workflow-definition,
 cashflow, CBS, fund-plan, observed-warning, attachment-metadata, marketing,
 notification metadata, OCR-status, error-log, AI-analytics, and AI Hub observation read boundaries. No
 workflow-instance mutation endpoint is inferred. The source cost contract/payment,
 budget scope/loan-balance, and workflow instance-observation reads are tracked
 separately from their command or definition surfaces.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


class MatrixError(RuntimeError):
    """The source or target surface could not be inspected."""


HANDLER = re.compile(r"\br\.(get|post|put|patch|delete)\s*\(\s*['\"]([^'\"]+)")
SOURCE_ROUTE = re.compile(r"\{\s*path:\s*'([^']+)'(?P<body>.*)")
COMPONENT = re.compile(r"component:\s*\(\)\s*=>\s*import\('([^']+)'\)")
REDIRECT = re.compile(r"redirect:\s*'([^']+)'")
TARGET_EXACT = re.compile(r'^\s*"(/[^" ]*)"\s*=>\s*([A-Za-z0-9_]+)\(', re.MULTILINE)
TARGET_PREFIX = re.compile(r'path\.has_prefix\("([^"]+)"\)')


# The ERP mounts each route file under /api/v1/<module>.  These associations
# are deliberately explicit so a renamed screen cannot silently inherit an
# unrelated API surface.
UI_MODULES: list[tuple[str, tuple[str, ...]]] = [
    ("auth", ("/login", "/profile")),
    ("dashboard", ("/dashboard", "/dashboard-v3", "/cockpit")),
    ("ai-hub", ("/ai-hub",)),
    ("ai-stats", ("/ai-stats",)),
    ("mdm", ("/projects",)),
    ("plan", ("/project-plan",)),
    ("progress", ("/project/progress",)),
    ("workflow", ("/tasks",)),
    ("sales", ("/sales/",)),
    ("marketing", ("/marketing",)),
    ("cost", ("/contracts", "/payment-applies", "/dynamic-cost", "/cost-dashboard-v3")),
    ("investment", ("/investment",)),
    ("budget", ("/expenses",)),
    ("loan", ("/loans",)),
    ("fund", ("/fund/plan",)),
    ("invoice", ("/invoice",)),
    ("tender", ("/tender",)),
    ("cbs", ("/cbs/",)),
    ("srm", ("/srm/",)),
    ("reports", ("/reports", "/report-builder")),
    ("warning", ("/warning",)),
    ("cashflow", ("/cashflow",)),
    ("attachment", ("/attachments",)),
    ("notify", ("/notify-config", "/inbox")),
    ("webhook", ("/webhook-config",)),
    ("admin", ("/admin", "/ocr-config", "/system-health", "/error-log", "/audit-log")),
    ("rbac", ("/users",)),
    ("share", ("/share/",)),
]


READ_METHODS = {"GET"}
MUTATION_METHODS = {"POST", "PUT", "PATCH", "DELETE"}


def source_routes(router_path: Path) -> list[dict[str, Any]]:
    routes: list[dict[str, Any]] = []
    for line in router_path.read_text(encoding="utf-8").splitlines():
        match = SOURCE_ROUTE.search(line)
        if match is None:
            continue
        raw_path = match.group(1)
        if raw_path == "/":
            continue
        path = raw_path if raw_path.startswith("/") else "/" + raw_path
        body = match.group("body")
        component = COMPONENT.search(body)
        redirect = REDIRECT.search(body)
        routes.append(
            {
                "path": path,
                "component": component.group(1) if component else None,
                "redirect": redirect.group(1) if redirect else None,
                "public": "public: true" in body,
            }
        )
    if not routes:
        raise MatrixError(f"no browser routes found in {router_path}")
    return routes


def target_surface(frontend_path: Path) -> tuple[dict[str, str], list[str], set[str]]:
    text = frontend_path.read_text(encoding="utf-8")
    exact = {path: function for path, function in TARGET_EXACT.findall(text)}
    prefixes = sorted(set(TARGET_PREFIX.findall(text)), key=len, reverse=True)
    functions = set(re.findall(r"^fn\s+([A-Za-z0-9_]+)\s*\(", text, re.MULTILINE))
    return exact, prefixes, functions


def source_api_stats(routes_dir: Path) -> tuple[dict[str, dict[str, int]], list[dict[str, str]]]:
    result: dict[str, dict[str, int]] = {}
    handlers: list[dict[str, str]] = []
    files = sorted(routes_dir.glob("*.js"))
    if not files:
        raise MatrixError(f"no source route files found in {routes_dir}")
    for path in files:
        route_handlers = [
            {"method": method.upper(), "path": route_path}
            for method, route_path in HANDLER.findall(path.read_text(encoding="utf-8"))
        ]
        handlers.extend(
            {
                "module": path.stem,
                "method": item["method"],
                "path": item["path"],
            }
            for item in route_handlers
        )
        result[path.stem] = {
            "handler_count": len(route_handlers),
            "read_handler_count": sum(item["method"] in READ_METHODS for item in route_handlers),
            "mutation_handler_count": sum(item["method"] in MUTATION_METHODS for item in route_handlers),
        }
    return result, handlers


def module_for(path: str) -> str | None:
    for module, prefixes in UI_MODULES:
        if any(path == prefix or path.startswith(prefix) for prefix in prefixes):
            return module
    return None


def match_target(
    path: str,
    exact: dict[str, str],
    prefixes: list[str],
    functions: set[str],
) -> tuple[str | None, str]:
    if path == "/login":
        return ("login_view" if "login_view" in functions else None, "public")
    if path == "/dashboard" and "dashboard_view" in functions:
        return "dashboard_view", "connected_dashboard_read"
    if path in exact:
        function = exact[path]
        if function == "placeholder_view":
            return function, "not_implemented"
        if path.startswith("/share"):
            return function, "read_only_public"
        if function == "dashboard_view":
            return function, "connected_dashboard_read"
        if path == "/expenses/new" and function == "expense_editor_view":
            return function, "connected_command_form"
        if path == "/expenses/:guid" and function == "expense_editor_view":
            return function, "connected_expense_detail_read"
        if path == "/contracts" and function == "contracts_view":
            return function, "connected_contract_read"
        if path == "/payment-applies" and function == "payment_applies_view":
            return function, "connected_payment_application_command_form"
        if path == "/tender" and function == "tender_view":
            return function, "connected_tender_command_form"
        if path == "/srm/providers" and function == "srm_providers_view":
            return function, "connected_supplier_command_form"
        if path == "/srm/risk-board" and function == "srm_risk_view":
            return function, "connected_supplier_risk_read"
        if path in {
            "/sales/customers",
            "/sales/subscriptions",
            "/sales/contracts",
            "/sales/mortgages",
            "/sales/revenues",
        }:
            return function, "connected_sales_read"
        if path in {"/project-plan", "/project/progress"}:
            return function, "connected_delivery_command_form"
        if path == "/invoice" and function == "invoice_view":
            return function, "connected_invoice_read"
        if path == "/reports" and function == "reports_view":
            return function, "connected_report_read"
        if path == "/tasks" and function == "tasks_view":
            return function, "connected_workflow_definition_read"
        if path == "/projects" and function == "project_view":
            return function, "connected_project_read"
        if path == "/loans/new" and function == "loan_editor_view":
            return function, "connected_loan_command_form"
        if path == "/loans" and function == "loans_view":
            return function, "connected_loan_read"
        if path == "/system-health" and function == "health_view":
            return function, "connected_admin_health_read"
        if path == "/admin" and function == "admin_view":
            return function, "connected_admin_read"
        if path == "/investment" and function == "investment_view":
            return function, "connected_investment_read"
        if path == "/users" and function == "users_view":
            return function, "connected_rbac_user_read"
        if path == "/audit-log" and function == "audit_view":
            return function, "connected_admin_audit_read"
        if path == "/dynamic-cost" and function == "dynamic_cost_view":
            return function, "connected_cost_read"
        if path == "/cost-dashboard-v3" and function == "cost_dashboard_view":
            return function, "connected_cost_dashboard_read"
        if path == "/cashflow" and function == "cashflow_view":
            return function, "connected_cashflow_read"
        if path in {"/cbs/dict", "/cbs/versions", "/cbs/r0-queue", "/cbs/approval-config"} and function == "cbs_view":
            return function, "connected_cbs_read"
        if path == "/fund/plan" and function == "fund_plan_view":
            return function, "connected_fund_read"
        if path in {"/warning", "/warning-rules"} and function in {"warning_view", "warning_rules_view"}:
            return function, "connected_warning_read"
        if path == "/attachments" and function == "attachments_view":
            return function, "connected_attachment_read"
        if path == "/marketing" and function == "marketing_view":
            return function, "connected_marketing_read"
        if path in {"/inbox", "/notify-config"} and function in {
            "inbox_view", "notify_view"
        }:
            return function, "connected_notification_read"
        if path == "/ocr-config" and function == "ocr_view":
            return function, "connected_admin_ocr_read"
        if path == "/error-log" and function == "error_view":
            return function, "connected_admin_error_read"
        if path == "/ai-stats" and function == "ai_stats_view":
            return function, "connected_ai_stats_read"
        if path == "/ai-hub" and function == "ai_hub_view":
            return function, "connected_ai_hub_read"
        if path == "/webhook-config" and function == "webhook_view":
            return function, "connected_webhook_read"
        if path == "/report-builder" and function == "report_builder_view":
            return function, "connected_report_builder_read"
        if path == "/profile" and function == "profile_view":
            return function, "connected_profile_read"
        if path == "/expenses" and function == "expenses_view":
            return function, "connected_expense_read"
        if path != "/expenses/new" and path.startswith("/expenses/") and function == "expense_editor_view":
            return function, "connected_expense_detail_read"
        if function in {"project_detail_view", "contract_detail_view", "expense_editor_view", "loan_editor_view", "provider_detail_view"}:
            return function, "fixture_backed_form"
        return function, "fixture_backed_read_only"
    for prefix in prefixes:
        if path.startswith(prefix):
            # Prefix branches in the target are currently all detail/share
            # screens; preserve the exact branch name where known.
            branch = {
                "/projects/": "project_detail_view",
                "/contracts/": "contract_detail_view",
                "/expenses/": "expense_editor_view",
                "/loans/": "loan_editor_view",
                "/srm/providers/": "provider_detail_view",
                "/share/": "share_view",
            }.get(prefix)
            if branch in functions:
                if prefix == "/contracts/":
                    return branch, "connected_contract_command_form"
                if prefix == "/projects/":
                    return branch, "connected_project_read"
                if prefix == "/loans/":
                    return branch, "connected_loan_command_form"
                if prefix == "/srm/providers/":
                    return branch, "connected_supplier_read"
                if prefix == "/expenses/":
                    return branch, "connected_expense_detail_read"
                return branch, "read_only_public" if prefix == "/share/" else "fixture_backed_form"
    return None, "not_implemented"


def required_next(target_function: str | None, target_state: str) -> str:
    if target_state == "not_implemented":
        return "implement_target_view"
    if target_state == "public":
        return "connect_authenticated_identity_boundary"
    if target_state == "read_only_public":
        return "accept_public_read_scenario"
    if target_state == "read_model_only":
        if target_function == "dashboard_view":
            return "connect_authenticated_dashboard_read_model_and_accept_scope"
        return "connect_authenticated_read_and_command_api"
    if target_state == "connected_dashboard_read":
        return "accept_browser_dashboard_scenario_and_production_identity"
    if target_state == "connected_profile_read":
        return "accept_browser_profile_scenario_and_production_identity"
    if target_state == "connected_expense_read":
        return "accept_browser_expense_scenario_and_production_identity"
    if target_state == "connected_expense_detail_read":
        return "accept_browser_expense_detail_scenario_and_production_identity"
    if target_state == "connected_cost_dashboard_read":
        return "accept_browser_cost_dashboard_scenario_and_production_identity"
    if target_state == "connected_supplier_risk_read":
        return "accept_browser_supplier_risk_scenario_and_production_identity"
    if target_state == "connected_command_form":
        return "accept_production_identity_and_full_session_scenario"
    if target_state in {"connected_contract_read", "connected_contract_command_form"}:
        return "accept_browser_contract_scenario_and_production_identity"
    if target_state == "connected_payment_application_command_form":
        return "accept_browser_payment_application_scenario_and_production_identity"
    if target_state == "connected_tender_command_form":
        return "accept_browser_tender_scenario_and_production_identity"
    if target_state == "connected_supplier_read":
        return "accept_browser_supplier_scenario_and_production_identity"
    if target_state == "connected_supplier_command_form":
        return "accept_browser_supplier_scenario_and_production_identity"
    if target_state == "connected_sales_read":
        return "accept_browser_sales_scenario_and_production_identity"
    if target_state == "connected_invoice_read":
        return "accept_browser_invoice_scenario_and_production_identity"
    if target_state == "connected_delivery_command_form":
        return "accept_browser_delivery_scenario_and_production_identity"
    if target_state == "connected_report_read":
        return "accept_browser_report_scenario_and_production_identity"
    if target_state == "connected_workflow_definition_read":
        return "accept_browser_workflow_definition_scenario_and_production_identity"
    if target_state == "connected_project_read":
        return "accept_browser_project_scenario_and_production_identity"
    if target_state == "connected_project_plan_read":
        return "accept_browser_project_plan_scenario_and_production_identity"
    if target_state == "connected_loan_read":
        return "accept_browser_loan_scenario_and_production_identity"
    if target_state == "connected_loan_command_form":
        return "accept_browser_loan_command_scenario_and_finance_owner"
    if target_state == "connected_admin_health_read":
        return "accept_browser_admin_health_scenario_and_super_user_owner"
    if target_state == "connected_admin_read":
        return "accept_browser_admin_scenario_and_super_user_owner"
    if target_state == "connected_investment_read":
        return "accept_browser_investment_scenario_and_production_identity"
    if target_state == "connected_rbac_user_read":
        return "accept_browser_user_roster_scenario_and_super_user_owner"
    if target_state == "connected_admin_audit_read":
        return "accept_browser_admin_audit_scenario_and_super_user_owner"
    if target_state == "connected_cost_read":
        return "accept_browser_cost_scenario_and_production_identity"
    if target_state == "connected_cost_source_read":
        return "accept_browser_cost_source_scenario_and_production_identity"
    if target_state == "connected_budget_scope_read":
        return "accept_browser_budget_scope_scenario_and_production_identity"
    if target_state == "connected_workflow_observation_read":
        return "accept_browser_workflow_observation_scenario_and_production_identity"
    if target_state == "connected_cashflow_read":
        return "accept_browser_cashflow_scenario_and_production_identity"
    if target_state == "connected_cbs_read":
        return "accept_browser_cbs_scenario_and_production_identity"
    if target_state == "connected_fund_read":
        return "accept_browser_fund_scenario_and_production_identity"
    if target_state == "connected_warning_read":
        return "accept_browser_warning_scenario_and_production_identity"
    if target_state == "connected_attachment_read":
        return "accept_browser_attachment_scenario_and_production_identity"
    if target_state == "connected_marketing_read":
        return "accept_browser_marketing_scenario_and_production_identity"
    if target_state == "connected_notification_read":
        return "accept_browser_notification_scenario_and_production_identity"
    if target_state == "connected_admin_ocr_read":
        return "accept_browser_ocr_scenario_and_super_user_owner"
    if target_state == "connected_admin_error_read":
        return "accept_browser_error_log_scenario_and_super_user_owner"
    if target_state == "connected_ai_stats_read":
        return "accept_browser_ai_stats_scenario_and_production_identity"
    if target_state == "connected_ai_hub_read":
        return "accept_browser_ai_hub_scenario_and_production_identity"
    if target_state == "connected_webhook_read":
        return "accept_browser_webhook_scenario_and_production_identity"
    if target_state == "connected_report_builder_read":
        return "accept_browser_report_builder_scenario_and_production_identity"
    if target_state == "fixture_backed_form":
        return "connect_authenticated_read_and_command_api_and_accept_scenario"
    return "connect_authenticated_read_api_and_accept_screenshot_and_scenario"


def api_action_state(handler: dict[str, str]) -> tuple[str, str]:
    """Return only source handlers backed by an explicit target endpoint."""

    if (
        handler["module"] == "reports"
        and handler["method"] == "GET"
        and handler["path"]
        in {
            "/cost-summary",
            "/contract-payment-ledger",
            "/supplier-analysis",
            "/approval-efficiency",
            "/project-stage-matrix",
        }
    ):
        return "connected_report_read", "accept_browser_report_scenario_and_production_identity"
    if (
        handler["module"] == "loan"
        and handler["method"] == "GET"
        and handler["path"] in {"/loans", "/loans/:guid"}
    ):
        return "connected_loan_read", "accept_browser_loan_scenario_and_production_identity"
    if (
        handler["module"] == "loan"
        and handler["path"] in {
            "/loans",
            "/loans/:guid/submit-for-approval",
            "/loans/:guid/offset",
        }
        and handler["method"] == "POST"
    ):
        return "connected_loan_command", "accept_browser_loan_command_scenario_and_finance_owner"
    if (
        handler["module"] == "workflow"
        and handler["method"] == "GET"
        and handler["path"] in {"/process-defs", "/process-defs/:processKey/preview"}
    ):
        return "connected_workflow_definition_read", "accept_browser_workflow_definition_scenario_and_production_identity"
    if (
        handler["module"] == "workflow"
        and handler["method"] == "GET"
        and handler["path"] in {
            "/tasks/mine",
            "/tasks/initiated",
            "/instances/by-biz",
            "/instances/:piGuid",
            "/tasks/my-history",
        }
    ):
        return "connected_workflow_observation_read", "accept_browser_workflow_observation_scenario_and_production_identity"
    if (
        handler["module"] == "cost"
        and handler["method"] == "GET"
        and handler["path"] in {
            "/contracts",
            "/contracts/:guid",
            "/contracts/:guid/milestones",
            "/payment-applies",
            "/dynamic-cost",
        }
    ):
        return "connected_cost_source_read", "accept_browser_cost_source_scenario_and_production_identity"
    if (
        handler["module"] == "attachment"
        and handler["method"] == "GET"
        and handler["path"] in {"/list", "/all", "/stats"}
    ):
        return "connected_attachment_read", "accept_browser_attachment_scenario_and_production_identity"
    if (
        handler["module"] == "invoice"
        and handler["method"] == "GET"
        and handler["path"] in {"/in", "/out", "/tax-ledger"}
    ):
        return "connected_invoice_source_read", "accept_browser_invoice_source_scenario_and_production_identity"
    if (
        handler["module"] == "budget"
        and handler["method"] == "GET"
        and handler["path"] in {"/users-in-bu", "/my-loan-balance"}
    ):
        return "connected_budget_scope_read", "accept_browser_budget_scope_scenario_and_production_identity"
    if (
        handler["module"] == "mdm"
        and handler["method"] == "GET"
        and handler["path"] == "/business-units/tree"
    ):
        return "connected_mdm_read", "accept_browser_mdm_scenario_and_production_identity"
    if (
        handler["module"] == "mdm"
        and handler["method"] == "GET"
        and handler["path"] in {"/projects", "/projects/:projGuid/lifecycle"}
    ):
        return "connected_project_read", "accept_browser_project_scenario_and_production_identity"
    if (
        handler["module"] == "budget"
        and handler["method"] == "GET"
        and handler["path"] in {"/dict/cost-subjects", "/proceedings"}
    ):
        return "connected_budget_read", "accept_browser_budget_scenario_and_production_identity"
    if (
        handler["module"] == "investment"
        and handler["method"] == "GET"
        and handler["path"] in {
            "/projects/:projGuid/versions",
            "/versions/:versionGuid/indices",
            "/projects/:projGuid/profit-summary",
            "/meta/dimensions",
        }
    ):
        return "connected_investment_read", "accept_browser_investment_scenario_and_production_identity"
    if (
        handler["module"] == "admin"
        and handler["method"] == "GET"
        and handler["path"]
        in {
            "/dict/groups",
            "/dict/options",
            "/quality/overview",
            "/audit/logs",
            "/audit/actions",
            "/health/tables",
            "/health/bpm-pool",
        }
    ):
        return "connected_admin_read", "accept_browser_admin_scenario_and_super_user_owner"
    if (
        handler["module"] == "rbac"
        and handler["method"] == "GET"
        and handler["path"] == "/users"
    ):
        return "connected_rbac_user_read", "accept_browser_user_roster_scenario_and_super_user_owner"
    if (
        handler["module"] == "dashboard"
        and handler["method"] == "GET"
        and handler["path"]
        in {
            "/group/overview",
            "/group/funnel",
            "/group/top-anomalies",
            "/project/:projGuid/kpi",
            "/project/:projGuid/anomalies",
        }
    ):
        return "connected_dashboard_read", "accept_browser_dashboard_scenario_and_production_identity"
    if (
        handler["module"] == "auth"
        and handler["method"] == "GET"
        and handler["path"] in {"/me", "/my-initiated"}
    ):
        return "connected_profile_read", "accept_browser_profile_scenario_and_production_identity"
    if (
        handler["module"] == "budget"
        and handler["method"] == "GET"
        and handler["path"] == "/expenses"
    ):
        return "connected_expense_read", "accept_browser_expense_scenario_and_production_identity"
    if (
        handler["module"] == "budget"
        and handler["method"] == "GET"
        and handler["path"] == "/expenses/:guid"
    ):
        return "connected_expense_detail_read", "accept_browser_expense_detail_scenario_and_production_identity"
    if (
        handler["module"] == "investment"
        and handler["method"] == "GET"
        and handler["path"] == "/projects/:projGuid/profit-actual-v2"
    ):
        return "connected_cost_dashboard_read", "accept_browser_cost_dashboard_scenario_and_production_identity"
    if (
        handler["module"] == "cashflow"
        and handler["method"] == "GET"
        and handler["path"] in {
            "/forecast",
            "/forecast-v3",
            "/forecast/detail",
            "/inflow",
            "/net",
            "/gap-alert",
        }
    ):
        return "connected_cashflow_read", "accept_browser_cashflow_scenario_and_production_identity"
    if (
        handler["module"] == "cbs"
        and handler["method"] == "GET"
        and handler["path"] in {
            "/r-master",
            "/dict",
            "/dict/f-balance",
            "/versions",
            "/versions/compare",
            "/r0/queue",
            "/approval-rules",
            "/approval-rules/pick",
            "/changes",
            "/demo/contracts",
        }
    ):
        return "connected_cbs_read", "accept_browser_cbs_scenario_and_production_identity"
    if (
        handler["module"] == "fund"
        and handler["method"] == "GET"
        and handler["path"] in {"/plans", "/gap-analysis", "/dispatches"}
    ):
        return "connected_fund_read", "accept_browser_fund_scenario_and_production_identity"
    if (
        handler["module"] == "warning"
        and handler["method"] == "GET"
        and handler["path"] in {
            "/badge",
            "/",
            "/rules",
            "/scans",
            "/custom-rules",
            "/rule-templates",
            "/tickets/mine",
        }
    ):
        return "connected_warning_read", "accept_browser_warning_scenario_and_production_identity"
    if (
        handler["module"] == "attachment"
        and handler["method"] == "GET"
        and handler["path"] in {"/list", "/all", "/stats"}
    ):
        return "connected_attachment_read", "accept_browser_attachment_scenario_and_production_identity"
    if (
        handler["module"] == "marketing"
        and handler["method"] == "GET"
        and handler["path"] in {"/campaigns", "/placements", "/channels", "/materials"}
    ):
        return "connected_marketing_read", "accept_browser_marketing_scenario_and_production_identity"
    if (
        handler["module"] == "notify"
        and handler["method"] == "GET"
        and handler["path"]
        in {
            "/messages",
            "/messages/unread-count",
            "/subscriptions",
            "/config",
            "/email-outbox",
            "/digest/preview",
            "/digest/log",
            "/llm-providers",
        }
    ):
        return "connected_notification_read", "accept_browser_notification_scenario_and_production_identity"
    if (
        handler["module"] == "admin"
        and handler["method"] == "GET"
        and handler["path"] in {"/ocr/status", "/error-log"}
    ):
        return (
            "connected_admin_ocr_read"
            if handler["path"] == "/ocr/status"
            else "connected_admin_error_read",
            "accept_browser_ocr_scenario_and_super_user_owner"
            if handler["path"] == "/ocr/status"
            else "accept_browser_error_log_scenario_and_super_user_owner",
        )
    if (
        handler["module"] == "ai-stats"
        and handler["method"] == "GET"
        and handler["path"] in {"/overview", "/activity", "/badge"}
    ):
        return "connected_ai_stats_read", "accept_browser_ai_stats_scenario_and_production_identity"
    if (
        handler["module"] == "ai-hub"
        and handler["method"] == "GET"
        and handler["path"] in {
            "/corrections",
            "/correction-stats",
            "/drafts",
            "/drafts/:draftId",
            "/query-log",
            "/usage-stats",
        }
    ):
        return "connected_ai_hub_read", "accept_browser_ai_hub_scenario_and_production_identity"
    if (
        handler["module"] == "webhook"
        and handler["method"] == "GET"
        and handler["path"] == "/config"
    ):
        return "connected_webhook_read", "accept_browser_webhook_scenario_and_production_identity"
    if (
        handler["module"] == "reports"
        and handler["method"] == "GET"
        and handler["path"] in {"/templates/meta", "/templates"}
    ):
        return "connected_report_builder_read", "accept_browser_report_builder_scenario_and_production_identity"
    if (
        handler["module"] == "srm"
        and handler["method"] == "GET"
        and handler["path"] in {"/providers", "/providers/:guid", "/stats/overview"}
    ):
        return "connected_supplier_read", "accept_browser_supplier_scenario_and_production_identity"
    if (
        handler["module"] == "srm"
        and handler["method"] == "GET"
        and handler["path"] == "/providers/:guid/risk"
    ):
        return "connected_supplier_risk_read", "accept_browser_supplier_risk_scenario_and_production_identity"
    if (
        handler["module"] == "srm"
        and handler["method"] == "GET"
        and handler["path"] == "/risk-board"
    ):
        return "connected_supplier_risk_read", "accept_browser_supplier_risk_scenario_and_production_identity"
    if (
        handler["module"] == "plan"
        and handler["method"] == "GET"
        and handler["path"]
        in {
            "/projects/:projGuid/tasks",
            "/tasks/:guid",
            "/projects/:projGuid/plan-summary",
            "/tasks/:guid/delay-impact",
        }
    ):
        return "connected_project_plan_read", "accept_browser_project_plan_scenario_and_production_identity"
    if (
        handler["module"] == "loan"
        and handler["path"] == "/loans/:guid"
        and handler["method"] in {"PUT", "DELETE"}
    ):
        return "connected_loan_command", "accept_browser_loan_command_scenario_and_finance_owner"
    return (
        "not_connected",
        "connect_authenticated_read_api"
        if handler["method"] in READ_METHODS
        else "implement_authenticated_command_and_audit",
    )


def build_matrix(
    router_path: Path,
    routes_dir: Path,
    frontend_path: Path,
    output: Path,
) -> dict[str, Any]:
    routes = source_routes(router_path)
    exact, prefixes, functions = target_surface(frontend_path)
    api_stats, api_handlers = source_api_stats(routes_dir)
    rows: list[dict[str, Any]] = []
    for route in routes:
        path = route["path"]
        target_function, target_state = match_target(path, exact, prefixes, functions)
        module = module_for(path)
        stats = api_stats.get(module, {}) if module else {}
        if target_state == "read_model_only":
            api_state = "connected_fixed_read_model"
        elif target_state == "connected_dashboard_read":
            api_state = "connected_dashboard_read"
        elif target_state == "connected_profile_read":
            api_state = "connected_profile_read"
        elif target_state == "connected_expense_read":
            api_state = "connected_expense_read"
        elif target_state == "connected_expense_detail_read":
            api_state = "connected_expense_detail_read"
        elif target_state == "connected_cost_dashboard_read":
            api_state = "connected_cost_dashboard_read"
        elif target_state == "connected_cashflow_read":
            api_state = "connected_cashflow_read"
        elif target_state == "connected_cbs_read":
            api_state = "connected_cbs_read"
        elif target_state == "connected_fund_read":
            api_state = "connected_fund_read"
        elif target_state == "connected_warning_read":
            api_state = "connected_warning_read"
        elif target_state == "connected_attachment_read":
            api_state = "connected_attachment_read"
        elif target_state == "connected_marketing_read":
            api_state = "connected_marketing_read"
        elif target_state == "connected_notification_read":
            api_state = "connected_notification_read"
        elif target_state == "connected_admin_ocr_read":
            api_state = "connected_admin_ocr_read"
        elif target_state == "connected_admin_error_read":
            api_state = "connected_admin_error_read"
        elif target_state == "connected_ai_stats_read":
            api_state = "connected_ai_stats_read"
        elif target_state == "connected_ai_hub_read":
            api_state = "connected_ai_hub_read"
        elif target_state == "connected_webhook_read":
            api_state = "connected_webhook_read"
        elif target_state == "connected_report_builder_read":
            api_state = "connected_report_builder_read"
        elif target_state == "connected_supplier_risk_read":
            api_state = "connected_supplier_risk_read"
        elif target_state == "connected_command_form":
            api_state = "connected_expense_command"
        elif target_state in {"connected_contract_read", "connected_contract_command_form"}:
            api_state = "connected_contract_command"
        elif target_state == "connected_payment_application_command_form":
            api_state = "connected_payment_application_command"
        elif target_state == "connected_tender_command_form":
            api_state = "connected_tender_command"
        elif target_state == "connected_supplier_read":
            api_state = "connected_supplier_read"
        elif target_state == "connected_supplier_command_form":
            api_state = "connected_supplier_command"
        elif target_state == "connected_sales_read":
            api_state = "connected_sales_read"
        elif target_state == "connected_invoice_read":
            api_state = "connected_invoice_read"
        elif target_state == "connected_delivery_command_form":
            api_state = "connected_delivery_command"
        elif target_state == "connected_report_read":
            api_state = "connected_report_read"
        elif target_state == "connected_workflow_definition_read":
            api_state = "connected_workflow_definition_read"
        elif target_state == "connected_project_read":
            api_state = "connected_project_read"
        elif target_state == "connected_loan_command_form":
            api_state = "connected_loan_command"
        elif target_state == "connected_loan_read":
            api_state = "connected_loan_read"
        elif target_state == "connected_admin_health_read":
            api_state = "connected_admin_health_read"
        elif target_state == "connected_admin_read":
            api_state = "connected_admin_read"
        elif target_state == "connected_investment_read":
            api_state = "connected_investment_read"
        elif target_state == "connected_rbac_user_read":
            api_state = "connected_rbac_user_read"
        elif target_state == "connected_admin_audit_read":
            api_state = "connected_admin_audit_read"
        elif target_state == "connected_cost_read":
            api_state = "connected_cost_read"
        elif target_function is None:
            api_state = "not_connected"
        elif stats.get("mutation_handler_count", 0) > 0:
            api_state = "read_only_fixture_no_source_api"
        else:
            api_state = "read_only_fixture_no_source_api"
        rows.append(
            {
                "path": path,
                "source_component": route["component"],
                "source_redirect": route["redirect"],
                "public": route["public"],
                "target_function": target_function,
                "target_state": target_state,
                "source_api_module": module,
                "source_api_handler_count": stats.get("handler_count", 0),
                "source_api_read_handler_count": stats.get("read_handler_count", 0),
                "source_api_mutation_handler_count": stats.get("mutation_handler_count", 0),
                "api_state": api_state,
                "required_next": required_next(target_function, target_state),
            }
        )
    state_counts = Counter(row["target_state"] for row in rows)
    api_counts = Counter(row["api_state"] for row in rows)
    source_handlers = sum(item["handler_count"] for item in api_stats.values())
    source_mutations = sum(item["mutation_handler_count"] for item in api_stats.values())
    report = {
        "format": "moonproj.erp.ui-parity-matrix.v1",
        "source_router": str(router_path),
        "source_routes_dir": str(routes_dir),
        "target_frontend": str(frontend_path),
        "source_browser_route_count": len(routes),
        "source_api_handler_count": source_handlers,
        "source_api_mutation_handler_count": source_mutations,
        "target_exact_route_count": len(exact),
        "target_dynamic_prefix_count": len(prefixes),
        "target_state_counts": dict(sorted(state_counts.items())),
        "api_state_counts": dict(sorted(api_counts.items())),
        "routes": rows,
        "api_handlers": [
            {
                **handler,
                "browser_route_paths": [
                    row["path"] for row in rows if row["source_api_module"] == handler["module"]
                ],
                "action_state": api_action_state(handler)[0],
                "required_next": api_action_state(handler)[1],
            }
            for handler in api_handlers
        ],
        "state": "functional_parity_incomplete",
        "cutover_authorized": False,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def render_markdown(report: dict[str, Any]) -> str:
    lines = [
        "# ERP UI and API parity matrix",
        "",
        "Generated from `../erp/erp_new/web/src/router/index.js`, the source",
        "`server/src/routes` directory, and `frontend/main/main.mbt`. This is an",
        "acceptance register, not a completion claim: mounted fixture screens do",
        "not count as connected company behavior. The generic PostgreSQL",
        "summary/read-model adapter is not dashboard parity; the three dashboard",
        "aliases now use the bounded connected v1 read. The connected exceptions are the local",
        "expense/contract/payment-application/tender command, supplier-provider, supplier, and supplier-risk reads,",
        "MDM organization/project master, budget dictionary, investment, admin governance reads, delivery, core report read,",
        "profile read, project-plan read, non-authorizing workflow-definition, cashflow, CBS,",
        "fund-plan, observed-warning, attachment-metadata, marketing, notification metadata, OCR-status, error-log, AI-analytics, AI Hub observation, webhook-configuration, and report-builder metadata read verticals.",
        "",
        f"- Browser routes: **{report['source_browser_route_count']}**",
        f"- Source API handlers: **{report['source_api_handler_count']}** ({report['source_api_mutation_handler_count']} mutations)",
        f"- Target states: `{json.dumps(report['target_state_counts'], ensure_ascii=False, sort_keys=True)}`",
        f"- API states: `{json.dumps(report['api_state_counts'], ensure_ascii=False, sort_keys=True)}`",
        f"- Matrix state: **{report['state']}**",
        "",
        "## Browser routes",
        "",
        "| Source route | Source view | Rabbita view | UI state | API module | GET / mutation handlers | API state | Required next |",
        "|---|---|---|---|---|---:|---|---|",
    ]
    for row in report["routes"]:
        source_view = row["source_component"] or ("redirect → " + row["source_redirect"] if row["source_redirect"] else "—")
        target_view = row["target_function"] or "—"
        counts = f"{row['source_api_read_handler_count']} / {row['source_api_mutation_handler_count']}"
        lines.append(
            f"| `{row['path']}` | `{source_view}` | `{target_view}` | "
            f"`{row['target_state']}` | `{row['source_api_module']}` | {counts} | "
            f"`{row['api_state']}` | `{row['required_next']}` |"
        )
    lines.extend(
        [
            "",
            "## API actions",
            "",
            "Every source handler remains an explicit action item until an",
            "authenticated target read/command path, authorization decision,",
            "idempotency key, durable audit evidence, and a role-based scenario",
            "are attached. The JSON output contains all 338 handler rows.",
            "",
            "| Module | Method | Source path | Browser routes | Current state | Required next |",
            "|---|---|---|---|---|---|",
        ]
    )
    for handler in report["api_handlers"]:
        browser_paths = ", ".join(f"`{path}`" for path in handler["browser_route_paths"])
        lines.append(
            f"| `{handler['module']}` | `{handler['method']}` | `{handler['path']}` | "
            f"{browser_paths or '—'} | `{handler['action_state']}` | "
            f"`{handler['required_next']}` |"
        )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_router", type=Path)
    parser.add_argument("source_routes_dir", type=Path)
    parser.add_argument("target_frontend", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    args = parser.parse_args()
    try:
        report = build_matrix(
            args.source_router,
            args.source_routes_dir,
            args.target_frontend,
            args.output,
        )
        if args.markdown_output is not None:
            args.markdown_output.parent.mkdir(parents=True, exist_ok=True)
            args.markdown_output.write_text(render_markdown(report), encoding="utf-8")
        print(
            json.dumps(
                {
                    "output": str(args.output),
                    "source_browser_route_count": report["source_browser_route_count"],
                    "source_api_handler_count": report["source_api_handler_count"],
                    "source_api_mutation_handler_count": report["source_api_mutation_handler_count"],
                    "target_state_counts": report["target_state_counts"],
                    "api_state_counts": report["api_state_counts"],
                    "state": report["state"],
                },
                sort_keys=True,
            )
        )
        return 0
    except (OSError, MatrixError) as error:
        print(f"ERP UI parity matrix failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
