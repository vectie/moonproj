#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REVIEWER_WORKSPACE="$ROOT/.moonsuite/reviewer-workspace"
MOONGATE_BIN=${MOONGATE_BIN:-"$ROOT/../moongate/_build/native/release/build/cmd/main/main.exe"}
MOONGATE_HOST=${MOONGATE_HOST:-127.0.0.1}
MOONGATE_PORT=${MOONGATE_PORT:-15721}
MOONGATE_MODEL=${MOONGATE_MODEL:-gpt-5.6-sol}

for workspace in "$ROOT" "$REVIEWER_WORKSPACE"; do
  skill_target="$workspace/.moonsuite/products/moonclaw/skills"
  mkdir -p "$skill_target"
  rm -rf \
    "$skill_target/moonsuite-progress-audit" \
    "$skill_target/moonsuite-health-audit"
  for skill in moonsuite-production-gate moonsuite-evidence-review; do
    source="$ROOT/skills/$skill"
    target="$skill_target/${source##*/}"
    mkdir -p "$target"
    cp -R "$source/." "$target/"
  done
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

mkdir -p "$REVIEWER_WORKSPACE/.moonsuite"
"$MOONGATE_BIN" suite write-status \
  --path "$REVIEWER_WORKSPACE/.moonsuite/suite-status.json" \
  --host "$MOONGATE_HOST" \
  --port "$MOONGATE_PORT" \
  --model "$MOONGATE_MODEL"

echo "MoonClaw engineering skills and MoonGate discovery are prepared for $ROOT"
