#!/usr/bin/env python3
"""Compile a reviewed employee expense/advance-offset map into a native plan.

The plan keeps the employee advance, expense claim, and offset identities
separate.  An offset changes the advance balance only after an approved claim;
it never releases cash, posts accounting, or closes a period.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


class PlanError(RuntimeError):
    pass


SECRET_KEY = re.compile(r"password|secret|token|private|ip$", re.IGNORECASE)


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error
    if not isinstance(value, dict):
        raise PlanError("expense/advance map is not an object")
    return value


def reject_secrets(value: Any, path: str = "mapping") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise PlanError(f"secret-shaped key at {path}.{key}")
            reject_secrets(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secrets(child, f"{path}[{index}]")


def string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
    return value


def integer(value: Any, label: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise PlanError(f"{label} must be an integer >= {minimum}")
    return value


def obj(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise PlanError(f"{label} must be an object")
    return value


def source_fields(value: dict[str, Any], label: str, expected_table: str) -> dict[str, str]:
    table = string(value.get("source_table"), f"{label}.source_table")
    if table != expected_table:
        raise PlanError(f"{label}.source_table must be {expected_table}")
    return {
        "source_table": table,
        "source_id": string(value.get("source_id"), f"{label}.source_id"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        config = load(args.mapping)
        reject_secrets(config)
        if config.get("format") != "moonproj.erp.expense-advance-cohort-map.v1":
            raise PlanError("unexpected expense/advance map format")
        if config.get("reviewed") is not True:
            raise PlanError("expense/advance map is not reviewed")
        source_snapshot_id = string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = string(config.get("mapping_version"), "mapping_version")
        run_id = string(config.get("run_id"), "run_id")

        advance = obj(config.get("advance"), "advance")
        expense = obj(config.get("expense"), "expense")
        offset = obj(config.get("offset"), "offset")
        advance_source = source_fields(advance, "advance", "vcb_loan_simple")
        expense_source = source_fields(expense, "expense", "vcb_expense")
        offset_source = source_fields(offset, "offset", "cb_loan_offset")

        advance_id = string(advance.get("advance_id"), "advance.advance_id")
        principal_id = string(advance.get("principal_id"), "advance.principal_id")
        employee_id = string(advance.get("employee_id"), "advance.employee_id")
        if employee_id.startswith("employee:"):
            raise PlanError("advance.employee_id must be the raw employee identity")
        currency = string(advance.get("currency"), "advance.currency")
        advance_amount = integer(advance.get("amount_minor"), "advance.amount_minor", 1)
        if string(advance.get("expected_state"), "advance.expected_state") != "partially_repaid":
            raise PlanError("advance.expected_state must be partially_repaid")

        expense_id = string(expense.get("expense_id"), "expense.expense_id")
        if string(expense.get("principal_id", principal_id), "expense.principal_id") != principal_id:
            raise PlanError("expense principal differs from advance")
        if string(expense.get("employee_id", employee_id), "expense.employee_id") != employee_id:
            raise PlanError("expense employee differs from advance")
        if string(expense.get("expected_state"), "expense.expected_state") != "approved":
            raise PlanError("expense.expected_state must be approved")
        expense_amount = integer(expense.get("amount_minor"), "expense.amount_minor", 1)
        expense_currency = string(expense.get("currency", currency), "expense.currency")
        if expense_currency != currency:
            raise PlanError("expense currency differs from advance")
        allocations = expense.get("allocations")
        if not isinstance(allocations, list) or not allocations:
            raise PlanError("expense.allocations must be a non-empty list")
        normalized_allocations: list[dict[str, Any]] = []
        allocation_total = 0
        for index, value in enumerate(allocations):
            allocation = obj(value, f"expense.allocations[{index}]")
            allocation_amount = integer(
                allocation.get("amount_minor"),
                f"expense.allocations[{index}].amount_minor",
                1,
            )
            allocation_currency = string(
                allocation.get("currency", currency),
                f"expense.allocations[{index}].currency",
            )
            if allocation_currency != currency:
                raise PlanError("expense allocation currency differs from advance")
            allocation_total += allocation_amount
            normalized_allocations.append(
                {
                    "project_scope": string(
                        allocation.get("project_scope"),
                        f"expense.allocations[{index}].project_scope",
                    ),
                    "cost_subject": string(
                        allocation.get("cost_subject"),
                        f"expense.allocations[{index}].cost_subject",
                    ),
                    "amount_minor": allocation_amount,
                    "currency": currency,
                }
            )
        if allocation_total != expense_amount:
            raise PlanError("expense allocations do not equal expense amount")

        offset_id = string(offset.get("offset_id"), "offset.offset_id")
        if string(offset.get("advance_id"), "offset.advance_id") != advance_id:
            raise PlanError("offset.advance_id differs from advance")
        if string(offset.get("expense_id", expense_id), "offset.expense_id") != expense_id:
            raise PlanError("offset expense differs from expense")
        offset_amount = integer(offset.get("amount_minor"), "offset.amount_minor", 1)
        if offset_amount > advance_amount or offset_amount > expense_amount:
            raise PlanError("offset exceeds advance or expense")
        if string(offset.get("currency", currency), "offset.currency") != currency:
            raise PlanError("offset currency differs from advance")
        expected_repaid = integer(
            advance.get("expected_repaid_minor", offset_amount),
            "advance.expected_repaid_minor",
        )
        if expected_repaid != offset_amount:
            raise PlanError("advance expected repaid amount differs from offset")

        identities = [
            (advance_source["source_table"], advance_source["source_id"]),
            (expense_source["source_table"], expense_source["source_id"]),
            (offset_source["source_table"], offset_source["source_id"]),
        ]
        if len(set(identities)) != len(identities):
            raise PlanError("source identities must be unique")
        targets = [advance_id, expense_id, offset_id]
        if len(set(targets)) != len(targets):
            raise PlanError("target identities must be unique")

        plan = {
            "format": "moonproj.erp.expense-advance-cohort-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "advance": {
                **advance_source,
                "advance_id": advance_id,
                "principal_id": principal_id,
                "employee_id": employee_id,
                "amount_minor": advance_amount,
                "offset_minor": offset_amount,
                "currency": currency,
            },
            "expense": {
                **expense_source,
                "expense_id": expense_id,
                "principal_id": principal_id,
                "employee_id": employee_id,
                "amount_minor": expense_amount,
                "currency": currency,
                "allocations": normalized_allocations,
            },
            "offset": {
                **offset_source,
                "offset_id": offset_id,
                "advance_id": advance_id,
                "expense_id": expense_id,
                "amount_minor": offset_amount,
                "currency": currency,
            },
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(json.dumps({"output": str(args.output), "items": 3}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"expense/advance cohort plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
