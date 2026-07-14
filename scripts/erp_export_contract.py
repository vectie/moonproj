#!/usr/bin/env python3
"""Validate a credential-free ERP export before migration staging.

The checker accepts the existing SQLite snapshot export and the future full
MySQL/JSON export shape. It verifies table coverage, per-table hashes, row
counts, safe relative paths, primary-key identity, and recursive secret
redaction. It never connects to the source database and never authorizes
promotion.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


class ExportError(RuntimeError):
    pass


SECRET_KEY = re.compile(r"password|secret|token|private|credential|ip$", re.IGNORECASE)
DSN_VALUE = re.compile(r"(?:postgres(?:ql)?|mysql)://", re.IGNORECASE)
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ExportError(f"cannot read JSON: {path}") from error


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise ExportError(f"cannot hash export file: {path}") from error
    return digest.hexdigest()


def reject_secrets(value: Any, path: str) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise ExportError(f"secret-shaped key at {path}.{key}")
            reject_secrets(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secrets(child, f"{path}[{index}]")
    elif isinstance(value, str) and DSN_VALUE.search(value):
        raise ExportError(f"raw database DSN at {path}")


def schema_tables(path: Path) -> set[str]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ExportError(f"cannot read schema initializer: {path}") from error
    names = set(re.findall(
        r"CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+([A-Za-z0-9_]+)",
        text,
        re.IGNORECASE,
    ))
    if not names:
        raise ExportError("schema initializer has no table definitions")
    return names


def validate(schema_path: Path, export_dir: Path) -> dict[str, Any]:
    manifest_path = export_dir / "manifest.json"
    manifest = load(manifest_path)
    if manifest.get("format") not in {
        "moonproj.erp.snapshot.v1",
        "moonproj.erp.full-export.v1",
    }:
        raise ExportError("unsupported export manifest format")
    source_hash = manifest.get("source_sha256")
    if not isinstance(source_hash, str) or not SHA256.fullmatch(source_hash):
        raise ExportError("export manifest has no valid source_sha256")
    if not isinstance(manifest.get("redaction"), str) or not manifest["redaction"].strip():
        raise ExportError("export manifest has no redaction declaration")
    entries = manifest.get("tables")
    if not isinstance(entries, list) or not entries:
        raise ExportError("export manifest tables must be a non-empty array")
    expected = schema_tables(schema_path)
    seen: set[str] = set()
    verified_rows = 0
    verified_files = 0
    table_reports: list[dict[str, Any]] = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ExportError("export table entry is not an object")
        table = entry.get("table")
        relative = entry.get("file")
        if not isinstance(table, str) or not re.fullmatch(r"[A-Za-z0-9_]+", table):
            raise ExportError("unsafe or missing table name")
        if table in seen:
            raise ExportError(f"duplicate table entry: {table}")
        seen.add(table)
        if not isinstance(relative, str) or not re.fullmatch(r"tables/[A-Za-z0-9_]+\.json", relative):
            raise ExportError(f"unsafe export path for {table}")
        if relative != f"tables/{table}.json":
            raise ExportError(f"table path does not match table name: {table}")
        table_path = export_dir / relative
        if not table_path.is_file():
            raise ExportError(f"export table missing: {table_path}")
        value = load(table_path)
        if not isinstance(value, list):
            raise ExportError(f"export table is not an array: {table}")
        reject_secrets(value, table)
        rows = entry.get("rows")
        if isinstance(rows, bool) or not isinstance(rows, int) or rows < 0:
            raise ExportError(f"invalid row count for {table}")
        if rows != len(value):
            raise ExportError(f"row count mismatch for {table}: manifest={rows}, file={len(value)}")
        primary_key = entry.get("primary_key", "")
        if rows and (not isinstance(primary_key, str) or not primary_key.strip()):
            raise ExportError(f"non-empty table has no primary key: {table}")
        if rows:
            seen_keys: set[str] = set()
            for index, row in enumerate(value):
                if not isinstance(row, dict):
                    raise ExportError(f"row is not an object for {table}[{index}]")
                key_value = row.get(primary_key)
                if key_value is None or key_value == "":
                    raise ExportError(f"primary-key value is missing for {table}[{index}]")
                key_identity = json.dumps(key_value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
                if key_identity in seen_keys:
                    raise ExportError(f"duplicate primary-key value for {table}: {key_value}")
                seen_keys.add(key_identity)
        table_hash = entry.get("sha256")
        if not isinstance(table_hash, str) or not SHA256.fullmatch(table_hash):
            raise ExportError(f"invalid table hash for {table}")
        actual_hash = hash_file(table_path)
        if actual_hash != table_hash:
            raise ExportError(f"table hash mismatch for {table}")
        verified_rows += rows
        verified_files += 1
        table_reports.append({"table": table, "rows": rows, "sha256": actual_hash, "verified": True})
    missing = sorted(expected - seen)
    extra = sorted(seen - expected)
    state = "ready_for_source_import" if not missing and not extra else "source_export_incomplete"
    return {
        "format": "moonproj.erp.export-contract.v1",
        "manifest_format": manifest.get("format"),
        "schema_tables": len(expected),
        "export_tables": len(seen),
        "present_tables": len(expected & seen),
        "missing_tables": missing,
        "extra_tables": extra,
        "verified_files": verified_files,
        "verified_rows": verified_rows,
        "source_sha256": source_hash,
        "state": state,
        "content_verified": True,
        "promotion_authorized": False,
        "cutover_authorized": False,
        "tables": sorted(table_reports, key=lambda item: item["table"]),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("schema", type=Path)
    parser.add_argument("export_dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        report = validate(args.schema, args.export_dir)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({
            "output": str(args.output),
            "schema_tables": report["schema_tables"],
            "export_tables": report["export_tables"],
            "missing_tables": len(report["missing_tables"]),
            "verified_rows": report["verified_rows"],
            "state": report["state"],
        }, sort_keys=True))
        return 0
    except (OSError, ExportError, TypeError, ValueError) as error:
        print(f"ERP export contract failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
