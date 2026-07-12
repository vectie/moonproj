#!/usr/bin/env python3
"""Apply the company SQL catalog to a SQLite rehearsal database.

The input is the redacted NDJSON produced by erp_snapshot_stage_raw.sh. This
is deliberately a staging adapter: it persists opaque legacy/raw envelopes in
company_record, but does not promote them into company aggregates or release
business effects. A production service may reuse the same schema and
transaction invariants behind a proper database connection pool.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import sys
from pathlib import Path
from typing import Any, Iterable


MIGRATIONS: tuple[tuple[int, str, tuple[str, ...]], ...] = (
    (
        1,
        "sha256:company-record-envelope-v1",
        (
            """
            CREATE TABLE IF NOT EXISTS company_schema (
              version INTEGER NOT NULL,
              checksum VARCHAR(255) NOT NULL,
              applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
              PRIMARY KEY (version)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS company_record (
              record_type VARCHAR(128) NOT NULL,
              record_id VARCHAR(255) NOT NULL,
              schema_version INTEGER NOT NULL,
              payload TEXT NOT NULL,
              source_id VARCHAR(255) NOT NULL,
              created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
              PRIMARY KEY (record_type, record_id),
              UNIQUE (source_id)
            )
            """,
            "CREATE INDEX IF NOT EXISTS company_record_source_idx ON company_record(source_id)",
        ),
    ),
    (
        2,
        "sha256:aggregate-projection-v1",
        (
            """
            CREATE TABLE IF NOT EXISTS company_aggregate_projection (
              aggregate_type VARCHAR(128) NOT NULL,
              aggregate_id VARCHAR(255) NOT NULL,
              revision INTEGER NOT NULL,
              payload TEXT NOT NULL,
              source_event_id VARCHAR(255) NOT NULL,
              created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
              PRIMARY KEY (aggregate_type, aggregate_id, revision),
              UNIQUE (aggregate_type, aggregate_id, source_event_id)
            )
            """,
            "CREATE INDEX IF NOT EXISTS company_projection_event_idx ON company_aggregate_projection(source_event_id)",
        ),
    ),
    (
        3,
        "sha256:accounting-event-link-v1",
        (
            """
            CREATE TABLE IF NOT EXISTS company_accounting_event_link (
              event_id VARCHAR(255) NOT NULL,
              source_type VARCHAR(128) NOT NULL,
              source_id VARCHAR(255) NOT NULL,
              journal_id VARCHAR(255) NOT NULL,
              principal_id VARCHAR(255) NOT NULL,
              created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
              PRIMARY KEY (event_id),
              UNIQUE (source_type, source_id),
              UNIQUE (journal_id)
            )
            """,
            "CREATE INDEX IF NOT EXISTS company_accounting_source_idx ON company_accounting_event_link(source_type, source_id)",
        ),
    ),
    (
        4,
        "sha256:migration-receipt-v1",
        (
            """
            CREATE TABLE IF NOT EXISTS company_migration_receipt (
              run_id VARCHAR(255) NOT NULL,
              source_snapshot_id VARCHAR(255) NOT NULL,
              target_schema_version INTEGER NOT NULL,
              mapping_version VARCHAR(255) NOT NULL,
              state VARCHAR(32) NOT NULL,
              baseline_hash VARCHAR(255) NOT NULL,
              applied_hash VARCHAR(255) NOT NULL,
              certified_at TIMESTAMP,
              PRIMARY KEY (run_id)
            )
            """,
            "CREATE INDEX IF NOT EXISTS company_receipt_snapshot_idx ON company_migration_receipt(source_snapshot_id)",
        ),
    ),
)

SECRET_KEY = re.compile(r"password|secret|token|private|ip$", re.IGNORECASE)


class RehearsalError(RuntimeError):
    """A fail-closed staging or database invariant failure."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def reject_secret_keys(value: Any, path: str = "payload") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise RehearsalError(f"secret-shaped key at {path}.{key}")
            reject_secret_keys(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secret_keys(child, f"{path}[{index}]")


def load_stage(stage_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    manifest_path = Path(str(stage_path) + ".manifest.json")
    if not manifest_path.is_file():
        raise RehearsalError(f"staging manifest not found: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    source_hash = manifest.get("source_sha256")
    if not isinstance(source_hash, str) or re.fullmatch(r"[0-9a-f]{64}", source_hash) is None:
        raise RehearsalError("staging manifest has an invalid source hash")
    expected_hash = manifest.get("output_sha256")
    actual_hash = sha256_file(stage_path)
    if expected_hash != actual_hash:
        raise RehearsalError(
            f"staging hash mismatch: expected {expected_hash}, got {actual_hash}"
        )

    records: list[dict[str, Any]] = []
    seen_sources: set[str] = set()
    with stage_path.open("r", encoding="utf-8") as source:
        for line_number, line in enumerate(source, start=1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as error:
                raise RehearsalError(f"invalid staging JSON at line {line_number}") from error
            if not isinstance(record, dict):
                raise RehearsalError(f"staging line {line_number} is not an object")
            for field in ("record_type", "record_id", "source_id", "payload"):
                if not record.get(field):
                    raise RehearsalError(f"staging line {line_number} missing {field}")
            if not str(record["record_type"]).startswith("legacy/raw/"):
                raise RehearsalError(f"non-raw record in staging line {line_number}")
            if not str(record["source_id"]).startswith("erp:"):
                raise RehearsalError(f"non-ERP source in staging line {line_number}")
            if not isinstance(record["payload"], (dict, list)):
                raise RehearsalError(f"staging line {line_number} payload is not JSON data")
            if record["source_id"] in seen_sources:
                raise RehearsalError(f"duplicate source in staging: {record['source_id']}")
            seen_sources.add(record["source_id"])
            reject_secret_keys(record["payload"])
            records.append(record)

    expected_rows = sum(int(table["rows"]) for table in manifest.get("tables", []))
    if expected_rows != len(records):
        raise RehearsalError(
            f"staging row count mismatch: manifest {expected_rows}, file {len(records)}"
        )
    return manifest, records


def apply_migrations(connection: sqlite3.Connection) -> None:
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute(
        "CREATE TABLE IF NOT EXISTS company_schema ("
        "version INTEGER NOT NULL PRIMARY KEY, "
        "checksum VARCHAR(255) NOT NULL, "
        "applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)"
    )
    for version, checksum, statements in MIGRATIONS:
        existing = connection.execute(
            "SELECT checksum FROM company_schema WHERE version = ?", (version,)
        ).fetchone()
        if existing is not None and existing[0] != checksum:
            raise RehearsalError(
                f"schema checksum mismatch at version {version}: {existing[0]} != {checksum}"
            )
        for statement in statements:
            connection.execute(statement)
        if existing is None:
            connection.execute(
                "INSERT INTO company_schema(version, checksum) VALUES (?, ?)",
                (version, checksum),
            )


def logical_record_hash(connection: sqlite3.Connection) -> str:
    digest = hashlib.sha256()
    rows = connection.execute(
        "SELECT record_type, record_id, schema_version, payload, source_id "
        "FROM company_record ORDER BY record_type, record_id"
    )
    for row in rows:
        digest.update(json.dumps(list(row), ensure_ascii=False, separators=(",", ":")).encode())
        digest.update(b"\n")
    return digest.hexdigest()


def insert_records(connection: sqlite3.Connection, records: Iterable[dict[str, Any]]) -> int:
    inserted = 0
    for record in records:
        payload = json.dumps(record["payload"], ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        existing = connection.execute(
            "SELECT schema_version, payload, source_id FROM company_record "
            "WHERE record_type = ? AND record_id = ?",
            (record["record_type"], record["record_id"]),
        ).fetchone()
        if existing is not None:
            if existing != (4, payload, record["source_id"]):
                raise RehearsalError(
                    f"record conflict at {record['record_type']}:{record['record_id']}"
                )
            continue
        try:
            connection.execute(
                "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) "
                "VALUES (?, ?, ?, ?, ?)",
                (record["record_type"], record["record_id"], 4, payload, record["source_id"]),
            )
        except sqlite3.IntegrityError as error:
            raise RehearsalError(f"record uniqueness conflict at {record['source_id']}") from error
        inserted += 1
    return inserted


def ensure_receipt(
    connection: sqlite3.Connection,
    run_id: str,
    source_snapshot_id: str,
    baseline_hash: str,
    applied_hash: str,
) -> bool:
    existing = connection.execute(
        "SELECT source_snapshot_id, target_schema_version, mapping_version, state, "
        "baseline_hash, applied_hash FROM company_migration_receipt WHERE run_id = ?",
        (run_id,),
    ).fetchone()
    expected = (source_snapshot_id, 4, "erp-raw-staging-v1", "Applied", baseline_hash, applied_hash)
    if existing is not None:
        same_receipt = existing[:4] == expected[:4]
        idempotent_replay = (
            same_receipt
            and existing[5] == baseline_hash
            and baseline_hash == applied_hash
        )
        if existing != expected and not idempotent_replay:
            raise RehearsalError(f"migration receipt conflict at run {run_id}")
        return False
    connection.execute(
        "INSERT INTO company_migration_receipt(" 
        "run_id, source_snapshot_id, target_schema_version, mapping_version, state, "
        "baseline_hash, applied_hash) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (run_id, source_snapshot_id, 4, "erp-raw-staging-v1", "Applied", baseline_hash, applied_hash),
    )
    return True


def run(stage_path: Path, database_path: Path, run_id: str | None) -> dict[str, Any]:
    manifest, records = load_stage(stage_path)
    source_hash = str(manifest["source_sha256"])
    source_snapshot_id = f"erp-snapshot:{source_hash}"
    effective_run_id = run_id or f"raw-staging-{source_hash[:16]}"
    database_path.parent.mkdir(parents=True, exist_ok=True)

    connection = sqlite3.connect(database_path)
    try:
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("BEGIN IMMEDIATE")
        apply_migrations(connection)
        baseline_hash = logical_record_hash(connection)
        inserted = insert_records(connection, records)
        applied_hash = logical_record_hash(connection)
        receipt_inserted = ensure_receipt(
            connection,
            effective_run_id,
            source_snapshot_id,
            baseline_hash,
            applied_hash,
        )
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()

    reopened = sqlite3.connect(database_path)
    try:
        schema_version = reopened.execute("SELECT max(version) FROM company_schema").fetchone()[0]
        record_count = reopened.execute("SELECT count(*) FROM company_record").fetchone()[0]
        unique_sources = reopened.execute(
            "SELECT count(DISTINCT source_id) FROM company_record"
        ).fetchone()[0]
        receipt_count = reopened.execute(
            "SELECT count(*) FROM company_migration_receipt WHERE run_id = ?",
            (effective_run_id,),
        ).fetchone()[0]
        if schema_version != 4 or record_count != len(records) or unique_sources != record_count or receipt_count != 1:
            raise RehearsalError("durability verification failed after reopen")
    finally:
        reopened.close()

    return {
        "database": str(database_path),
        "source_sha256": source_hash,
        "run_id": effective_run_id,
        "schema_version": schema_version,
        "staged_rows": len(records),
        "inserted_rows": inserted,
        "receipt_inserted": receipt_inserted,
        "reopened_record_count": record_count,
        "unique_sources": unique_sources,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path, help="redacted raw staging NDJSON")
    parser.add_argument("database", type=Path, help="SQLite rehearsal database")
    parser.add_argument("--run-id", default=None)
    args = parser.parse_args()
    try:
        print(json.dumps(run(args.stage, args.database, args.run_id), ensure_ascii=False, sort_keys=True))
    except (OSError, RehearsalError, sqlite3.Error) as error:
        print(f"company SQLite rehearsal failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
