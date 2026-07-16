#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DATABASE=${1:?usage: erp_relationship_audit.sh DATABASE EXPORT_MANIFEST OUTPUT}
MANIFEST=${2:?usage: erp_relationship_audit.sh DATABASE EXPORT_MANIFEST OUTPUT}
OUTPUT=${3:?usage: erp_relationship_audit.sh DATABASE EXPORT_MANIFEST OUTPUT}
SQLITE_BIN=${SQLITE_BIN:-sqlite3}
WORK_DIR=${TMPDIR:-/tmp}/moonproj-relationship-audit.$$
mkdir -p "$WORK_DIR"; trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM
moon run --target native "$SCRIPT_DIR/../cmd/relationship_audit" -- prepare "$MANIFEST" "$WORK_DIR"
$SQLITE_BIN -batch -noheader -separator '|' "$DATABASE" < "$WORK_DIR/audit.sql" > "$WORK_DIR/rows"
exec moon run --target native "$SCRIPT_DIR/../cmd/relationship_audit" -- report "$MANIFEST" "$WORK_DIR/rows" "$DATABASE" "$OUTPUT"
