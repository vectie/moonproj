#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE_PORT=${SERVICE_PORT:-4300}
GATEWAY_PORT=${GATEWAY_PORT:-4301}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-attachment-gateway-smoke-token}
ACTOR_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-attachment-gateway-secret}
USER_CODE=${MOONPROJ_DEV_USER:-attachment-gateway-user}
PASSWORD=${MOONPROJ_DEV_PASSWORD:-attachment-gateway-password}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-attachment-gateway.XXXXXX")
SERVICE_PID=""
GATEWAY_PID=""
cleanup() {
  if [ -n "$GATEWAY_PID" ]; then
    kill "$GATEWAY_PID" 2>/dev/null || true
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
"$ROOT/scripts/company_postgres_service.sh" --port "$SERVICE_PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!
MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
MOONPROJ_SESSION_SECRET="attachment-gateway-session" MOONPROJ_DEV_USER="$USER_CODE" \
MOONPROJ_DEV_PASSWORD="$PASSWORD" "$ROOT/scripts/company_postgres_gateway.sh" \
  --port "$GATEWAY_PORT" --service-port "$SERVICE_PORT" --actor-id admin >"$TMP_DIR/gateway.log" 2>&1 &
GATEWAY_PID=$!

ready=0
i=0
while [ "$i" -lt 120 ]; do
  if /usr/bin/curl -sS "http://127.0.0.1:$GATEWAY_PORT/api/session" >"$TMP_DIR/session.json" 2>/dev/null; then
    ready=1
    break
  fi
  i=$((i + 1))
  /bin/sleep 1
done
if [ "$ready" -ne 1 ]; then
  /bin/cat "$TMP_DIR/service.log" "$TMP_DIR/gateway.log"
  exit 1
fi

/usr/bin/curl -fsS -c "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"user_code\":\"$USER_CODE\",\"password\":\"$PASSWORD\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/session/login" >"$TMP_DIR/login.json"
/usr/bin/jq -e '.authenticated == true and .actor_id == "admin"' "$TMP_DIR/login.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/upload.json" -w '%{http_code}' -X POST \
  -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{"idempotency_key":"rabbita-attachment-upload-v1"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/attachments/upload")
test "$status" = 409
/usr/bin/jq -e '.code == 43002 and .data.multipartAccepted == false and .persisted == false and .authorizing == false and .provider_execution == false' "$TMP_DIR/upload.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/reextract.json" -w '%{http_code}' -X POST \
  -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/attachments/re-extract/ATT-RABBITA-LOCAL")
test "$status" = 404
/usr/bin/jq -e '.code == 43001 and .persisted == false and .authorizing == false and .provider_execution == false' "$TMP_DIR/reextract.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/download.json" -w '%{http_code}' \
  -b "$TMP_DIR/cookies.txt" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/attachments/download/ATT-RABBITA-LOCAL")
test "$status" = 404
/usr/bin/jq -e '.code == 43001 and .downloadable == false and .binary_storage == "not_imported" and .authorizing == false' "$TMP_DIR/download.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/delete.json" -w '%{http_code}' -X DELETE \
  -b "$TMP_DIR/cookies.txt" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/attachments/ATT-RABBITA-LOCAL")
test "$status" = 409
/usr/bin/jq -e '.code == 43003 and .data.deleted == false and .persisted == false and .authorizing == false and .provider_execution == false' "$TMP_DIR/delete.json" >/dev/null

echo "native MoonBit attachment upload/re-extract/download/delete gateway boundary smoke passed"
