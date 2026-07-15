#!/bin/sh
set -eu

# Run the reviewed investment valuation event and its separate accounting-link
# map.  This boundary creates no position mutation, cash movement, journal
# posting, period close, or legacy-source write.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
USAGE="usage: company_investment_valuation_accounting_rehearsal.sh PERFORMANCE_MAPPING VALUATION_MAPPING ACCOUNTING_MAPPING [SQLITE_DATABASE] [PGDATABASE] [WORK_DIR]"
PERFORMANCE_MAPPING=${1:?$USAGE}
VALUATION_MAPPING=${2:?$USAGE}
ACCOUNTING_MAPPING=${3:?$USAGE}
WORK_DIR=${6:-/tmp/moonproj-investment-valuation-accounting}
SQLITE_DATABASE=${4:-$WORK_DIR/investment-valuation.sqlite3}
PG_DATABASE=${5:-${PGDATABASE:-}}
PG_HOST=${PGHOST:-/tmp}
PG_PORT=${PGPORT:-5432}
PG_USER=${PGUSER:-moonproj}

mkdir -p "$WORK_DIR"
PERFORMANCE_PLAN="$WORK_DIR/investment-performance-plan.json"
"$SCRIPT_DIR/erp_investment_performance_plan.sh" \
  "$PERFORMANCE_MAPPING" "$PERFORMANCE_PLAN"
VALUATION_PLAN="$WORK_DIR/investment-valuation-plan.json"
"$SCRIPT_DIR/erp_investment_valuation_plan.sh" \
  "$PERFORMANCE_PLAN" "$VALUATION_MAPPING" "$VALUATION_PLAN"
VALUATION_DOMAIN_RECEIPT="$WORK_DIR/investment-valuation-domain-receipt.json"
moon run --target native cmd/investment_valuation -- \
  "$VALUATION_PLAN" "$VALUATION_DOMAIN_RECEIPT"
ACCOUNTING_PLAN="$WORK_DIR/investment-valuation-accounting-plan.json"
"$SCRIPT_DIR/erp_accounting_link_plan.sh" \
  "$VALUATION_DOMAIN_RECEIPT" "$ACCOUNTING_MAPPING" "$ACCOUNTING_PLAN"
ACCOUNTING_RECEIPT="$WORK_DIR/investment-valuation-accounting-receipt.json"
moon run --target native cmd/accounting_link -- \
  "$ACCOUNTING_PLAN" "$ACCOUNTING_RECEIPT"

rm -f "$SQLITE_DATABASE" "$SQLITE_DATABASE-wal" "$SQLITE_DATABASE-shm"
python3 "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" \
  "$ACCOUNTING_RECEIPT" "$SQLITE_DATABASE" > "$WORK_DIR/sqlite-apply.json"
python3 "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" \
  "$ACCOUNTING_RECEIPT" "$SQLITE_DATABASE" > "$WORK_DIR/sqlite-replay.json"
python3 "$SCRIPT_DIR/company_accounting_link_parity.py" \
  "$ACCOUNTING_RECEIPT" --backend sqlite --database "$SQLITE_DATABASE" \
  > "$WORK_DIR/sqlite-parity.json"

if [ -n "$PG_DATABASE" ]; then
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$ACCOUNTING_RECEIPT" --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
    --database "$PG_DATABASE" > "$WORK_DIR/postgres-apply.json"
  "$SCRIPT_DIR/company_postgres_accounting_link_apply.sh" \
    "$ACCOUNTING_RECEIPT" --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
    --database "$PG_DATABASE" > "$WORK_DIR/postgres-replay.json"
  python3 "$SCRIPT_DIR/company_accounting_link_parity.py" \
    "$ACCOUNTING_RECEIPT" --backend postgres --host "$PG_HOST" --port "$PG_PORT" \
    --user "$PG_USER" --database-name "$PG_DATABASE" \
    > "$WORK_DIR/postgres-parity.json"
fi

printf '%s\n' "work_dir=$WORK_DIR"
printf '%s\n' "valuation_domain_receipt=$VALUATION_DOMAIN_RECEIPT"
printf '%s\n' "accounting_receipt=$ACCOUNTING_RECEIPT"
printf '%s\n' "sqlite_database=$SQLITE_DATABASE"
if [ -n "$PG_DATABASE" ]; then
  printf '%s\n' "postgres_target=$PG_DATABASE"
fi
