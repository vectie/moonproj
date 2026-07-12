#!/usr/bin/env python3
"""Exercise the shared SQLite driver transaction and rollback contract."""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

from company_sqlite_driver import CompanySqliteDriver, INSERT_RECORD_SQL
from company_sqlite_rehearsal import RehearsalError


def run(path: Path) -> dict[str, object]:
    if path.exists():
        raise RehearsalError(f"driver smoke database already exists: {path}")
    driver = CompanySqliteDriver(path)
    try:
        try:
            with driver.transaction() as connection:
                driver.execute_prepared_command(
                    connection,
                    INSERT_RECORD_SQL,
                    ["driver_smoke", "rollback", "4", "{}", "smoke:rollback"],
                )
                raise RuntimeError("intentional rollback probe")
        except RuntimeError as error:
            if str(error) != "intentional rollback probe":
                raise
        try:
            with driver.transaction() as connection:
                params = ["driver_smoke", "duplicate", "4", "{}", "smoke:duplicate"]
                driver.execute_prepared_command(connection, INSERT_RECORD_SQL, params)
                driver.execute_prepared_command(connection, INSERT_RECORD_SQL, params)
        except RehearsalError:
            pass
        else:
            raise RehearsalError("duplicate command unexpectedly committed")
        with driver.transaction() as connection:
            driver.execute_prepared_command(
                connection,
                INSERT_RECORD_SQL,
                ["driver_smoke", "committed", "4", "{}", "smoke:committed"],
            )
        connection = driver.connect()
        try:
            count = int(
                connection.execute(
                    "SELECT count(*) FROM company_record WHERE record_type = 'driver_smoke'"
                ).fetchone()[0]
            )
        finally:
            connection.close()
        integrity = driver.verify_integrity()
        if count != 1 or integrity != "ok":
            raise RehearsalError("driver smoke verification failed")
        return {
            "database": str(path),
            "state": "driver_transaction_verified",
            "rolled_back_rows": 0,
            "committed_rows": count,
            "sql_command_verified": True,
            "duplicate_rejected": True,
            "integrity": integrity,
        }
    finally:
        for suffix in ("", "-wal", "-shm"):
            candidate = Path(str(path) + suffix)
            if candidate.exists():
                candidate.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(run(args.database), ensure_ascii=False, sort_keys=True))
    except (OSError, RehearsalError, sqlite3.Error) as error:
        print(f"company SQLite driver smoke failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
