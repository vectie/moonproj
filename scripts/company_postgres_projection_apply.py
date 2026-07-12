#!/usr/bin/env python3
"""Persist a native promotion receipt as PostgreSQL aggregate projections.

The native MoonBit promotion receipt remains the authority boundary.  This
adapter only persists already-validated candidates into the PostgreSQL catalog
using immutable revisions, source-event identity, conflict checks, and a
cohort-scoped migration receipt.  It intentionally does not infer business
state, post accounting, or release cash.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
import tempfile
from pathlib import Path
from typing import Any, Sequence

from company_postgres_target_apply import (
    PostgresTargetError,
    run_psql,
    schema,
    sql_literal,
)
from company_sqlite_projection_apply import (
    canonical_payload,
    event_id,
    load_receipt,
)


def write_stage_csv(receipt: dict[str, Any], destination: Path) -> None:
    with destination.open("w", encoding="utf-8", newline="") as output:
        writer = csv.writer(output, lineterminator="\n")
        writer.writerow(("aggregate_type", "aggregate_id", "payload", "source_event_id"))
        for item in receipt["accepted_items"]:
            writer.writerow(
                (
                    str(item["target_type"]),
                    str(item["target_id"]),
                    canonical_payload(receipt, item),
                    event_id(receipt, item),
                )
            )


def query_output(args: argparse.Namespace, sql: str) -> list[str]:
    return [line for line in run_psql(args, sql).splitlines() if line]


def logical_projection_hash(args: argparse.Namespace, receipt: dict[str, Any]) -> str:
    snapshot = sql_literal(str(receipt["source_snapshot_id"]))
    mapping = sql_literal(str(receipt["mapping_version"]))
    sql = f"""
SELECT encode(convert_to(aggregate_type, 'UTF8'), 'hex'),
       encode(convert_to(aggregate_id, 'UTF8'), 'hex'),
       revision::text,
       encode(convert_to(payload::text, 'UTF8'), 'hex'),
       encode(convert_to(source_event_id, 'UTF8'), 'hex')
FROM company_aggregate_projection
WHERE payload->>'source_snapshot_id' = {snapshot}
  AND payload->>'mapping_version' = {mapping}
ORDER BY aggregate_type, aggregate_id, revision
"""
    digest = hashlib.sha256()
    for line in query_output(args, "\n".join(part.strip() for part in sql.splitlines() if part.strip())):
        fields = line.split("|")
        if len(fields) != 5:
            raise PostgresTargetError("unexpected PostgreSQL projection hash output")
        try:
            decoded = [
                bytes.fromhex(fields[0]).decode("utf-8"),
                bytes.fromhex(fields[1]).decode("utf-8"),
                int(fields[2]),
                bytes.fromhex(fields[3]).decode("utf-8"),
                bytes.fromhex(fields[4]).decode("utf-8"),
            ]
        except (ValueError, UnicodeDecodeError) as error:
            raise PostgresTargetError("invalid PostgreSQL projection hash output") from error
        digest.update(json.dumps(decoded, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def apply_rows(args: argparse.Namespace, csv_path: Path) -> int:
    sql = f"""
BEGIN;
LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE;
CREATE TEMP TABLE staging_company_projection (
  aggregate_type VARCHAR(128) NOT NULL,
  aggregate_id VARCHAR(255) NOT NULL,
  payload JSONB NOT NULL,
  source_event_id VARCHAR(255) NOT NULL
) ON COMMIT DROP;
\\copy staging_company_projection(aggregate_type, aggregate_id, payload, source_event_id) FROM {sql_literal(str(csv_path))} WITH (FORMAT csv, HEADER true);
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM staging_company_projection s
    JOIN company_aggregate_projection p ON p.source_event_id = s.source_event_id
    WHERE p.aggregate_type <> s.aggregate_type
       OR p.aggregate_id <> s.aggregate_id
       OR p.payload <> s.payload
  ) THEN
    RAISE EXCEPTION 'company aggregate projection event conflict';
  END IF;
