#!/usr/bin/env python3
"""Prove that every non-empty exported ERP row has a migration disposition.

Accepted native receipts provide direct source identities. A small number of
domain importers intentionally aggregate source rows into one governed record;
their plan candidates provide structural counts that are checked explicitly.
The report is coverage evidence, not promotion authorization.
"""

from __future__ import annotations

import argparse
import glob
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


class CoverageError(RuntimeError):
    pass


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CoverageError(f"cannot read JSON evidence: {path}") from error


def source_rows(export_dir: Path) -> dict[str, set[str]]:
    manifest = load(export_dir / "manifest.json")
    if manifest.get("format") not in {"moonproj.erp.snapshot.v1", "moonproj.erp.full-export.v1"}:
        raise CoverageError("unexpected export manifest format")
    result: dict[str, set[str]] = {}
    for entry in manifest.get("tables", []):
        table = entry.get("table")
        relative = entry.get("file")
        primary_key = entry.get("primary_key")
        if not isinstance(table, str) or not isinstance(relative, str):
            raise CoverageError("invalid export table entry")
        rows = load(export_dir / relative)
        if not isinstance(rows, list):
            raise CoverageError(f"export table is not an array: {table}")
        identities: set[str] = set()
        if rows:
            if not isinstance(primary_key, str) or not primary_key:
                raise CoverageError(f"non-empty table has no primary key: {table}")
            for row in rows:
                if not isinstance(row, dict) or primary_key not in row:
                    raise CoverageError(f"missing source identity in {table}")
                identities.add(str(row[primary_key]))
            if len(identities) != len(rows):
                raise CoverageError(f"duplicate source identity in {table}")
        result[table] = identities
    return result


def add_nested_counts(path: Path, nested: dict[str, int]) -> None:
    try:
        value = load(path)
    except CoverageError:
        return
    if not isinstance(value, dict):
        return
    fmt = value.get("format")
    if fmt == "moonproj.erp.workflow-promotion-plan.v1":
        for item in value.get("items", []):
            candidate = item.get("target_candidate", {}) if isinstance(item, dict) else {}
            nested["wf_step_def"] += len(candidate.get("steps", [])) if isinstance(candidate, dict) else 0
    elif fmt == "moonproj.erp.investment-promotion-plan.v1":
        for item in value.get("items", []):
            candidate = item.get("target_candidate", {}) if isinstance(item, dict) else {}
            nested["tzsy_plan_index"] += len(candidate.get("indexes", [])) if isinstance(candidate, dict) else 0
    elif fmt == "moonproj.erp.parameter-promotion-plan.v1":
        for item in value.get("items", []):
            if not isinstance(item, dict) or item.get("source_table") != "my_biz_param_option":
                continue
            candidate = item.get("target_candidate", {})
            nested["my_biz_param_option"] += len(candidate.get("options", [])) if isinstance(candidate, dict) else 0


def direct_receipt_ids(work_dir: Path, source: dict[str, set[str]]) -> dict[str, set[str]]:
    accepted: dict[str, set[str]] = defaultdict(set)
    paths = [Path(path) for path in glob.glob(str(work_dir / "*.json"))]
    paths.extend(Path(path) for path in glob.glob(str(work_dir / "typed-cohorts" / "*.json")))
    for path in paths:
        try:
            value = load(path)
        except CoverageError:
            continue
        if not isinstance(value, dict) or not isinstance(value.get("accepted_items"), list):
            continue
        for item in value["accepted_items"]:
            if not isinstance(item, dict):
                continue
            table = item.get("source_table")
            source_id = item.get("source_id")
            if table in source and isinstance(source_id, str) and source_id in source[table]:
                accepted[table].add(source_id)
    return accepted


def run(export_dir: Path, work_dir: Path, output: Path) -> dict[str, Any]:
    source = source_rows(export_dir)
    accepted = direct_receipt_ids(work_dir, source)
    nested: dict[str, int] = defaultdict(int)
    for path in [Path(path) for path in glob.glob(str(work_dir / "*.json"))]:
        add_nested_counts(path, nested)
    for path in [Path(path) for path in glob.glob(str(work_dir / "typed-cohorts" / "*.json"))]:
        add_nested_counts(path, nested)

    table_reports: list[dict[str, Any]] = []
    total_rows = 0
    covered_rows = 0
    uncovered_tables: list[str] = []
    for table in sorted(source):
        rows = len(source[table])
        direct = len(accepted.get(table, set()))
        structural = nested.get(table, 0)
        covered = min(rows, direct + structural)
        uncovered = rows - covered
        if uncovered:
            uncovered_tables.append(table)
        total_rows += rows
        covered_rows += covered
        table_reports.append({
            "table": table,
            "source_rows": rows,
            "direct_rows": direct,
            "structural_rows": structural,
            "covered_rows": covered,
            "uncovered_rows": uncovered,
            "state": "empty" if rows == 0 else ("covered" if uncovered == 0 else "uncovered"),
        })
    report = {
        "format": "moonproj.erp.row-coverage.v1",
        "state": "row_coverage_verified" if not uncovered_tables else "row_coverage_incomplete",
        "source_tables": len(source),
        "source_rows": total_rows,
        "covered_rows": covered_rows,
        "uncovered_rows": total_rows - covered_rows,
        "uncovered_tables": uncovered_tables,
        "promotion_authorized": False,
        "cutover_authorized": False,
        "tables": table_reports,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(output),
        "source_tables": len(source),
        "source_rows": total_rows,
        "covered_rows": covered_rows,
        "uncovered_rows": total_rows - covered_rows,
        "state": report["state"],
    }, sort_keys=True))
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export_dir", type=Path)
    parser.add_argument("work_dir", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        run(args.export_dir, args.work_dir, args.output)
        return 0
    except (OSError, CoverageError, TypeError, ValueError) as error:
        print(f"ERP row coverage failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
