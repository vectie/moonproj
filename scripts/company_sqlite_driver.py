#!/usr/bin/env python3
"""Shared SQLite driver boundary for the company migration adapters.

The domain and migration commands remain database-neutral. This driver owns
the concrete SQLite concerns that must be consistent across every adapter:
foreign keys, WAL mode, busy timeout, immediate transactions, catalog
migrations, and rollback on an exception. It is suitable for the local
production-service prototype; deployment still needs a managed database,
pooling, encryption, retention, and operational restore controls.
"""

from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

from company_sqlite_rehearsal import RehearsalError, apply_migrations


INSERT_RECORD_SQL = (
    "INSERT INTO company_record (record_type, record_id, schema_version, payload, source_id, created_at) "
    "VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)"
)


class CompanySqliteDriver:
    """A transaction-safe SQLite connection boundary."""

    def __init__(self, path: Path, timeout_seconds: float = 30.0) -> None:
        self.path = path
        self.timeout_seconds = timeout_seconds

    def connect(self) -> sqlite3.Connection:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(self.path, timeout=self.timeout_seconds)
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 30000")
        connection.execute("PRAGMA journal_mode = WAL")
        return connection

    @contextmanager
    def transaction(self) -> Iterator[sqlite3.Connection]:
        connection = self.connect()
        try:
            connection.execute("BEGIN IMMEDIATE")
            apply_migrations(connection)
            yield connection
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()

    def execute_prepared_command(
        self,
        connection: sqlite3.Connection,
        sql: str,
        params: list[str],
    ) -> int:
        """Execute the record command emitted by `persistence/sql`.

        The allow-list is intentional: this adapter is a command port, not an
        arbitrary SQL console. New command shapes require a versioned contract
        and a corresponding invariant check.
        """
        if sql != INSERT_RECORD_SQL or len(params) != 5:
            raise RehearsalError("unsupported or malformed prepared SQL command")
        if any(not isinstance(value, str) for value in params):
            raise RehearsalError("prepared SQL parameters must be strings")
        try:
            schema_version = int(params[2])
        except ValueError as error:
            raise RehearsalError("prepared record schema version is not an integer") from error
        if schema_version <= 0:
            raise RehearsalError("prepared record schema version is not positive")
        if any(not value for value in (params[0], params[1], params[3], params[4])):
            raise RehearsalError("prepared record identity or payload is empty")
        try:
            connection.execute(sql, tuple(params))
        except sqlite3.IntegrityError as error:
            raise RehearsalError("prepared record uniqueness conflict") from error
        return 1

    def verify_integrity(self) -> str:
        connection = self.connect()
        try:
            return str(connection.execute("PRAGMA integrity_check").fetchone()[0])
        finally:
            connection.close()

    def backup_to(self, destination_path: Path, overwrite: bool = False) -> None:
        if destination_path.exists() and not overwrite:
            raise RehearsalError(f"backup destination already exists: {destination_path}")
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        source = self.connect()
        destination = sqlite3.connect(destination_path)
        try:
            source.backup(destination)
        finally:
            destination.close()
            source.close()


__all__ = ["CompanySqliteDriver", "INSERT_RECORD_SQL", "RehearsalError"]
