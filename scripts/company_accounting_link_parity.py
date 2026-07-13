#!/usr/bin/env python3
"""Compare a reviewed accounting-link receipt with durable target rows.

The check is identity-only: it proves that event, source, journal, and
principal fields survived the adapter.  It does not post journals, release
cash, or certify a period.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path
from typing import Any

from company_postgres_target_apply import PostgresTargetError, run_psql, sql_literal
from company_sqlite_accounting_link_apply import load_receipt


class ParityError(RuntimeError):
    pass


def sqlite_rows(receipt: dict[str, Any], database: Path) -> dict[str, tuple[str, ...]]:
    connection = sqlite3.connect(database)
    try:
        event_ids = [str(item["event_id"]) for item in receipt["accepted_items"]]
        placeholders = ",".join("?" for _ in event_ids)
        rows = connection.execute(
            "SELECT event_id, source_type, source_id, journal_id, principal_id "
            "FROM company_accounting_event_link WHERE event_id IN (" + placeholders + ")",
            event_ids,
        ).fetchall()
        return {str(row[0]): tuple(str(value) for value in row) for row in rows}
    finally:
        connection.close()


def postgres_rows(args: argparse.Namespace, receipt: dict[str, Any]) -> dict[str, tuple[str, ...]]:
    event_ids = [str(item["event_id"]) for item in receipt["accepted_items"]]
    values = ", ".join(sql_literal(event_id) for event_id in event_ids)
    query = f"""
SELECT encode(convert_to(event_id, 'UTF8'), 'hex'),
       encode(convert_to(source_type, 'UTF8'), 'hex'),
       encode(convert_to(source_id, 'UTF8'), 'hex'),
       encode(convert_to(journal_id, 'UTF8'), 'hex'),
       encode(convert_to(principal_id, 'UTF8'), 'hex')
FROM company_accounting_event_link
WHERE event_id IN ({values})
ORDER BY event_id
"""
    output = run_psql(args, "\n".join(line.strip() for line in query.splitlines() if line.strip()))
    rows: dict[str, tuple[str, ...]] = {}
    for line in output.splitlines():
        if not line:
            continue
        fields = line.split("|")
        if len(fields) != 5:
            raise ParityError("unexpected PostgreSQL accounting-link row")
        try:
            decoded = tuple(bytes.fromhex(field).decode("utf-8") for field in fields)
        except (ValueError, UnicodeDecodeError) as error:
            raise ParityError("invalid PostgreSQL accounting-link row") from error
        rows[decoded[0]] = decoded
    return rows


def run(args: argparse.Namespace) -> dict[str, Any]:
    receipt = load_receipt(args.receipt)
    expected = {
        str(item["event_id"]): (
            str(item["event_id"]),
            str(item["source_type"]),
            str(item["source_id"]),
            str(item["journal_id"]),
            str(item["principal_id"]),
        )
        for item in receipt["accepted_items"]
    }
    if args.backend == "sqlite":
        if args.database is None:
            raise ParityError("--database is required for SQLite parity")
        actual = sqlite_rows(receipt, args.database)
    else:
        actual = postgres_rows(args, receipt)
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    mismatches = sorted(
        event_id
        for event_id in set(expected) & set(actual)
        if expected[event_id] != actual[event_id]
    )
    exact = not missing and not extra and not mismatches
    report = {
        "format": "moonproj.erp.accounting-link-parity.v1",
        "backend": args.backend,
        "source_snapshot_id": receipt["source_snapshot_id"],
        "mapping_version": receipt["mapping_version"],
        "state": "shadow_verified" if exact else "mismatch",
        "expected_count": len(expected),
        "matched_count": len(expected) - len(missing) - len(mismatches),
        "missing_event_ids": missing,
        "extra_event_ids": extra,
        "mismatched_event_ids": mismatches,
        "cash_released": False,
        "period_posted": False,
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    if not exact:
        raise ParityError("durable accounting-link identity mismatch")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("--backend", choices=("sqlite", "postgres"), required=True)
    parser.add_argument("--database", type=Path)
    parser.add_argument("--schema", type=Path, default=Path(__file__).with_name("postgres_target_schema.sql"))
    parser.add_argument("--psql", default=None)
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", default=None)
    parser.add_argument("--user", default=None)
    parser.add_argument("--database-name", dest="postgres_database", default="moonproj")
    args = parser.parse_args()
    if args.backend == "postgres":
        # company_postgres_target_apply.run_psql reads this conventional name.
        args.database = args.postgres_database
    try:
        run(args)
        return 0
    except (OSError, sqlite3.Error, PostgresTargetError, ParityError) as error:
        print(f"company accounting-link parity failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
