#!/usr/bin/env python3
"""Apply the redacted ERP raw staging envelope to the PostgreSQL target.

The ERP export remains a source-side, credential-free artifact.  This adapter
is the target-side boundary: it validates the staging manifest with the same
rules as the SQLite rehearsal, applies the PostgreSQL catalog, and inserts the
opaque envelopes in one transaction.  A deterministic migration receipt is
finalized after the data transaction; a retry therefore repairs an interrupted
receipt write without duplicating or changing a row.

The password is intentionally not a command-line option.  Use ``PGPASSWORD``,
``.pgpass``, or the service's secret environment when invoking this script.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Sequence

from company_sqlite_rehearsal import RehearsalError, load_stage


class PostgresTargetError(RuntimeError):
    """A fail-closed target connection or persistence invariant failure."""


def executable(value: str | None) -> str:
    if value:
        return value
    bundled = Path("/Library/PostgreSQL/18/bin/psql")
    if bundled.is_file():
        return str(bundled)
    resolved = shutil.which("psql")
    if resolved:
        return resolved
    raise PostgresTargetError("psql executable was not found")


def connection_args(args: argparse.Namespace) -> list[str]:
    result: list[str] = []
    for flag, value in (("-h", args.host), ("-p", args.port), ("-U", args.user), ("-d", args.database)):
        if value:
            result.extend((flag, value))
    return result


def run_psql(
    args: argparse.Namespace,
    sql: str | None = None,
    *,
    file_path: Path | None = None,
) -> str:
    command = [
        executable(args.psql),
        "-X",
        "-v",
        "ON_ERROR_STOP=1",
        "-A",
        "-t",
        "-F",
        "|",
        *connection_args(args),
    ]
    if file_path is not None:
        command.extend(("-f", str(file_path)))
    else:
        command.extend(("-c", sql or ""))
    environment = os.environ.copy()
    # Never print or persist the password; psql reads it from the environment
    # or a user's normal PostgreSQL credential mechanism.
    completed = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        env=environment,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "unknown psql error"
        raise PostgresTargetError(detail)
    return completed.stdout


def schema(args: argparse.Namespace) -> None:
    schema_path = args.schema.resolve()
    if not schema_path.is_file():
        raise PostgresTargetError(f"PostgreSQL schema file not found: {schema_path}")
    run_psql(args, file_path=schema_path)


def payload_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def write_stage_csv(records: Sequence[dict[str, Any]], destination: Path) -> None:
    with destination.open("w", encoding="utf-8", newline="") as output:
        writer = csv.writer(output, lineterminator="\n")
        writer.writerow(("record_type", "record_id", "schema_version", "payload", "source_id"))
        for record in records:
            writer.writerow(
                (
                    str(record["record_type"]),
                    str(record["record_id"]),
                    "4",
                    payload_text(record["payload"]),
                    str(record["source_id"]),
                )
            )


def hash_rows(args: argparse.Namespace) -> str:
    # Hex encoding keeps psql's line protocol unambiguous even when a source
    # payload contains punctuation or escaped whitespace.
    query = """
SELECT encode(convert_to(record_type, 'UTF8'), 'hex'),
       encode(convert_to(record_id, 'UTF8'), 'hex'),
       schema_version::text,
       encode(convert_to(payload::text, 'UTF8'), 'hex'),
       encode(convert_to(source_id, 'UTF8'), 'hex')
FROM company_record
ORDER BY record_type, record_id
"""
    output = run_psql(args, "\n".join(line.strip() for line in query.splitlines() if line.strip()))
    digest = hashlib.sha256()
    for line in output.splitlines():
        if not line:
            continue
        fields = line.split("|")
        if len(fields) != 5:
            raise PostgresTargetError("unexpected PostgreSQL record hash output")
        try:
            row = [
                bytes.fromhex(fields[0]).decode("utf-8"),
                bytes.fromhex(fields[1]).decode("utf-8"),
                int(fields[2]),
                bytes.fromhex(fields[3]).decode("utf-8"),
                bytes.fromhex(fields[4]).decode("utf-8"),
            ]
        except (ValueError, UnicodeDecodeError) as error:
            raise PostgresTargetError("invalid PostgreSQL record hash output") from error
        digest.update(json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def sql_literal(value: str) -> str:
    # All caller values are generated hashes/identifiers, but keep the SQL
    # boundary explicit so future callers cannot accidentally interpolate a
    # quote into the target command.
    return "'" + value.replace("'", "''") + "'"


def apply_rows(args: argparse.Namespace, csv_path: Path) -> int:
    csv_literal = sql_literal(str(csv_path))
    sql = f"""
BEGIN;
CREATE TEMP TABLE staging_company_record (
  record_type VARCHAR(128) NOT NULL,
  record_id VARCHAR(255) NOT NULL,
  schema_version INTEGER NOT NULL,
  payload JSONB NOT NULL,
  source_id VARCHAR(255) NOT NULL
) ON COMMIT DROP;
\\copy staging_company_record(record_type, record_id, schema_version, payload, source_id) FROM {csv_literal} WITH (FORMAT csv, HEADER true);
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM staging_company_record s
    JOIN company_record r
      ON r.record_type = s.record_type AND r.record_id = s.record_id
    WHERE r.schema_version <> s.schema_version
       OR r.payload <> s.payload
       OR r.source_id <> s.source_id
  ) THEN
    RAISE EXCEPTION 'company_record identity conflict';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM staging_company_record s
    JOIN company_record r ON r.source_id = s.source_id
    WHERE r.record_type <> s.record_type OR r.record_id <> s.record_id
  ) THEN
    RAISE EXCEPTION 'company_record source conflict';
  END IF;
