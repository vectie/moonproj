#!/usr/bin/env python3
"""Compile a reviewed cash-plan/dispatch map into a native migration plan.

This boundary preserves liquidity planning and inter-project dispatch approval
evidence. It does not release a bank movement or post accounting.
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
PLAN_STATES = {"planned", "confirmed", "actualized"}
DISPATCH_STATES = {"pending", "approved", "executed"}
DIRECTIONS = {"inflow", "outflow"}


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error
    if not isinstance(value, dict):
        raise PlanError("treasury plan map is not an object")
    return value


def string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
    return value


def integer(value: Any, label: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise PlanError(f"{label} must be an integer >= {minimum}")
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
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        config = load(args.mapping)
        reject_secrets(config)
        if config.get("format") != "moonproj.erp.treasury-plan-dispatch-map.v1":
            raise PlanError("unexpected treasury plan map format")
        if config.get("reviewed") is not True:
            raise PlanError("treasury plan map is not reviewed")
        source_snapshot_id = string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = string(config.get("mapping_version"), "mapping_version")
        run_id = string(config.get("run_id"), "run_id")
        cash_plans = config.get("cash_plans")
        dispatches = config.get("fund_dispatches")
        if not isinstance(cash_plans, list) or not cash_plans:
            raise PlanError("cash_plans must be a non-empty array")
        if not isinstance(dispatches, list) or not dispatches:
            raise PlanError("fund_dispatches must be a non-empty array")
        seen_plans: set[str] = set()
        normalized_plans: list[dict[str, Any]] = []
        for index, plan in enumerate(cash_plans):
            if not isinstance(plan, dict):
                raise PlanError(f"cash_plans[{index}] is not an object")
            prefix = f"cash_plans[{index}]"
            source_table = string(plan.get("source_table"), f"{prefix}.source_table")
            source_id = string(plan.get("source_id"), f"{prefix}.source_id")
            plan_id = string(plan.get("plan_id"), f"{prefix}.plan_id")
            principal_id = string(plan.get("principal_id"), f"{prefix}.principal_id")
            project_scope = string(plan.get("project_scope"), f"{prefix}.project_scope")
            period = string(plan.get("period"), f"{prefix}.period")
            category = string(plan.get("category"), f"{prefix}.category")
            direction = string(plan.get("direction"), f"{prefix}.direction")
            expected_state = string(plan.get("expected_state"), f"{prefix}.expected_state")
            currency = string(plan.get("currency"), f"{prefix}.currency")
            planned_minor = integer(plan.get("planned_amount_minor"), f"{prefix}.planned_amount_minor", 1)
            actual_minor = integer(plan.get("actual_amount_minor"), f"{prefix}.actual_amount_minor")
            if direction not in DIRECTIONS:
                raise PlanError(f"{prefix}.direction is invalid")
            if expected_state not in PLAN_STATES:
                raise PlanError(f"{prefix}.expected_state is invalid")
            if actual_minor > planned_minor:
                raise PlanError(f"{prefix}.actual_amount_minor exceeds planned amount")
            if expected_state == "actualized" and actual_minor <= 0:
                raise PlanError(f"{prefix}.actualized state requires positive actual amount")
            if expected_state != "actualized" and actual_minor != 0:
                raise PlanError(f"{prefix}.actual_amount_minor requires actualized state")
            if plan_id in seen_plans:
                raise PlanError(f"duplicate plan_id: {plan_id}")
            seen_plans.add(plan_id)
            normalized_plans.append(
                {
                    "source_table": source_table,
                    "source_id": source_id,
                    "plan_id": plan_id,
                    "principal_id": principal_id,
                    "project_scope": project_scope,
                    "period": period,
                    "category": category,
                    "direction": direction,
                    "currency": currency,
                    "planned_amount_minor": planned_minor,
                    "actual_amount_minor": actual_minor,
                    "expected_state": expected_state,
                }
            )
        seen_dispatches: set[str] = set()
        normalized_dispatches: list[dict[str, Any]] = []
        for index, dispatch in enumerate(dispatches):
            if not isinstance(dispatch, dict):
                raise PlanError(f"fund_dispatches[{index}] is not an object")
            prefix = f"fund_dispatches[{index}]"
            source_table = string(dispatch.get("source_table"), f"{prefix}.source_table")
            source_id = string(dispatch.get("source_id"), f"{prefix}.source_id")
            dispatch_id = string(dispatch.get("dispatch_id"), f"{prefix}.dispatch_id")
            principal_id = string(dispatch.get("principal_id"), f"{prefix}.principal_id")
            from_project = string(dispatch.get("from_project"), f"{prefix}.from_project")
            to_project = string(dispatch.get("to_project"), f"{prefix}.to_project")
            reason = string(dispatch.get("reason"), f"{prefix}.reason")
            currency = string(dispatch.get("currency"), f"{prefix}.currency")
            expected_state = string(dispatch.get("expected_state"), f"{prefix}.expected_state")
            amount_minor = integer(dispatch.get("amount_minor"), f"{prefix}.amount_minor", 1)
            if expected_state not in DISPATCH_STATES:
                raise PlanError(f"{prefix}.expected_state is invalid")
            if from_project == to_project:
                raise PlanError(f"{prefix}.from_project and to_project must differ")
            if dispatch_id in seen_dispatches:
                raise PlanError(f"duplicate dispatch_id: {dispatch_id}")
            seen_dispatches.add(dispatch_id)
            normalized_dispatches.append(
                {
                    "source_table": source_table,
                    "source_id": source_id,
                    "dispatch_id": dispatch_id,
                    "principal_id": principal_id,
                    "from_project": from_project,
                    "to_project": to_project,
                    "amount_minor": amount_minor,
                    "currency": currency,
                    "reason": reason,
                    "expected_state": expected_state,
                }
            )
        plan = {
            "format": "moonproj.erp.treasury-plan-dispatch-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "summary": {
                "cash_plans": len(normalized_plans),
                "fund_dispatches": len(normalized_dispatches),
            },
            "cash_plans": normalized_plans,
            "fund_dispatches": normalized_dispatches,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"treasury plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
