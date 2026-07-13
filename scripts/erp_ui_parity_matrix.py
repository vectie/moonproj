#!/usr/bin/env python3
"""Build a source-to-Rabbita UI and API parity matrix.

The ERP route inventory answers *which server handlers exist*.  This report
answers the next migration question: for every source browser route, which
Rabbita view is mounted, whether it is a real/read-model/fixture surface, and
which source API module still needs a connected command/read workflow.

The report is intentionally evidence-oriented.  A mounted page is not marked
functional merely because it renders: the dashboard's fixed summary read-model
and the local expense/contract/payment-application/tender/supplier/sales read
verticals are explicitly identified, including the delivery/project-progress
runtime and the non-authorizing workflow-definition read boundary, while no
workflow-instance mutation endpoint is inferred.
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
        return "dashboard_view", "read_model_only"
    if path in exact:
        function = exact[path]
        if function == "placeholder_view":
            return function, "not_implemented"
        if path.startswith("/share"):
            return function, "read_only_public"
        if function == "dashboard_view":
            return function, "read_model_only"
        if path == "/expenses/new" and function == "expense_editor_view":
            return function, "connected_command_form"
        if path == "/contracts" and function == "contracts_view":
            return function, "connected_contract_read"
        if path == "/payment-applies" and function == "payment_applies_view":
            return function, "connected_payment_application_command_form"
        if path == "/tender" and function == "tender_view":
            return function, "connected_tender_command_form"
        if path == "/srm/providers" and function == "srm_providers_view":
            return function, "connected_supplier_command_form"
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
        return "connect_authenticated_read_and_command_api"
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
        handler["module"] == "mdm"
        and handler["method"] == "GET"
        and handler["path"] in {"/projects", "/projects/:projGuid/lifecycle"}
    ):
        return "connected_project_read", "accept_browser_project_scenario_and_production_identity"
    if (
        handler["module"] == "plan"
        and handler["method"] == "GET"
        and handler["path"]
        in {
            "/projects/:projGuid/tasks",
            "/tasks/:guid",
            "/projects/:projGuid/plan-summary",
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
        "not count as connected company behavior. The connected exceptions are",
        "the fixed dashboard read-model and the local",
        "expense/contract/payment-application/tender command, supplier read,",
        "project master read, delivery, core report read, employee-loan",
        "read/command, project-plan read, and non-authorizing workflow-definition",
        "read verticals.",
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
