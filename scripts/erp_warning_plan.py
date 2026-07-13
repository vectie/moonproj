#!/usr/bin/env python3
"""Build a source-bound cost-overrun warning plan.

The ERP fixture has no ``sys_warning`` rows, but its ``cb_cost`` rows expose
the cost components needed for a reviewed overrun scan. The mapping must name
the project and the exact source rows included in the scan. This prevents
parent/child cost rows from being double-counted and keeps the result as
warning evidence rather than a workflow or accounting mutation.
"""

from __future__ import annotations

import argparse
import json
from decimal import Decimal, InvalidOperation, ROUND_HALF_EVEN
from pathlib import Path
from typing import Any


class PlanError(RuntimeError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read JSON: {path}") from error


def required_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"{field} must be a non-empty string")
    return value


def money_minor(value: Any, currency: str, policy: dict[str, Any]) -> int:
    try:
        decimal = Decimal(str(value))
    except InvalidOperation as error:
        raise PlanError(f"invalid monetary value: {value!r}") from error
    scale = int(policy.get("minor_units_per_unit", 100))
    if scale <= 0 or policy.get("rounding", "half_even") != "half_even":
        raise PlanError("money policy must declare positive scale and half_even rounding")
    scaled = decimal * scale
    rounded = scaled.quantize(Decimal("1"), rounding=ROUND_HALF_EVEN)
    if rounded != scaled and not bool(policy.get("allow_rounding", False)):
        raise PlanError(f"amount requires rounding: {value!r}")
    if rounded < 0:
        raise PlanError(f"amount must not be negative: {value!r}")
    return int(rounded)


def build_plan(export_dir: Path, mapping_path: Path) -> dict[str, Any]:
    manifest = load_json(export_dir / "manifest.json")
    source_sha256 = required_string(manifest.get("source_sha256"), "source_sha256")
    if len(source_sha256) != 64:
        raise PlanError("source_sha256 must be a 64-character hash")
    rows = load_json(export_dir / "tables" / "cb_cost.json")
    if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
        raise PlanError("cb_cost export must be an object array")
    config = load_json(mapping_path)
    if not isinstance(config, dict):
        raise PlanError("warning mapping must be an object")

    project_id = required_string(config.get("project_id"), "project_id")
    scope = required_string(config.get("scope"), "scope")
    if scope != f"project:{project_id}":
        raise PlanError("scope must match project_id")
    principal_id = required_string(config.get("principal_id"), "principal_id")
    target_field = required_string(config.get("target_field"), "target_field")
    component_fields = config.get("component_fields")
    if not isinstance(component_fields, list) or not component_fields:
        raise PlanError("component_fields must be a non-empty array")
    component_fields = [required_string(field, "component field") for field in component_fields]
    source_ids = config.get("source_ids")
    if not isinstance(source_ids, list) or not source_ids:
        raise PlanError("source_ids must be a non-empty array")
    selected_ids = [required_string(value, "source id") for value in source_ids]
    if len(set(selected_ids)) != len(selected_ids):
        raise PlanError("source_ids must be unique")
    currency = required_string(config.get("currency"), "currency")
    if len(currency) != 3:
        raise PlanError("currency must be an ISO-like three-letter code")
    warning_id = required_string(config.get("warning_id"), "warning_id")
    evidence_id = required_string(config.get("evidence_id"), "evidence_id")
    mapping_version = required_string(config.get("mapping_version"), "mapping_version")
    rule_code = required_string(config.get("rule_code"), "rule_code")
    target_type = required_string(config.get("target_type"), "target_type")
    target_id = required_string(config.get("target_id"), "target_id")
    message_prefix = required_string(config.get("message_prefix"), "message_prefix")
    severity = required_string(config.get("severity"), "severity")
    if severity not in {"info", "warning", "critical"}:
        raise PlanError("severity must be info, warning, or critical")

    policy = config.get("money_policy", {})
    if not isinstance(policy, dict):
        raise PlanError("money_policy must be an object")
    by_id: dict[str, dict[str, Any]] = {}
    for row in rows:
        source_id = required_string(row.get("cost_guid"), "cost_guid")
        if source_id in by_id:
            raise PlanError(f"duplicate cost_guid: {source_id}")
        by_id[source_id] = row
    for source_id in selected_ids:
        row = by_id.get(source_id)
        if row is None:
            raise PlanError(f"source id is not present in cb_cost: {source_id}")
        if str(row.get("proj_guid", "")) != project_id:
            raise PlanError(f"source row is outside project scope: {source_id}")

    positive_overruns: dict[str, int] = {}
    for row in rows:
        if str(row.get("proj_guid", "")) != project_id:
            continue
        source_id = required_string(row.get("cost_guid"), "cost_guid")
        target = money_minor(row.get(target_field), currency, policy)
        components = sum(
            money_minor(row.get(field), currency, policy) for field in component_fields
        )
        overrun = components - target
        if overrun > 0:
            positive_overruns[source_id] = overrun

    if set(selected_ids) != set(positive_overruns):
        missing = sorted(set(positive_overruns) - set(selected_ids))
        extra = sorted(set(selected_ids) - set(positive_overruns))
        raise PlanError(
            "source_ids must exactly cover positive overruns; "
            f"missing={missing}, extra={extra}"
        )
    total_overrun = sum(positive_overruns.values())
    message = (
        f"{message_prefix}: {total_overrun} minor units across "
        + ",".join(selected_ids)
    )
    return {
        "format": "moonproj.company.warning-plan.v1",
        "warning_id": warning_id,
        "principal_id": principal_id,
        "scope": scope,
        "rule_code": rule_code,
        "target_type": target_type,
        "target_id": target_id,
        "message": message,
        "severity": severity,
        "source_snapshot_id": f"erp-snapshot:{source_sha256}",
        "mapping_version": mapping_version,
        "evidence_id": evidence_id,
        "source_table": "cb_cost",
        "source_ids": selected_ids,
        "overrun_minor": total_overrun,
        "scan_policy": "explicit-source-rows-no-parent-child-double-count",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        plan = build_plan(args.export, args.mapping)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(
            json.dumps(
                {
                    "output": str(args.output),
                    "mapping_version": plan["mapping_version"],
                    "source_ids": len(plan["source_ids"]),
                    "overrun_minor": plan["overrun_minor"],
                },
                sort_keys=True,
            )
        )
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"warning plan failed: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
