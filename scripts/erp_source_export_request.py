#!/usr/bin/env python3
"""Generate an exact request for the missing ERP schema tables."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


class RequestError(RuntimeError):
    pass


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RequestError(f"cannot read evidence: {path}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("schema_gap", type=Path)
    parser.add_argument("cohort_plan", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        gap = load(args.schema_gap)
        plan = load(args.cohort_plan)
        if gap.get("format") != "moonproj.erp.schema-gap.v1":
            raise RequestError("unexpected schema-gap format")
        if plan.get("format") != "moonproj.erp.schema-cohort-plan.v1":
            raise RequestError("unexpected schema-cohort-plan format")
        entries = [
            item for item in plan.get("entries", [])
            if isinstance(item, dict) and item.get("state") == "schema_only"
        ]
        if len(entries) != 49:
            raise RequestError(f"expected 49 schema-only entries, found {len(entries)}")
        request_entries = []
        for item in entries:
            request_entries.append({
                "table": item.get("table"),
                "wave": item.get("wave"),
                "capability_id": item.get("capability_id"),
                "snapshot_rows": item.get("snapshot_rows", 0),
                "required_export": {
                    "format": "redacted_json_array",
                    "primary_key": "required_for_non_empty_table",
                    "per_table_sha256": True,
                    "source_snapshot_hash": True,
                    "secret_keys_removed": ["password", "secret", "token", "private", "credential", "ip"],
                },
                "migration_action": item.get("migration_action"),
                "requested": True,
            })
        report = {
            "format": "moonproj.erp.source-export-request.v1",
            "state": "awaiting_source_export",
            "source_engine": "mysql",
            "schema_tables": gap.get("schema_tables"),
            "present_tables": gap.get("present_tables"),
            "requested_tables": len(request_entries),
            "source_snapshot_id": gap.get("source_snapshot_id"),
            "cutover_authorized": False,
            "promotion_authorized": False,
            "request": {
                "read_only": True,
                "credential_free_output": True,
                "include_empty_tables": True,
                "include_primary_keys": True,
                "include_table_hashes": True,
                "include_source_snapshot_hash": True,
                "exclude_credentials_and_network_secrets": True,
            },
            "tables": request_entries,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({
            "output": str(args.output),
            "requested_tables": len(request_entries),
            "state": report["state"],
        }, sort_keys=True))
        return 0
    except (OSError, RequestError, TypeError, ValueError) as error:
        print(f"ERP source export request failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
