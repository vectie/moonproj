#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="$ROOT/config/moontown-engineering-standing-goals.json"
MOONSUITE_HOME=${MOONSUITE_HOME:-"$HOME/.moonsuite"}
TARGET_DIR="$MOONSUITE_HOME/products/moontown"
TARGET="$TARGET_DIR/standing-goals.json"

command -v jq >/dev/null 2>&1 || {
  echo "jq is required to merge MoonTown standing goals" >&2
  exit 1
}

mkdir -p "$TARGET_DIR"
if [ ! -f "$TARGET" ]; then
  printf '%s\n' '[]' >"$TARGET"
fi

TMP="$TARGET.tmp.$$"
jq -s '.[0] + .[1] | unique_by(.id)' "$TARGET" "$SOURCE" >"$TMP"
mv "$TMP" "$TARGET"
echo "Installed MoonProj engineering freshness goal in $TARGET"
