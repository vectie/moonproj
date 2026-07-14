#!/bin/sh
set -eu

# Reconcile the reviewed sales/receivables lifecycle through the native
# domain importer. Revenue remains evidence-only; no cash, refund payment,
# receivable collection, accounting posting, or period close is performed.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
USAGE="usage: company_sales_cohort_rehearsal.sh SALES_MAPPING [SQLITE_DATABASE] [PGDATABASE] [WORK_DIR]"
SALES_MAPPING=${1:?$USAGE}
WORK_DIR=${4:-/tmp/moonproj-sales-cohort}
SQLITE_DATABASE=${2:-$WORK_DIR/sales-cohort.sqlite3}
PG_DATABASE=${3:-${PGDATABASE:-}}
PG_HOST=${PGHOST:-/tmp}
PG_PORT=${PGPORT:-5432}
PG_USER=${PGUSER:-moonproj}

mkdir -p "$WORK_DIR"
rm -f "$SQLITE_DATABASE" "$SQLITE_DATABASE-wal" "$SQLITE_DATABASE-shm"

python3 "$SCRIPT_DIR/erp_sales_cohort_plan.py" \
  "$SALES_MAPPING" "$WORK_DIR/sales-cohort-plan.json"
moon run --target native cmd/sales_cohort -- \
  "$WORK_DIR/sales-cohort-plan.json" "$WORK_DIR/sales-cohort-receipt.json"
python3 "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
  "$WORK_DIR/sales-cohort-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/sqlite-apply.json"
python3 "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
  "$WORK_DIR/sales-cohort-receipt.json" "$SQLITE_DATABASE" \
  "$WORK_DIR/sqlite-parity.json"
python3 "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
  "$WORK_DIR/sales-cohort-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/sqlite-replay.json"

if [ -n "$PG_DATABASE" ]; then
  "$SCRIPT_DIR/company_postgres_projection_apply.sh" \
    "$WORK_DIR/sales-cohort-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/postgres-apply.json"
  python3 "$SCRIPT_DIR/company_postgres_projection_parity.py" \
    "$WORK_DIR/sales-cohort-receipt.json" "$WORK_DIR/postgres-parity.json" \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
    --database "$PG_DATABASE"
  "$SCRIPT_DIR/company_postgres_projection_apply.sh" \
    "$WORK_DIR/sales-cohort-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/postgres-replay.json"
fi

printf '%s\n' "work_dir=$WORK_DIR"
printf '%s\n' "sqlite_database=$SQLITE_DATABASE"
if [ -n "$PG_DATABASE" ]; then
  printf '%s\n' "postgres_target=$PG_DATABASE"
fi
