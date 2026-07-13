#!/usr/bin/env python3
"""Build a source-bound CBS budget-reservation plan.

The source fixture stores planned budget amounts on ``cb_cost.dfs_budget``.
That field is not treated as a target budget by convention: the reviewed
mapping must name the source amount field, project, and consume decision for
every positive source amount.  The generated plan is consumed by
``cmd/cbs_budget`` and remains budget-control evidence only.
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


def build_plan(
    export_dir: Path,
    cbs_mapping_path: Path,
    budget_mapping_path: Path,
) -> dict[str, Any]:
    manifest = load_json(export_dir / "manifest.json")
    source_sha256 = required_string(manifest.get("source_sha256"), "source_sha256")
    if len(source_sha256) != 64:
        raise PlanError("source_sha256 must be a 64-character hash")
    rows = load_json(export_dir / "tables" / "cb_cost.json")
    if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
        raise PlanError("cb_cost export must be an object array")
    cbs = load_json(cbs_mapping_path)
    budget = load_json(budget_mapping_path)
    if not isinstance(cbs, dict) or not isinstance(budget, dict):
        raise PlanError("CBS and budget mappings must be objects")

    project_id = required_string(budget.get("project_id"), "project_id")
    amount_field = required_string(
        budget.get("budget_amount_field"), "budget_amount_field"
    )
    reservation_prefix = required_string(
        budget.get("reservation_id_prefix"), "reservation_id_prefix"
    )
    consume_by_source = budget.get("consume_by_source")
    if not isinstance(consume_by_source, dict):
        raise PlanError("consume_by_source must be an object")

    cbs_projects = cbs.get("cbs_by_project")
    if not isinstance(cbs_projects, dict):
        raise PlanError("cbs_by_project must be an object")
    project = cbs_projects.get(project_id)
    if not isinstance(project, dict):
        raise PlanError(f"CBS mapping has no project: {project_id}")
    version_id = required_string(project.get("version_id"), "version_id")
    principal_id = required_string(project.get("principal_id"), "principal_id")
    project_scope = required_string(project.get("project_scope"), "project_scope")
    if project_scope != f"project:{project_id}":
        raise PlanError("project_scope must match project_id")
    currency = required_string(project.get("currency"), "currency")
    if len(currency) != 3:
        raise PlanError("currency must be an ISO-like three-letter code")
    subjects_by_source = project.get("subject_by_cost_code")
    if not isinstance(subjects_by_source, dict) or not subjects_by_source:
        raise PlanError("subject_by_cost_code must be a non-empty object")
    subjects: list[dict[str, Any]] = []
    for source_code, raw_subject in subjects_by_source.items():
        if not isinstance(raw_subject, dict):
            raise PlanError(f"subject mapping is not an object: {source_code}")
        subjects.append(
            {
                "subject_id": required_string(raw_subject.get("subject_id"), "subject_id"),
                "code": required_string(raw_subject.get("code"), "code"),
                "name": required_string(raw_subject.get("name"), "name"),
                "parent_code": str(raw_subject.get("parent_code", "")),
                "target_minor": int(raw_subject.get("target_minor", 0)),
            }
        )
    subjects.sort(key=lambda value: value["code"])

    policy = cbs.get("money_policy", {})
    if not isinstance(policy, dict):
        raise PlanError("money_policy must be an object")

    positive_source_ids: set[str] = set()
    links: list[dict[str, Any]] = []
    for row in rows:
        if str(row.get("proj_guid", "")) != project_id:
            continue
        source_id = required_string(row.get("cost_guid"), "cost_guid")
        amount_minor = money_minor(row.get(amount_field), currency, policy)
        if amount_minor == 0:
            continue
        positive_source_ids.add(source_id)
        cost_code = required_string(row.get("cost_code"), "cost_code")
        raw_subject = subjects_by_source.get(cost_code)
        if not isinstance(raw_subject, dict):
            raise PlanError(f"missing CBS subject mapping: {cost_code}")
        consume = consume_by_source.get(source_id)
        if not isinstance(consume, bool):
            raise PlanError(f"missing consume decision: {source_id}")
        links.append(
            {
                "link_id": f"cbs-budget-link:{source_id}",
                "source_id": source_id,
                "subject_code": required_string(raw_subject.get("code"), "subject code"),
                "reservation_id": reservation_prefix + source_id,
                "amount_minor": amount_minor,
                "currency": currency,
                "consume": consume,
            }
        )

    extra_decisions = set(str(key) for key in consume_by_source) - positive_source_ids
    if extra_decisions:
        raise PlanError(
            "consume decisions must name exactly positive source amounts: "
            + ",".join(sorted(extra_decisions))
        )
    if not links:
        raise PlanError(f"no positive {amount_field} values for project: {project_id}")

    return {
        "format": "moonproj.company.cbs-budget-plan.v1",
        "source_snapshot_id": f"erp-snapshot:{source_sha256}",
        "mapping_version": required_string(
            budget.get("mapping_version"), "mapping_version"
        ),
        "version_id": version_id,
        "project_scope": project_scope,
        "principal_id": principal_id,
        "currency": currency,
        "subjects": subjects,
        "links": links,
        "source_table": "cb_cost",
        "source_amount_field": amount_field,
        "budget_control_only": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("cbs_mapping", type=Path)
    parser.add_argument("budget_mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        plan = build_plan(args.export, args.cbs_mapping, args.budget_mapping)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(
            json.dumps(
                {
                    "output": str(args.output),
                    "items": len(plan["links"]),
                    "mapping_version": plan["mapping_version"],
                },
                sort_keys=True,
            )
        )
        return 0
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"CBS budget plan failed: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
