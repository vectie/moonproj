#!/bin/sh
set -eu

DB_PATH=${1:-../erp/erp_new/backup/erp-v0.1.0-snapshot.db}

if [ ! -f "$DB_PATH" ]; then
  echo "ERP snapshot not found: $DB_PATH" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  HASH=$(shasum -a 256 "$DB_PATH" | awk '{print $1}')
else
  HASH=$(sha256sum "$DB_PATH" | awk '{print $1}')
fi

echo "source=$DB_PATH"
echo "sha256=$HASH"
printf '%-32s %s\n' table rows
printf '%-32s %s\n' '-----' ----

total=0
table_count=0
tables=$(sqlite3 "$DB_PATH" \
  "SELECT name FROM sqlite_master WHERE type='table' AND name <> 'sqlite_sequence' ORDER BY name;")
for table in $tables; do
  rows=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM \"$table\";")
  printf '%-32s %s\n' "$table" "$rows"
  total=$((total + rows))
  table_count=$((table_count + 1))
done

printf '%-32s %s\n' total_tables "$table_count"
printf '%-32s %s\n' total_rows "$total"
