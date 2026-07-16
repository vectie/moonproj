#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE=${1:?usage: company_sqlite_backup_restore.sh [--overwrite] DATABASE BACKUP [OUTPUT]}
if [ "$SOURCE" = "--overwrite" ]; then
  OVERWRITE=1
  SOURCE=${2:?missing source database}
  BACKUP=${3:?missing backup database}
  OUTPUT=${4:-}
else
  OVERWRITE=0
  BACKUP=${2:?missing backup database}
  OUTPUT=${3:-}
fi
SQLITE_BIN=${SQLITE_BIN:-sqlite3}
if [ "$SOURCE" = "$BACKUP" ]; then
  echo "company SQLite backup/restore failed: source and backup paths must differ" >&2
  exit 1
fi
if [ ! -f "$SOURCE" ]; then
  echo "company SQLite backup/restore failed: source database not found: $SOURCE" >&2
  exit 1
fi
if [ -e "$BACKUP" ] && [ "$OVERWRITE" -ne 1 ]; then
  echo "company SQLite backup/restore failed: backup destination already exists: $BACKUP" >&2
  exit 1
fi
mkdir -p "$(dirname -- "$BACKUP")"
if [ "$OVERWRITE" -eq 1 ]; then rm -f "$BACKUP" "$BACKUP-wal" "$BACKUP-shm"; fi
WORK_DIR=${TMPDIR:-/tmp}/moonproj-sqlite-backup-restore.$$
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

moon run --target native "$SCRIPT_DIR/../cmd/sqlite_backup_restore" -- prepare "$WORK_DIR"
$SQLITE_BIN -batch -noheader "$SOURCE" ".backup '$BACKUP'"
$SQLITE_BIN -batch -noheader "$SOURCE" < "$WORK_DIR/logical-dump.sql" > "$WORK_DIR/source.rows"
$SQLITE_BIN -batch -noheader "$BACKUP" < "$WORK_DIR/logical-dump.sql" > "$WORK_DIR/backup.rows"
source_integrity=$($SQLITE_BIN -batch -noheader "$SOURCE" 'PRAGMA integrity_check;')
backup_integrity=$($SQLITE_BIN -batch -noheader "$BACKUP" 'PRAGMA integrity_check;')
source_schema=$($SQLITE_BIN -batch -noheader "$SOURCE" 'SELECT max(version) FROM company_schema;')
backup_schema=$($SQLITE_BIN -batch -noheader "$BACKUP" 'SELECT max(version) FROM company_schema;')
summary_json() {
  database=$1
  integrity=$2
  schema=$3
  company_schema=$($SQLITE_BIN -batch -noheader "$database" 'SELECT count(*) FROM company_schema;')
  company_record=$($SQLITE_BIN -batch -noheader "$database" 'SELECT count(*) FROM company_record;')
  company_projection=$($SQLITE_BIN -batch -noheader "$database" 'SELECT count(*) FROM company_aggregate_projection;')
  company_links=$($SQLITE_BIN -batch -noheader "$database" 'SELECT count(*) FROM company_accounting_event_link;')
  company_receipts=$($SQLITE_BIN -batch -noheader "$database" 'SELECT count(*) FROM company_migration_receipt;')
  jq -n --arg integrity "$integrity" --argjson schema_version "$schema" \
    --argjson company_schema "$company_schema" --argjson company_record "$company_record" \
    --argjson company_projection "$company_projection" --argjson company_links "$company_links" \
    --argjson company_receipts "$company_receipts" \
    '{integrity:$integrity,schema_version:$schema_version,counts:{company_schema:$company_schema,company_record:$company_record,company_aggregate_projection:$company_projection,company_accounting_event_link:$company_links,company_migration_receipt:$company_receipts}}'
}
summary_json "$SOURCE" "$source_integrity" "$source_schema" > "$WORK_DIR/source-summary.json"
summary_json "$BACKUP" "$backup_integrity" "$backup_schema" > "$WORK_DIR/backup-summary.json"
if [ -z "$OUTPUT" ]; then OUTPUT="$WORK_DIR/report.json"; fi
exec moon run --target native "$SCRIPT_DIR/../cmd/sqlite_backup_restore" -- report "$SOURCE" "$BACKUP" "$WORK_DIR/source.rows" "$WORK_DIR/backup.rows" "$WORK_DIR/source-summary.json" "$WORK_DIR/backup-summary.json" "$OUTPUT"
