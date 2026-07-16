#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STAGE=${1:?usage: company_sqlite_rehearsal.sh STAGE DATABASE [--run-id ID]}
DATABASE=${2:?usage: company_sqlite_rehearsal.sh STAGE DATABASE [--run-id ID]}
SQLITE_BIN=${SQLITE_BIN:-sqlite3}
RUN_ID=
if [ "${3:-}" = "--run-id" ]; then RUN_ID=${4:?missing --run-id value}; fi
WORK_DIR=${TMPDIR:-/tmp}/moonproj-sqlite-rehearsal.$$
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

moon run --target native "$SCRIPT_DIR/../cmd/sqlite_rehearsal" -- prepare "$STAGE" "$WORK_DIR"
$SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/schema.sql"
schema_conflict=$($SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/schema-check.sql")
if [ -n "$schema_conflict" ]; then echo "company SQLite rehearsal failed: schema checksum conflict" >&2; exit 1; fi
$SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" < "$WORK_DIR/before.sql" > "$WORK_DIR/before.rows"
if [ -n "$RUN_ID" ]; then
  moon run --target native "$SCRIPT_DIR/../cmd/sqlite_rehearsal" -- plan "$STAGE" "$WORK_DIR" "$WORK_DIR/before.rows" "$RUN_ID"
else
  moon run --target native "$SCRIPT_DIR/../cmd/sqlite_rehearsal" -- plan "$STAGE" "$WORK_DIR" "$WORK_DIR/before.rows"
fi
conflict=$($SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/preflight.sql")
if [ -n "$conflict" ]; then echo "company SQLite rehearsal failed: record conflict" >&2; exit 1; fi
receipt_conflict=$($SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/receipt-check.sql")
if [ -n "$receipt_conflict" ]; then echo "company SQLite rehearsal failed: migration receipt conflict" >&2; exit 1; fi
$SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/apply.sql" > "$WORK_DIR/apply.out"
receipt_inserted=$(tail -n 1 "$WORK_DIR/apply.out")
$SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" < "$WORK_DIR/before.sql" > /dev/null
$SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" "SELECT coalesce(hex(record_type), ''), coalesce(hex(record_id), ''), schema_version, coalesce(hex(payload), ''), coalesce(hex(source_id), '') FROM company_record ORDER BY record_type, record_id;" > "$WORK_DIR/after.rows"
integrity=$($SQLITE_BIN -batch -noheader "$DATABASE" 'PRAGMA integrity_check;')
run_id=$(sed -n 's/.*"run_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK_DIR/metadata.json" | head -n 1)
counts=$($SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" "SELECT (SELECT max(version) FROM company_schema), (SELECT count(*) FROM company_record), (SELECT count(DISTINCT source_id) FROM company_record), (SELECT count(*) FROM company_migration_receipt WHERE run_id='$(printf '%s' "$run_id" | sed "s/'/''/g")');")
schema_version=${counts%%|*}; rest=${counts#*|}; record_count=${rest%%|*}; rest=${rest#*|}; unique_sources=${rest%%|*}; receipt_count=${rest#*|}
OUTPUT=${3:-}
if [ "$OUTPUT" = "--run-id" ]; then OUTPUT=${5:-}; fi
if [ -z "$OUTPUT" ] || [ "$OUTPUT" = "--run-id" ]; then OUTPUT="$WORK_DIR/report.json"; fi
exec moon run --target native "$SCRIPT_DIR/../cmd/sqlite_rehearsal" -- report "$WORK_DIR" "$WORK_DIR/after.rows" "$integrity" "$schema_version" "$record_count" "$unique_sources" "$receipt_count" "$receipt_inserted" "$DATABASE" "$OUTPUT"
