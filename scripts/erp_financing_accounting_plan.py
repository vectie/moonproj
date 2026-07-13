#!/usr/bin/env python3
"""Compile explicit draw/repayment accounting maps for a facility plan."""

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


def event_map(mappings: dict[str, Any], source_id: str, action: str) -> dict[str, Any]:
    value = mappings.get("financing_facility:" + source_id)
    if not isinstance(value, dict):
        raise PlanError(f"missing accounting map for financing_facility:{source_id}")
    if value.get("action") != action:
        raise PlanError(f"financing map action mismatch for {source_id}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("facility_plan", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        facility_plan = load(args.facility_plan)
        config = load(args.mapping)
        reject_secrets(config)
        if facility_plan.get("format") != "moonproj.erp.financing-facility-plan.v1" or facility_plan.get("reviewed") is not True:
            raise PlanError("financing plan is not reviewed")
        if config.get("format") != "moonproj.erp.financing-accounting-map.v1" or config.get("reviewed") is not True:
            raise PlanError("financing accounting map is not reviewed")
        source_snapshot_id = string(facility_plan.get("source_snapshot_id"), "facility_plan.source_snapshot_id")
        if string(config.get("source_snapshot_id"), "source_snapshot_id") != source_snapshot_id:
            raise PlanError("financing accounting map source snapshot differs from facility plan")
        mappings = config.get("accounting_by_source")
        if not isinstance(mappings, dict):
            raise PlanError("accounting_by_source must be an object")
        facilities: list[dict[str, Any]] = []
        for index, facility in enumerate(facility_plan.get("facilities", [])):
            if not isinstance(facility, dict):
                raise PlanError(f"facilities[{index}] is not an object")
            facility_id = string(facility.get("facility_id"), f"facilities[{index}].facility_id")
            source_id = string(facility.get("source_id"), f"facilities[{index}].source_id")
            principal_id = string(facility.get("principal_id"), f"facilities[{index}].principal_id")
            scope = string(facility.get("project_scope"), f"facilities[{index}].project_scope")
            currency = string(facility.get("currency"), f"facilities[{index}].currency")
            draw_id = facility_id + "/draw"
            repayment_id = facility_id + "/repayment"
            draw = event_map(mappings, draw_id, "draw")
            repayment = event_map(mappings, repayment_id, "repayment")
            for action, mapping, expected in (("draw", draw, integer(facility.get("draw_amount_minor"), f"facilities[{index}].draw_amount_minor", 1)), ("repayment", repayment, integer(facility.get("repay_amount_minor"), f"facilities[{index}].repay_amount_minor", 1))):
                for field in ("event_id", "event_type", "journal_id", "description", "scope", "debit_account", "credit_account", "principal_id", "amount_minor", "currency"):
                    if field not in mapping or mapping[field] in (None, ""):
                        raise PlanError(f"{action} accounting map missing {field}")
                if mapping["principal_id"] != principal_id or mapping["scope"] != scope or mapping["currency"] != currency or mapping["amount_minor"] != expected:
                    raise PlanError(f"{action} accounting identity/amount mismatch for {facility_id}")
                expected_journal = "financing/" + (draw_id if action == "draw" else repayment_id) + ("/draw" if action == "draw" else "/repayment")
                if mapping["journal_id"] != expected_journal:
                    raise PlanError(f"{action} journal identity mismatch for {facility_id}")
            facilities.append({
                "source_table": string(facility.get("source_table"), f"facilities[{index}].source_table"),
                "source_id": source_id,
                "facility_id": facility_id,
                "principal_id": principal_id,
                "project_scope": scope,
                "lender_id": string(facility.get("lender_id"), f"facilities[{index}].lender_id"),
                "currency": currency,
                "limit_amount_minor": integer(facility.get("limit_amount_minor"), f"facilities[{index}].limit_amount_minor", 1),
                "annual_rate_bps": integer(facility.get("annual_rate_bps"), f"facilities[{index}].annual_rate_bps"),
                "draw_amount_minor": integer(facility.get("draw_amount_minor"), f"facilities[{index}].draw_amount_minor", 1),
                "repay_amount_minor": integer(facility.get("repay_amount_minor"), f"facilities[{index}].repay_amount_minor", 1),
                "draw": {"source_id": draw_id, **{key: draw[key] for key in ("event_id", "event_type", "journal_id", "description", "scope", "debit_account", "credit_account", "amount_minor")}},
                "repayment": {"source_id": repayment_id, **{key: repayment[key] for key in ("event_id", "event_type", "journal_id", "description", "scope", "debit_account", "credit_account", "amount_minor")}},
            })
        if not facilities:
            raise PlanError("facility plan has no facilities")
        plan = {
            "format": "moonproj.erp.financing-accounting-plan.v1",
            "reviewed": True,
            "source_snapshot_id": source_snapshot_id,
            "mapping_version": string(config.get("mapping_version"), "mapping_version"),
            "run_id": string(config.get("run_id"), "run_id"),
            "facilities": facilities,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), "facilities": len(facilities), "links": len(facilities) * 2}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"financing accounting plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
