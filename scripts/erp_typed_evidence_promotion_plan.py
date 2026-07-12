#!/usr/bin/env python3
"""Build a fail-closed plan for typed ERP evidence rows.

These rows are deliberately not business aggregates. They are preserved as
typed, redacted evidence projections so task reports, workflow assignees,
lifecycle history/catalog labels, and proceeding catalogs remain queryable
without inventing target authority or state transitions.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


SECRET_KEY = re.compile(r"password|secret|token|private|ip$", re.IGNORECASE)
TABLES = {
    "jd_task": ("task_guid", "task_record_snapshot"),
    "jd_task_report": ("report_guid", "task_progress_report"),
    "wf_step_assignee": ("assignee_guid", "workflow_assignment"),
    "proj_lifecycle_instance": ("instance_id", "lifecycle_instance_history"),
    "proj_lifecycle_stage": ("stage_code", "lifecycle_stage_catalog"),
    "vys_proceeding": ("proceeding_guid", "expense_proceeding_catalog"),
}


class PlanError(RuntimeError):
    pass


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read {path}") from error


def reject_secrets(value: Any, path: str = "payload") -> None:
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
    parser.add_argument("export", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        manifest = load(args.export / "manifest.json")
        config = load(args.mapping)
        if not isinstance(config, dict):
            raise PlanError("mapping must be an object")
        classes = config.get("typed_evidence_class_by_table", {})
        if not isinstance(classes, dict):
            raise PlanError("typed_evidence_class_by_table must be an object")
        items: list[dict[str, Any]] = []
        for table, (primary_key, default_class) in TABLES.items():
            rows = load(args.export / "tables" / f"{table}.json")
            if not isinstance(rows, list):
                raise PlanError(f"evidence export is not an array: {table}")
            evidence_class = classes.get(table)
            reasons: list[str] = []
            if evidence_class != default_class:
                reasons.append(f"missing_or_invalid_evidence_class:{table}")
            seen: set[str] = set()
            for row in rows:
                if not isinstance(row, dict):
                    raise PlanError(f"evidence row is not an object: {table}")
                source_id = str(row.get(primary_key, ""))
                row_reasons = list(reasons)
                if not source_id or source_id in seen:
                    row_reasons.append("missing_or_duplicate_source_id")
                seen.add(source_id)
                try:
                    reject_secrets(row, f"{table}:{source_id}")
                except PlanError as error:
                    row_reasons.append(str(error))
                target_id = table + ":" + source_id
                candidate = {
                    "evidence_id": target_id,
                    "evidence_class": evidence_class,
                    "source_table": table,
                    "source_id": source_id,
                    "evidence_payload": row,
                    "evidence_policy": "typed-preservation-only",
                }
                items.append(
                    {
                        "source_table": table,
                        "source_id": source_id,
                        "target_type": "typed_evidence",
                        "target_id": target_id,
                        "disposition": "ready_for_domain_import" if not row_reasons else "quarantined",
                        "reasons": sorted(set(row_reasons)),
                        "warnings": [
                            "evidence is queryable preservation only; no target workflow, authority, or economic state is inferred"
                        ],
                        "target_candidate": candidate if not row_reasons else None,
                    }
                )
        ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
        plan = {
            "format": "moonproj.erp.typed-evidence-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-typed-evidence-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"typed-evidence promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
