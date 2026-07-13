#!/usr/bin/env python3
"""Compare exact reviewed opening controls with durable projections.

The generic projection parity gate checks identity/counts. This gate also
compares each opening-control candidate, including value, tolerance, unit, and
dimension, so a durable row cannot pass merely because its metric ID exists.
It supports both the SQLite rehearsal and the PostgreSQL target.
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


class OpeningParityError(RuntimeError):
    pass


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def expected(receipt: dict[str, Any]) -> dict[tuple[str, str, str, str], list[dict[str, Any]]]:
    if receipt.get("cohort") != "opening-control-v1":
        raise OpeningParityError("receipt is not an opening-control cohort")
    result: dict[tuple[str, str, str, str], list[dict[str, Any]]] = defaultdict(list)
    for item in receipt["accepted_items"]:
        if not isinstance(item, dict) or item.get("target_type") != "opening_control_total":
            raise OpeningParityError("opening receipt contains an invalid item")
        candidate = item.get("target_candidate")
        if not isinstance(candidate, dict):
            raise OpeningParityError("opening receipt candidate is not an object")
        key = (
            str(item["target_type"]),
            str(item["target_id"]),
            str(item["source_table"]),
            str(item["source_id"]),
        )
        result[key].append(candidate)
    if not result:
        raise OpeningParityError("opening receipt contains no controls")
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
            raise OpeningParityError("opening projection candidate is not an object")
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
        "format": "moonproj.erp.opening-control-parity.v1",
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


def sqlite_rows(receipt: dict[str, Any], database: Path) -> tuple[list[tuple[str, str, dict[str, Any]]], str]:
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
            raise OpeningParityError("SQLite projection payload is invalid JSON") from error
        if not isinstance(value, dict):
            raise OpeningParityError("SQLite projection payload is not an object")
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
        integrity_output = run_psql(args, "SELECT 'ok'").strip()
    except PostgresTargetError as error:
        raise OpeningParityError(str(error)) from error
    rows: list[tuple[str, str, dict[str, Any]]] = []
    for line in output.splitlines():
        if not line:
            continue
        fields = line.split("|")
        if len(fields) != 3:
            raise OpeningParityError("unexpected PostgreSQL opening parity output")
        try:
            payload = json.loads(bytes.fromhex(fields[2]).decode("utf-8"))
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise OpeningParityError("PostgreSQL opening projection payload is invalid") from error
        if not isinstance(payload, dict):
            raise OpeningParityError("PostgreSQL projection payload is not an object")
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
                raise OpeningParityError("SQLite backend requires --database")
            rows, integrity = sqlite_rows(receipt, args.database)
        else:
            rows, integrity = postgres_rows(args, receipt)
        report = compare_rows(receipt, rows, integrity)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return 0 if report["state"] == "shadow_verified" else 1
    except (OSError, OpeningParityError, sqlite3.Error) as error:
        print(f"opening-control parity failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
