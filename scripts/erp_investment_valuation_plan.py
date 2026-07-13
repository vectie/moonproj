#!/usr/bin/env python3
"""Compile a reviewed investment valuation map against a performance plan.

The performance plan supplies the already-reviewed portfolio, positions, and
quotes.  This planner adds only an explicit mark-to-market event map; it does
not infer accounts, posting policy, cash movement, or period state.
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
        raise PlanError(f"JSON root is not an object: {path}")
    return value


def string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
    return value


def integer(value: Any, label: str, minimum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise PlanError(f"{label} must be an integer")
    if minimum is not None and value < minimum:
        raise PlanError(f"{label} must be >= {minimum}")
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("performance_plan", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        performance = load(args.performance_plan)
        config = load(args.mapping)
        reject_secrets(config)
        if performance.get("format") != "moonproj.erp.investment-performance-plan.v1":
            raise PlanError("unexpected investment performance plan format")
        if performance.get("reviewed") is not True:
            raise PlanError("performance plan is not reviewed")
        if config.get("format") != "moonproj.erp.investment-valuation-map.v1":
            raise PlanError("unexpected investment valuation map format")
        if config.get("reviewed") is not True:
            raise PlanError("investment valuation map is not reviewed")

        source_snapshot_id = string(performance.get("source_snapshot_id"), "performance.source_snapshot_id")
        if string(config.get("source_snapshot_id"), "source_snapshot_id") != source_snapshot_id:
            raise PlanError("valuation map source_snapshot_id differs from performance plan")
        mapping_version = string(config.get("mapping_version"), "mapping_version")
        run_id = string(config.get("run_id"), "run_id")
        portfolio = performance.get("portfolio")
        if not isinstance(portfolio, dict):
            raise PlanError("performance plan has no portfolio")
        for field in ("source_id", "portfolio_id", "principal_id", "project_scope", "currency"):
            expected = string(portfolio.get(field), f"performance.portfolio.{field}")
            if string(config.get(f"portfolio_{field}"), f"portfolio_{field}") != expected:
                raise PlanError(f"valuation map portfolio_{field} differs from performance plan")

        valuation = config.get("valuation")
        if not isinstance(valuation, dict):
            raise PlanError("valuation must be an object")
        source_table = string(valuation.get("source_table"), "valuation.source_table")
        source_id = string(valuation.get("source_id"), "valuation.source_id")
        valuation_id = string(valuation.get("valuation_id"), "valuation.valuation_id")
        if source_id != valuation_id:
            raise PlanError("valuation.source_id must equal valuation_id")
        event_id = string(valuation.get("event_id"), "valuation.event_id")
        event_type = string(valuation.get("event_type"), "valuation.event_type")
        scope = string(valuation.get("scope"), "valuation.scope")
        if scope != portfolio["project_scope"]:
            raise PlanError("valuation.scope differs from performance portfolio project_scope")
        investment_account = string(valuation.get("investment_account"), "valuation.investment_account")
        gain_account = string(valuation.get("gain_account"), "valuation.gain_account")
        loss_account = string(valuation.get("loss_account"), "valuation.loss_account")
        expected_gain_loss = integer(valuation.get("expected_gain_loss_minor"), "valuation.expected_gain_loss_minor")
        expected_amount = integer(valuation.get("expected_amount_minor"), "valuation.expected_amount_minor", 1)
        if abs(expected_gain_loss) != expected_amount:
            raise PlanError("expected_amount_minor must equal the absolute gain/loss")
        expected_journal_id = "investment/" + valuation_id + ("/gain" if expected_gain_loss > 0 else "/loss")
        journal_id = string(valuation.get("journal_id"), "valuation.journal_id")
        if journal_id != expected_journal_id:
            raise PlanError("valuation.journal_id does not match the expected gain/loss direction")

        plan = {
            "format": "moonproj.erp.investment-valuation-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "portfolio": portfolio,
            "valuation": {
                "source_table": source_table,
                "source_id": source_id,
                "valuation_id": valuation_id,
                "event_id": event_id,
                "event_type": event_type,
                "scope": scope,
                "investment_account": investment_account,
                "gain_account": gain_account,
                "loss_account": loss_account,
                "expected_gain_loss_minor": expected_gain_loss,
                "expected_amount_minor": expected_amount,
                "journal_id": journal_id,
                "principal_id": portfolio["principal_id"],
                "currency": portfolio["currency"],
            },
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), "valuation_id": valuation_id, "amount_minor": expected_amount}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"investment valuation plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
