#!/usr/bin/env python3
"""Persist validated accounting-event links into the company SQLite rehearsal.

This adapter consumes only the native accounting-link receipt. It records the
source-to-journal identity and principal, but it does not post cash, infer a
journal, or recognize an accounting event that was not explicitly reviewed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import sys
from pathlib import Path
from typing import Any

from company_sqlite_rehearsal import RehearsalError
from company_sqlite_driver import CompanySqliteDriver


def load_receipt(path: Path) -> dict[str, Any]:
    try:
        receipt = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RehearsalError(f"cannot read accounting-link receipt: {path}") from error
    if not isinstance(receipt, dict):
        raise RehearsalError("accounting-link receipt is not an object")
    if receipt.get("format") != "moonproj.erp.accounting-link-receipt.v1":
        raise RehearsalError("unexpected accounting-link receipt format")
    if receipt.get("state") != "validated_accounting_links":
        raise RehearsalError("accounting-link receipt is not native-validated")
    for field in ("source_snapshot_id", "mapping_version"):
        if not isinstance(receipt.get(field), str) or not receipt[field]:
            raise RehearsalError(f"accounting-link receipt has no {field}")
    accepted = receipt.get("accepted_items")
    if not isinstance(accepted, list) or not accepted:
        raise RehearsalError("accounting-link receipt has no accepted items")
    seen_events: set[str] = set()
    seen_sources: set[tuple[str, str]] = set()
    seen_journals: set[str] = set()
    for index, item in enumerate(accepted):
        if not isinstance(item, dict):
            raise RehearsalError(f"accounting-link item {index} is not an object")
        required = ("source_type", "source_id", "principal_id", "event_id", "journal_id")
        if any(not isinstance(item.get(field), str) or not item[field] for field in required):
            raise RehearsalError(f"accounting-link item {index} is missing identity")
        event_id = str(item["event_id"])
        source = (str(item["source_type"]), str(item["source_id"]))
        journal_id = str(item["journal_id"])
        if event_id in seen_events:
            raise RehearsalError(f"duplicate accounting event in receipt: {event_id}")
        if source in seen_sources:
            raise RehearsalError(f"duplicate accounting source in receipt: {source[0]}:{source[1]}")
        if journal_id in seen_journals:
            raise RehearsalError(f"duplicate journal in receipt: {journal_id}")
        seen_events.add(event_id)
        seen_sources.add(source)
        seen_journals.add(journal_id)
    return receipt


def logical_link_hash(
    connection: sqlite3.Connection,
    receipt: dict[str, Any] | None = None,
) -> str:
    digest = hashlib.sha256()
    if receipt is None:
        rows = connection.execute(
            "SELECT event_id, source_type, source_id, journal_id, principal_id "
            "FROM company_accounting_event_link ORDER BY event_id"
        )
    else:
        event_ids = [str(item["event_id"]) for item in receipt["accepted_items"]]
        placeholders = ",".join("?" for _ in event_ids)
        rows = connection.execute(
            "SELECT event_id, source_type, source_id, journal_id, principal_id "
            "FROM company_accounting_event_link WHERE event_id IN (" + placeholders + ") "
            "ORDER BY event_id",
            event_ids,
        )
    for row in rows:
        digest.update(json.dumps(list(row), separators=(",", ":")).encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def apply_links(connection: sqlite3.Connection, receipt: dict[str, Any]) -> int:
    inserted = 0
    for item in receipt["accepted_items"]:
        values = (
            str(item["event_id"]),
            str(item["source_type"]),
            str(item["source_id"]),
            str(item["journal_id"]),
            str(item["principal_id"]),
        )
        existing = connection.execute(
            "SELECT event_id, source_type, source_id, journal_id, principal_id "
            "FROM company_accounting_event_link WHERE event_id = ?",
            (values[0],),
        ).fetchone()
        if existing is not None:
            if tuple(existing) != values:
                raise RehearsalError(f"accounting-event conflict at {values[0]}")
            continue
        try:
            connection.execute(
                "INSERT INTO company_accounting_event_link(" 
                "event_id, source_type, source_id, journal_id, principal_id) "
                "VALUES (?, ?, ?, ?, ?)",
                values,
            )
        except sqlite3.IntegrityError as error:
            raise RehearsalError(f"accounting-event uniqueness conflict at {values[0]}") from error
        inserted += 1
    return inserted


def ensure_receipt(
    connection: sqlite3.Connection,
    run_id: str,
    receipt: dict[str, Any],
    baseline_hash: str,
    applied_hash: str,
) -> bool:
    mapping_version = "accounting:" + str(receipt["mapping_version"])
    expected = (
        str(receipt["source_snapshot_id"]),
        4,
        mapping_version,
        "AccountingLinked",
    )
    existing = connection.execute(
        "SELECT source_snapshot_id, target_schema_version, mapping_version, state, "
        "baseline_hash, applied_hash FROM company_migration_receipt WHERE run_id = ?",
        (run_id,),
    ).fetchone()
    if existing is not None:
        if tuple(existing[:4]) != expected or existing[5] != applied_hash:
            raise RehearsalError(f"accounting-link receipt conflict at {run_id}")
        return False
    connection.execute(
        "INSERT INTO company_migration_receipt(" 
        "run_id, source_snapshot_id, target_schema_version, mapping_version, state, "
        "baseline_hash, applied_hash) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (run_id, *expected, baseline_hash, applied_hash),
    )
    return True


def run(receipt_path: Path, database_path: Path) -> dict[str, Any]:
    receipt = load_receipt(receipt_path)
    seed = "|".join((str(receipt["source_snapshot_id"]), str(receipt["mapping_version"])))
    run_id = "accounting-link-" + hashlib.sha256(seed.encode("utf-8")).hexdigest()[:16]
    driver = CompanySqliteDriver(database_path)
    with driver.transaction() as connection:
        baseline_hash = logical_link_hash(connection, receipt)
        inserted = apply_links(connection, receipt)
        applied_hash = logical_link_hash(connection, receipt)
        receipt_inserted = ensure_receipt(
            connection, run_id, receipt, baseline_hash, applied_hash
        )

    reopened = driver.connect()
    try:
        integrity = reopened.execute("PRAGMA integrity_check").fetchone()[0]
        link_count = reopened.execute(
            "SELECT count(*) FROM company_accounting_event_link"
        ).fetchone()[0]
        receipt_count = reopened.execute(
            "SELECT count(*) FROM company_migration_receipt WHERE run_id = ?", (run_id,)
        ).fetchone()[0]
        if integrity != "ok" or receipt_count != 1:
            raise RehearsalError("accounting-link durability verification failed")
    finally:
        reopened.close()
    return {
        "database": str(database_path),
        "run_id": run_id,
        "source_snapshot_id": receipt["source_snapshot_id"],
        "mapping_version": receipt["mapping_version"],
        "inserted_accounting_links": inserted,
        "accounting_link_count": link_count,
        "receipt_inserted": receipt_inserted,
        "integrity": integrity,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path, help="native accounting-link receipt")
    parser.add_argument("database", type=Path, help="company SQLite database")
    args = parser.parse_args()
    try:
        print(json.dumps(run(args.receipt, args.database), ensure_ascii=False, sort_keys=True))
    except (OSError, RehearsalError, sqlite3.Error) as error:
        print(f"company SQLite accounting-link apply failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
