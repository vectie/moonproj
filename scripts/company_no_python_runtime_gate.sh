#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MANIFEST=${1:-"$SCRIPT_DIR/pure_moonbit_runtime_paths.txt"}

if [ ! -f "$MANIFEST" ]; then
  printf '%s\n' "runtime manifest not found: $MANIFEST" >&2
  exit 2
fi

# Match executable interpreter/module references, not historical prose such as
# a MoonBit comment that explains this migration.
PYTHON_INVOKE='(^|[[:space:];|&(<])python([0-9.]*)?([[:space:]]|$)|(^|[[:space:];|&(<])[^[:space:]]*\.py([[:space:]]|$))'
failed=0

while IFS= read -r relative || [ -n "$relative" ]; do
  case "$relative" in
    ''|'#'*) continue ;;
  esac

  case "$relative" in
    /*|*..*)
      printf '%s\n' "invalid runtime-manifest path: $relative" >&2
      failed=1
      continue
      ;;
  esac

  path="$ROOT_DIR/$relative"
  if [ ! -e "$path" ]; then
    printf '%s\n' "runtime-manifest path missing: $relative" >&2
    failed=1
    continue
  fi

  if [ -d "$path" ]; then
    files=$(find "$path" -type f -print)
  else
    files=$path
  fi

  for file in $files; do
    if matches=$(rg -n -e "$PYTHON_INVOKE" "$file" 2>/dev/null); then
      printf '%s\n' "Python invocation in supported runtime path: ${file#"$ROOT_DIR/"}" >&2
      printf '%s\n' "$matches" >&2
      failed=1
    fi
  done
done < "$MANIFEST"

if [ "$failed" -ne 0 ]; then
  printf '%s\n' 'pure MoonBit runtime gate failed' >&2
  exit 1
fi

printf '%s\n' 'pure MoonBit runtime gate passed (compiled MoonBit plus shell/PostgreSQL tools only)'
