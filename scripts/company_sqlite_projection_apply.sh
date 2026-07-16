#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RECEIPT=${1:?usage: company_sqlite_projection_apply.sh RECEIPT DATABASE}
DATABASE=${2:?usage: company_sqlite_projection_apply.sh RECEIPT DATABASE}
SQLITE_BIN=${SQLITE_BIN:-sqlite3}
WORK_DIR=${TMPDIR:-/tmp}/moonproj-sqlite-apply.$$
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

moon run --target native "$SCRIPT_DIR/../cmd/sqlite_projection_apply" -- prepare "$RECEIPT" "$WORK_DIR"
conflict=$($SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/preflight.sql")
if [ -n "$conflict" ]; then
  echo "company SQLite projection apply failed: projection event conflict" >&2
  exit 1
fi
$SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" < "$WORK_DIR/before.sql" > "$WORK_DIR/before.rows"
$SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" < "$WORK_DIR/revisions.sql" > "$WORK_DIR/revisions.rows"
moon run --target native "$SCRIPT_DIR/../cmd/sqlite_projection_apply" -- plan "$RECEIPT" "$WORK_DIR" "$WORK_DIR/before.rows" "$WORK_DIR/revisions.rows"
receipt_conflict=$($SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/receipt-check.sql")
if [ -n "$receipt_conflict" ]; then
  echo "company SQLite projection apply failed: projection receipt conflict" >&2
  exit 1
fi
$SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/apply.sql" > "$WORK_DIR/apply.out"
receipt_inserted=$(tail -n 1 "$WORK_DIR/apply.out")
metadata_run=$(sed -n 's/.*"run_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK_DIR/metadata.json" | head -n 1)
source_snapshot_id=$(sed -n 's/.*"source_snapshot_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK_DIR/metadata.json" | head -n 1)
mapping_version=$(sed -n 's/.*"mapping_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK_DIR/metadata.json" | head -n 1)
$SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" "SELECT coalesce(hex(aggregate_type), ''), coalesce(hex(aggregate_id), ''), revision, coalesce(hex(payload), ''), coalesce(hex(source_event_id), '') FROM company_aggregate_projection WHERE json_extract(payload, '\$.source_snapshot_id') = '$(printf '%s' "$source_snapshot_id" | sed "s/'/''/g")' AND json_extract(payload, '\$.mapping_version') = '$(printf '%s' "$mapping_version" | sed "s/'/''/g")' ORDER BY aggregate_type, aggregate_id, revision;" > "$WORK_DIR/after.rows"
integrity=$($SQLITE_BIN -batch -noheader "$DATABASE" 'PRAGMA integrity_check;')
counts=$($SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" "SELECT (SELECT count(*) FROM company_aggregate_projection), (SELECT count(*) FROM company_migration_receipt WHERE run_id='$(printf '%s' "$metadata_run" | sed "s/'/''/g")');")
projection_count=${counts%%|*}
receipt_count=${counts#*|}
OUTPUT=${3:-}
if [ -z "$OUTPUT" ]; then
  OUTPUT="$WORK_DIR/report.json"
fi
exec moon run --target native "$SCRIPT_DIR/../cmd/sqlite_projection_apply" -- report "$WORK_DIR" "$WORK_DIR/after.rows" "$integrity" "$projection_count" "$receipt_count" "$receipt_inserted" "$DATABASE" "$OUTPUT"
