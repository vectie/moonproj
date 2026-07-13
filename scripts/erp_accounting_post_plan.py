#!/usr/bin/env python3
"""Compile an explicit reviewed accounting-link cohort into a posting plan.

Posting is intentionally downstream of source-to-journal validation.  The
planner accepts only the native link-plan shape, an explicit chart/period, and
an allow-listed set of link event IDs.  It never derives accounts, amounts, or
periods from ERP rows.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class PlanError(RuntimeError):
    pass


ACCOUNT_KINDS = {"asset", "liability", "equity", "revenue", "expense"}


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error
    if not isinstance(value, dict):
        raise PlanError(f"JSON root is not an object: {path}")
    return value


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("accounting_link_plan", type=Path)
    parser.add_argument("accounting_link_receipt", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        link_plan = load(args.accounting_link_plan)
        link_receipt = load(args.accounting_link_receipt)
        config = load(args.mapping)
        if link_plan.get("format") != "moonproj.erp.accounting-link-plan.v1":
            raise PlanError("unexpected accounting-link plan format")
        if link_receipt.get("format") != "moonproj.erp.accounting-link-receipt.v1":
            raise PlanError("unexpected accounting-link receipt format")
        if link_receipt.get("state") != "validated_accounting_links":
            raise PlanError("accounting-link receipt is not native-validated")
        if config.get("format") != "moonproj.erp.accounting-posting-map.v1":
            raise PlanError("unexpected accounting-posting mapping format")
        if config.get("reviewed") is not True:
            raise PlanError("accounting-posting mapping is not reviewed")
        source_snapshot_id = require_string(link_plan.get("source_snapshot_id"), "source_snapshot_id")
        if link_receipt.get("source_snapshot_id") != source_snapshot_id:
            raise PlanError("accounting-link plan/receipt source snapshot mismatch")
        receipt_items = link_receipt.get("accepted_items")
        if not isinstance(receipt_items, list) or not receipt_items:
            raise PlanError("accounting-link receipt has no accepted items")
        receipt_by_event: dict[str, tuple[str, str, str, str]] = {}
        for item in receipt_items:
            if not isinstance(item, dict):
                raise PlanError("accounting-link receipt item is not an object")
            event_id = require_string(item.get("event_id"), "accounting-link receipt event_id")
            identity = (
                require_string(item.get("source_type"), f"receipt {event_id}.source_type"),
                require_string(item.get("source_id"), f"receipt {event_id}.source_id"),
                require_string(item.get("principal_id"), f"receipt {event_id}.principal_id"),
                require_string(item.get("journal_id"), f"receipt {event_id}.journal_id"),
            )
            if event_id in receipt_by_event or identity[3] in {value[3] for value in receipt_by_event.values()}:
                raise PlanError(f"duplicate accounting-link receipt identity: {event_id}")
            receipt_by_event[event_id] = identity
        if int(link_plan.get("summary", {}).get("quarantined", 1)) != 0:
            raise PlanError("accounting-link plan contains quarantined items")
        book = config.get("book")
        if not isinstance(book, dict):
            raise PlanError("mapping has no book")
        for field in ("book_id", "principal_id", "scope", "period_id", "period_label"):
            require_string(book.get(field), f"book.{field}")
        accounts = book.get("accounts")
        if not isinstance(accounts, list) or not accounts:
            raise PlanError("book.accounts must be a non-empty array")
        account_codes: set[str] = set()
        account_ids: set[str] = set()
        for index, account in enumerate(accounts):
            if not isinstance(account, dict):
                raise PlanError(f"book.accounts[{index}] is not an object")
            for field in ("account_id", "account_code", "name", "kind", "currency"):
                require_string(account.get(field), f"book.accounts[{index}].{field}")
            if account["kind"] not in ACCOUNT_KINDS:
                raise PlanError(f"unsupported account kind: {account['kind']}")
            if len(account["currency"]) != 3:
                raise PlanError(f"invalid account currency: {account['currency']}")
            if account["account_id"] in account_ids or account["account_code"] in account_codes:
                raise PlanError("duplicate chart account")
            account_ids.add(account["account_id"])
            account_codes.add(account["account_code"])

        items = link_plan.get("items")
        if not isinstance(items, list) or not items:
            raise PlanError("accounting-link plan has no items")
        approved = config.get("approved_event_ids")
        if not isinstance(approved, list) or not approved or not all(isinstance(value, str) for value in approved):
            raise PlanError("approved_event_ids must be a non-empty string array")
        approved_set = set(approved)
        output_items: list[dict[str, Any]] = []
        event_ids: set[str] = set()
        for index, item in enumerate(items):
            if not isinstance(item, dict):
                raise PlanError(f"accounting-link item {index} is not an object")
            if item.get("disposition") != "ready_for_domain_import":
                raise PlanError(f"accounting-link item {index} is not ready")
            candidate = item.get("target_candidate")
            if not isinstance(candidate, dict):
                raise PlanError(f"accounting-link item {index} has no candidate")
            event_id = require_string(candidate.get("event_id"), f"item[{index}].event_id")
            if event_id not in approved_set:
                continue
            if event_id not in receipt_by_event:
                raise PlanError(f"event was not accepted by the native link receipt: {event_id}")
            if event_id in event_ids:
                raise PlanError(f"duplicate posting event: {event_id}")
            event_ids.add(event_id)
            if candidate.get("principal_id") != book["principal_id"]:
                raise PlanError(f"principal mismatch for {event_id}")
            if candidate.get("scope") != book["scope"]:
                raise PlanError(f"scope mismatch for {event_id}")
            journal = candidate.get("journal")
            if not isinstance(journal, dict):
                raise PlanError(f"journal missing for {event_id}")
            for field in ("entry_id", "description", "debit_account", "credit_account", "currency"):
                require_string(journal.get(field), f"{event_id}.journal.{field}")
            if journal["debit_account"] not in account_codes or journal["credit_account"] not in account_codes:
                raise PlanError(f"journal account is absent from explicit chart: {event_id}")
            receipt_source_type, receipt_source_id, receipt_principal, receipt_journal_id = receipt_by_event[event_id]
            if (
                receipt_source_type != candidate.get("source_type")
                or receipt_source_id != candidate.get("source_id")
                or receipt_principal != candidate.get("principal_id")
                or receipt_journal_id != journal["entry_id"]
            ):
                raise PlanError(f"accounting-link receipt identity mismatch: {event_id}")
            amount = journal.get("amount_minor")
            if not isinstance(amount, int) or amount <= 0:
                raise PlanError(f"journal amount is not positive: {event_id}")
            if journal["currency"] not in {account["currency"] for account in accounts}:
                raise PlanError(f"journal currency is absent from explicit chart: {event_id}")
            output_items.append(
                {
                    "source_table": require_string(item.get("source_table"), f"item[{index}].source_table"),
                    "source_id": require_string(item.get("source_id"), f"item[{index}].source_id"),
                    "target_type": "accounting_posting",
                    "target_id": journal["entry_id"],
                    "disposition": "ready_for_posting",
                    "target_candidate": {**candidate, "link_event_id": event_id},
                }
            )
        if event_ids != approved_set:
            raise PlanError("approved_event_ids must exactly match the link-plan events")
        plan = {
            "format": "moonproj.erp.accounting-posting-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": require_string(config.get("mapping_version"), "mapping_version"),
            "book": book,
            "summary": {"items": len(output_items), "ready": len(output_items), "quarantined": 0},
            "items": output_items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"accounting-post plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
