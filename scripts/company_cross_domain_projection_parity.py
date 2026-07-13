#!/usr/bin/env python3
"""Compare every reviewed projection cohort across SQLite and PostgreSQL.

Individual backend parity reports prove that a receipt can be reopened in one
target.  This report adds the missing cross-domain assertion: the same source
snapshot/mapping cohort must have the same projection identities and canonical
payloads in both target stores.  It is evidence only; it never writes either
database.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from company_postgres_target_apply import PostgresTargetError, run_psql
from company_sqlite_projection_apply import RehearsalError, load_receipt


class CrossDomainParityError(RuntimeError):
    """A fail-closed cross-target evidence error."""


ProjectionKey = tuple[str, str, str, str]


def canonical(value: dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def receipt_paths(work_dir: Path) -> list[Path]:
    paths: list[Path] = []
    for path in sorted(work_dir.rglob("*.json")):
        if not (path.name.endswith("-promotion.json") or path.name.endswith("-receipt.json")):
            continue
        try:
            receipt = load_receipt(path)
        except (OSError, RehearsalError, json.JSONDecodeError, TypeError, KeyError):
            continue
        if receipt.get("format") == "moonproj.erp.domain-promotion.v1":
            paths.append(path)
    if not paths:
        raise CrossDomainParityError(f"no domain promotion receipts found below {work_dir}")
    return paths


def expected_keys(receipt: dict[str, Any]) -> list[ProjectionKey]:
    accepted = receipt.get("accepted_items")
    if not isinstance(accepted, list) or not accepted:
        raise CrossDomainParityError("promotion receipt has no accepted_items")
    result: list[ProjectionKey] = []
    for item in accepted:
        if not isinstance(item, dict):
            raise CrossDomainParityError("promotion receipt accepted item is not an object")
        result.append(
            (
                str(item.get("target_type", "")),
                str(item.get("target_id", "")),
                str(item.get("source_table", "")),
                str(item.get("source_id", "")),
            )
        )
    return result


def sqlite_rows(database: Path, receipt: dict[str, Any]) -> list[tuple[ProjectionKey, str]]:
    connection = sqlite3.connect(database)
    try:
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise CrossDomainParityError(f"SQLite integrity check failed: {integrity}")
        rows = connection.execute(
            "SELECT aggregate_type, aggregate_id, revision, payload "
            "FROM company_aggregate_projection "
            "ORDER BY aggregate_type, aggregate_id, revision"
        ).fetchall()
    except sqlite3.Error as error:
        raise CrossDomainParityError(f"cannot read SQLite projections: {error}") from error
    finally:
        connection.close()

    result: list[tuple[ProjectionKey, str]] = []
    for aggregate_type, aggregate_id, _revision, payload in rows:
        try:
            value = json.loads(payload)
        except (TypeError, json.JSONDecodeError) as error:
            raise CrossDomainParityError("SQLite projection payload is invalid JSON") from error
        if not isinstance(value, dict):
            raise CrossDomainParityError("SQLite projection payload is not an object")
        if (
            value.get("source_snapshot_id") != receipt.get("source_snapshot_id")
            or value.get("mapping_version") != receipt.get("mapping_version")
        ):
            continue
        key = (
            str(aggregate_type),
            str(aggregate_id),
            str(value.get("source_table", "")),
            str(value.get("source_id", "")),
        )
        result.append((key, canonical(value)))
    return result


def postgres_rows(args: argparse.Namespace, receipt: dict[str, Any]) -> list[tuple[ProjectionKey, str]]:
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
    try:
        output = run_psql(args, "\n".join(line.strip() for line in sql.splitlines() if line.strip()))
    except PostgresTargetError:
        raise
    result: list[tuple[ProjectionKey, str]] = []
    for line in output.splitlines():
        if not line:
            continue
        fields = line.split("|")
        if len(fields) != 3:
            raise CrossDomainParityError("unexpected PostgreSQL projection output")
        try:
            value = json.loads(bytes.fromhex(fields[2]).decode("utf-8"))
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise CrossDomainParityError("PostgreSQL projection payload is invalid JSON") from error
        if not isinstance(value, dict):
            raise CrossDomainParityError("PostgreSQL projection payload is not an object")
        key = (
            fields[0],
            fields[1],
            str(value.get("source_table", "")),
            str(value.get("source_id", "")),
        )
        result.append((key, canonical(value)))
    return result


def counters(values: list[tuple[ProjectionKey, str]]) -> Counter[ProjectionKey]:
    return Counter(key for key, _payload in values)


def payloads(values: list[tuple[ProjectionKey, str]]) -> dict[ProjectionKey, list[str]]:
    result: dict[ProjectionKey, list[str]] = defaultdict(list)
    for key, payload in values:
        result[key].append(payload)
    for entries in result.values():
        entries.sort()
    return dict(result)


def compare_receipt(
    args: argparse.Namespace,
    sqlite_database: Path,
    receipt_path: Path,
) -> dict[str, Any]:
    receipt = load_receipt(receipt_path)
    expected = expected_keys(receipt)
    expected_counter = Counter(expected)
    duplicate_expected = sorted(
        [list(key) + [count] for key, count in expected_counter.items() if count > 1]
    )
    sqlite_values = sqlite_rows(sqlite_database, receipt)
    postgres_values = postgres_rows(args, receipt)
    sqlite_counter = counters(sqlite_values)
    postgres_counter = counters(postgres_values)
    sqlite_payloads = payloads(sqlite_values)
    postgres_payloads = payloads(postgres_values)
    sqlite_missing = sorted([list(key) + [count] for key, count in (expected_counter - sqlite_counter).items()])
    postgres_missing = sorted([list(key) + [count] for key, count in (expected_counter - postgres_counter).items()])
    sqlite_extra = sorted([list(key) + [count] for key, count in (sqlite_counter - expected_counter).items()])
    postgres_extra = sorted([list(key) + [count] for key, count in (postgres_counter - expected_counter).items()])
    cross_missing = sorted([list(key) + [count] for key, count in (sqlite_counter - postgres_counter).items()])
    cross_extra = sorted([list(key) + [count] for key, count in (postgres_counter - sqlite_counter).items()])
    payload_mismatches = []
    for key in sorted(set(sqlite_payloads) & set(postgres_payloads)):
        if sqlite_payloads[key] != postgres_payloads[key]:
            payload_mismatches.append(
                {
                    "key": list(key),
                    "sqlite_payload_count": len(sqlite_payloads[key]),
                    "postgres_payload_count": len(postgres_payloads[key]),
                }
            )
    state = "shadow_verified" if not (
        duplicate_expected
        or sqlite_missing
        or postgres_missing
        or sqlite_extra
        or postgres_extra
        or cross_missing
        or cross_extra
        or payload_mismatches
    ) else "mismatch"
    return {
        "file": str(receipt_path),
        "source_snapshot_id": receipt["source_snapshot_id"],
        "mapping_version": receipt["mapping_version"],
        "state": state,
        "expected_items": len(expected),
        "sqlite_items": len(sqlite_values),
        "postgres_items": len(postgres_values),
        "duplicate_expected": duplicate_expected,
        "sqlite_missing": sqlite_missing,
        "postgres_missing": postgres_missing,
        "sqlite_extra": sqlite_extra,
        "postgres_extra": postgres_extra,
        "cross_domain_missing": cross_missing,
        "cross_domain_extra": cross_extra,
        "payload_mismatches": payload_mismatches,
    }


def compare(args: argparse.Namespace) -> dict[str, Any]:
    receipts = receipt_paths(args.work_dir)
    cohorts = [compare_receipt(args, args.sqlite_database, path) for path in receipts]
    return {
        "format": "moonproj.erp.cross-domain-projection-parity.v1",
        "state": "shadow_verified" if cohorts and all(item["state"] == "shadow_verified" for item in cohorts) else "mismatch",
        "sqlite_database": str(args.sqlite_database),
        "postgres_database": args.database,
        "receipt_count": len(cohorts),
        "verified_receipts": sum(item["state"] == "shadow_verified" for item in cohorts),
        "cohorts": cohorts,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("work_dir", type=Path)
    parser.add_argument("sqlite_database", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--psql", default=None)
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", default=None)
    parser.add_argument("--user", default=None)
    parser.add_argument("--database", default="moonproj")
    args = parser.parse_args()
    try:
        report = compare(args)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({
            "output": str(args.output),
            "receipt_count": report["receipt_count"],
            "verified_receipts": report["verified_receipts"],
            "state": report["state"],
        }, sort_keys=True))
        return 0 if report["state"] == "shadow_verified" else 1
    except (OSError, CrossDomainParityError, PostgresTargetError, RehearsalError, sqlite3.Error) as error:
        print(f"company cross-domain projection parity failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
