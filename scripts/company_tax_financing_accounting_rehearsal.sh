#!/bin/sh
set -eu

# Reconcile tax recognition and financing draw/repayment source events through
# the explicit accounting-link boundary. This is a traceability cohort: it
# creates no tax filing/payment, lender call, cash movement, journal posting,
# period close, or legacy-source write.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
USAGE="usage: company_tax_financing_accounting_rehearsal.sh TAX_MAPPING FINANCING_MAPPING TAX_ACCOUNTING_MAPPING FINANCING_ACCOUNTING_MAPPING [SQLITE_DATABASE] [PGDATABASE] [WORK_DIR]"
TAX_MAPPING=${1:?$USAGE}
FINANCING_MAPPING=${2:?$USAGE}
TAX_ACCOUNTING_MAPPING=${3:?$USAGE}
FINANCING_ACCOUNTING_MAPPING=${4:?$USAGE}
WORK_DIR=${7:-/tmp/moonproj-tax-financing-accounting}
SQLITE_DATABASE=${5:-$WORK_DIR/tax-financing-accounting.sqlite3}
PG_DATABASE=${6:-${PGDATABASE:-}}
PG_HOST=${PGHOST:-/tmp}
PG_PORT=${PGPORT:-5432}
PG_USER=${PGUSER:-moonproj}

mkdir -p "$WORK_DIR"
rm -f "$SQLITE_DATABASE" "$SQLITE_DATABASE-wal" "$SQLITE_DATABASE-shm"

"$SCRIPT_DIR/erp_tax_filing_plan.sh" \
  "$TAX_MAPPING" "$WORK_DIR/tax-filing-plan.json"
"$SCRIPT_DIR/erp_tax_accounting_plan.sh" \
  "$WORK_DIR/tax-filing-plan.json" "$TAX_ACCOUNTING_MAPPING" \
  "$WORK_DIR/tax-accounting-plan.json"
moon run --target native cmd/tax_accounting_link -- \
  "$WORK_DIR/tax-accounting-plan.json" "$WORK_DIR/tax-accounting-domain-receipt.json"
"$SCRIPT_DIR/erp_accounting_link_plan.sh" \
  "$WORK_DIR/tax-accounting-domain-receipt.json" "$TAX_ACCOUNTING_MAPPING" \
  "$WORK_DIR/tax-accounting-link-plan.json"
moon run --target native cmd/accounting_link -- \
  "$WORK_DIR/tax-accounting-link-plan.json" \
  "$WORK_DIR/tax-accounting-link-receipt.json"
"$SCRIPT_DIR/company_sqlite_accounting_link_apply.sh" \
  "$WORK_DIR/tax-accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/tax-sqlite-apply.json"
"$SCRIPT_DIR/company_sqlite_accounting_link_apply.sh" \
  "$WORK_DIR/tax-accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/tax-sqlite-replay.json"
"$SCRIPT_DIR/company_sqlite_accounting_link_parity.sh" \
  "$WORK_DIR/tax-accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/tax-sqlite-parity.json"

"$SCRIPT_DIR/erp_financing_facility_plan.sh" \
  "$FINANCING_MAPPING" "$WORK_DIR/financing-facility-plan.json"
"$SCRIPT_DIR/erp_financing_accounting_plan.sh" \
  "$WORK_DIR/financing-facility-plan.json" "$FINANCING_ACCOUNTING_MAPPING" \
  "$WORK_DIR/financing-accounting-plan.json"
moon run --target native cmd/financing_accounting_link -- \
  "$WORK_DIR/financing-accounting-plan.json" \
  "$WORK_DIR/financing-accounting-domain-receipt.json"
"$SCRIPT_DIR/erp_accounting_link_plan.sh" \
  "$WORK_DIR/financing-accounting-domain-receipt.json" "$FINANCING_ACCOUNTING_MAPPING" \
  "$WORK_DIR/financing-accounting-link-plan.json"
moon run --target native cmd/accounting_link -- \
  "$WORK_DIR/financing-accounting-link-plan.json" \
  "$WORK_DIR/financing-accounting-link-receipt.json"
"$SCRIPT_DIR/company_sqlite_accounting_link_apply.sh" \
  "$WORK_DIR/financing-accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/financing-sqlite-apply.json"
"$SCRIPT_DIR/company_sqlite_accounting_link_apply.sh" \
  "$WORK_DIR/financing-accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/financing-sqlite-replay.json"
"$SCRIPT_DIR/company_sqlite_accounting_link_parity.sh" \
  "$WORK_DIR/financing-accounting-link-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/financing-sqlite-parity.json"

if [ -n "$PG_DATABASE" ]; then
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$WORK_DIR/tax-accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/tax-postgres-apply.json"
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$WORK_DIR/tax-accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/tax-postgres-replay.json"
  "$SCRIPT_DIR/company_postgres_accounting_link_parity.sh" \
    "$WORK_DIR/tax-accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/tax-postgres-parity.json"
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$WORK_DIR/financing-accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/financing-postgres-apply.json"
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$WORK_DIR/financing-accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/financing-postgres-replay.json"
  "$SCRIPT_DIR/company_postgres_accounting_link_parity.sh" \
    "$WORK_DIR/financing-accounting-link-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/financing-postgres-parity.json"
fi

printf '%s\n' "work_dir=$WORK_DIR"
printf '%s\n' "sqlite_database=$SQLITE_DATABASE"
if [ -n "$PG_DATABASE" ]; then
  printf '%s\n' "postgres_target=$PG_DATABASE"
fi
