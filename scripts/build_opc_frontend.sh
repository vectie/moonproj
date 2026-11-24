#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST=${1:-"$ROOT/dist/opc"}

warren build "$ROOT/frontend/opc" --dist "$DIST"
cp "$ROOT/frontend/opc_public/index.html" "$DIST/index.html"
cp "$ROOT/frontend/opc_public/styles.css" "$DIST/styles.css"
cp "$ROOT/frontend/opc_public/prd_workspace.css" "$DIST/prd_workspace.css"
cp "$ROOT/frontend/opc_public/prd_workspace.js" "$DIST/prd_workspace.js"
cp "$ROOT/frontend/opc_public/portfolio_home.js" "$DIST/portfolio_home.js"
cp "$ROOT/frontend/opc_public/deliverable_panel.js" "$DIST/deliverable_panel.js"
cp "$ROOT/frontend/opc_public/deliverable_acceptance.js" "$DIST/deliverable_acceptance.js"
cp "$ROOT/frontend/opc_public/portfolio_home.css" "$DIST/portfolio_home.css"
cp "$ROOT/frontend/opc_public/portfolio_catalog.json" "$DIST/portfolio_catalog.json"
cp "$ROOT/frontend/opc_public/moonproj.svg" "$DIST/moonproj.svg"
cp "$ROOT/frontend/opc_public/company_workspace.css" "$DIST/company_workspace.css"
cp "$ROOT/frontend/opc_public/company_workspace.js" "$DIST/company_workspace.js"

printf 'Basic OPC frontend built at %s\n' "$DIST"
