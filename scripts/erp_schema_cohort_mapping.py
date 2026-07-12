#!/usr/bin/env python3
"""Validate an explicit target mapping for one ERP schema-only wave.

The source fixture may not contain rows for a schema-only table.  This command
therefore records semantic ownership and security handling without inventing
records or treating a mapping as a promotion receipt.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class MappingError(RuntimeError):
    pass


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise MappingError(f"cannot read {path}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cohort_plan", type=Path)
    parser.add_argument("mapping", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        plan = load(args.cohort_plan)
        mapping = load(args.mapping)
        if plan.get("format") != "moonproj.erp.schema-cohort-plan.v1":
            raise MappingError("unexpected schema cohort plan format")
        if mapping.get("format") != "moonproj.erp.schema-cohort-mapping.v1":
            raise MappingError("unexpected schema cohort mapping format")
        wave = mapping.get("wave")
        if not isinstance(wave, str) or not wave:
            raise MappingError("mapping wave is required")
        wave_entries = [item for item in plan.get("entries", []) if item.get("wave") == wave]
        if not wave_entries:
            raise MappingError(f"wave has no schema-only entries: {wave}")
        expected_tables = {str(item.get("table")) for item in wave_entries}
        rows = mapping.get("tables")
        if not isinstance(rows, list) or not rows:
            raise MappingError("mapping tables must be a non-empty array")
        seen: set[str] = set()
        accepted: list[dict[str, Any]] = []
        for item in rows:
            if not isinstance(item, dict):
                raise MappingError("mapping table entry is not an object")
            table = item.get("table")
            if not isinstance(table, str) or not table.strip():
                raise MappingError("mapping table has no table name")
            if table in seen:
                raise MappingError(f"duplicate mapping table: {table}")
            seen.add(table)
            if table not in expected_tables:
                raise MappingError(f"mapping table is outside wave {wave}: {table}")
            target = item.get("target")
            controls = item.get("security_controls")
            disposition = item.get("disposition")
            if not isinstance(target, dict) or not target.get("owner") or not target.get("record_type"):
                raise MappingError(f"{table} requires target owner and record type")
            if not isinstance(controls, list) or not controls:
                raise MappingError(f"{table} requires security controls")
            if disposition not in {"typed_import", "evidence_only", "exclude_sensitive"}:
                raise MappingError(f"{table} has unsupported disposition: {disposition}")
            source_rows = next(
                (int(entry.get("snapshot_rows", 0)) for entry in wave_entries if entry.get("table") == table),
                None,
            )
            if source_rows is None:
                raise MappingError(f"{table} is absent from cohort plan")
            accepted.append(
                {
                    "table": table,
                    "wave": wave,
                    "snapshot_rows": source_rows,
                    "target": target,
                    "security_controls": controls,
                    "disposition": disposition,
                    "promotion_authorized": False,
                }
            )
        missing = sorted(expected_tables - seen)
        if missing:
            raise MappingError("wave tables missing mappings: " + ",".join(missing))
        report = {
            "format": "moonproj.erp.schema-cohort-mapping-result.v1",
            "cohort_plan_format": plan.get("format"),
            "mapping_version": mapping.get("mapping_version"),
            "wave": wave,
            "state": "mapped_scope_only",
            "source_rows_available": sum(item["snapshot_rows"] for item in accepted),
            "mapped_tables": len(accepted),
            "tables": sorted(accepted, key=lambda item: item["table"]),
            "promotion_authorized": False,
            "cutover_authorized": False,
            "note": "Semantic ownership is explicit; no absent source rows were fabricated or promoted.",
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({
            "output": str(args.output),
            "wave": wave,
            "mapped_tables": len(accepted),
            "source_rows_available": report["source_rows_available"],
            "state": report["state"],
        }, sort_keys=True))
        return 0
    except (OSError, MappingError, TypeError, ValueError) as error:
        print(f"ERP schema cohort mapping failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