END $$;
WITH inserted AS (
  INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id)
  SELECT record_type, record_id, schema_version, payload, source_id
  FROM staging_company_record
  ON CONFLICT DO NOTHING
  RETURNING 1
)
SELECT count(*)::text FROM inserted;
COMMIT;
"""
    sql_path = csv_path.with_name("apply-company-records.sql")
    sql_path.write_text(sql, encoding="utf-8")
    output = run_psql(args, file_path=sql_path)
    values = [line.strip() for line in output.splitlines() if line.strip().isdigit()]
    if not values:
        raise PostgresTargetError("PostgreSQL apply did not return an inserted-row count")
    return int(values[-1])


def finalize_receipt(
    args: argparse.Namespace,
    *,
    run_id: str,
    source_snapshot_id: str,
    baseline_hash: str,
    applied_hash: str,
) -> bool:
    sql = f"""
BEGIN;
DO $$
DECLARE existing company_migration_receipt%ROWTYPE;
BEGIN
  SELECT * INTO existing FROM company_migration_receipt WHERE run_id = {sql_literal(run_id)};
  IF FOUND THEN
    IF existing.source_snapshot_id <> {sql_literal(source_snapshot_id)}
       OR existing.target_schema_version <> 4
       OR existing.mapping_version <> 'erp-raw-staging-v1'
       OR existing.state <> 'Applied'
       OR existing.applied_hash <> {sql_literal(applied_hash)} THEN
      RAISE EXCEPTION 'migration receipt conflict';
    END IF;
  END IF;
END $$;
WITH inserted AS (
  INSERT INTO company_migration_receipt(
    run_id, source_snapshot_id, target_schema_version, mapping_version, state,
    baseline_hash, applied_hash, certified_at
  ) VALUES (
    {sql_literal(run_id)}, {sql_literal(source_snapshot_id)}, 4,
    'erp-raw-staging-v1', 'Applied', {sql_literal(baseline_hash)},
    {sql_literal(applied_hash)}, CURRENT_TIMESTAMP
  )
  ON CONFLICT (run_id) DO NOTHING
  RETURNING 1
)
SELECT count(*)::text FROM inserted;
COMMIT;
"""
    output = run_psql(args, sql)
    values = [line.strip() for line in output.splitlines() if line.strip().isdigit()]
    if not values:
        raise PostgresTargetError("PostgreSQL receipt finalize did not return a row count")
    return int(values[-1]) == 1


def run(stage_path: Path, args: argparse.Namespace) -> dict[str, Any]:
    manifest, records = load_stage(stage_path)
    source_hash = str(manifest["source_sha256"])
    source_snapshot_id = f"erp-snapshot:{source_hash}"
    run_id = args.run_id or f"raw-staging-{source_hash[:16]}"
    schema(args)
    with tempfile.TemporaryDirectory(prefix="moonproj-postgres-") as temporary:
        csv_path = Path(temporary) / "company-records.csv"
        write_stage_csv(records, csv_path)
        baseline_hash = hash_rows(args)
        inserted = apply_rows(args, csv_path)
        applied_hash = hash_rows(args)
    receipt_inserted = finalize_receipt(
        args,
        run_id=run_id,
        source_snapshot_id=source_snapshot_id,
        baseline_hash=baseline_hash,
        applied_hash=applied_hash,
    )
    output = run_psql(
        args,
        "SELECT (SELECT max(version) FROM company_schema)::text, "
        "(SELECT count(*) FROM company_schema)::text, "
        "(SELECT count(*) FROM company_record)::text, "
        "(SELECT count(DISTINCT source_id) FROM company_record)::text, "
        "(SELECT count(*)::text FROM company_migration_receipt WHERE run_id = "
        + sql_literal(run_id)
        + ");",
    )
    fields = [field for line in output.splitlines() if line.strip() for field in line.split("|")]
    if len(fields) != 5:
        raise PostgresTargetError("PostgreSQL durability query returned an unexpected shape")
    schema_version, schema_count, record_count, unique_sources, receipt_count = map(int, fields)
    if schema_version != 4 or schema_count != 4 or record_count != len(records) or unique_sources != record_count or receipt_count != 1:
        raise PostgresTargetError("PostgreSQL durability verification failed")
    return {
        "target": "postgresql",
        "source_sha256": source_hash,
        "run_id": run_id,
        "schema_version": schema_version,
        "staged_rows": len(records),
        "inserted_rows": inserted,
        "receipt_inserted": receipt_inserted,
        "reopened_record_count": record_count,
        "unique_sources": unique_sources,
        "baseline_hash": baseline_hash,
        "applied_hash": applied_hash,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path, help="redacted raw staging NDJSON")
    parser.add_argument("--schema", type=Path, default=Path(__file__).with_name("postgres_target_schema.sql"))
    parser.add_argument("--psql", default=None)
    parser.add_argument("--host", default=os.environ.get("PGHOST"))
    parser.add_argument("--port", default=os.environ.get("PGPORT"))
    parser.add_argument("--user", default=os.environ.get("PGUSER"))
    parser.add_argument("--database", default=os.environ.get("PGDATABASE"))
    parser.add_argument("--run-id", default=None)
    args = parser.parse_args()
    try:
        print(json.dumps(run(args.stage, args), ensure_ascii=False, sort_keys=True))
    except (OSError, RehearsalError, PostgresTargetError, ValueError) as error:
        print(f"company PostgreSQL target apply failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
