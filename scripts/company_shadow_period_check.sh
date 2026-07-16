#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK_DIR=${1:?usage: company_shadow_period_check.sh WORK_DIR MANIFEST OUTPUT}
MANIFEST=${2:?missing shadow manifest}
OUTPUT=${3:?missing output path}
set -- "$WORK_DIR" "$MANIFEST" "$OUTPUT"
for path in "$WORK_DIR"/*-parity.json "$WORK_DIR"/typed-cohorts/*-parity.json; do
  if [ -f "$path" ]; then set -- "$@" "$path"; fi
done
set -- "$@" --reconciliations
for path in "$WORK_DIR"/*-reconciliation.json; do
  if [ -f "$path" ]; then set -- "$@" "$path"; fi
done
exec moon run --target native "$SCRIPT_DIR/../cmd/shadow_period_check" -- "$@"
