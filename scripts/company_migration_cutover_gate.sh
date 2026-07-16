#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK_DIR=${1:?usage: company_migration_cutover_gate.sh WORK_DIR OUTPUT [--expected-raw N] [--expected-projections N] [--expected-links N]}
OUTPUT=${2:?missing output path}
shift 2
EXPECTED_RAW=-1
EXPECTED_PROJECTIONS=-1
EXPECTED_LINKS=-1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --expected-raw) EXPECTED_RAW=${2:?missing expected raw}; shift 2 ;;
    --expected-projections) EXPECTED_PROJECTIONS=${2:?missing expected projections}; shift 2 ;;
    --expected-links) EXPECTED_LINKS=${2:?missing expected links}; shift 2 ;;
    *) echo "company cutover gate failed: unknown option: $1" >&2; exit 2 ;;
  esac
done
DATABASE="$WORK_DIR/company.sqlite3"
SQLITE_BIN=${SQLITE_BIN:-sqlite3}
integrity=$($SQLITE_BIN -batch -noheader "$DATABASE" 'PRAGMA integrity_check;')
schema_version=$($SQLITE_BIN -batch -noheader "$DATABASE" 'SELECT max(version) FROM company_schema;')
raw_count=$($SQLITE_BIN -batch -noheader "$DATABASE" 'SELECT count(*) FROM company_record;')
projection_count=$($SQLITE_BIN -batch -noheader "$DATABASE" 'SELECT count(*) FROM company_aggregate_projection;')
link_count=$($SQLITE_BIN -batch -noheader "$DATABASE" 'SELECT count(*) FROM company_accounting_event_link;')
receipt_count=$($SQLITE_BIN -batch -noheader "$DATABASE" 'SELECT count(*) FROM company_migration_receipt;')
exec moon run --target native "$SCRIPT_DIR/../cmd/cutover_gate" -- \
  "$WORK_DIR" "$OUTPUT" "$EXPECTED_RAW" "$EXPECTED_PROJECTIONS" "$EXPECTED_LINKS" \
  "$integrity" "$schema_version" "$raw_count" "$projection_count" "$link_count" "$receipt_count"
