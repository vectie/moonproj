#!/bin/sh
set -eu

# Reconcile reviewed marketing campaign/placement lifecycle and catalog
# evidence. This boundary does not call providers, consume a budget ledger,
# release cash, post accounting, or close a period.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
USAGE="usage: company_marketing_cohort_rehearsal.sh MARKETING_MAPPING [SQLITE_DATABASE] [PGDATABASE] [WORK_DIR]"
MARKETING_MAPPING=${1:?$USAGE}
WORK_DIR=${4:-/tmp/moonproj-marketing-cohort}
SQLITE_DATABASE=${2:-$WORK_DIR/marketing-cohort.sqlite3}
PG_DATABASE=${3:-${PGDATABASE:-}}
PG_HOST=${PGHOST:-/tmp}
PG_PORT=${PGPORT:-5432}
PG_USER=${PGUSER:-moonproj}

mkdir -p "$WORK_DIR"
rm -f "$SQLITE_DATABASE" "$SQLITE_DATABASE-wal" "$SQLITE_DATABASE-shm"

"$SCRIPT_DIR/erp_marketing_cohort_plan.sh" \
  "$MARKETING_MAPPING" "$WORK_DIR/marketing-cohort-plan.json"
moon run --target native cmd/marketing_cohort -- \
  "$WORK_DIR/marketing-cohort-plan.json" "$WORK_DIR/marketing-cohort-receipt.json"
python3 "$SCRIPT_DIR/company_sqlite_projection_apply.sh" \
  "$WORK_DIR/marketing-cohort-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/sqlite-apply.json"
"$SCRIPT_DIR/company_sqlite_projection_parity.sh" \
  "$WORK_DIR/marketing-cohort-receipt.json" "$SQLITE_DATABASE" \
  "$WORK_DIR/sqlite-parity.json"
python3 "$SCRIPT_DIR/company_sqlite_projection_apply.sh" \
  "$WORK_DIR/marketing-cohort-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/sqlite-replay.json"

if [ -n "$PG_DATABASE" ]; then
  "$SCRIPT_DIR/company_postgres_projection_apply.sh" \
    "$WORK_DIR/marketing-cohort-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/postgres-apply.json"
  "$SCRIPT_DIR/company_postgres_projection_parity.sh" \
    "$WORK_DIR/marketing-cohort-receipt.json" "$WORK_DIR/postgres-parity.json" \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
    --database "$PG_DATABASE"
  "$SCRIPT_DIR/company_postgres_projection_apply.sh" \
    "$WORK_DIR/marketing-cohort-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/postgres-replay.json"
fi

printf '%s\n' "work_dir=$WORK_DIR"
printf '%s\n' "sqlite_database=$SQLITE_DATABASE"
if [ -n "$PG_DATABASE" ]; then
  printf '%s\n' "postgres_target=$PG_DATABASE"
fi
