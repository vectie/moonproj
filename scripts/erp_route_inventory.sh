#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ROUTES_DIR=${1:?route directory is required}
OUTPUT=${2:?output path is required}

set -- "$ROUTES_DIR" "$OUTPUT" $(find "$ROUTES_DIR" -maxdepth 1 -type f -name '*.js' -print | sort)
if [ "$#" -lt 3 ]; then
  echo "route directory has no JavaScript files: $ROUTES_DIR" >&2
  exit 1
fi
moon run --target native "$ROOT/cmd/route_inventory" -- "$@"
