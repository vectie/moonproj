#!/usr/bin/env python3
"""Back up and reopen a company SQLite database with parity checks.

The check is deliberately logical rather than file-byte based: SQLite may
rewrite pages, WAL metadata, or timestamps while preserving the company data.
The destination is a restored database and must have the same schema, table
counts, integrity result, and deterministic logical digest as the source.
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


TABLES = (
    "company_schema",
    "company_record",
    "company_aggregate_projection",
    "company_accounting_event_link",
    "company_migration_receipt",
)


def logical_digest(connection: sqlite3.Connection) -> str:
    digest = hashlib.sha256()
    for table in TABLES:
        digest.update(table.encode("utf-8"))
        digest.update(b"\n")
        rows = connection.execute(f"SELECT * FROM {table} ORDER BY rowid").fetchall()
        for row in rows:
            digest.update(json.dumps(list(row), ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
            digest.update(b"\n")
    return digest.hexdigest()


def summary(path: Path) -> dict[str, Any]:
    connection = sqlite3.connect(path)
    try:
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        counts: dict[str, int] = {}
        for table in TABLES:
            try:
                counts[table] = int(connection.execute(f"SELECT count(*) FROM {table}").fetchone()[0])
            except sqlite3.Error as error:
                raise RehearsalError(f"restored database is missing {table}") from error
        schema_version = int(connection.execute("SELECT max(version) FROM company_schema").fetchone()[0])
        return {
            "integrity": integrity,
            "schema_version": schema_version,
            "counts": counts,
            "logical_digest": logical_digest(connection),
        }
    finally:
        connection.close()


def run(source_path: Path, backup_path: Path, overwrite: bool = False) -> dict[str, Any]:
    if not source_path.is_file():
        raise RehearsalError(f"source database not found: {source_path}")
    if backup_path.exists() and not overwrite:
        raise RehearsalError(f"backup destination already exists: {backup_path}")
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    CompanySqliteDriver(source_path).backup_to(backup_path, overwrite=overwrite)
    source_summary = summary(source_path)
    restored_summary = summary(backup_path)
    if source_summary["integrity"] != "ok" or restored_summary["integrity"] != "ok":
        raise RehearsalError("source or restored database failed integrity check")
    if source_summary != restored_summary:
        raise RehearsalError(
            "backup/restore parity mismatch: "
            + json.dumps({"source": source_summary, "restored": restored_summary}, sort_keys=True)
        )
    return {
        "source": str(source_path),
        "backup": str(backup_path),
        "state": "backup_restore_verified",
        "source_summary": source_summary,
        "restored_summary": restored_summary,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("backup", type=Path)
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()
    try:
        print(
            json.dumps(
                run(args.database, args.backup, overwrite=args.overwrite),
                ensure_ascii=False,
                sort_keys=True,
            )
        )
    except (OSError, RehearsalError, sqlite3.Error) as error:
        print(f"company SQLite backup/restore failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
