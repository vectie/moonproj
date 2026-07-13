#!/bin/sh
set -eu

# Run any explicitly reviewed native accounting-link cohort through the
# PostgreSQL traceability adapter.  This never posts a journal, releases cash,
# closes a period, or mutates the legacy source.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
USAGE="usage: company_postgres_accounting_cohort_rehearsal.sh DOMAIN_RECEIPT MAPPING [PGDATABASE] [WORK_DIR]"
DOMAIN_RECEIPT=${1:?$USAGE}
MAPPING_PATH=${2:?$USAGE}
PG_DATABASE=${3:-${PGDATABASE:-moonproj}}
WORK_DIR=${4:-/tmp/moonproj-postgres-accounting-cohort}
PG_HOST=${PGHOST:-/tmp}
PG_PORT=${PGPORT:-5432}
PG_USER=${PGUSER:-moonproj}

mkdir -p "$WORK_DIR"
PLAN="$WORK_DIR/accounting-link-plan.json"
RECEIPT="$WORK_DIR/accounting-link-receipt.json"

python3 "$SCRIPT_DIR/erp_accounting_link_plan.py" \
  "$DOMAIN_RECEIPT" "$MAPPING_PATH" "$PLAN"
moon run --target native cmd/accounting_link -- "$PLAN" "$RECEIPT"

python3 "$SCRIPT_DIR/company_postgres_accounting_link_apply.py" \
  "$RECEIPT" --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
  --database "$PG_DATABASE" > "$WORK_DIR/postgres-apply.json"
python3 "$SCRIPT_DIR/company_postgres_accounting_link_apply.py" \
  "$RECEIPT" --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
  --database "$PG_DATABASE" > "$WORK_DIR/postgres-replay.json"

printf '%s\n' "postgres_target=$PG_DATABASE"
printf '%s\n' "work_dir=$WORK_DIR"
printf '%s\n' "receipt=$RECEIPT"
