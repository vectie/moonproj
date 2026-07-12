#!/usr/bin/env python3
"""Build an explicit CBS source-to-subject cost-link cohort.

The planner consumes only the credential-safe ERP export. It never treats a
legacy cost code as a target CBS subject implicitly: every project, version,
subject, amount source, and owner must be named in the reviewed mapping.
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


def money_minor(value: Any, currency: str, policy: dict[str, Any]) -> int:
    if not isinstance(currency, str) or len(currency) != 3:
        raise PlanError(f"invalid currency: {currency!r}")
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
    if rounded <= 0:
        raise PlanError(f"amount must be positive: {value!r}")
    return int(rounded)


def item(
    source_id: str,
    target_id: str,
    candidate: dict[str, Any] | None,
    reasons: list[str],
) -> dict[str, Any]:
    return {
        "source_table": "cb_cost",
        "source_id": source_id,
        "target_type": "cbs_cost_link",
        "target_id": target_id,
        "disposition": "ready_for_domain_import" if not reasons else "quarantined",
        "reasons": sorted(set(reasons)),
        "warnings": [
            "CBS link allocates a source amount only; it does not consume budget or post accounting"
        ],
        "target_candidate": candidate if not reasons else None,
    }


def subject_value(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PlanError(f"subject {field} must be a non-empty string")
    return value


def build_plan(export_dir: Path, mapping_path: Path) -> dict[str, Any]:
    manifest = load_json(export_dir / "manifest.json")
    source_sha256 = manifest.get("source_sha256")
    if not isinstance(source_sha256, str) or len(source_sha256) != 64:
        raise PlanError("export manifest has no valid source hash")
    rows = load_json(export_dir / "tables" / "cb_cost.json")
    if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
        raise PlanError("cb_cost export is not an object array")
    config = load_json(mapping_path)
    if not isinstance(config, dict):
        raise PlanError("CBS mapping must be an object")
    projects = config.get("cbs_by_project")
    if not isinstance(projects, dict) or not projects:
        raise PlanError("cbs_by_project must be a non-empty object")
    policy = config.get("money_policy", {})
    if not isinstance(policy, dict):
        raise PlanError("money_policy must be an object")

    plans: dict[str, dict[str, Any]] = {}
    for project_id, raw in projects.items():
        if not isinstance(raw, dict):
            raise PlanError(f"CBS project mapping is not an object: {project_id}")
        version_id = subject_value(raw.get("version_id"), "version_id")
        principal_id = subject_value(raw.get("principal_id"), "principal_id")
        project_scope = subject_value(raw.get("project_scope"), "project_scope")
        amount_field = subject_value(raw.get("amount_field"), "amount_field")
        currency = subject_value(raw.get("currency"), "currency")
        if project_scope != f"project:{project_id}":
            raise PlanError(f"CBS project scope does not match project: {project_id}")
        raw_subjects = raw.get("subject_by_cost_code")
        if not isinstance(raw_subjects, dict) or not raw_subjects:
            raise PlanError(f"subject_by_cost_code must be non-empty: {project_id}")
        subjects: list[dict[str, Any]] = []
        seen_codes: set[str] = set()
        subjects_by_source: dict[str, dict[str, Any]] = {}
        for source_code, subject_raw in raw_subjects.items():
            if not isinstance(subject_raw, dict):
                raise PlanError(f"subject mapping is not an object: {project_id}/{source_code}")
            subject = {
                "subject_id": subject_value(subject_raw.get("subject_id"), "subject_id"),
                "code": subject_value(subject_raw.get("code"), "code"),
                "name": subject_value(subject_raw.get("name"), "name"),
                "parent_code": str(subject_raw.get("parent_code", "")),
                "target_minor": int(subject_raw.get("target_minor", 0)),
            }
            if subject["target_minor"] < 0:
                raise PlanError(f"negative subject target: {project_id}/{source_code}")
            if subject["code"] in seen_codes:
                raise PlanError(f"duplicate target subject code: {project_id}/{subject['code']}")
            seen_codes.add(subject["code"])
            subjects.append(subject)
            subjects_by_source[str(source_code)] = subject
        subjects.sort(key=lambda value: value["code"])
        plans[str(project_id)] = {
            "version_id": version_id,
            "principal_id": principal_id,
            "project_scope": project_scope,
            "amount_field": amount_field,
            "currency": currency,
            "subjects": subjects,
            "subjects_by_source": subjects_by_source,
        }

    items: list[dict[str, Any]] = []
    for row in rows:
        source_id = str(row.get("cost_guid", ""))
        project_id = str(row.get("proj_guid", ""))
        cost_code = str(row.get("cost_code", ""))
        target_id = f"cbs-link:{source_id}"
        reasons: list[str] = []
        config_for_project = plans.get(project_id)
        if not source_id or not project_id or not cost_code:
            reasons.append("missing_cost_identity")
        if config_for_project is None:
            reasons.append("missing_cbs_project_mapping")
        subject = None
        if config_for_project is not None:
            subject = config_for_project["subjects_by_source"].get(cost_code)
            if subject is None:
                reasons.append("missing_cbs_subject_mapping")
        amount_minor: int | None = None
        currency = config_for_project["currency"] if config_for_project is not None else ""
        if config_for_project is not None:
            try:
                amount_minor = money_minor(row.get(config_for_project["amount_field"]), currency, policy)
            except (PlanError, TypeError, ValueError) as error:
                reasons.append(str(error))
        candidate: dict[str, Any] | None = None
        if config_for_project is not None and subject is not None and amount_minor is not None:
            candidate = {
                "link_id": target_id,
                "source_id": source_id,
                "version_id": config_for_project["version_id"],
                "project_scope": config_for_project["project_scope"],
                "subject_code": subject["code"],
                "principal_id": config_for_project["principal_id"],
                "amount_minor": amount_minor,
                "currency": currency,
                "cbs_version": {
                    "version_id": config_for_project["version_id"],
                    "project_scope": config_for_project["project_scope"],
                    "principal_id": config_for_project["principal_id"],
                    "subjects": config_for_project["subjects"],
                },
            }
        items.append(item(source_id, target_id, candidate, reasons))
    ready = sum(value["disposition"] == "ready_for_domain_import" for value in items)
    return {
        "format": "moonproj.erp.cbs-cost-link-plan.v1",
        "source_snapshot_id": f"erp-snapshot:{source_sha256}",
        "source_sha256": source_sha256,
        "mapping_version": config.get("mapping_version", "unversioned-cbs-cost-map"),
        "cohort": "cbs-cost-links-v1",
        "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
        "items": items,
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
        print(json.dumps({"output": str(args.output), **plan["summary"]}, sort_keys=True))
        return 0
    except (OSError, PlanError, TypeError, ValueError) as error:
        print(f"CBS cost-link plan failed: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
