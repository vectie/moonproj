#!/usr/bin/env python3
"""Compare a native promotion cohort with reopened SQLite projections."""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from company_sqlite_rehearsal import RehearsalError


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RehearsalError(f"cannot read {path}") from error
    if not isinstance(value, dict):
        raise RehearsalError("JSON root is not an object")
    return value


def compare(receipt: dict[str, Any], database: Path) -> dict[str, Any]:
    if receipt.get("format") != "moonproj.erp.domain-promotion.v1":
        raise RehearsalError("unexpected promotion receipt format")
    source_snapshot_id = receipt.get("source_snapshot_id")
    mapping_version = receipt.get("mapping_version")
    accepted = receipt.get("accepted_items")
    if not isinstance(source_snapshot_id, str) or not isinstance(mapping_version, str):
        raise RehearsalError("promotion receipt is missing identity")
    if not isinstance(accepted, list) or not accepted:
        raise RehearsalError("promotion receipt has no accepted items")

    expected_keys: list[tuple[str, str, str, str]] = []
    for item in accepted:
        if not isinstance(item, dict):
            raise RehearsalError("accepted item is not an object")
        expected_keys.append(
            (
                str(item.get("target_type", "")),
                str(item.get("target_id", "")),
                str(item.get("source_table", "")),
                str(item.get("source_id", "")),
            )
        )
    expected_counter = Counter(expected_keys)
    duplicates = sorted(
        [list(key) + [count] for key, count in expected_counter.items() if count > 1]
    )

    connection = sqlite3.connect(database)
    try:
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        rows = connection.execute(
            "SELECT aggregate_type, aggregate_id, revision, payload "
            "FROM company_aggregate_projection ORDER BY aggregate_type, aggregate_id, revision"
        ).fetchall()
    finally:
        connection.close()
    if integrity != "ok":
        raise RehearsalError(f"SQLite integrity check failed: {integrity}")

    actual_keys: list[tuple[str, str, str, str]] = []
    for aggregate_type, aggregate_id, _revision, payload in rows:
        try:
            value = json.loads(payload)
        except json.JSONDecodeError as error:
            raise RehearsalError("projection payload is invalid JSON") from error
        if (
            value.get("source_snapshot_id") != source_snapshot_id
            or value.get("mapping_version") != mapping_version
        ):
            continue
        actual_keys.append(
            (
                str(aggregate_type),
                str(aggregate_id),
                str(value.get("source_table", "")),
                str(value.get("source_id", "")),
            )
        )
    actual_counter = Counter(actual_keys)
    missing = sorted([list(key) + [count] for key, count in (expected_counter - actual_counter).items()])
    extra = sorted([list(key) + [count] for key, count in (actual_counter - expected_counter).items()])
    expected_counts = dict(sorted(Counter(key[0] for key in expected_keys).items()))
    actual_counts = dict(sorted(Counter(key[0] for key in actual_keys).items()))
    state = "shadow_verified" if not duplicates and not missing and not extra else "mismatch"
    return {
        "format": "moonproj.erp.projection-parity.v1",
        "source_snapshot_id": source_snapshot_id,
        "mapping_version": mapping_version,
        "state": state,
        "integrity": integrity,
        "expected_items": len(expected_keys),
        "actual_items": len(actual_keys),
        "expected_counts": expected_counts,
        "actual_counts": actual_counts,
        "duplicate_expected": duplicates,
        "missing": missing,
        "extra": extra,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("database", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        report = compare(load(args.receipt), args.database)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return 0 if report["state"] == "shadow_verified" else 1
    except (OSError, RehearsalError, sqlite3.Error) as error:
        print(f"company SQLite projection parity failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
