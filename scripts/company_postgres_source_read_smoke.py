#!/usr/bin/env python3
"""Read-only smoke coverage for the evidence-ready source read batch."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

from company_postgres_service_smoke import SmokeError, request, wait_for


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise SmokeError(message)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", default="moonproj")
    parser.add_argument("--port", type=int, default=4187)
    parser.add_argument("--psql", default=None)
    args = parser.parse_args()
    token = "moonproj-source-read-smoke-token"
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
    process = subprocess.Popen(
        command,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        wait_for(args.port, time.monotonic() + 10)
        status, contracts = request(
            args.port, "/api/company/source/cost/contracts", token=token,
        )
        expect(
            status == 200
            and contracts is not None
            and len(contracts.get("data", [])) == 2
            and contracts.get("source_coverage", {}).get("cb_contract") == 2
            and contracts.get("authorizing") is False,
            f"source contract list failed: {status} {contracts}",
        )
        status, detail = request(
            args.port, "/api/company/source/cost/contracts/ht-tj-001", token=token,
        )
        detail_contract = (detail or {}).get("data", {}).get("contract", {})
        expect(
            status == 200
            and detail is not None
            and detail_contract.get("contractGuid") == "ht-tj-001"
            and detail_contract.get("paid_amount_display") == "¥3,600,000.00"
            and len((detail.get("data") or {}).get("plans", [])) == 3
            and len((detail.get("data") or {}).get("applies", [])) == 2,
            f"source contract detail failed: {status} {detail}",
        )
        status, milestones = request(
            args.port,
            "/api/company/source/cost/contracts/ht-tj-001/milestones",
            token=token,
        )
        expect(
            status == 200
            and milestones is not None
            and milestones.get("data") == []
            and milestones.get("source_coverage", {}).get("cb_contract_milestone") == 0
            and milestones.get("authorizing") is False,
            f"source milestone empty boundary failed: {status} {milestones}",
        )
        status, applies = request(
            args.port, "/api/company/source/cost/payment-applies?view=all", token=token,
        )
        expect(
            status == 200
            and applies is not None
            and len(applies.get("data", [])) == 3
            and applies.get("source_coverage", {}).get("cb_htfk_apply") == 3
            and applies.get("authorizing") is False,
            f"source payment application read failed: {status} {applies}",
        )
        status, dynamic = request(
            args.port,
            "/api/company/cost/dynamic-cost?projGuid=proj-0001",
            token=token,
        )
        dynamic_data = (dynamic or {}).get("data", {})
        dynamic_summary = dynamic_data.get("summary", {})
        expect(
            status == 200
            and dynamic is not None
            and len(dynamic_data.get("items", [])) == 7
            and dynamic_summary.get("endCount") == 6
            and dynamic_summary.get("A_targetCost") == 35900000.0
            and dynamic_summary.get("B_dtCost") == 36350000.0
            and dynamic.get("source_coverage", {}).get("cb_cost") == 7,
            f"source dynamic-cost read failed: {status} {dynamic}",
        )
        status, attachment_all = request(
            args.port, "/api/company/attachments/all", token=token,
        )
        attachment_all_data = (attachment_all or {}).get("data", {})
        expect(
            status == 200
            and attachment_all is not None
            and attachment_all_data.get("total") == 0
            and attachment_all_data.get("rows") == []
            and attachment_all.get("source_coverage", {}).get("attachment") == 0
            and attachment_all.get("downloadable") is False
            and attachment_all.get("authorizing") is False,
            f"source attachment metadata read failed: {status} {attachment_all}",
        )
        status, attachment_stats = request(
            args.port, "/api/company/attachments/stats", token=token,
        )
        expect(
            status == 200
            and attachment_stats is not None
            and (attachment_stats.get("data") or {}).get("total") == {"count": 0, "bytes": 0}
            and attachment_stats.get("authorizing") is False,
            f"source attachment stats read failed: {status} {attachment_stats}",
        )
        for direction in ("in", "out"):
            status, invoice_rows = request(
                args.port,
                f"/api/company/source/invoice/{direction}?projGuid=proj-0001",
                token=token,
            )
            expect(
                status == 200
                and invoice_rows is not None
                and invoice_rows.get("data") == []
                and invoice_rows.get("source_coverage", {}).get("invoice_" + direction) == 0
                and invoice_rows.get("authorizing") is False,
                f"source invoice {direction} read failed: {status} {invoice_rows}",
            )
        status, tax_ledger = request(
            args.port,
            "/api/company/source/invoice/tax-ledger?projGuid=proj-0001",
            token=token,
        )
        expect(
            status == 200
            and tax_ledger is not None
            and (tax_ledger.get("data") or {}).get("rows") == []
            and tax_ledger.get("authorizing") is False,
            f"source invoice tax ledger read failed: {status} {tax_ledger}",
        )
        status, source_progress = request(
            args.port,
            "/api/company/source/delivery/progress?projGuid=proj-0001",
            token=token,
        )
        expect(
            status == 200
            and source_progress is not None
            and source_progress.get("data") == []
            and source_progress.get("source_coverage", {}).get("proj_progress") == 0
            and source_progress.get("authorizing") is False
            and source_progress.get("persisted") is False,
            f"source delivery progress empty boundary failed: {status} {source_progress}",
        )
        status, source_outputs = request(
            args.port,
            "/api/company/source/delivery/outputs?projGuid=proj-0001",
            token=token,
        )
        expect(
            status == 200
            and source_outputs is not None
            and source_outputs.get("data") == []
            and source_outputs.get("source_coverage", {}).get("proj_output") == 0
            and source_outputs.get("authorizing") is False
            and source_outputs.get("persisted") is False,
            f"source delivery outputs empty boundary failed: {status} {source_outputs}",
        )
        for family, table in (
            ("customers", "sale_customer"),
            ("subscriptions", "sale_subscription"),
            ("contracts", "sale_contract"),
            ("mortgages", "sale_mortgage"),
            ("refunds", "sale_refund"),
            ("revenues", "sale_revenue"),
        ):
            status, sales_source = request(
                args.port,
                f"/api/company/source/sales/{family}?projGuid=proj-0001",
                token=token,
            )
            expect(
                status == 200
                and sales_source is not None
                and sales_source.get("data") == []
                and sales_source.get("source_coverage", {}).get(table) == 0
                and sales_source.get("authorizing") is False
                and sales_source.get("persisted") is False,
                f"source sales {family} empty boundary failed: {status} {sales_source}",
            )
        for family, table in (
            ("tenders", "tender_plan"),
            ("awards", "tender_award"),
            ("splits", "contract_split"),
        ):
            status, tender_source = request(
                args.port,
                f"/api/company/source/tender/{family}?projGuid=proj-0001",
                token=token,
            )
            expect(
                status == 200
                and tender_source is not None
                and tender_source.get("data") == []
                and tender_source.get("source_coverage", {}).get(table) == 0
                and tender_source.get("authorizing") is False
                and tender_source.get("persisted") is False,
                f"source tender {family} empty boundary failed: {status} {tender_source}",
            )
        status, categories = request(
            args.port,
            "/api/company/source/srm/categories",
            token=token,
        )
        expect(
            status == 200
            and categories is not None
            and categories.get("data") == []
            and categories.get("source_coverage", {}).get("srm_category") == 0
            and categories.get("authorizing") is False
            and categories.get("persisted") is False,
            f"source supplier categories empty boundary failed: {status} {categories}",
        )
        for path, expected_count in (
            ("/api/company/source/srm/dict/eval-results", 6),
            ("/api/company/source/srm/dict/sources", 4),
        ):
            status, dictionary = request(args.port, path, token=token)
            expect(
                status == 200
                and dictionary is not None
                and len(dictionary.get("data", [])) == expected_count
                and dictionary.get("authorizing") is False
                and dictionary.get("persisted") is False,
                f"source supplier dictionary read failed: {status} {dictionary}",
            )
        status, scope = request(
            args.port,
            "/api/company/source/budget/users-in-bu?buGuid=bu-tjgs-0001",
            token=token,
        )
        expect(
            status == 200
            and scope is not None
            and len(scope.get("data", [])) == 4
            and scope.get("scope_applied") is True
            and scope.get("authorizing") is False,
            f"source budget scope read failed: {status} {scope}",
        )
        status, balance = request(
            args.port,
            "/api/company/source/budget/my-loan-balance?userCode=limingjin",
            token=token,
        )
        balance_data = (balance or {}).get("data", {})
        expect(
            status == 200
            and balance_data.get("total") == 3500.0
            and len(balance_data.get("loans", [])) == 1
            and balance.get("scope_applied") is True
            and balance.get("authorizing") is False,
            f"source loan balance read failed: {status} {balance}",
        )
        for path in (
            "/api/company/source/workflow/tasks/mine?userCode=limingjin",
            "/api/company/source/workflow/tasks/initiated?userCode=limingjin",
            "/api/company/source/workflow/tasks/my-history?userCode=limingjin",
        ):
            status, workflow = request(args.port, path, token=token)
            expect(
                status == 200
                and workflow is not None
                and workflow.get("data") == []
                and workflow.get("source_coverage", {}).get("wf_process_instance") == 0
                and workflow.get("authorizing") is False,
                f"source workflow empty boundary failed: {status} {workflow}",
            )
        status, by_biz = request(
            args.port,
            "/api/company/source/workflow/instances/by-biz?bizType=Expense&bizDataGuid=EXP-260712-008",
            token=token,
        )
        expect(
            status == 200
            and by_biz is not None
            and by_biz.get("data") is None
            and by_biz.get("authorizing") is False,
            f"source workflow by-biz empty boundary failed: {status} {by_biz}",
        )
        status, missing = request(
            args.port,
            "/api/company/source/workflow/instances/missing-instance",
            token=token,
        )
        expect(
            status == 404
            and missing is not None
            and missing.get("code") == 43001,
            f"source workflow detail 404 failed: {status} {missing}",
        )
        print(
            "source-read-smoke: contracts=2 payment_applies=3 dynamic_cost=7 "
            "attachments=0 invoices=0 budget_users=4 loan_balance=3500 "
            "workflow_instances=0 workflow_actions=0 progress=0 outputs=0 "
            "sales_customers=0 sales_revenues=0 tender_plans=0 tender_awards=0 "
            "supplier_categories=0 supplier_eval=6 supplier_sources=4",
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
    except SmokeError as error:
        print(f"source-read-smoke: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
