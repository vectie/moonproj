#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -z "${PSQL_BIN:-}" ]; then
  if command -v psql >/dev/null 2>&1; then
    PSQL_BIN=$(command -v psql)
  elif [ -x /Library/PostgreSQL/18/bin/psql ]; then
    PSQL_BIN=/Library/PostgreSQL/18/bin/psql
  else
    PSQL_BIN=psql
  fi
  export PSQL_BIN
fi
exec moon run --target native "$ROOT/cmd/postgres_accounting_reconciliation" -- "$@"
