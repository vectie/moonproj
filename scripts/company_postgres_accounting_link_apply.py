#!/usr/bin/env python3
"""Persist a native accounting-link receipt in PostgreSQL.

Only the reviewed source/event/journal identity is persisted.  This adapter
does not post journals, release cash, infer a journal, or close a period.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
import tempfile
from pathlib import Path
from typing import Any

from company_postgres_target_apply import (
    PostgresTargetError,
    run_psql,
    schema,
    sql_literal,
)
from company_sqlite_accounting_link_apply import load_receipt


def write_stage_csv(receipt: dict[str, Any], destination: Path) -> None:
    with destination.open("w", encoding="utf-8", newline="") as output:
        writer = csv.writer(output, lineterminator="\n")
        writer.writerow(("event_id", "source_type", "source_id", "journal_id", "principal_id"))
        for item in receipt["accepted_items"]:
            writer.writerow(
                (
                    str(item["event_id"]),
                    str(item["source_type"]),
                    str(item["source_id"]),
                    str(item["journal_id"]),
                    str(item["principal_id"]),
                )
            )


def query_output(args: argparse.Namespace, sql: str) -> list[str]:
    return [line for line in run_psql(args, sql).splitlines() if line]


def logical_link_hash(args: argparse.Namespace, receipt: dict[str, Any]) -> str:
    event_ids = [str(item["event_id"]) for item in receipt["accepted_items"]]
    if not event_ids:
        raise PostgresTargetError("accounting-link receipt has no event IDs")
    values = ", ".join(sql_literal(event_id) for event_id in event_ids)
    sql = f"""
SELECT encode(convert_to(event_id, 'UTF8'), 'hex'),
       encode(convert_to(source_type, 'UTF8'), 'hex'),
       encode(convert_to(source_id, 'UTF8'), 'hex'),
       encode(convert_to(journal_id, 'UTF8'), 'hex'),
       encode(convert_to(principal_id, 'UTF8'), 'hex')
FROM company_accounting_event_link
WHERE event_id IN ({values})
ORDER BY event_id
"""
    digest = hashlib.sha256()
    for line in query_output(args, "\n".join(part.strip() for part in sql.splitlines() if part.strip())):
        fields = line.split("|")
        if len(fields) != 5:
            raise PostgresTargetError("unexpected PostgreSQL accounting-link hash output")
        try:
            decoded = [bytes.fromhex(field).decode("utf-8") for field in fields]
        except (ValueError, UnicodeDecodeError) as error:
            raise PostgresTargetError("invalid PostgreSQL accounting-link hash output") from error
        digest.update(json.dumps(decoded, separators=(",", ":")).encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def apply_rows(args: argparse.Namespace, csv_path: Path) -> int:
    sql = f"""
BEGIN;
LOCK TABLE company_accounting_event_link IN SHARE ROW EXCLUSIVE MODE;
CREATE TEMP TABLE staging_company_accounting_link (
  event_id VARCHAR(255) NOT NULL,
  source_type VARCHAR(128) NOT NULL,
  source_id VARCHAR(255) NOT NULL,
  journal_id VARCHAR(255) NOT NULL,
  principal_id VARCHAR(255) NOT NULL
) ON COMMIT DROP;
\\copy staging_company_accounting_link(event_id, source_type, source_id, journal_id, principal_id) FROM {sql_literal(str(csv_path))} WITH (FORMAT csv, HEADER true);
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM staging_company_accounting_link s
    JOIN company_accounting_event_link l ON l.event_id = s.event_id
    WHERE l.source_type <> s.source_type
       OR l.source_id <> s.source_id
       OR l.journal_id <> s.journal_id
       OR l.principal_id <> s.principal_id
  ) THEN
    RAISE EXCEPTION 'company accounting-link event conflict';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM staging_company_accounting_link s
    JOIN company_accounting_event_link l
      ON l.source_type = s.source_type AND l.source_id = s.source_id
    WHERE l.event_id <> s.event_id
  ) THEN
    RAISE EXCEPTION 'company accounting-link source conflict';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM staging_company_accounting_link s
    JOIN company_accounting_event_link l ON l.journal_id = s.journal_id
    WHERE l.event_id <> s.event_id
  ) THEN
    RAISE EXCEPTION 'company accounting-link journal conflict';
  END IF;
