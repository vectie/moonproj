#!/usr/bin/env python3
"""Persist a validated native promotion receipt as durable projections.

The native MoonBit command remains the authority boundary. This adapter only
persists the already-accepted target candidates into the SQL projection table,
using the same transaction, revision, source-event, and migration-receipt
controls as the raw staging rehearsal. It is a SQLite projection adapter, not
the final production connection pool/service.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import sys
from pathlib import Path
from typing import Any

from company_sqlite_rehearsal import RehearsalError
from company_sqlite_driver import CompanySqliteDriver


SECRET_KEY = re.compile(r"password|secret|token|private|ip$", re.IGNORECASE)


def reject_secret_keys(value: Any, path: str = "candidate") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SECRET_KEY.search(str(key)):
                raise RehearsalError(f"secret-shaped key at {path}.{key}")
            reject_secret_keys(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secret_keys(child, f"{path}[{index}]")


def load_receipt(path: Path) -> dict[str, Any]:
    try:
        receipt = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RehearsalError(f"cannot read promotion receipt: {path}") from error
    if not isinstance(receipt, dict):
        raise RehearsalError("promotion receipt is not an object")
    if receipt.get("format") != "moonproj.erp.domain-promotion.v1":
        raise RehearsalError("unexpected promotion receipt format")
    if receipt.get("state") != "promoted_through_domain_importers":
        raise RehearsalError("promotion receipt is not domain-validated")
    if not isinstance(receipt.get("source_snapshot_id"), str):
        raise RehearsalError("promotion receipt has no source snapshot")
    if not isinstance(receipt.get("mapping_version"), str):
        raise RehearsalError("promotion receipt has no mapping version")
    accepted = receipt.get("accepted_items")
    if not isinstance(accepted, list) or not accepted:
        raise RehearsalError("promotion receipt has no accepted items")
    for index, item in enumerate(accepted):
        if not isinstance(item, dict):
            raise RehearsalError(f"accepted item {index} is not an object")
        for field in ("source_table", "source_id", "target_type", "target_id", "target_candidate"):
            if not item.get(field):
                raise RehearsalError(f"accepted item {index} missing {field}")
        if not isinstance(item["target_candidate"], dict):
            raise RehearsalError(f"accepted item {index} candidate is not an object")
        reject_secret_keys(item["target_candidate"], f"accepted[{index}].target_candidate")
    return receipt


def canonical_payload(receipt: dict[str, Any], item: dict[str, Any]) -> str:
    payload = {
        "format": "moonproj.company.aggregate-projection.v1",
        "source_snapshot_id": receipt["source_snapshot_id"],
        "mapping_version": receipt["mapping_version"],
        "source_table": item["source_table"],
        "source_id": item["source_id"],
        "aggregate_type": item["target_type"],
        "aggregate_id": item["target_id"],
        "candidate": item["target_candidate"],
    }
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def event_id(receipt: dict[str, Any], item: dict[str, Any]) -> str:
    raw = "|".join(
        (
            str(receipt["source_snapshot_id"]),
            str(receipt["mapping_version"]),
            str(item["source_table"]),
            str(item["source_id"]),
            str(item["target_type"]),
            str(item["target_id"]),
        )
    )
    return "erp-promotion:" + hashlib.sha256(raw.encode("utf-8")).hexdigest()


def logical_projection_hash(
    connection: sqlite3.Connection,
    source_snapshot_id: str | None = None,
    mapping_version: str | None = None,
) -> str:
    digest = hashlib.sha256()
    rows = connection.execute(
        "SELECT aggregate_type, aggregate_id, revision, payload, source_event_id "
        "FROM company_aggregate_projection "
        "ORDER BY aggregate_type, aggregate_id, revision"
    )
    for row in rows:
        if source_snapshot_id is not None or mapping_version is not None:
            try:
                payload = json.loads(row[3])
            except json.JSONDecodeError as error:
                raise RehearsalError("projection payload is invalid JSON") from error
            if (
                payload.get("source_snapshot_id") != source_snapshot_id
                or payload.get("mapping_version") != mapping_version
            ):
                continue
        digest.update(
            json.dumps(list(row), ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        )
        digest.update(b"\n")
    return digest.hexdigest()


def apply_projection_items(
    connection: sqlite3.Connection,
    receipt: dict[str, Any],
) -> int:
    inserted = 0
    for item in receipt["accepted_items"]:
        aggregate_type = str(item["target_type"])
        aggregate_id = str(item["target_id"])
        source_event_id = event_id(receipt, item)
        payload = canonical_payload(receipt, item)
        existing_event = connection.execute(
            "SELECT aggregate_type, aggregate_id, payload FROM company_aggregate_projection "
            "WHERE source_event_id = ?",
            (source_event_id,),
        ).fetchone()
        if existing_event is not None:
            if existing_event != (aggregate_type, aggregate_id, payload):
                raise RehearsalError(f"projection event conflict at {source_event_id}")
            continue
        revision_row = connection.execute(
            "SELECT COALESCE(MAX(revision), 0) FROM company_aggregate_projection "
            "WHERE aggregate_type = ? AND aggregate_id = ?",
            (aggregate_type, aggregate_id),
        ).fetchone()
        revision = int(revision_row[0]) + 1
        try:
            connection.execute(
                "INSERT INTO company_aggregate_projection(" 
                "aggregate_type, aggregate_id, revision, payload, source_event_id) "
                "VALUES (?, ?, ?, ?, ?)",
                (aggregate_type, aggregate_id, revision, payload, source_event_id),
            )
        except sqlite3.IntegrityError as error:
            raise RehearsalError(f"projection uniqueness conflict at {source_event_id}") from error
        inserted += 1
    return inserted


def ensure_projection_receipt(
    connection: sqlite3.Connection,
    run_id: str,
    receipt: dict[str, Any],
    baseline_hash: str,
    applied_hash: str,
) -> bool:
    mapping_version = "domain:" + str(receipt["mapping_version"])
    existing = connection.execute(
        "SELECT source_snapshot_id, target_schema_version, mapping_version, state, "
        "baseline_hash, applied_hash FROM company_migration_receipt WHERE run_id = ?",
        (run_id,),
    ).fetchone()
    expected = (
        receipt["source_snapshot_id"],
        4,
        mapping_version,
        "Projected",
        baseline_hash,
        applied_hash,
    )
    if existing is not None:
        if existing[:4] != expected[:4] or existing[5] != applied_hash:
            raise RehearsalError(f"projection receipt conflict at {run_id}")
        return False
    connection.execute(
        "INSERT INTO company_migration_receipt(" 
        "run_id, source_snapshot_id, target_schema_version, mapping_version, state, "
        "baseline_hash, applied_hash) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (run_id, *expected),
    )
    return True


def run(receipt_path: Path, database_path: Path) -> dict[str, Any]:
    receipt = load_receipt(receipt_path)
    run_seed = "|".join((str(receipt["source_snapshot_id"]), str(receipt["mapping_version"])))
    run_id = "domain-projection-" + hashlib.sha256(run_seed.encode("utf-8")).hexdigest()[:16]
    driver = CompanySqliteDriver(database_path)
    with driver.transaction() as connection:
        baseline_hash = logical_projection_hash(
            connection,
            source_snapshot_id=str(receipt["source_snapshot_id"]),
            mapping_version=str(receipt["mapping_version"]),
        )
        inserted = apply_projection_items(connection, receipt)
        applied_hash = logical_projection_hash(
            connection,
            source_snapshot_id=str(receipt["source_snapshot_id"]),
            mapping_version=str(receipt["mapping_version"]),
        )
        receipt_inserted = ensure_projection_receipt(
            connection, run_id, receipt, baseline_hash, applied_hash
        )

    reopened = driver.connect()
    try:
        integrity = reopened.execute("PRAGMA integrity_check").fetchone()[0]
        projection_count = reopened.execute(
            "SELECT count(*) FROM company_aggregate_projection"
        ).fetchone()[0]
        receipt_count = reopened.execute(
            "SELECT count(*) FROM company_migration_receipt WHERE run_id = ?", (run_id,)
        ).fetchone()[0]
        if integrity != "ok" or receipt_count != 1:
            raise RehearsalError("projection durability verification failed")
    finally:
        reopened.close()
    return {
        "database": str(database_path),
        "run_id": run_id,
        "source_snapshot_id": receipt["source_snapshot_id"],
        "mapping_version": receipt["mapping_version"],
        "inserted_projections": inserted,
        "projection_count": projection_count,
        "receipt_inserted": receipt_inserted,
        "integrity": integrity,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path, help="native domain-promotion receipt")
    parser.add_argument("database", type=Path, help="SQLite database from the raw rehearsal")
    args = parser.parse_args()
    try:
        print(json.dumps(run(args.receipt, args.database), ensure_ascii=False, sort_keys=True))
    except (OSError, RehearsalError, sqlite3.Error) as error:
        print(f"company SQLite projection apply failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
