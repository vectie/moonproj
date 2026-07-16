#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK_ROOT=${1:?usage: company_period_close_control.sh WORK_DIR OUTPUT [PERIOD_ID]}
OUTPUT=${2:?usage: company_period_close_control.sh WORK_DIR OUTPUT [PERIOD_ID]}
PERIOD_ID=${3:-migration-opening}
set -- $(find "$WORK_ROOT" -type f -name '*-reconciliation.json' -print | sort)
if [ "$#" -eq 0 ]; then echo "period close control failed: no accounting reconciliation cohorts found" >&2; exit 1; fi
exec moon run --target native "$SCRIPT_DIR/../cmd/period_close_control" -- "$OUTPUT" "$PERIOD_ID" "$@"
