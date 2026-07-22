#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SKILL_TARGET="$ROOT/.moonsuite/products/moonclaw/skills"
MOONGATE_BIN=${MOONGATE_BIN:-"$ROOT/../moongate/_build/native/release/build/cmd/main/main.exe"}
MOONGATE_HOST=${MOONGATE_HOST:-127.0.0.1}
MOONGATE_PORT=${MOONGATE_PORT:-15721}
MOONGATE_MODEL=${MOONGATE_MODEL:-gpt-5.6-sol}

mkdir -p "$SKILL_TARGET"
rm -rf \
  "$SKILL_TARGET/moonsuite-progress-audit" \
  "$SKILL_TARGET/moonsuite-health-audit"
for skill in moonsuite-production-gate moonsuite-evidence-review; do
  source="$ROOT/skills/$skill"
  target="$SKILL_TARGET/${source##*/}"
  mkdir -p "$target"
  cp -R "$source/." "$target/"
done

if test ! -x "$MOONGATE_BIN"; then
  echo "MoonGate binary is unavailable: $MOONGATE_BIN" >&2
  echo "Build ../moongate or set MOONGATE_BIN." >&2
  exit 1
fi

mkdir -p "$ROOT/.moonsuite"
"$MOONGATE_BIN" suite write-status \
  --path "$ROOT/.moonsuite/suite-status.json" \
  --host "$MOONGATE_HOST" \
  --port "$MOONGATE_PORT" \
  --model "$MOONGATE_MODEL"

echo "MoonClaw engineering skills and MoonGate discovery are prepared for $ROOT"
