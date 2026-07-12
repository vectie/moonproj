#!/usr/bin/env python3
"""Reconcile reviewed source-to-journal links against promoted projections.

This check proves identity, principal, amount, currency, and durable-link
continuity. It intentionally does not post journals, release cash, or certify
period-close accounting.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path
from typing import Any

from company_sqlite_rehearsal import RehearsalError


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RehearsalError(f"cannot read accounting reconciliation input: {path}") from error
    if not isinstance(value, dict):
        raise RehearsalError(f"input is not an object: {path}")
    return value


def run(
    domain_path: Path,
    plan_path: Path,
    receipt_path: Path,
    database_path: Path,
    output_path: Path,
) -> dict[str, Any]:
    domain = load(domain_path)
    plan = load(plan_path)
    receipt = load(receipt_path)
    if domain.get("format") != "moonproj.erp.domain-promotion.v1":
        raise RehearsalError("unexpected domain promotion format")
    if plan.get("format") != "moonproj.erp.accounting-link-plan.v1":
        raise RehearsalError("unexpected accounting-link plan format")
    if receipt.get("format") != "moonproj.erp.accounting-link-receipt.v1":
        raise RehearsalError("unexpected accounting-link receipt format")
    if receipt.get("state") != "validated_accounting_links":
        raise RehearsalError("accounting-link receipt is not validated")

    domain_items = {
        (str(item.get("source_table")), str(item.get("source_id"))): item
        for item in domain.get("accepted_items", [])
        if isinstance(item, dict)
    }
    plan_items = [item for item in plan.get("items", []) if isinstance(item, dict)]
    receipt_items = {
        (str(item.get("source_table")), str(item.get("source_id"))): item
        for item in receipt.get("accepted_items", [])
        if isinstance(item, dict)
    }
    if not plan_items or not receipt_items:
        raise RehearsalError("accounting reconciliation has no accepted items")
    if any(item.get("disposition") != "ready_for_domain_import" for item in plan_items):
        raise RehearsalError("accounting plan contains quarantined items")

    connection = sqlite3.connect(database_path)
    checks: list[dict[str, Any]] = []
    try:
        integrity = str(connection.execute("PRAGMA integrity_check").fetchone()[0])
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
            if not isinstance(domain_candidate, dict):
                raise RehearsalError(f"missing promoted candidate at {source_key[0]}:{source_key[1]}")
            journal = candidate.get("journal")
            if not isinstance(journal, dict):
                raise RehearsalError(f"missing journal mapping at {source_key[0]}:{source_key[1]}")
            if candidate.get("principal_id") != domain_candidate.get("principal_id"):
                raise RehearsalError(f"principal_id mismatch at {source_key[0]}:{source_key[1]}")
            domain_amount = domain_candidate.get("amount_minor")
            if domain_item.get("target_type") == "payment_application":
                application = domain_candidate.get("application")
                domain_amount = application.get("amount_minor") if isinstance(application, dict) else None
            if journal.get("amount_minor") != domain_amount:
                raise RehearsalError(f"amount_minor mismatch at {source_key[0]}:{source_key[1]}")
            if journal.get("currency") != domain_candidate.get("currency"):
                raise RehearsalError(f"currency mismatch at {source_key[0]}:{source_key[1]}")
            event_id = str(receipt_item.get("event_id"))
            row = connection.execute(
                "SELECT source_type, source_id, journal_id, principal_id "
                "FROM company_accounting_event_link WHERE event_id = ?",
                (event_id,),
            ).fetchone()
            expected = (
                str(receipt_item.get("source_type")),
                str(receipt_item.get("source_id")),
                str(receipt_item.get("journal_id")),
                str(receipt_item.get("principal_id")),
            )
            if row is None or tuple(row) != expected:
                raise RehearsalError(f"durable accounting link mismatch at {event_id}")
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
    finally:
        connection.close()

    report = {
        "format": "moonproj.erp.accounting-reconciliation.v1",
        "source_snapshot_id": receipt.get("source_snapshot_id"),
        "mapping_version": receipt.get("mapping_version"),
        "state": "reconciled",
        "integrity": integrity,
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
    parser.add_argument("database", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        report = run(
            args.domain_receipt,
            args.accounting_plan,
            args.accounting_receipt,
            args.database,
            args.output,
        )
        print(json.dumps({"output": str(args.output), "state": report["state"], "link_count": report["link_count"]}, sort_keys=True))
        return 0
    except (OSError, RehearsalError, sqlite3.Error) as error:
        print(f"company accounting reconciliation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
