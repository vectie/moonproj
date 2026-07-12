#!/bin/sh
set -eu

# Run the reviewed typed ERP cohorts through both the deterministic SQLite
# rehearsal and the PostgreSQL target adapters.  The source export is read
# only; the PostgreSQL target is selected explicitly by its connection flags.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EXPORT_DIR=${1:?usage: company_postgres_cohort_rehearsal.sh EXPORT_DIR MAPPING RAW_STAGING [PGDATABASE] [WORK_DIR]}
MAPPING_PATH=${2:?usage: company_postgres_cohort_rehearsal.sh EXPORT_DIR MAPPING RAW_STAGING [PGDATABASE] [WORK_DIR]}
STAGING_PATH=${3:?usage: company_postgres_cohort_rehearsal.sh EXPORT_DIR MAPPING RAW_STAGING [PGDATABASE] [WORK_DIR]}
PG_DATABASE=${4:-${PGDATABASE:-moonproj}}
WORK_DIR=${5:-/tmp/moonproj-postgres-cohort-rehearsal}
PG_HOST=${PGHOST:-/tmp}
PG_PORT=${PGPORT:-5432}
PG_USER=${PGUSER:-moonproj}

SQLITE_DB="$WORK_DIR/company.sqlite3"
TYPED_WORK_DIR="$WORK_DIR/typed-cohorts"
mkdir -p "$WORK_DIR"

# Keep the SQLite rehearsal isolated to this run while using the same staged
# source envelope that is sent to PostgreSQL.
rm -f "$SQLITE_DB" "$SQLITE_DB.pending"
"$SCRIPT_DIR/company_sqlite_rehearsal.py" "$STAGING_PATH" "$SQLITE_DB" > "$WORK_DIR/sqlite-raw-apply.json"
python3 "$SCRIPT_DIR/company_postgres_target_apply.py" \
  "$STAGING_PATH" --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
  --database "$PG_DATABASE" > "$WORK_DIR/postgres-raw-apply.json"

"$SCRIPT_DIR/erp_typed_cohort_rehearsal.sh" \
  "$EXPORT_DIR" "$MAPPING_PATH" "$SQLITE_DB" "$TYPED_WORK_DIR" > "$WORK_DIR/typed-cohort.log"

for label in workflow lifecycle task-structure task-state-project2 evidence investment payment users audit parameter
do
  receipt="$TYPED_WORK_DIR/$label-promotion.json"
  apply="$WORK_DIR/$label-postgres-apply.json"
  parity="$WORK_DIR/$label-postgres-parity.json"
  replay="$WORK_DIR/$label-postgres-replay.json"
  python3 "$SCRIPT_DIR/company_postgres_projection_apply.py" "$receipt" \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" > "$apply"
  python3 "$SCRIPT_DIR/company_postgres_projection_parity.py" "$receipt" "$parity" \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE"
  python3 "$SCRIPT_DIR/company_postgres_projection_apply.py" "$receipt" \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" > "$replay"
done

echo "postgres_target=$PG_DATABASE"
echo "work_dir=$WORK_DIR"
echo "typed_work_dir=$TYPED_WORK_DIR"
