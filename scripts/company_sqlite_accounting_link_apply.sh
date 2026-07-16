#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RECEIPT=${1:?usage: company_sqlite_accounting_link_apply.sh RECEIPT DATABASE}
DATABASE=${2:?usage: company_sqlite_accounting_link_apply.sh RECEIPT DATABASE}
SQLITE_BIN=${SQLITE_BIN:-sqlite3}
WORK_DIR=${TMPDIR:-/tmp}/moonproj-sqlite-accounting-link.$$
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

moon run --target native "$SCRIPT_DIR/../cmd/sqlite_accounting_link_apply" -- prepare "$RECEIPT" "$WORK_DIR"
conflict=$($SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/preflight.sql")
if [ -n "$conflict" ]; then echo "company SQLite accounting-link apply failed: accounting-link conflict" >&2; exit 1; fi
$SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" < "$WORK_DIR/before.sql" > "$WORK_DIR/before.rows"
moon run --target native "$SCRIPT_DIR/../cmd/sqlite_accounting_link_apply" -- plan "$RECEIPT" "$WORK_DIR" "$WORK_DIR/before.rows"
receipt_conflict=$($SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/receipt-check.sql")
if [ -n "$receipt_conflict" ]; then echo "company SQLite accounting-link apply failed: accounting-link receipt conflict" >&2; exit 1; fi
$SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/apply.sql" > "$WORK_DIR/apply.out"
receipt_inserted=$(tail -n 1 "$WORK_DIR/apply.out")
metadata_run=$(sed -n 's/.*"run_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK_DIR/metadata.json" | head -n 1)
$SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" < "$WORK_DIR/after.sql" > "$WORK_DIR/after.rows"
integrity=$($SQLITE_BIN -batch -noheader "$DATABASE" 'PRAGMA integrity_check;')
link_count=$($SQLITE_BIN -batch -noheader "$DATABASE" 'SELECT count(*) FROM company_accounting_event_link;')
receipt_count=$($SQLITE_BIN -batch -noheader "$DATABASE" "SELECT count(*) FROM company_migration_receipt WHERE run_id='$(printf '%s' "$metadata_run" | sed "s/'/''/g")';")
OUTPUT=${3:-$WORK_DIR/report.json}
exec moon run --target native "$SCRIPT_DIR/../cmd/sqlite_accounting_link_apply" -- report "$WORK_DIR" "$WORK_DIR/after.rows" "$integrity" "$link_count" "$receipt_count" "$receipt_inserted" "$DATABASE" "$OUTPUT"
