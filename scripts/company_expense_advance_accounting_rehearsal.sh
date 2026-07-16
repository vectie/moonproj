#!/bin/sh
set -eu

# Bind only the reviewed employee-advance issuance and offset identities to
# explicit journals. This traceability cohort never posts the book, releases
# cash, recognizes expense, or closes a period.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
USAGE="usage: company_expense_advance_accounting_rehearsal.sh EXPENSE_ADVANCE_MAPPING ACCOUNTING_MAPPING [SQLITE_DATABASE] [PGDATABASE] [WORK_DIR]"
EXPENSE_ADVANCE_MAPPING=${1:?$USAGE}
ACCOUNTING_MAPPING=${2:?$USAGE}
WORK_DIR=${5:-/tmp/moonproj-expense-advance-accounting}
SQLITE_DATABASE=${3:-$WORK_DIR/expense-advance-accounting.sqlite3}
PG_DATABASE=${4:-${PGDATABASE:-}}
PG_HOST=${PGHOST:-/tmp}
PG_PORT=${PGPORT:-5432}
PG_USER=${PGUSER:-moonproj}

mkdir -p "$WORK_DIR"
rm -f "$SQLITE_DATABASE" "$SQLITE_DATABASE-wal" "$SQLITE_DATABASE-shm"

"$SCRIPT_DIR/erp_expense_advance_cohort_plan.sh" \
  "$EXPENSE_ADVANCE_MAPPING" "$WORK_DIR/expense-advance-plan.json"
moon run --target native cmd/expense_advance_cohort -- \
  "$WORK_DIR/expense-advance-plan.json" \
  "$WORK_DIR/expense-advance-receipt.json"
"$SCRIPT_DIR/erp_accounting_link_plan.sh" \
  "$WORK_DIR/expense-advance-receipt.json" "$ACCOUNTING_MAPPING" \
  "$WORK_DIR/accounting-link-plan.json"
moon run --target native cmd/accounting_link -- \
  "$WORK_DIR/accounting-link-plan.json" \
  "$WORK_DIR/accounting-link-receipt.json"

"$SCRIPT_DIR/company_sqlite_accounting_link_apply.sh" \
  "$WORK_DIR/accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/sqlite-apply.json"
"$SCRIPT_DIR/company_sqlite_accounting_link_apply.sh" \
  "$WORK_DIR/accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/sqlite-replay.json"
"$SCRIPT_DIR/company_sqlite_accounting_link_parity.sh" \
  "$WORK_DIR/accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/sqlite-parity.json"
python3 "$SCRIPT_DIR/company_sqlite_accounting_reconciliation.py" \
  "$WORK_DIR/expense-advance-receipt.json" \
  "$WORK_DIR/accounting-link-plan.json" \
  "$WORK_DIR/accounting-link-receipt.json" "$SQLITE_DATABASE" \
  "$WORK_DIR/sqlite-reconciliation.json"

if [ -n "$PG_DATABASE" ]; then
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$WORK_DIR/accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/postgres-apply.json"
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$WORK_DIR/accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/postgres-replay.json"
  python3 "$SCRIPT_DIR/company_accounting_link_parity.py" \
    "$WORK_DIR/accounting-link-receipt.json" --backend postgres \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
    --database-name "$PG_DATABASE" > "$WORK_DIR/postgres-parity.json"
  python3 "$SCRIPT_DIR/company_postgres_accounting_reconciliation.py" \
    "$WORK_DIR/expense-advance-receipt.json" \
    "$WORK_DIR/accounting-link-plan.json" \
    "$WORK_DIR/accounting-link-receipt.json" \
    "$WORK_DIR/postgres-reconciliation.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database-name "$PG_DATABASE"
fi

printf '%s\n' "work_dir=$WORK_DIR"
printf '%s\n' "sqlite_database=$SQLITE_DATABASE"
if [ -n "$PG_DATABASE" ]; then
  printf '%s\n' "postgres_target=$PG_DATABASE"
fi
