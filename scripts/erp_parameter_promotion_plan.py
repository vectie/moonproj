#!/usr/bin/env python3
"""Build an authority-scoped ERP parameter/dictionary promotion plan."""

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
        mappings = config.get("parameter_by_name", {})
        if not isinstance(mappings, dict):
            raise PlanError("parameter_by_name must be an object")
        source_by_name = config.get("parameter_source_by_name", {})
        if source_by_name is None:
            source_by_name = {}
        if not isinstance(source_by_name, dict):
            raise PlanError("parameter_source_by_name must be an object")
        allowed_sources = {"my_biz_param_option", "vys_proceeding"}
        for name, table in source_by_name.items():
            if not isinstance(name, str) or not isinstance(table, str):
                raise PlanError("parameter_source_by_name keys and values must be strings")
            if table not in allowed_sources:
                raise PlanError(f"unsupported parameter source: {table}")
        proceeding_names = [
            name for name, table in source_by_name.items() if table == "vys_proceeding"
        ]
        if len(proceeding_names) > 1:
            raise PlanError("vys_proceeding can map to only one parameter dictionary")

        # The original ERP parameter table and the expense-proceeding catalog
        # have different column names but both represent opaque, governed
        # configuration.  Keep the source table explicit in the mapping so a
        # catalog is never reinterpreted as accounting, CBS, or authority data.
        source_rows: dict[str, list[dict[str, Any]]] = {}
        default_rows = load(args.export / "tables" / "my_biz_param_option.json")
        if not isinstance(default_rows, list):
            raise PlanError("parameter export must be an array")
        for row in default_rows:
            if not isinstance(row, dict):
                raise PlanError("parameter row must be an object")
            parameter_name = str(row.get("param_name", ""))
            source_rows.setdefault(parameter_name, []).append(
                {
                    "source_table": "my_biz_param_option",
                    "parameter_id": str(row.get("id", "")),
                    "parameter_name": parameter_name,
                    "parameter_code": str(row.get("param_code", "")),
                    "parameter_value": row.get("param_value"),
                    "display_order": int(row.get("display_order", 0)),
                    "enabled": bool(row.get("enabled", 0)),
                }
            )

        proceeding_name = proceeding_names[0] if proceeding_names else None
        if proceeding_name is not None:
            proceeding_rows = load(args.export / "tables" / "vys_proceeding.json")
            if not isinstance(proceeding_rows, list):
                raise PlanError("proceeding export must be an array")
            normalized: list[dict[str, Any]] = []
            for index, row in enumerate(proceeding_rows):
                if not isinstance(row, dict):
                    raise PlanError("proceeding row must be an object")
                normalized.append(
                    {
                        "source_table": "vys_proceeding",
                        "parameter_id": str(row.get("proceeding_guid", "")),
                        "parameter_name": proceeding_name,
                        "parameter_code": str(row.get("proceeding_code", "")),
                        "parameter_value": row.get("proceeding_name"),
                        "display_order": index,
                        "enabled": bool(row.get("enabled", 0)),
                    }
                )
            source_rows[proceeding_name] = normalized

        grouped = source_rows
        items: list[dict[str, Any]] = []
        for parameter_name, group in sorted(grouped.items()):
            mapping = mappings.get(parameter_name)
            reasons: list[str] = []
            if not parameter_name:
                reasons.append("missing_parameter_name")
            if not group:
                reasons.append("empty_parameter_group")
            if not isinstance(mapping, dict):
                reasons.append("missing_parameter_mapping")
                mapping = {}
            principal = mapping.get("principal_id")
            scope = mapping.get("scope")
            if not principal or not scope:
                reasons.append("incomplete_parameter_mapping")
            source_table = str(group[0].get("source_table", "my_biz_param_option")) if group else "my_biz_param_option"
            expected_source = source_by_name.get(parameter_name, "my_biz_param_option")
            if expected_source != source_table:
                reasons.append("source_table_mapping_mismatch")
            group.sort(
                key=lambda row: (
                    int(row.get("display_order", 0)),
                    str(row.get("parameter_id", "")),
                )
            )
            options: list[dict[str, Any]] = []
            seen_ids: set[str] = set()
            seen_codes: set[str] = set()
            for row in group:
                option_id = str(row.get("parameter_id", ""))
                code = str(row.get("parameter_code", ""))
                if not option_id or option_id in seen_ids:
                    reasons.append(f"duplicate_or_missing_option_id:{option_id}")
                if not code or code in seen_codes:
                    reasons.append(f"duplicate_or_missing_option_code:{code}")
                if not isinstance(row.get("parameter_value"), str):
                    reasons.append(f"missing_parameter_value:{option_id}")
                seen_ids.add(option_id)
                seen_codes.add(code)
                options.append(
                    {
                        "parameter_id": option_id,
                        "parameter_name": parameter_name,
                        "parameter_code": code,
                        "parameter_value": row.get("parameter_value"),
                        "display_order": int(row.get("display_order", 0)),
                        "enabled": bool(row.get("enabled", 0)),
                    }
                )
            candidate = {
                "parameter_name": parameter_name,
                "principal_id": principal,
                "authority_scope": scope,
                "options": options,
            }
            items.append(
                {
                    "source_table": source_table,
                    "source_id": parameter_name,
                    "target_type": "parameter_dictionary",
                    "target_id": parameter_name,
                    "disposition": "ready_for_domain_import" if not reasons else "quarantined",
                    "reasons": sorted(set(reasons)),
                    "warnings": [
                        "parameter values remain opaque configuration; no CBS/accounting meaning is inferred",
                        "catalog metadata such as manager, department, and cost code remains source evidence",
                    ],
                    "target_candidate": candidate if not reasons else None,
                }
            )

        ready = sum(item["disposition"] == "ready_for_domain_import" for item in items)
        plan = {
            "format": "moonproj.erp.parameter-promotion-plan.v1",
            "source_snapshot_id": f"erp-snapshot:{manifest['source_sha256']}",
            "source_sha256": manifest["source_sha256"],
            "mapping_version": config.get("mapping_version", "unversioned-parameter-map"),
            "summary": {"items": len(items), "ready": ready, "quarantined": len(items) - ready},
            "items": items,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"output": str(args.output), **plan["summary"]}, ensure_ascii=False, sort_keys=True))
    except (OSError, PlanError, TypeError, ValueError, KeyError) as error:
        print(f"parameter promotion plan failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
