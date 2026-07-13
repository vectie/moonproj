#!/usr/bin/env python3
"""Reconcile reviewed accounting links against durable PostgreSQL rows.

The report proves source identity, principal, amount, currency, and journal
continuity for one reviewed domain/accounting cohort. It never posts a journal,
releases cash, or certifies a period close.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from company_postgres_target_apply import (
    PostgresTargetError,
    run_psql,
    schema,
    sql_literal,
)
from company_sqlite_accounting_link_apply import load_receipt
from company_sqlite_rehearsal import RehearsalError


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RehearsalError(f"cannot read accounting reconciliation input: {path}") from error
    if not isinstance(value, dict):
        raise RehearsalError(f"accounting reconciliation input is not an object: {path}")
    return value


def durable_link(args: argparse.Namespace, event_id: str) -> tuple[str, ...] | None:
    query = f"""
SELECT encode(convert_to(source_type, 'UTF8'), 'hex'),
       encode(convert_to(source_id, 'UTF8'), 'hex'),
       encode(convert_to(journal_id, 'UTF8'), 'hex'),
       encode(convert_to(principal_id, 'UTF8'), 'hex')
FROM company_accounting_event_link
WHERE event_id = {sql_literal(event_id)}
"""
    lines = [line for line in run_psql(args, "\n".join(line.strip() for line in query.splitlines() if line.strip())).splitlines() if line]
    if not lines:
        return None
    if len(lines) != 1:
        raise RehearsalError(f"duplicate PostgreSQL accounting link at {event_id}")
    fields = lines[0].split("|")
    if len(fields) != 4:
        raise RehearsalError("unexpected PostgreSQL accounting-link row")
    try:
        return tuple(bytes.fromhex(field).decode("utf-8") for field in fields)
    except (ValueError, UnicodeDecodeError) as error:
        raise RehearsalError("invalid PostgreSQL accounting-link row") from error


def run(
    args: argparse.Namespace,
    domain_path: Path,
    plan_path: Path,
    receipt_path: Path,
    output_path: Path,
) -> dict[str, Any]:
    domain = load_json(domain_path)
    plan = load_json(plan_path)
    receipt = load_receipt(receipt_path)
    if domain.get("format") != "moonproj.erp.domain-promotion.v1":
        raise RehearsalError("unexpected domain promotion format")
    if plan.get("format") != "moonproj.erp.accounting-link-plan.v1":
        raise RehearsalError("unexpected accounting-link plan format")
    domain_items = {
        (str(item.get("source_table")), str(item.get("source_id"))): item
        for item in domain.get("accepted_items", [])
        if isinstance(item, dict)
    }
    receipt_items = {
        (str(item.get("source_table")), str(item.get("source_id"))): item
        for item in receipt.get("accepted_items", [])
        if isinstance(item, dict)
    }
    plan_items = [item for item in plan.get("items", []) if isinstance(item, dict)]
    if not plan_items or not receipt_items:
        raise RehearsalError("accounting reconciliation has no accepted items")
    if any(item.get("disposition") != "ready_for_domain_import" for item in plan_items):
        raise RehearsalError("accounting plan contains quarantined items")

    checks: list[dict[str, Any]] = []
    for item in plan_items:
        source_key = (str(item.get("source_table")), str(item.get("source_id")))
        domain_item = domain_items.get(source_key)
        receipt_item = receipt_items.get(source_key)
        candidate = item.get("target_candidate")
        if not isinstance(domain_item, dict) or not isinstance(receipt_item, dict):
            raise RehearsalError(f"missing domain or receipt identity at {source_key[0]}:{source_key[1]}")
        if not isinstance(candidate, dict):
            raise RehearsalError(f"missing accounting candidate at {source_key[0]}:{source_key[1]}")
        domain_candidate = domain_item.get("target_candidate")
        journal = candidate.get("journal")
        if not isinstance(domain_candidate, dict) or not isinstance(journal, dict):
            raise RehearsalError(f"missing candidate or journal at {source_key[0]}:{source_key[1]}")
        if candidate.get("principal_id") != domain_candidate.get("principal_id"):
            raise RehearsalError(f"principal_id mismatch at {source_key[0]}:{source_key[1]}")
        domain_amount = domain_candidate.get("amount_minor")
        if domain_item.get("target_type") == "payment_application":
            application = domain_candidate.get("application")
            domain_amount = application.get("amount_minor") if isinstance(application, dict) else None
        elif domain_amount is None:
            for amount_field in (
                "completed_value_minor",
                "tax_amount_minor",
                "reported_tax_amount_minor",
                "notional_minor",
                "actual_amount_minor",
            ):
                if amount_field in domain_candidate:
                    domain_amount = domain_candidate.get(amount_field)
                    break
        if journal.get("amount_minor") != domain_amount:
            raise RehearsalError(f"amount_minor mismatch at {source_key[0]}:{source_key[1]}")
        if journal.get("currency") != domain_candidate.get("currency"):
            raise RehearsalError(f"currency mismatch at {source_key[0]}:{source_key[1]}")
        event_id = str(receipt_item.get("event_id"))
        actual = durable_link(args, event_id)
        expected = (
            str(receipt_item.get("source_type")),
            str(receipt_item.get("source_id")),
            str(receipt_item.get("journal_id")),
            str(receipt_item.get("principal_id")),
        )
        if actual != expected:
            raise RehearsalError(f"durable PostgreSQL accounting link mismatch at {event_id}")
        checks.append(
            {
                "source_table": source_key[0],
                "source_id": source_key[1],
                "event_id": event_id,
                "journal_id": expected[2],
                "principal_id": expected[3],
                "amount_minor": journal.get("amount_minor"),
                "currency": journal.get("currency"),
            }
        )

    report = {
        "format": "moonproj.erp.accounting-reconciliation.v1",
        "backend": "postgres",
        "source_snapshot_id": receipt.get("source_snapshot_id"),
        "mapping_version": receipt.get("mapping_version"),
        "state": "reconciled",
        "integrity": "ok",
        "link_count": len(checks),
        "checks": checks,
        "cash_released": False,
        "period_posted": False,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("domain_receipt", type=Path)
    parser.add_argument("accounting_plan", type=Path)
    parser.add_argument("accounting_receipt", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--schema", type=Path, default=Path(__file__).with_name("postgres_target_schema.sql"))
    parser.add_argument("--psql", default=None)
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", default=None)
    parser.add_argument("--user", default=None)
    parser.add_argument("--database-name", dest="database", default="moonproj")
    args = parser.parse_args()
    try:
        schema(args)
        report = run(args, args.domain_receipt, args.accounting_plan, args.accounting_receipt, args.output)
        print(json.dumps({"output": str(args.output), "state": report["state"], "link_count": report["link_count"]}, sort_keys=True))
        return 0
    except (OSError, RehearsalError, PostgresTargetError, ValueError) as error:
        print(f"company PostgreSQL accounting reconciliation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
