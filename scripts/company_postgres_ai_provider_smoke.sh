#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4282}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-ai-provider-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-ai-provider-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-ai-provider.XXXXXX")
PID=""
SUFFIX=$(/bin/date +%s)
LLM_KEY="ai-provider-llm-$SUFFIX"
OCR_KEY="ai-provider-ocr-$SUFFIX"
ADMIN_LLM_KEY="ai-provider-admin-llm-$SUFFIX"

psql() {
  PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" \
    PGPASSWORD=${PGPASSWORD:-520825} "$PSQL_BIN" "$@"
}

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql -v ON_ERROR_STOP=0 -c \
    "DELETE FROM company_record WHERE source_id LIKE '%$LLM_KEY%' OR source_id LIKE '%$OCR_KEY%' OR source_id LIKE '%$ADMIN_LLM_KEY%' OR source_id LIKE '%ai:llm_test:%$SUFFIX%' OR source_id LIKE '%ai:ocr_test:%$SUFFIX%'; DELETE FROM company_aggregate_projection WHERE aggregate_type = 'ai_provider_test' AND source_event_id LIKE '%$SUFFIX%';" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" \
  PGPASSWORD=${PGPASSWORD:-520825} PSQL_BIN="$PSQL_BIN" \
  MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" \
  "$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
PID=$!
ready=0
for i in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then ready=1; break; fi
  /bin/sleep 1
done
test "$ready" = 1

SIGNATURE=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/sed 's/^.*= //')
curl_common() {
  /usr/bin/curl -sS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
    -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
    -H 'Content-Type: application/json' "$@"
}

status=$(curl_common -o "$TMP_DIR/llm.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $LLM_KEY" --data '{"provider":"openai","key":"super-secret-key","model":"gpt-test","endpoint":"https://example.invalid/v1"}' "http://127.0.0.1:$PORT/api/company/notify/llm-test")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.commandType == "llm_test" and .data.provider == "openai" and .data.ok == false and .data.tested == false and .data.reason == "provider_execution_disabled" and .data.keyConfigured == true and .data.endpointConfigured == true and .data.providerExecution == false and (.data | tostring | contains("super-secret-key") | not)' "$TMP_DIR/llm.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/llm-replay.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $LLM_KEY" --data '{"provider":"openai","key":"super-secret-key","model":"gpt-test","endpoint":"https://example.invalid/v1"}' "http://127.0.0.1:$PORT/api/company/source/notify/llm-test")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.provider == "openai" and .data.providerExecution == false' "$TMP_DIR/llm-replay.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/ocr.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $OCR_KEY" --data '{"provider":"paddle"}' "http://127.0.0.1:$PORT/api/company/admin/ocr/test")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.commandType == "ocr_test" and .data.provider == "paddle" and .data.tested == false and .data.dryRun == true and .data.providerExecution == false' "$TMP_DIR/ocr.json" >/dev/null

status=$(curl_common -o "$TMP_DIR/admin-llm.json" -w '%{http_code}' -X POST -H "Idempotency-Key: $ADMIN_LLM_KEY" --data '{"provider":"mock","model":"mock-model"}' "http://127.0.0.1:$PORT/api/company/source/admin/llm/test")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.commandType == "llm_test" and .data.provider == "mock" and .data.reason == "provider_execution_disabled" and .data.providerExecution == false' "$TMP_DIR/admin-llm.json" >/dev/null

/usr/bin/printf '%s\n' 'native PostgreSQL AI provider candidate smoke passed'
