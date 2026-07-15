#!/bin/sh
set -eu

# Preserve quarantined ERP task-state observations as non-authorizing evidence.
# This boundary never repairs dependencies, mutates target task state, posts
# accounting, releases cash, or closes a period.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
USAGE="usage: company_task_state_exception_evidence_rehearsal.sh EXPORT_DIR MAPPING [SQLITE_DATABASE] [PGDATABASE] [WORK_DIR]"
EXPORT_DIR=${1:?$USAGE}
MAPPING_PATH=${2:?$USAGE}
WORK_DIR=${5:-/tmp/moonproj-task-state-exception-evidence}
SQLITE_DATABASE=${3:-$WORK_DIR/task-state-exception-evidence.sqlite3}
PG_DATABASE=${4:-${PGDATABASE:-}}
PG_HOST=${PGHOST:-/tmp}
PG_PORT=${PGPORT:-5432}
PG_USER=${PGUSER:-moonproj}

mkdir -p "$WORK_DIR"
rm -f "$SQLITE_DATABASE" "$SQLITE_DATABASE-wal" "$SQLITE_DATABASE-shm"

EVIDENCE_MAPPING="$WORK_DIR/task-state-evidence-mapping.json"
"$SCRIPT_DIR/erp_mapping_variant.sh" \
  "$MAPPING_PATH" "$EVIDENCE_MAPPING" \
  "task-state-exception-evidence-v1-review-001" >/dev/null
"$SCRIPT_DIR/erp_task_state_promotion_plan.sh" \
  "$EXPORT_DIR" "$EVIDENCE_MAPPING" "$WORK_DIR/task-state-plan.json"
"$SCRIPT_DIR/erp_task_state_exception_review.sh" \
  "$WORK_DIR/task-state-plan.json" "$WORK_DIR/task-state-exception-review.json"
moon run --target native cmd/task_state_evidence -- \
  "$WORK_DIR/task-state-exception-review.json" \
  "$WORK_DIR/task-state-exception-evidence-receipt.json"
python3 "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
  "$WORK_DIR/task-state-exception-evidence-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/sqlite-apply.json"
python3 "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
  "$WORK_DIR/task-state-exception-evidence-receipt.json" "$SQLITE_DATABASE" \
  "$WORK_DIR/sqlite-parity.json"
python3 "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
  "$WORK_DIR/task-state-exception-evidence-receipt.json" "$SQLITE_DATABASE" \
  > "$WORK_DIR/sqlite-replay.json"

if [ -n "$PG_DATABASE" ]; then
  "$SCRIPT_DIR/company_postgres_projection_apply.sh" \
    "$WORK_DIR/task-state-exception-evidence-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/postgres-apply.json"
  "$SCRIPT_DIR/company_postgres_projection_parity.sh" \
    "$WORK_DIR/task-state-exception-evidence-receipt.json" \
    "$WORK_DIR/postgres-parity.json" --host "$PG_HOST" --port "$PG_PORT" \
    --user "$PG_USER" --database "$PG_DATABASE"
  "$SCRIPT_DIR/company_postgres_projection_apply.sh" \
    "$WORK_DIR/task-state-exception-evidence-receipt.json" --host "$PG_HOST" \
    --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" \
    > "$WORK_DIR/postgres-replay.json"
fi

printf '%s\n' "work_dir=$WORK_DIR"
printf '%s\n' "sqlite_database=$SQLITE_DATABASE"
if [ -n "$PG_DATABASE" ]; then
  printf '%s\n' "postgres_target=$PG_DATABASE"
fi