END $$;
WITH pending AS (
  SELECT s.aggregate_type, s.aggregate_id, s.payload, s.source_event_id,
         COALESCE(existing.max_revision, 0)
           + row_number() OVER (
               PARTITION BY s.aggregate_type, s.aggregate_id
               ORDER BY s.source_event_id
             )::integer AS revision
  FROM staging_company_projection s
  LEFT JOIN (
    SELECT aggregate_type, aggregate_id, max(revision) AS max_revision
    FROM company_aggregate_projection
    GROUP BY aggregate_type, aggregate_id
  ) existing
    ON existing.aggregate_type = s.aggregate_type
   AND existing.aggregate_id = s.aggregate_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM company_aggregate_projection p
    WHERE p.source_event_id = s.source_event_id
  )
), inserted AS (
  INSERT INTO company_aggregate_projection(
    aggregate_type, aggregate_id, revision, payload, source_event_id
  )
  SELECT aggregate_type, aggregate_id, revision, payload, source_event_id
  FROM pending
  ON CONFLICT DO NOTHING
  RETURNING 1
)
SELECT count(*)::text FROM inserted;
COMMIT;
"""
    sql_path = csv_path.with_name("apply-company-projections.sql")
    sql_path.write_text(sql, encoding="utf-8")
    values = [line.strip() for line in run_psql(args, file_path=sql_path).splitlines() if line.strip().isdigit()]
    if not values:
        raise PostgresTargetError("PostgreSQL projection apply did not return an inserted-row count")
    return int(values[-1])


def finalize_receipt(
    args: argparse.Namespace,
    receipt: dict[str, Any],
    run_id: str,
    baseline_hash: str,
    applied_hash: str,
) -> bool:
    mapping = "domain:" + str(receipt["mapping_version"])
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
       OR existing.state <> 'Projected'
       OR existing.applied_hash <> {sql_literal(applied_hash)} THEN
      RAISE EXCEPTION 'projection migration receipt conflict';
    END IF;
  END IF;
END $$;
WITH inserted AS (
  INSERT INTO company_migration_receipt(
    run_id, source_snapshot_id, target_schema_version, mapping_version,
    state, baseline_hash, applied_hash, certified_at
  ) VALUES (
    {sql_literal(run_id)}, {sql_literal(source)}, 4,
    {sql_literal(mapping)}, 'Projected',
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
        raise PostgresTargetError("PostgreSQL projection receipt did not return a row count")
    return int(values[-1]) == 1


def run(args: argparse.Namespace, receipt_path: Path) -> dict[str, Any]:
    receipt = load_receipt(receipt_path)
    seed = "|".join((str(receipt["source_snapshot_id"]), str(receipt["mapping_version"])))
    run_id = "postgres-domain-projection-" + hashlib.sha256(seed.encode("utf-8")).hexdigest()[:16]
    schema(args)
    with tempfile.TemporaryDirectory(prefix="moonproj-postgres-projection-") as directory:
        csv_path = Path(directory) / "projection.csv"
        write_stage_csv(receipt, csv_path)
        baseline_hash = logical_projection_hash(args, receipt)
        inserted = apply_rows(args, csv_path)
        applied_hash = logical_projection_hash(args, receipt)
    receipt_inserted = finalize_receipt(args, receipt, run_id, baseline_hash, applied_hash)
    verification = query_output(
        args,
        "SELECT count(*)::text FROM company_aggregate_projection",
    )
    if not verification or not verification[-1].isdigit():
        raise PostgresTargetError("PostgreSQL projection durability verification failed")
    return {
        "database": args.database,
        "run_id": run_id,
        "source_snapshot_id": receipt["source_snapshot_id"],
        "mapping_version": receipt["mapping_version"],
        "inserted_projections": inserted,
        "projection_count": int(verification[-1]),
        "receipt_inserted": receipt_inserted,
        "baseline_hash": baseline_hash,
        "applied_hash": applied_hash,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path, help="native domain-promotion receipt")
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
        print(f"company PostgreSQL projection apply failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
