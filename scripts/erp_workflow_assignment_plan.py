#!/usr/bin/env python3
"""Build an explicit workflow-assignee promotion cohort.

Assignments are workflow configuration, not permissions. The plan requires
explicit target identities, process scopes, and step-capability mappings.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class PlanError(RuntimeError):
    pass


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read JSON: {path}") from error


def required_map(config: dict[str, Any], key: str) -> dict[str, str]:
    value = config.get(key)
    if not isinstance(value, dict) or not value:
        raise PlanError(f"{key} must be a non-empty object")
    return {str(k): str(v) for k, v in value.items()}


def build_plan(export: Path, mapping_path: Path) -> dict[str, Any]:
    manifest = load(export / "manifest.json")
    source_sha256 = manifest.get("source_sha256")
    if not isinstance(source_sha256, str) or len(source_sha256) != 64:
        raise PlanError("export manifest has no valid source hash")
    config = load(mapping_path)
    if not isinstance(config, dict):
        raise PlanError("mapping must be an object")
    capabilities = required_map(config, "workflow_capability_by_step")
    assignee_by_user = required_map(config, "assignee_by_user")
    principal_by_process = required_map(config, "principal_by_process")
    scope_by_process = required_map(config, "scope_by_process")
    definitions = load(export / "tables" / "wf_process_def.json")
    steps = load(export / "tables" / "wf_step_def.json")
    assignments = load(export / "tables" / "wf_step_assignee.json")
    users = load(export / "tables" / "sys_user.json")
    if not all(isinstance(value, list) for value in (definitions, steps, assignments, users)):
        raise PlanError("workflow exports must be arrays")
    definition_by_id = {str(row.get("process_guid", "")): row for row in definitions}
    step_by_id = {str(row.get("step_guid", "")): row for row in steps}
    user_ids = {str(row.get("user_id", "")) for row in users}
    items: list[dict[str, Any]] = []
    seen_assignments: set[str] = set()
    for row in assignments:
        source_id = str(row.get("assignee_guid", ""))
        step_id = str(row.get("step_guid", ""))
        user_id = str(row.get("assignee_user_guid", ""))
        reasons: list[str] = []
        if not source_id or source_id in seen_assignments:
            reasons.append("missing_or_duplicate_assignment_id")
        seen_assignments.add(source_id)
        step = step_by_id.get(step_id)
        if step is None:
            reasons.append("missing_workflow_step")
        process_id = str(step.get("process_guid", "")) if step else ""
        definition = definition_by_id.get(process_id)
        if definition is None:
            reasons.append("missing_workflow_definition")
        if user_id not in user_ids:
            reasons.append("missing_source_user")
        assignee_id = assignee_by_user.get(user_id)
        if not assignee_id:
            reasons.append("missing_assignee_mapping")
        principal_id = principal_by_process.get(process_id)
        if not principal_id:
            reasons.append("missing_principal_mapping")
        scope = scope_by_process.get(process_id)
        if not scope:
            reasons.append("missing_scope_mapping")
        capability = capabilities.get(step_id)
        if not capability:
            reasons.append("missing_capability_mapping")
        weight = int(row.get("weight") or 0)
        if weight <= 0:
            reasons.append("invalid_weight")
        target_id = "workflow-assignment:" + source_id
        candidate = None
        if not reasons and step is not None and definition is not None:
            candidate = {
                "assignment_id": target_id,
                "process_id": process_id,
                "process_key": definition.get("process_key"),
                "step_id": step_id,
                "assignee_id": assignee_id,
                "principal_id": principal_id,
                "scope": scope,
                "weight": weight,
                "step": {
                    "step_id": step_id,
                    "capability": capability,
                    "required_weight": int(step.get("threshold") or 1),
                },
            }
        items.append(
            {
                "source_table": "wf_step_assignee",
                "source_id": source_id,
                "target_type": "workflow_assignment",
                "target_id": target_id,
                "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                "reasons": sorted(set(reasons)),
                "warnings": [
                    "workflow assignment is configuration only; it does not grant permission or bypass decision authority"
                ],
                "target_candidate": candidate,
            }
        )
    ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
    return {
        "format": "moonproj.erp.workflow-assignment-plan.v1",
        "source_snapshot_id": f"erp-snapshot:{source_sha256}",
        "source_sha256": source_sha256,
        "mapping_version": config.get("mapping_version", "unversioned-workflow-assignment-map"),
        "cohort": "workflow-assignments-v1",
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
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"workflow assignment plan failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
