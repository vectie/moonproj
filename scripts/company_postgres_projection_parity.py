#!/usr/bin/env python3
"""Compare a native promotion receipt with reopened PostgreSQL projections."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from company_postgres_target_apply import PostgresTargetError, run_psql
from company_sqlite_projection_apply import load_receipt


def query_rows(args: argparse.Namespace, receipt: dict[str, Any]) -> list[tuple[str, str, dict[str, Any]]]:
    snapshot = str(receipt["source_snapshot_id"]).replace("'", "''")
    mapping = str(receipt["mapping_version"]).replace("'", "''")
    sql = f"""
SELECT aggregate_type, aggregate_id,
       encode(convert_to(payload::text, 'UTF8'), 'hex')
FROM company_aggregate_projection
WHERE payload->>'source_snapshot_id' = '{snapshot}'
  AND payload->>'mapping_version' = '{mapping}'
ORDER BY aggregate_type, aggregate_id, revision
"""
    rows: list[tuple[str, str, dict[str, Any]]] = []
    for line in run_psql(args, "\n".join(part.strip() for part in sql.splitlines() if part.strip())).splitlines():
        if not line:
            continue
        fields = line.split("|")
        if len(fields) != 3:
            raise PostgresTargetError("unexpected PostgreSQL projection parity output")
        try:
            payload = json.loads(bytes.fromhex(fields[2]).decode("utf-8"))
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise PostgresTargetError("invalid PostgreSQL projection payload") from error
        if not isinstance(payload, dict):
            raise PostgresTargetError("projection payload is not an object")
        rows.append((fields[0], fields[1], payload))
    return rows


def compare(args: argparse.Namespace, receipt_path: Path) -> dict[str, Any]:
    receipt = load_receipt(receipt_path)
    expected_keys: list[tuple[str, str, str, str]] = []
    for item in receipt["accepted_items"]:
        expected_keys.append(
            (
                str(item["target_type"]),
                str(item["target_id"]),
                str(item["source_table"]),
                str(item["source_id"]),
            )
        )
    expected_counter = Counter(expected_keys)
    duplicates = sorted(
        [list(key) + [count] for key, count in expected_counter.items() if count > 1]
    )
    actual_keys: list[tuple[str, str, str, str]] = []
    for aggregate_type, aggregate_id, payload in query_rows(args, receipt):
        actual_keys.append(
            (
                aggregate_type,
                aggregate_id,
                str(payload.get("source_table", "")),
                str(payload.get("source_id", "")),
            )
        )
    actual_counter = Counter(actual_keys)
    missing = sorted(
        [list(key) + [count] for key, count in (expected_counter - actual_counter).items()]
    )
    extra = sorted(
        [list(key) + [count] for key, count in (actual_counter - expected_counter).items()]
    )
    expected_counts = dict(sorted(Counter(key[0] for key in expected_keys).items()))
    actual_counts = dict(sorted(Counter(key[0] for key in actual_keys).items()))
    state = "shadow_verified" if not duplicates and not missing and not extra else "mismatch"
    return {
        "format": "moonproj.erp.postgres-projection-parity.v1",
        "source_snapshot_id": receipt["source_snapshot_id"],
        "mapping_version": receipt["mapping_version"],
        "state": state,
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
    parser.add_argument("output", type=Path)
    parser.add_argument("--psql", default=None)
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", default=None)
    parser.add_argument("--user", default=None)
    parser.add_argument("--database", default="moonproj")
    args = parser.parse_args()
    try:
        report = compare(args, args.receipt)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return 0 if report["state"] == "shadow_verified" else 1
    except (OSError, PostgresTargetError) as error:
        print(f"company PostgreSQL projection parity failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