END $$;
WITH inserted AS (
  INSERT INTO company_accounting_event_link(
    event_id, source_type, source_id, journal_id, principal_id
  )
  SELECT event_id, source_type, source_id, journal_id, principal_id
  FROM staging_company_accounting_link
  ON CONFLICT DO NOTHING
  RETURNING 1
)
SELECT count(*)::text FROM inserted;
COMMIT;
"""
    sql_path = csv_path.with_name("apply-company-accounting-links.sql")
    sql_path.write_text(sql, encoding="utf-8")
    values = [line.strip() for line in run_psql(args, file_path=sql_path).splitlines() if line.strip().isdigit()]
    if not values:
        raise PostgresTargetError("PostgreSQL accounting-link apply did not return an inserted-row count")
    return int(values[-1])


def finalize_receipt(
    args: argparse.Namespace,
    receipt: dict[str, Any],
    run_id: str,
    baseline_hash: str,
    applied_hash: str,
) -> bool:
    mapping = "accounting:" + str(receipt["mapping_version"])
    source = str(receipt["source_snapshot_id"])
    sql = f"""
BEGIN;
DO $$
DECLARE existing company_migration_receipt%ROWTYPE;
BEGIN
  SELECT * INTO existing
  FROM company_migration_receipt
  WHERE run_id = {sql_literal(run_id)};
  IF FOUND THEN
    IF existing.source_snapshot_id <> {sql_literal(source)}
       OR existing.target_schema_version <> 4
       OR existing.mapping_version <> {sql_literal(mapping)}
       OR existing.state <> 'AccountingLinked'
       OR existing.applied_hash <> {sql_literal(applied_hash)} THEN
      RAISE EXCEPTION 'accounting-link migration receipt conflict';
    END IF;
  END IF;
END $$;
WITH inserted AS (
  INSERT INTO company_migration_receipt(
    run_id, source_snapshot_id, target_schema_version, mapping_version,
    state, baseline_hash, applied_hash, certified_at
  ) VALUES (
    {sql_literal(run_id)}, {sql_literal(source)}, 4,
    {sql_literal(mapping)}, 'AccountingLinked',
    {sql_literal(baseline_hash)}, {sql_literal(applied_hash)}, CURRENT_TIMESTAMP
  )
  ON CONFLICT (run_id) DO NOTHING
  RETURNING 1
)
SELECT count(*)::text FROM inserted;
COMMIT;
"""
    values = [line.strip() for line in run_psql(args, sql).splitlines() if line.strip().isdigit()]
    if not values:
        raise PostgresTargetError("PostgreSQL accounting-link receipt did not return a row count")
    return int(values[-1]) == 1


def run(args: argparse.Namespace, receipt_path: Path) -> dict[str, Any]:
    receipt = load_receipt(receipt_path)
    seed = "|".join((str(receipt["source_snapshot_id"]), str(receipt["mapping_version"])))
    run_id = "postgres-accounting-link-" + hashlib.sha256(seed.encode("utf-8")).hexdigest()[:16]
    schema(args)
    with tempfile.TemporaryDirectory(prefix="moonproj-postgres-accounting-") as directory:
        csv_path = Path(directory) / "accounting-links.csv"
        write_stage_csv(receipt, csv_path)
        baseline_hash = logical_link_hash(args, receipt)
        inserted = apply_rows(args, csv_path)
        applied_hash = logical_link_hash(args, receipt)
    receipt_inserted = finalize_receipt(args, receipt, run_id, baseline_hash, applied_hash)
    verification = query_output(
        args,
        "SELECT count(*)::text FROM company_accounting_event_link",
    )
    if not verification or not verification[-1].isdigit():
        raise PostgresTargetError("PostgreSQL accounting-link durability verification failed")
    return {
        "database": args.database,
        "run_id": run_id,
        "source_snapshot_id": receipt["source_snapshot_id"],
        "mapping_version": receipt["mapping_version"],
        "inserted_accounting_links": inserted,
        "accounting_link_count": int(verification[-1]),
        "receipt_inserted": receipt_inserted,
        "baseline_hash": baseline_hash,
        "applied_hash": applied_hash,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path, help="native accounting-link receipt")
    parser.add_argument("--schema", type=Path, default=Path(__file__).with_name("postgres_target_schema.sql"))
    parser.add_argument("--psql", default=None)
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", default=None)
    parser.add_argument("--user", default=None)
    parser.add_argument("--database", default="moonproj")
    args = parser.parse_args()
    try:
        print(json.dumps(run(args, args.receipt), ensure_ascii=False, sort_keys=True))
        return 0
    except (OSError, PostgresTargetError) as error:
        print(f"company PostgreSQL accounting-link apply failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
