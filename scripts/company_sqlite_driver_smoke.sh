#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DATABASE=${1:?usage: company_sqlite_driver_smoke.sh DATABASE [OUTPUT]}
OUTPUT=${2:-}
SQLITE_BIN=${SQLITE_BIN:-sqlite3}
if [ -e "$DATABASE" ] || [ -e "$DATABASE-wal" ] || [ -e "$DATABASE-shm" ]; then
  echo "company SQLite driver smoke failed: driver smoke database already exists: $DATABASE" >&2
  exit 1
fi
WORK_DIR=${TMPDIR:-/tmp}/moonproj-sqlite-driver-smoke.$$
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"; rm -f "$DATABASE" "$DATABASE-wal" "$DATABASE-shm"' EXIT HUP INT TERM

moon run --target native "$SCRIPT_DIR/../cmd/sqlite_driver_smoke" -- prepare "$WORK_DIR"
$SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/schema.sql" >/dev/null
$SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/rollback.sql" >/dev/null
rollback_count=$($SQLITE_BIN -batch -noheader "$DATABASE" "SELECT count(*) FROM company_record WHERE record_type='driver_smoke';")
if [ "$rollback_count" != "0" ]; then
  echo "company SQLite driver smoke failed: rollback committed rows" >&2
  exit 1
fi
if $SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/duplicate.sql" >/dev/null 2>&1; then
  echo "company SQLite driver smoke failed: duplicate command unexpectedly committed" >&2
  exit 1
fi
duplicate_count=$($SQLITE_BIN -batch -noheader "$DATABASE" "SELECT count(*) FROM company_record WHERE record_type='driver_smoke';")
if [ "$duplicate_count" != "0" ]; then
  echo "company SQLite driver smoke failed: duplicate transaction was not rolled back" >&2
  exit 1
fi
$SQLITE_BIN -batch -noheader "$DATABASE" < "$WORK_DIR/commit.sql" >/dev/null
count=$($SQLITE_BIN -batch -noheader "$DATABASE" "SELECT count(*) FROM company_record WHERE record_type='driver_smoke';")
integrity=$($SQLITE_BIN -batch -noheader "$DATABASE" 'PRAGMA integrity_check;')
if [ -z "$OUTPUT" ]; then OUTPUT="$WORK_DIR/report.json"; fi
exec moon run --target native "$SCRIPT_DIR/../cmd/sqlite_driver_smoke" -- report "$DATABASE" "$count" "$integrity" "$duplicate_count" "$OUTPUT"
