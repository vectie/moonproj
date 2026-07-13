#!/usr/bin/env python3
"""Compile a reviewed bank-statement map into a native import plan.

The planner preserves statement lines and balances exactly. It does not infer
cash movements, match a line to a ledger event, release cash, or post journals.
Those are separate reviewed treasury/accounting operations.
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
DIRECTIONS = {"inflow", "outflow"}


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error
    if not isinstance(value, dict):
        raise PlanError("bank-statement mapping is not an object")
    return value


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
    return value


def require_int(value: Any, label: str, *, minimum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise PlanError(f"{label} must be an integer")
    if minimum is not None and value < minimum:
        raise PlanError(f"{label} must be >= {minimum}")
    return value


def reject_secret_keys(value: Any, path: str = "mapping") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise PlanError(f"secret-shaped key at {path}.{key}")
            reject_secret_keys(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secret_keys(child, f"{path}[{index}]")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        config = load(args.mapping)
        reject_secret_keys(config)
        if config.get("format") != "moonproj.erp.bank-statement-map.v1":
            raise PlanError("unexpected bank-statement map format")
        if config.get("reviewed") is not True:
            raise PlanError("bank-statement map is not reviewed")
        source_snapshot_id = require_string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = require_string(config.get("mapping_version"), "mapping_version")
        run_id = require_string(config.get("run_id"), "run_id")
        statements = config.get("statements")
        if not isinstance(statements, list) or not statements:
            raise PlanError("statements must be a non-empty array")
        seen_statement_ids: set[str] = set()
        seen_source_ids: set[str] = set()
        normalized_statements: list[dict[str, Any]] = []
        for index, statement in enumerate(statements):
            if not isinstance(statement, dict):
                raise PlanError(f"statements[{index}] is not an object")
            source_table = require_string(statement.get("source_table"), f"statements[{index}].source_table")
            source_id = require_string(statement.get("source_id"), f"statements[{index}].source_id")
            statement_id = require_string(statement.get("statement_id"), f"statements[{index}].statement_id")
            account_id = require_string(statement.get("account_id"), f"statements[{index}].account_id")
            principal_id = require_string(statement.get("principal_id"), f"statements[{index}].principal_id")
            project_scope = require_string(statement.get("project_scope"), f"statements[{index}].project_scope")
            period = require_string(statement.get("period"), f"statements[{index}].period")
            currency = require_string(statement.get("currency"), f"statements[{index}].currency")
            opening_balance_minor = require_int(
                statement.get("opening_balance_minor"), f"statements[{index}].opening_balance_minor"
            )
            closing_balance_minor = require_int(
                statement.get("closing_balance_minor"), f"statements[{index}].closing_balance_minor"
            )
            lines = statement.get("lines")
            if not isinstance(lines, list) or not lines:
                raise PlanError(f"statements[{index}].lines must be a non-empty array")
            seen_line_ids: set[str] = set()
            normalized_lines: list[dict[str, Any]] = []
            for line_index, line in enumerate(lines):
                if not isinstance(line, dict):
                    raise PlanError(f"statements[{index}].lines[{line_index}] is not an object")
                line_id = require_string(
                    line.get("line_id"), f"statements[{index}].lines[{line_index}].line_id"
                )
                external_reference = require_string(
                    line.get("external_reference"),
                    f"statements[{index}].lines[{line_index}].external_reference",
                )
                booked_at = require_string(
                    line.get("booked_at"), f"statements[{index}].lines[{line_index}].booked_at"
                )
                amount_minor = require_int(
                    line.get("amount_minor"),
                    f"statements[{index}].lines[{line_index}].amount_minor",
                    minimum=1,
                )
                direction = require_string(
                    line.get("direction"), f"statements[{index}].lines[{line_index}].direction"
                )
                if direction not in DIRECTIONS:
                    raise PlanError(f"statements[{index}].lines[{line_index}].direction is invalid")
                if line_id in seen_line_ids:
                    raise PlanError(f"duplicate line_id in statement {statement_id}: {line_id}")
                seen_line_ids.add(line_id)
                normalized_lines.append(
                    {
                        "line_id": line_id,
                        "external_reference": external_reference,
                        "booked_at": booked_at,
                        "amount_minor": amount_minor,
                        "direction": direction,
                    }
                )
            if statement_id in seen_statement_ids:
                raise PlanError(f"duplicate statement_id: {statement_id}")
            if source_id in seen_source_ids:
                raise PlanError(f"duplicate source_id: {source_id}")
            seen_statement_ids.add(statement_id)
            seen_source_ids.add(source_id)
            normalized_statements.append(
                {
                    "source_table": source_table,
                    "source_id": source_id,
                    "statement_id": statement_id,
                    "account_id": account_id,
                    "principal_id": principal_id,
                    "project_scope": project_scope,
                    "period": period,
                    "currency": currency,
                    "opening_balance_minor": opening_balance_minor,
                    "closing_balance_minor": closing_balance_minor,
                    "lines": normalized_lines,
                }
            )
        plan = {
            "format": "moonproj.erp.bank-statement-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "summary": {
                "statements": len(normalized_statements),
                "lines": sum(len(statement["lines"]) for statement in normalized_statements),
            },
            "statements": normalized_statements,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"bank-statement plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
