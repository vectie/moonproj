#!/bin/sh
set -eu

SCHEMA_PATH=${1:-../erp/erp_new/server/src/db/index.js}
DB_PATH=${2:-../erp/erp_new/backup/erp-v0.1.0-snapshot.db}

if [ ! -f "$SCHEMA_PATH" ]; then
  echo "ERP schema initializer not found: $SCHEMA_PATH" >&2
  exit 1
fi

echo "schema=$SCHEMA_PATH"
echo "backup=$DB_PATH"
printf '%-36s %-12s %s\n' table backup_rows status
printf '%-36s %-12s %s\n' '-----' ------------ ------

schema_count=0
present_count=0
for table in $(sed -n \
  's/.*CREATE TABLE IF NOT EXISTS \([A-Za-z0-9_]*\).*/\1/p' \
  "$SCHEMA_PATH" | sort -u); do
  schema_count=$((schema_count + 1))
  rows="absent"
  status="schema-only"
  if [ -f "$DB_PATH" ] && sqlite3 "$DB_PATH" \
    "SELECT 1 FROM sqlite_master WHERE type='table' AND name='$table';" \
    | grep -q 1; then
    rows=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM \"$table\";")
    status="present"
    present_count=$((present_count + 1))
  fi
  printf '%-36s %-12s %s\n' "$table" "$rows" "$status"
done

printf '%-36s %-12s %s\n' schema_tables "$schema_count" ""
printf '%-36s %-12s %s\n' backup_tables "$present_count" ""
