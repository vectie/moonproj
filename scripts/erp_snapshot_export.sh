#!/bin/sh
set -eu

# Export a deterministic, credential-safe row snapshot for migration review.
# This script never mutates the ERP database. It deliberately writes outside
# the repository by default when used for a rehearsal, and the caller should
# treat the output as controlled migration evidence rather than target data.

DB_PATH=${1:-../erp/erp_new/backup/erp-v0.1.0-snapshot.db}
OUT_DIR=${2:-/tmp/moonproj-erp-export}

if [ ! -f "$DB_PATH" ]; then
  echo "ERP snapshot not found: $DB_PATH" >&2
  exit 1
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

mkdir -p "$OUT_DIR/tables"

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

SOURCE_HASH=$(hash_file "$DB_PATH")
MANIFEST="$OUT_DIR/manifest.json"
ENTRIES="$OUT_DIR/.table-entries.ndjson"

: > "$ENTRIES"

tables=$(sqlite3 "$DB_PATH" \
  "SELECT name FROM sqlite_master WHERE type='table' AND name <> 'sqlite_sequence' ORDER BY name;")
for table in $tables; do
  case "$table" in
    *[!A-Za-z0-9_]*|"")
      echo "unsafe table name from sqlite metadata: $table" >&2
      exit 1
      ;;
  esac

  table_path="$OUT_DIR/tables/$table.json"
  # ORDER BY rowid makes the export stable for this SQLite snapshot. The
  # fallback ordering is intentionally not used: a table without rowid must
  # be handled explicitly rather than silently producing a different export.
  raw_json=$(sqlite3 -json "$DB_PATH" "SELECT * FROM \"$table\" ORDER BY rowid;")
  if [ -z "$raw_json" ]; then
    printf '%s\n' '[]' > "$table_path"
  else
    printf '%s\n' "$raw_json" \
      | jq 'map(with_entries(select(.key | test("password|secret|token|private|ip$"; "i") | not)))' \
      > "$table_path"
  fi

  rows=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM \"$table\";")
  primary_key=$(sqlite3 "$DB_PATH" \
    "SELECT name FROM pragma_table_info('$table') WHERE pk > 0 ORDER BY pk LIMIT 1;")
  if [ "$rows" -gt 0 ] && [ -z "$primary_key" ]; then
    echo "table has no primary key: $table" >&2
    exit 1
  fi
  table_hash=$(hash_file "$table_path")
  entry=$(jq -cn \
    --arg table "$table" \
    --arg primary_key "$primary_key" \
    --argjson rows "$rows" \
    --arg sha256 "$table_hash" \
    '{table:$table,primary_key:$primary_key,rows:$rows,sha256:$sha256,file:("tables/" + $table + ".json")}')
  printf '%s\n' "$entry" >> "$ENTRIES"
done

jq -s \
  --arg format "moonproj.erp.snapshot.v1" \
  --arg source_path "$DB_PATH" \
  --arg source_sha256 "$SOURCE_HASH" \
  --arg redaction "keys matching password, secret, token, private, or ip are removed" \
  '{format:$format,source_path:$source_path,source_sha256:$source_sha256,redaction:$redaction,tables:.}' \
  "$ENTRIES" > "$MANIFEST"
rm -f "$ENTRIES"
jq empty "$MANIFEST"
echo "exported=$OUT_DIR"
echo "source_sha256=$SOURCE_HASH"
echo "tables=$(printf '%s\n' "$tables" | awk 'NF { count += 1 } END { print count + 0 }')"
