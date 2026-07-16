#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RECEIPT=${1:?usage: company_sqlite_projection_parity.sh RECEIPT DATABASE OUTPUT}
DATABASE=${2:?usage: company_sqlite_projection_parity.sh RECEIPT DATABASE OUTPUT}
OUTPUT=${3:?usage: company_sqlite_projection_parity.sh RECEIPT DATABASE OUTPUT}
SQLITE_BIN=${SQLITE_BIN:-sqlite3}

source_snapshot_id=$(sed -n 's/.*"source_snapshot_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$RECEIPT" | head -n 1)
mapping_version=$(sed -n 's/.*"mapping_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$RECEIPT" | head -n 1)
if [ -z "$source_snapshot_id" ] || [ -z "$mapping_version" ]; then
  echo "company SQLite projection parity failed: receipt identity is missing" >&2
  exit 1
fi
sql_literal() {
  printf "%s" "$1" | sed "s/'/''/g"
}
snapshot_sql=$(sql_literal "$source_snapshot_id")
mapping_sql=$(sql_literal "$mapping_version")
WORK_DIR=${TMPDIR:-/tmp}/moonproj-sqlite-parity.$$
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM
integrity=$($SQLITE_BIN -batch -noheader "$DATABASE" 'PRAGMA integrity_check;')
rows="$WORK_DIR/rows"
$SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" \
  "SELECT coalesce(hex(aggregate_type), ''), coalesce(hex(aggregate_id), ''), coalesce(hex(json_extract(payload, '\$.source_table')), ''), coalesce(hex(json_extract(payload, '\$.source_id')), '') FROM company_aggregate_projection WHERE json_extract(payload, '\$.source_snapshot_id') = '$snapshot_sql' AND json_extract(payload, '\$.mapping_version') = '$mapping_sql' ORDER BY aggregate_type, aggregate_id, revision;" > "$rows"
exec moon run --target native "$SCRIPT_DIR/../cmd/sqlite_projection_parity" -- "$RECEIPT" "$OUTPUT" "$rows" "$integrity"
