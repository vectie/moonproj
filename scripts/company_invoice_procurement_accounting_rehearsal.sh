#!/bin/sh
set -eu

# Reconcile invoice receivable/payable openings and procurement commitments
# through the same explicit accounting-link boundary. This is a traceability
# cohort: it never releases cash, posts a journal, or mutates the source.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
USAGE="usage: company_invoice_procurement_accounting_rehearsal.sh INVOICE_MAPPING PROCUREMENT_MAPPING ACCOUNTING_MAPPING [SQLITE_DATABASE] [PGDATABASE] [WORK_DIR]"
INVOICE_MAPPING=${1:?$USAGE}
PROCUREMENT_MAPPING=${2:?$USAGE}
ACCOUNTING_MAPPING=${3:?$USAGE}
WORK_DIR=${6:-/tmp/moonproj-invoice-procurement-accounting}
SQLITE_DATABASE=${4:-$WORK_DIR/invoice-procurement-accounting.sqlite3}
PG_DATABASE=${5:-${PGDATABASE:-}}
PG_HOST=${PGHOST:-/tmp}
PG_PORT=${PGPORT:-5432}
PG_USER=${PGUSER:-moonproj}

mkdir -p "$WORK_DIR"
rm -f "$SQLITE_DATABASE" "$SQLITE_DATABASE-wal" "$SQLITE_DATABASE-shm"

python3 "$SCRIPT_DIR/erp_invoice_subledger_plan.py" \
  "$INVOICE_MAPPING" "$WORK_DIR/invoice-subledger-plan.json"
moon run --target native cmd/invoice_subledger -- \
  "$WORK_DIR/invoice-subledger-plan.json" "$WORK_DIR/invoice-subledger-receipt.json"
python3 "$SCRIPT_DIR/erp_accounting_link_plan.py" \
  "$WORK_DIR/invoice-subledger-receipt.json" "$ACCOUNTING_MAPPING" \
  "$WORK_DIR/invoice-accounting-link-plan.json"
moon run --target native cmd/accounting_link -- \
  "$WORK_DIR/invoice-accounting-link-plan.json" \
  "$WORK_DIR/invoice-accounting-link-receipt.json"
python3 "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" \
  "$WORK_DIR/invoice-accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/invoice-sqlite-apply.json"
python3 "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" \
  "$WORK_DIR/invoice-accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/invoice-sqlite-replay.json"
python3 "$SCRIPT_DIR/company_accounting_link_parity.py" \
  "$WORK_DIR/invoice-accounting-link-receipt.json" --backend sqlite \
  --database "$SQLITE_DATABASE" > "$WORK_DIR/invoice-sqlite-parity.json"

python3 "$SCRIPT_DIR/erp_procurement_cohort_plan.py" \
  "$PROCUREMENT_MAPPING" "$WORK_DIR/procurement-plan.json"
moon run --target native cmd/procurement_cohort -- \
  "$WORK_DIR/procurement-plan.json" "$WORK_DIR/procurement-receipt.json"
python3 "$SCRIPT_DIR/erp_accounting_link_plan.py" \
  "$WORK_DIR/procurement-receipt.json" "$ACCOUNTING_MAPPING" \
  "$WORK_DIR/procurement-accounting-link-plan.json"
moon run --target native cmd/accounting_link -- \
  "$WORK_DIR/procurement-accounting-link-plan.json" \
  "$WORK_DIR/procurement-accounting-link-receipt.json"
python3 "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" \
  "$WORK_DIR/procurement-accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/procurement-sqlite-apply.json"
python3 "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" \
  "$WORK_DIR/procurement-accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/procurement-sqlite-replay.json"
python3 "$SCRIPT_DIR/company_accounting_link_parity.py" \
  "$WORK_DIR/procurement-accounting-link-receipt.json" --backend sqlite \
  --database "$SQLITE_DATABASE" > "$WORK_DIR/procurement-sqlite-parity.json"

if [ -n "$PG_DATABASE" ]; then
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$WORK_DIR/invoice-accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/invoice-postgres-apply.json"
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$WORK_DIR/invoice-accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/invoice-postgres-replay.json"
  python3 "$SCRIPT_DIR/company_accounting_link_parity.py" \
    "$WORK_DIR/invoice-accounting-link-receipt.json" --backend postgres \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
    --database-name "$PG_DATABASE" > "$WORK_DIR/invoice-postgres-parity.json"
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$WORK_DIR/procurement-accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/procurement-postgres-apply.json"
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$WORK_DIR/procurement-accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/procurement-postgres-replay.json"
  python3 "$SCRIPT_DIR/company_accounting_link_parity.py" \
    "$WORK_DIR/procurement-accounting-link-receipt.json" --backend postgres \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
    --database-name "$PG_DATABASE" > "$WORK_DIR/procurement-postgres-parity.json"
fi

printf '%s\n' "work_dir=$WORK_DIR"
printf '%s\n' "sqlite_database=$SQLITE_DATABASE"
if [ -n "$PG_DATABASE" ]; then
  printf '%s\n' "postgres_target=$PG_DATABASE"
fi
