#!/usr/bin/env python3
"""Generate or validate owner-approved empty-table dispositions.

The available ERP export is a 26-table rehearsal artifact while the schema
contains 75 tables.  This contract lets a source owner explicitly document
that a missing table was observed empty in a credential-safe source snapshot.
It does not import rows and never authorizes promotion or cutover.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class DispositionError(RuntimeError):
    pass


FORMAT = "moonproj.erp.empty-disposition.v1"
EMPTY_TABLE_SHA256 = hashlib.sha256(b"[]\n").hexdigest()
SNAPSHOT_HASH = re.compile(r"^[0-9a-f]{64}$")
SENSITIVE = re.compile(
    r"(?:password|secret|token|private|credential|dsn|connection.?string|bearer)",
    re.IGNORECASE,
)
DISPOSITIONS = {"pending", "owner_approved_empty", "source_export_required"}
SAFE_METADATA_VALUES = {
    "format",
    "state",
    "baseline_source_snapshot_id",
    "source_snapshot_hash",
    "source_snapshot_kind",
    "table",
    "capability_id",
    "wave",
    "snapshot_rows",
    "disposition",
    "row_count",
    "table_sha256",
    "promotion_authorized",
    "cutover_authorized",
    "schema_only_tables",
}


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise DispositionError(f"cannot read JSON evidence: {path}") from error


def write(path: Path, value: dict[str, Any]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except OSError as error:
        raise DispositionError(f"cannot write disposition: {path}") from error


def schema_only_entries(schema_gap: dict[str, Any], cohort_plan: dict[str, Any]) -> list[dict[str, Any]]:
    if schema_gap.get("format") != "moonproj.erp.schema-gap.v1":
        raise DispositionError("unexpected schema-gap format")
    if cohort_plan.get("format") != "moonproj.erp.schema-cohort-plan.v1":
        raise DispositionError("unexpected schema-cohort-plan format")
    gap_tables = {
        str(item.get("table")): item
        for item in schema_gap.get("entries", [])
        if isinstance(item, dict) and item.get("state") == "schema_only" and item.get("table")
    }
    plan_entries = [
        item for item in cohort_plan.get("entries", [])
        if isinstance(item, dict) and item.get("state") == "schema_only"
    ]
    if len(gap_tables) != 49 or len(plan_entries) != 49:
        raise DispositionError(
            f"expected 49 schema-only tables, found gap={len(gap_tables)} plan={len(plan_entries)}"
        )
    entries: list[dict[str, Any]] = []
    for item in sorted(plan_entries, key=lambda value: str(value.get("table"))):
        table = str(item.get("table"))
        if table not in gap_tables:
            raise DispositionError(f"cohort table is absent from schema gap: {table}")
        entries.append(
            {
                "table": table,
                "capability_id": item.get("capability_id"),
                "wave": item.get("wave"),
                "snapshot_rows": gap_tables[table].get("snapshot_rows", 0),
                "disposition": "pending",
                "source_evidence": {
                    "row_count": None,
                    "table_sha256": None,
                },
                "owner": None,
                "approved_at": None,
                "rationale": None,
                "evidence_ref": None,
            }
        )
    return entries


def template(schema_gap: dict[str, Any], cohort_plan: dict[str, Any]) -> dict[str, Any]:
    return {
        "format": FORMAT,
        "state": "awaiting_owner_disposition",
        "baseline_source_snapshot_id": schema_gap.get("source_snapshot_id"),
        "source_snapshot_hash": None,
        "source_snapshot_kind": "redacted_empty_table_evidence",
        "entries": schema_only_entries(schema_gap, cohort_plan),
        "promotion_authorized": False,
        "cutover_authorized": False,
    }


def reject_sensitive(value: Any, path: str = "root", key: str | None = None) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SENSITIVE.search(str(key)):
                raise DispositionError(f"sensitive key is not allowed: {path}.{key}")
            reject_sensitive(child, f"{path}.{key}", str(key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_sensitive(child, f"{path}[{index}]", key)
    elif isinstance(value, str) and key not in SAFE_METADATA_VALUES and SENSITIVE.search(value):
        raise DispositionError(f"sensitive value is not allowed: {path}")


def parse_utc(value: Any, path: str) -> datetime:
    if not isinstance(value, str) or not value.strip():
        raise DispositionError(f"{path} must be an ISO-8601 UTC timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise DispositionError(f"{path} must be an ISO-8601 UTC timestamp") from error
    if parsed.tzinfo is None or parsed.utcoffset() != timezone.utc.utcoffset(parsed):
        raise DispositionError(f"{path} must include UTC timezone")
    return parsed


def validate(
    schema_gap: dict[str, Any],
    cohort_plan: dict[str, Any],
    report: dict[str, Any],
) -> dict[str, Any]:
    expected = schema_only_entries(schema_gap, cohort_plan)
    expected_by_table = {entry["table"]: entry for entry in expected}
    if report.get("format") != FORMAT:
        raise DispositionError("unexpected empty-disposition format")
    source_hash = report.get("source_snapshot_hash")
    if not isinstance(source_hash, str) or not SNAPSHOT_HASH.fullmatch(source_hash):
        raise DispositionError("source_snapshot_hash must be a 64-character lowercase SHA-256")
    entries = report.get("entries")
    if not isinstance(entries, list):
        raise DispositionError("entries must be an array")
    seen: set[str] = set()
    counts = {name: 0 for name in DISPOSITIONS}
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise DispositionError(f"entries[{index}] must be an object")
        table = entry.get("table")
        if not isinstance(table, str) or table not in expected_by_table:
            raise DispositionError(f"entries[{index}] has an unexpected table")
        if table in seen:
            raise DispositionError(f"duplicate disposition for table: {table}")
        seen.add(table)
        disposition = entry.get("disposition")
        if disposition not in DISPOSITIONS:
            raise DispositionError(f"unsupported disposition for {table}: {disposition}")
        counts[disposition] += 1
        if entry.get("capability_id") != expected_by_table[table]["capability_id"]:
            raise DispositionError(f"capability_id does not match cohort plan for {table}")
        if entry.get("wave") != expected_by_table[table]["wave"]:
            raise DispositionError(f"wave does not match cohort plan for {table}")
        evidence = entry.get("source_evidence")
        if not isinstance(evidence, dict):
            raise DispositionError(f"source_evidence is required for {table}")
        if disposition == "owner_approved_empty":
            if type(evidence.get("row_count")) is not int or evidence.get("row_count") != 0:
                raise DispositionError(f"owner-approved empty table must have row_count=0: {table}")
            if evidence.get("table_sha256") != EMPTY_TABLE_SHA256:
                raise DispositionError(f"empty table hash does not match []\\n: {table}")
            owner = entry.get("owner")
            if not isinstance(owner, str) or not owner.strip() or len(owner) > 128:
                raise DispositionError(f"owner is required for {table}")
            parse_utc(entry.get("approved_at"), f"entries[{index}].approved_at")
            for field in ("rationale", "evidence_ref"):
                value = entry.get(field)
                if not isinstance(value, str) or not value.strip() or len(value) > 1000:
                    raise DispositionError(f"{field} is required for {table}")
        elif disposition == "pending":
            if entry.get("owner") not in (None, ""):
                raise DispositionError(f"pending entry cannot have an owner: {table}")
            if entry.get("approved_at") not in (None, ""):
                raise DispositionError(f"pending entry cannot have approval time: {table}")
        else:
            if entry.get("approved_at") not in (None, ""):
                raise DispositionError(f"source-export-required entry cannot be approved: {table}")
    missing = sorted(set(expected_by_table) - seen)
    if missing:
        raise DispositionError("missing schema-only dispositions: " + ",".join(missing))
    if len(entries) != len(expected_by_table):
        raise DispositionError(f"expected {len(expected_by_table)} dispositions, found {len(entries)}")
    state = "owner_dispositions_complete" if counts["pending"] == 0 and counts["source_export_required"] == 0 else (
        "source_export_required" if counts["pending"] == 0 else "awaiting_owner_disposition"
    )
    result = dict(report)
    result["state"] = state
    result["schema_only_tables"] = len(expected_by_table)
    result["disposition_counts"] = counts
    result["promotion_authorized"] = False
    result["cutover_authorized"] = False
    result["baseline_source_snapshot_id"] = schema_gap.get("source_snapshot_id")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("schema_gap", type=Path)
    parser.add_argument("cohort_plan", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--input", type=Path, help="disposition JSON to validate")
    parser.add_argument("--template", action="store_true", help="write a pending 49-table template")
    args = parser.parse_args()
    if args.template and args.input:
        parser.error("--template and --input are mutually exclusive")
    if not args.template and not args.input:
        parser.error("one of --template or --input is required")
    try:
        schema_gap = load(args.schema_gap)
        cohort_plan = load(args.cohort_plan)
        if args.template:
            report = template(schema_gap, cohort_plan)
        else:
            report = load(args.input)
            reject_sensitive(report)
            report = validate(schema_gap, cohort_plan, report)
        write(args.output, report)
        print(json.dumps({
            "output": str(args.output),
            "schema_only_tables": len(report.get("entries", [])),
            "state": report.get("state"),
            "promotion_authorized": False,
            "cutover_authorized": False,
        }, sort_keys=True))
        return 0
    except (OSError, DispositionError, TypeError, ValueError) as error:
        print(f"ERP empty disposition failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
