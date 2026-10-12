#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST=${MOONPROJ_DIST:-"$ROOT/dist/opc"}

sh "$ROOT/scripts/build_opc_frontend.sh" "$DIST"
MOONPROJ_DIST="$DIST" exec node "$ROOT/scripts/portfolio_host.mjs"
