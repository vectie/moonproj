#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE_PORT=${SERVICE_PORT:-4294}
GATEWAY_PORT=${GATEWAY_PORT:-4295}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-ai-gateway-smoke-token}
ACTOR_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-ai-gateway-secret}
USER_CODE=${MOONPROJ_DEV_USER:-ai-gateway-user}
PASSWORD=${MOONPROJ_DEV_PASSWORD:-ai-gateway-password}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
export PGHOST PGPORT PGUSER PGPASSWORD PSQL_BIN

TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-ai-gateway.XXXXXX")
SERVICE_PID=""
GATEWAY_PID=""
SUFFIX=$(/bin/date +%s)
OCR_KEY="ai-gateway-ocr-$SUFFIX"
LLM_KEY="ai-gateway-llm-$SUFFIX"

cleanup() {
  if [ -n "$GATEWAY_PID" ]; then
    kill "$GATEWAY_PID" 2>/dev/null || true
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE aggregate_type = 'ai_provider_test' AND aggregate_id IN ('$OCR_KEY', '$LLM_KEY'); DELETE FROM company_record WHERE source_id LIKE '%$OCR_KEY%' OR source_id LIKE '%$LLM_KEY%';" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
"$ROOT/scripts/company_postgres_service.sh" --port "$SERVICE_PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
MOONPROJ_SESSION_SECRET="ai-gateway-session" \
MOONPROJ_DEV_USER="$USER_CODE" \
MOONPROJ_DEV_PASSWORD="$PASSWORD" \
"$ROOT/scripts/company_postgres_gateway.sh" --port "$GATEWAY_PORT" --service-port "$SERVICE_PORT" --actor-id admin >"$TMP_DIR/gateway.log" 2>&1 &
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

/usr/bin/curl -fsS -c "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  --data "{\"user_code\":\"$USER_CODE\",\"password\":\"$PASSWORD\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/session/login" >"$TMP_DIR/login.json"
/usr/bin/jq -e '.authenticated == true and .actor_id == "admin"' "$TMP_DIR/login.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/ocr.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$OCR_KEY\",\"provider\":\"paddle\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/admin/ocr/test")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.commandType == "ocr_test" and .data.provider == "paddle" and .data.providerExecution == false' "$TMP_DIR/ocr.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/llm.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$LLM_KEY\",\"provider\":\"openai\",\"key\":\"gateway-secret\",\"model\":\"gpt-test\",\"endpoint\":\"https://example.invalid/v1\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/admin/llm/test")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.commandType == "llm_test" and .data.provider == "openai" and .data.providerExecution == false and ((.data | tostring) | contains("gateway-secret") | not)' "$TMP_DIR/llm.json" >/dev/null

echo "native MoonBit AI provider gateway/redaction smoke passed"
