#!/usr/bin/env sh
set -eu

# Seed the persisted Company Operating Charter for the OPC Research Lab pilot
# through the authenticated MoonProj gateway (or verify existing revision).
# Never modifies ~/Downloads/Research originals.

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GATEWAY_URL=${MOONPROJ_GATEWAY_URL:-"http://127.0.0.1:4173"}
CHARTER_FILE=${1:-"$ROOT/scripts/fixtures/opc_research_charter.json"}
IDEMPOTENCY_KEY=${MOONPROJ_CHARTER_KEY:-"seed-opc-research-charter-v1"}

if [ ! -f "$CHARTER_FILE" ]; then
  printf 'Charter fixture not found: %s\n' "$CHARTER_FILE" >&2
  exit 1
fi

if [ -n "${MOONPROJ_SESSION_COOKIE:-}" ]; then
  curl -fsS -X PUT "$GATEWAY_URL/api/company/charter" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: $IDEMPOTENCY_KEY" \
    -H "Cookie: $MOONPROJ_SESSION_COOKIE" \
    --data-binary "@$CHARTER_FILE"
  printf '\n'
  exit 0
fi

# Direct authenticated desktop session flow when MOONPROJ_DEV_USER / PASSWORD are set
if [ -n "${MOONPROJ_DEV_USER:-}" ] && [ -n "${MOONPROJ_DEV_PASSWORD:-}" ]; then
  COOKIE_JAR=$(mktemp)
  trap 'rm -f "$COOKIE_JAR"' EXIT INT TERM
  curl -fsS -c "$COOKIE_JAR" -X POST "$GATEWAY_URL/api/company/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$MOONPROJ_DEV_USER\",\"password\":\"$MOONPROJ_DEV_PASSWORD\"}" >/dev/null
  curl -fsS -b "$COOKIE_JAR" -X PUT "$GATEWAY_URL/api/company/charter" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: $IDEMPOTENCY_KEY" \
    --data-binary "@$CHARTER_FILE"
  printf '\n'
  exit 0
fi

printf 'Set MOONPROJ_SESSION_COOKIE or MOONPROJ_DEV_USER + MOONPROJ_DEV_PASSWORD to seed %s\n' "$GATEWAY_URL/api/company/charter" >&2
exit 1
