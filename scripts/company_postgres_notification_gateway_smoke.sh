#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE_PORT=${SERVICE_PORT:-4302}
GATEWAY_PORT=${GATEWAY_PORT:-4303}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-notification-gateway-smoke-token}
ACTOR_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-notification-gateway-secret}
USER_CODE=${MOONPROJ_DEV_USER:-notification-gateway-user}
PASSWORD=${MOONPROJ_DEV_PASSWORD:-notification-gateway-password}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
export PGHOST PGPORT PGUSER PGPASSWORD PSQL_BIN

TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-notification-gateway.XXXXXX")
SERVICE_PID=""
GATEWAY_PID=""
SUFFIX=$(/bin/date +%s)
COMMAND_KEY="notification-gateway-$SUFFIX"
SUBSCRIPTION_KEY="notification-subscription-gateway-$SUFFIX"
DIGEST_KEY="notification-digest-gateway-$SUFFIX"

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
    "DELETE FROM company_aggregate_projection WHERE (aggregate_type = 'notification_message' AND aggregate_id = 'message-all:admin') OR (aggregate_type = 'notification_subscription' AND aggregate_id = 'sub-$SUBSCRIPTION_KEY') OR (aggregate_type = 'notification_digest_dispatch' AND aggregate_id = '$DIGEST_KEY'); DELETE FROM company_record WHERE source_id IN ('moonproj:command:$COMMAND_KEY', 'moonproj:audit:notification:message_read_all:$COMMAND_KEY', 'moonproj:command:$SUBSCRIPTION_KEY', 'moonproj:audit:notification:subscription_create:$SUBSCRIPTION_KEY', 'moonproj:command:$DIGEST_KEY', 'moonproj:audit:notification:digest_dispatch:$DIGEST_KEY');" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
PSQL_BIN="$PSQL_BIN" "$ROOT/scripts/company_postgres_service.sh" \
  --port "$SERVICE_PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!
MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
MOONPROJ_SESSION_SECRET="notification-gateway-session" MOONPROJ_DEV_USER="$USER_CODE" \
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

status=$(/usr/bin/curl -sS -o "$TMP_DIR/subscription.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$SUBSCRIPTION_KEY\",\"ruleCode\":\"W005\",\"bizType\":\"expense\",\"severityMin\":\"warning\",\"channels\":[\"in_app\",\"webhook\"],\"enabled\":true}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/notify/subscriptions")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.subId == "sub-'"$SUBSCRIPTION_KEY"'" and .data.delivery_effect == false and .data.providerExecution == false' "$TMP_DIR/subscription.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/subscription-replay.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$SUBSCRIPTION_KEY\",\"ruleCode\":\"W005\",\"bizType\":\"expense\",\"severityMin\":\"warning\",\"channels\":[\"in_app\",\"webhook\"],\"enabled\":true}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/notify/subscriptions")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.subId == "sub-'"$SUBSCRIPTION_KEY"'"' "$TMP_DIR/subscription-replay.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/read-all.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$COMMAND_KEY\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/notify/messages/read-all")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.state == "read" and .data.delivery_effect == false and .data.providerExecution == false' "$TMP_DIR/read-all.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$COMMAND_KEY\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/notify/messages/read-all")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.state == "read"' "$TMP_DIR/replay.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/digest.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $DIGEST_KEY" --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/notify/digest/dispatch")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .data.sent == false and .data.dryRun == true and .data.delivery_effect == false and .data.providerExecution == false' "$TMP_DIR/digest.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/digest-replay.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $DIGEST_KEY" --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/notify/digest/dispatch")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.sent == false and .data.dryRun == true' "$TMP_DIR/digest-replay.json" >/dev/null

echo "native MoonBit notification read-all/digest gateway smoke passed"
