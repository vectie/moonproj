#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EXPORT_DIR=${1:?usage: erp_row_coverage.sh EXPORT_DIR WORK_DIR OUTPUT}
WORK_DIR=${2:?missing work directory}
OUTPUT=${3:?missing output path}
set -- "$EXPORT_DIR" "$OUTPUT"
for path in "$WORK_DIR"/*.json "$WORK_DIR"/typed-cohorts/*.json; do
  if [ -f "$path" ]; then set -- "$@" "$path"; fi
done
exec moon run --target native "$SCRIPT_DIR/../cmd/row_coverage" -- "$@"
