#!/usr/bin/env python3
"""Compile a reviewed financing-facility map into a native migration plan.

The plan names facility limits and explicit draw/repayment operations. It does
not authorize a lender call, cash movement, or accounting-book posting.
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
STATES = {"active", "partially_repaid", "closed", "defaulted"}


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error
    if not isinstance(value, dict):
        raise PlanError("financing map is not an object")
    return value


def string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{label} must be a non-empty string")
    return value


def integer(value: Any, label: str, minimum: int = 0, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise PlanError(f"{label} must be an integer")
    if value < minimum or maximum is not None and value > maximum:
        raise PlanError(f"{label} is outside the allowed range")
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
        if config.get("format") != "moonproj.erp.financing-facility-map.v1":
            raise PlanError("unexpected financing map format")
        if config.get("reviewed") is not True:
            raise PlanError("financing map is not reviewed")
        source_snapshot_id = string(config.get("source_snapshot_id"), "source_snapshot_id")
        mapping_version = string(config.get("mapping_version"), "mapping_version")
        run_id = string(config.get("run_id"), "run_id")
        facilities = config.get("facilities")
        if not isinstance(facilities, list) or not facilities:
            raise PlanError("facilities must be a non-empty array")
        seen: set[str] = set()
        normalized: list[dict[str, Any]] = []
        for index, facility in enumerate(facilities):
            if not isinstance(facility, dict):
                raise PlanError(f"facilities[{index}] is not an object")
            source_table = string(facility.get("source_table"), f"facilities[{index}].source_table")
            source_id = string(facility.get("source_id"), f"facilities[{index}].source_id")
            facility_id = string(facility.get("facility_id"), f"facilities[{index}].facility_id")
            principal_id = string(facility.get("principal_id"), f"facilities[{index}].principal_id")
            project_scope = string(facility.get("project_scope"), f"facilities[{index}].project_scope")
            lender_id = string(facility.get("lender_id"), f"facilities[{index}].lender_id")
            currency = string(facility.get("currency"), f"facilities[{index}].currency")
            limit_minor = integer(facility.get("limit_amount_minor"), f"facilities[{index}].limit_amount_minor", 1)
            annual_rate_bps = integer(
                facility.get("annual_rate_bps"), f"facilities[{index}].annual_rate_bps", 0, 10000
            )
            draw_minor = integer(facility.get("draw_amount_minor"), f"facilities[{index}].draw_amount_minor")
            repay_minor = integer(facility.get("repay_amount_minor"), f"facilities[{index}].repay_amount_minor")
            interest_days = integer(facility.get("interest_days"), f"facilities[{index}].interest_days")
            expected_state = string(facility.get("expected_state"), f"facilities[{index}].expected_state")
            if expected_state not in STATES:
                raise PlanError(f"facilities[{index}].expected_state is invalid")
            if draw_minor > limit_minor:
                raise PlanError(f"facilities[{index}].draw_amount_minor exceeds facility limit")
            if repay_minor > draw_minor:
                raise PlanError(f"facilities[{index}].repay_amount_minor exceeds draw amount")
            if facility_id in seen:
                raise PlanError(f"duplicate facility_id: {facility_id}")
            seen.add(facility_id)
            normalized.append(
                {
                    "source_table": source_table,
                    "source_id": source_id,
                    "facility_id": facility_id,
                    "principal_id": principal_id,
                    "project_scope": project_scope,
                    "lender_id": lender_id,
                    "currency": currency,
                    "limit_amount_minor": limit_minor,
                    "annual_rate_bps": annual_rate_bps,
                    "draw_amount_minor": draw_minor,
                    "repay_amount_minor": repay_minor,
                    "interest_days": interest_days,
                    "expected_state": expected_state,
                }
            )
        plan = {
            "format": "moonproj.erp.financing-facility-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": mapping_version,
            "run_id": run_id,
            "summary": {"facilities": len(normalized)},
            "facilities": normalized,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"financing plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
