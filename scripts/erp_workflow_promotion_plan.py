#!/usr/bin/env python3
"""Build an explicit workflow-definition promotion plan from a safe export."""

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
        raise PlanError(f"cannot read {path}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        manifest = load(args.export / "manifest.json")
        config = load(args.mapping)
        capabilities = config.get("workflow_capability_by_step", {})
        if not isinstance(capabilities, dict):
            raise PlanError("workflow_capability_by_step must be an object")
        definitions = load(args.export / "tables" / "wf_process_def.json")
        steps = load(args.export / "tables" / "wf_step_def.json")
        if not isinstance(definitions, list) or not isinstance(steps, list):
            raise PlanError("workflow exports must be arrays")
        plan_items: list[dict[str, Any]] = []
        for definition in definitions:
            process_id = str(definition.get("process_guid", ""))
            process_steps = [step for step in steps if step.get("process_guid") == process_id]
            reasons: list[str] = []
            if not process_steps:
                reasons.append("missing_workflow_steps")
            process_steps.sort(key=lambda step: int(step.get("step_order", 0)))
            candidate_steps: list[dict[str, Any]] = []
            previous_order = 0
            for step in process_steps:
                step_id = str(step.get("step_guid", ""))
                order = int(step.get("step_order", 0))
                capability = capabilities.get(step_id)
                if not capability:
                    reasons.append(f"missing_capability_mapping:{step_id}")
                if order <= previous_order:
                    reasons.append(f"non_increasing_step_order:{step_id}")
                previous_order = order
                candidate_steps.append(
                    {
                        "step_id": step_id,
                        "process_id": process_id,
                        "step_key": step.get("step_key"),
                        "step_order": order,
                        "step_type": int(step.get("step_type", 1)),
                        "step_name": step.get("step_name"),
                        "threshold": int(step.get("threshold") or 1),
                        "remind_days": step.get("remind_days"),
                        "warn_days": step.get("warn_days"),
                        "capability": str(capability) if capability else None,
                    }
                )
            plan_items.append(
                {
                    "source_table": "wf_process_def",
                    "source_id": process_id,
                    "target_type": "workflow_definition",
                    "target_id": process_id,
                    "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                    "reasons": reasons,
                    "warnings": [],
                    "target_candidate": {
                        "process_id": process_id,
                        "process_key": definition.get("process_key"),
                        "process_name": definition.get("process_name"),
                        "biz_type": definition.get("biz_type"),
                        "steps": candidate_steps,
                    } if not reasons else None,
                }
            )
        ready = sum(item["disposition"] == "ready_for_domain_import" for item in plan_items)
        plan = {
            "format": "moonproj.erp.workflow-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-workflow-map"),
            "summary": {"items": len(plan_items), "ready": ready, "quarantined": len(plan_items) - ready},
            "items": plan_items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError) as error:
        print(f"workflow promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
