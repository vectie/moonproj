#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST=${1:-"$ROOT/dist/opc"}

warren build "$ROOT/frontend/opc" --dist "$DIST"
cp "$ROOT/frontend/opc_public/index.html" "$DIST/index.html"
cp "$ROOT/frontend/opc_public/styles.css" "$DIST/styles.css"
cp "$ROOT/frontend/opc_public/moonproj.svg" "$DIST/moonproj.svg"

printf 'Basic OPC frontend built at %s\n' "$DIST"
