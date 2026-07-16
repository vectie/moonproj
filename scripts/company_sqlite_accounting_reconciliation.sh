#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DOMAIN=${1:?usage: company_sqlite_accounting_reconciliation.sh DOMAIN PLAN RECEIPT DATABASE OUTPUT}
PLAN=${2:?usage: company_sqlite_accounting_reconciliation.sh DOMAIN PLAN RECEIPT DATABASE OUTPUT}
RECEIPT=${3:?usage: company_sqlite_accounting_reconciliation.sh DOMAIN PLAN RECEIPT DATABASE OUTPUT}
DATABASE=${4:?usage: company_sqlite_accounting_reconciliation.sh DOMAIN PLAN RECEIPT DATABASE OUTPUT}
OUTPUT=${5:?usage: company_sqlite_accounting_reconciliation.sh DOMAIN PLAN RECEIPT DATABASE OUTPUT}
WORK_DIR=${TMPDIR:-/tmp}/moonproj-sqlite-accounting-reconciliation.$$
mkdir -p "$WORK_DIR"; trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM
moon run --target native "$SCRIPT_DIR/../cmd/sqlite_accounting_reconciliation" -- prepare "$RECEIPT" "$WORK_DIR"
sqlite3 -batch -noheader -separator '|' "$DATABASE" < "$WORK_DIR/query.sql" > "$WORK_DIR/rows"
integrity=$(sqlite3 -batch -noheader "$DATABASE" 'PRAGMA integrity_check;')
exec moon run --target native "$SCRIPT_DIR/../cmd/sqlite_accounting_reconciliation" -- report "$DOMAIN" "$PLAN" "$RECEIPT" "$WORK_DIR/rows" "$integrity" "$OUTPUT"
