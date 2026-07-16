#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RECEIPT=${1:?usage: company_sqlite_accounting_link_parity.sh RECEIPT DATABASE}
DATABASE=${2:?usage: company_sqlite_accounting_link_parity.sh RECEIPT DATABASE}
WORK_DIR=${TMPDIR:-/tmp}/moonproj-sqlite-accounting-parity.$$
mkdir -p "$WORK_DIR"; trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM
moon run --target native "$SCRIPT_DIR/../cmd/sqlite_accounting_link_parity" -- prepare "$RECEIPT" "$WORK_DIR"
sqlite3 -batch -noheader -separator '|' "$DATABASE" < "$WORK_DIR/query.sql" > "$WORK_DIR/rows"
OUTPUT=${3:-$WORK_DIR/report.json}
exec moon run --target native "$SCRIPT_DIR/../cmd/sqlite_accounting_link_parity" -- report "$RECEIPT" "$WORK_DIR/rows" sqlite "$DATABASE" "$OUTPUT"
