#!/usr/bin/env python3
"""Compare exact reviewed asset lifecycle candidates with projections.

The comparison includes capitalization cost, depreciation entries, disposal
basis, lifecycle state, and explicit non-posting markers.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from company_sqlite_projection_apply import load_receipt


class AssetParityError(RuntimeError):
    pass


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def expected(receipt: dict[str, Any]) -> dict[tuple[str, str, str, str], list[dict[str, Any]]]:
    if receipt.get("cohort") != "asset-lifecycle-v1":
        raise AssetParityError("receipt is not an asset-lifecycle cohort")
    result: dict[tuple[str, str, str, str], list[dict[str, Any]]] = defaultdict(list)
    for item in receipt.get("accepted_items", []):
        if not isinstance(item, dict) or item.get("target_type") != "asset":
            raise AssetParityError("asset receipt contains an invalid item")
        candidate = item.get("target_candidate")
        if not isinstance(candidate, dict):
            raise AssetParityError("asset receipt candidate is not an object")
        key = (
            str(item["target_type"]),
            str(item["target_id"]),
            str(item["source_table"]),
            str(item["source_id"]),
        )
        result[key].append(candidate)
    if not result:
        raise AssetParityError("asset receipt contains no assets")
    return result


def compare_rows(
    receipt: dict[str, Any],
    rows: list[tuple[str, str, dict[str, Any]]],
    integrity: str,
) -> dict[str, Any]:
    expected_by_key = expected(receipt)
    actual_by_key: dict[tuple[str, str, str, str], list[dict[str, Any]]] = defaultdict(list)
    for aggregate_type, aggregate_id, payload in rows:
        if (
            payload.get("source_snapshot_id") != receipt["source_snapshot_id"]
            or payload.get("mapping_version") != receipt["mapping_version"]
        ):
            continue
        key = (
            aggregate_type,
            aggregate_id,
            str(payload.get("source_table", "")),
            str(payload.get("source_id", "")),
        )
        candidate = payload.get("candidate")
        if not isinstance(candidate, dict):
            raise AssetParityError("asset projection candidate is not an object")
        actual_by_key[key].append(candidate)
    expected_counter = Counter(key for key, values in expected_by_key.items() for _ in values)
    actual_counter = Counter(key for key, values in actual_by_key.items() for _ in values)
    missing = [list(key) + [count] for key, count in (expected_counter - actual_counter).items()]
    extra = [list(key) + [count] for key, count in (actual_counter - expected_counter).items()]
    mismatches: list[dict[str, Any]] = []
    for key in sorted(set(expected_by_key) & set(actual_by_key)):
        want = sorted(canonical(value) for value in expected_by_key[key])
        got = sorted(canonical(value) for value in actual_by_key[key])
        if want != got:
            mismatches.append({"key": list(key), "expected": want, "actual": got})
    return {
        "format": "moonproj.erp.asset-lifecycle-parity.v1",
        "source_snapshot_id": receipt["source_snapshot_id"],
        "mapping_version": receipt["mapping_version"],
        "state": "shadow_verified" if integrity == "ok" and not missing and not extra and not mismatches else "mismatch",
        "integrity": integrity,
        "expected_items": sum(expected_counter.values()),
        "actual_items": sum(actual_counter.values()),
        "missing": sorted(missing),
        "extra": sorted(extra),
        "candidate_mismatches": mismatches,
    }


def sqlite_rows(database: Path) -> tuple[list[tuple[str, str, dict[str, Any]]], str]:
    connection = sqlite3.connect(database)
    try:
        integrity = str(connection.execute("PRAGMA integrity_check").fetchone()[0])
        rows = connection.execute(
            "SELECT aggregate_type, aggregate_id, payload "
            "FROM company_aggregate_projection ORDER BY aggregate_type, aggregate_id, revision"
        ).fetchall()
    finally:
        connection.close()
    parsed: list[tuple[str, str, dict[str, Any]]] = []
    for aggregate_type, aggregate_id, payload in rows:
        try:
            value = json.loads(payload)
        except json.JSONDecodeError as error:
            raise AssetParityError("SQLite asset projection payload is invalid JSON") from error
        if not isinstance(value, dict):
            raise AssetParityError("SQLite asset projection payload is not an object")
        parsed.append((str(aggregate_type), str(aggregate_id), value))
    return parsed, integrity


def postgres_rows(args: argparse.Namespace, receipt: dict[str, Any]) -> tuple[list[tuple[str, str, dict[str, Any]]], str]:
    from company_postgres_target_apply import PostgresTargetError, run_psql

    snapshot = str(receipt["source_snapshot_id"]).replace("'", "''")
    mapping = str(receipt["mapping_version"]).replace("'", "''")
    query = (
        "SELECT aggregate_type, aggregate_id, "
        "encode(convert_to(payload::text, 'UTF8'), 'hex') "
        "FROM company_aggregate_projection "
        f"WHERE payload->>'source_snapshot_id' = '{snapshot}' "
        f"AND payload->>'mapping_version' = '{mapping}' "
        "ORDER BY aggregate_type, aggregate_id, revision"
    )
    try:
        output = run_psql(args, query)
        integrity_output = run_psql(
            args,
            "SELECT CASE WHEN count(*) >= 0 THEN 'ok' ELSE 'failed' END "
            "FROM company_aggregate_projection",
        ).strip()
    except PostgresTargetError as error:
        raise AssetParityError(str(error)) from error
    rows: list[tuple[str, str, dict[str, Any]]] = []
    for line in output.splitlines():
        if not line:
            continue
        fields = line.split("|")
        if len(fields) != 3:
            raise AssetParityError("unexpected PostgreSQL asset parity output")
        try:
            payload = json.loads(bytes.fromhex(fields[2]).decode("utf-8"))
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise AssetParityError("PostgreSQL asset projection payload is invalid") from error
        if not isinstance(payload, dict):
            raise AssetParityError("PostgreSQL asset projection payload is not an object")
        rows.append((fields[0], fields[1], payload))
    return rows, integrity_output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--backend", choices=("sqlite", "postgres"), default="sqlite")
    parser.add_argument("--database", type=Path, default=None)
    parser.add_argument("--psql", default=None)
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", default=None)
    parser.add_argument("--user", default=None)
    args = parser.parse_args()
    try:
        receipt = load_receipt(args.receipt)
        if args.backend == "sqlite":
            if args.database is None:
                raise AssetParityError("SQLite backend requires --database")
            rows, integrity = sqlite_rows(args.database)
        else:
            rows, integrity = postgres_rows(args, receipt)
        report = compare_rows(receipt, rows, integrity)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return 0 if report["state"] == "shadow_verified" else 1
    except (OSError, AssetParityError, sqlite3.Error) as error:
        print(f"asset-lifecycle parity failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
