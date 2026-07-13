#!/usr/bin/env python3
"""Serve a read-only PostgreSQL company projection API for local development.

This is a deliberately small adapter for the Rabbita browser surface.  It
exposes only fixed read-model queries; it never accepts arbitrary SQL and has
no mutation endpoints.  It covers company, procurement, sales/receivables,
reviewed invoice, and delivery/project-progress projections. Production authentication, pooling, TLS,
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
    contracts as service_contracts,
    contract_milestones as service_contract_milestones,
    payment_applications as service_payment_applications,
    payment_application_eligibility as service_payment_application_eligibility,
    suppliers as service_suppliers,
    supplier_risk as service_supplier_risk,
    supplier_risk_board as service_supplier_risk_board,
    tenders as service_tenders,
    contract_splits as service_contract_splits,
    sales_rows as service_sales_rows,
    delivery_progress as service_delivery_progress,
    delivery_outputs as service_delivery_outputs,
    delivery_tasks as service_delivery_tasks,
    delivery_task_reports as service_delivery_task_reports,
    delivery_plan_summary as service_delivery_plan_summary,
    delivery_overview as service_delivery_overview,
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


def supplier_risk(args: argparse.Namespace, supplier_id: str) -> dict[str, Any] | None:
    return service_supplier_risk(_ReadModelPool(args), supplier_id)


def supplier_risk_board(args: argparse.Namespace) -> list[dict[str, Any]]:
    return service_supplier_risk_board(_ReadModelPool(args), 500)


def contract_splits(
    args: argparse.Namespace,
    split_id: str | None,
    parent_contract_id: str | None,
) -> list[dict[str, Any]]:
    return service_contract_splits(_ReadModelPool(args), split_id, parent_contract_id, 500)


def sales_rows(args: argparse.Namespace, family: str, aggregate_id: str | None) -> list[dict[str, Any]]:
    return service_sales_rows(_ReadModelPool(args), family, aggregate_id, 500)


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
                if parsed.path == "/api/company/receipts":
                    response(self, 200, {"items": receipts(args)})
                    return
                if parsed.path == "/api/company/projections":
                    value = parse_qs(parsed.query).get("aggregate_type", [None])[0]
                    response(self, 200, {"items": projections(args, value)})
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
                if parsed.path == "/api/company/supplier-risk-board":
                    response(self, 200, {"items": supplier_risk_board(args)})
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
                if parsed.path == "/api/company/delivery/progress":
                    query = parse_qs(parsed.query)
                    rows = delivery_progress(
                        args,
                        query.get("progress_id", [None])[0],
                        query.get("project_id", [None])[0],
                    )
                    response(self, 200, {"items": rows})
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
