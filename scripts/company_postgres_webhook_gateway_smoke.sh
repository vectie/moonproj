#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE_PORT=${SERVICE_PORT:-4296}
GATEWAY_PORT=${GATEWAY_PORT:-4297}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-webhook-gateway-smoke-token}
ACTOR_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-webhook-gateway-secret}
USER_CODE=${MOONPROJ_DEV_USER:-webhook-gateway-user}
PASSWORD=${MOONPROJ_DEV_PASSWORD:-webhook-gateway-password}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required}
export PGHOST PGPORT PGUSER PGPASSWORD PSQL_BIN

TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-webhook-gateway.XXXXXX")
SERVICE_PID=""
GATEWAY_PID=""
SUFFIX=$(/bin/date +%s)
COMMAND_KEY="webhook-gateway-$SUFFIX"
CONFIG_KEY="webhook-config-gateway-$SUFFIX"
SCAN_KEY="webhook-scan-gateway-$SUFFIX"

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
    "DELETE FROM company_aggregate_projection WHERE (aggregate_type = 'webhook_test_delivery' AND aggregate_id = '$COMMAND_KEY') OR (aggregate_type = 'webhook_config' AND aggregate_id = 'wecom' AND source_event_id LIKE '%$CONFIG_KEY%') OR (aggregate_type = 'webhook_overdue_scan' AND aggregate_id = '$SCAN_KEY'); DELETE FROM company_record WHERE source_id LIKE '%$COMMAND_KEY%' OR source_id LIKE '%$CONFIG_KEY%' OR source_id LIKE '%$SCAN_KEY%';" \
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
MOONPROJ_SESSION_SECRET="webhook-gateway-session" \
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

status=$(/usr/bin/curl -sS -o "$TMP_DIR/config.json" -w '%{http_code}' \
  -X PUT -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$CONFIG_KEY\",\"enabled\":true,\"secret\":\"__keep__\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/webhook/config/wecom")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.platform == "wecom" and .data.credentialsBound == false and .data.providerExecution == false and .data.delivery_effect == false' "$TMP_DIR/config.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/config-replay.json" -w '%{http_code}' \
  -X PUT -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$CONFIG_KEY\",\"enabled\":true,\"secret\":\"__keep__\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/webhook/config/wecom")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.platform == "wecom"' "$TMP_DIR/config-replay.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$COMMAND_KEY\",\"title\":\"Rabbita gateway test\",\"content\":\"no provider call\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/webhook/test/wecom")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.platform == "wecom" and .data.wouldSend == false and .data.providerExecution == false and .data.delivery_effect == false' "$TMP_DIR/create.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$COMMAND_KEY\",\"title\":\"Rabbita gateway test\",\"content\":\"no provider call\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/webhook/test/wecom")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.wouldSend == false' "$TMP_DIR/replay.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/preview.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{"idempotency_key":"webhook-preview-gateway"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/webhook/scan-overdue/preview")
test "$status" = 200
/usr/bin/jq -e '.success == true and .persisted == false and .provider_execution == false and .delivery_effect == false and .query_execution == false and .authorizing == false' "$TMP_DIR/preview.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/scan.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$SCAN_KEY\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/webhook/scan-overdue")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.dryRun == true and .data.sent == false and .data.ticketMutation == false and .data.providerExecution == false and .data.delivery_effect == false' "$TMP_DIR/scan.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/scan-replay.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$SCAN_KEY\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/webhook/scan-overdue")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.dryRun == true and .data.sent == false' "$TMP_DIR/scan-replay.json" >/dev/null

echo "native MoonBit webhook gateway/test/overdue-scan smoke passed"
