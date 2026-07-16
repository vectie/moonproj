#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE_PORT=${SERVICE_PORT:-4298}
GATEWAY_PORT=${GATEWAY_PORT:-4299}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-warning-gateway-smoke-token}
ACTOR_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-warning-gateway-secret}
USER_CODE=${MOONPROJ_DEV_USER:-warning-gateway-user}
PASSWORD=${MOONPROJ_DEV_PASSWORD:-warning-gateway-password}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
export PGHOST PGPORT PGUSER PGPASSWORD PSQL_BIN

TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-warning-gateway.XXXXXX")
SERVICE_PID=""
GATEWAY_PID=""
SUFFIX=$(/bin/date +%s)
COMMAND_KEY="warning-gateway-$SUFFIX"
WARNING_GUID="source:W005:proj-0002"

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
    "DELETE FROM company_aggregate_projection WHERE aggregate_type = 'warning_state' AND aggregate_id = '$WARNING_GUID'; DELETE FROM company_record WHERE source_id IN ('moonproj:command:$COMMAND_KEY', 'moonproj:audit:warning:resolve:$COMMAND_KEY');" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
PSQL_BIN="$PSQL_BIN" \
"$ROOT/scripts/company_postgres_service.sh" --port "$SERVICE_PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
MOONPROJ_SESSION_SECRET="warning-gateway-session" \
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

/usr/bin/curl -fsS -b "$TMP_DIR/cookies.txt" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/warning?status=open" >"$TMP_DIR/warnings.json"
/usr/bin/jq -e '.data.rows | any(.[]; .warningGuid == "'"$WARNING_GUID"'")' "$TMP_DIR/warnings.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/scan-preview.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{"idempotency_key":"warning-scan-preview-gateway"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/warning/scan")
test "$status" = 200
/usr/bin/jq -e '.data.dryRun == true and .data.rulesRun == 12 and .data.persisted == false and .data.providerExecution == false and .data.queryExecution == false and .data.notificationsSent == 0 and .authorizing == false' "$TMP_DIR/scan-preview.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/resolve.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$COMMAND_KEY\",\"note\":\"gateway warning smoke\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/warning/$WARNING_GUID/resolve")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .warning.warningGuid == "'"$WARNING_GUID"'" and .warning.state == "resolved" and .warning.authorizing == false and .warning.cashEffect == false and .warning.providerExecution == false' "$TMP_DIR/resolve.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data "{\"idempotency_key\":\"$COMMAND_KEY\",\"note\":\"gateway warning smoke\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/warning/$WARNING_GUID/resolve")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .warning.state == "resolved"' "$TMP_DIR/replay.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/custom-preview.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{"idempotency_key":"warning-custom-preview-gateway","sqlTemplate":"SELECT 1"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/warning/custom-rules/preview")
test "$status" = 200
/usr/bin/jq -e '.success == true and .data.total == 0 and .data.queryExecution == false and .data.persisted == false and .authorizing == false and .source_kind == "warning_custom_rule_preview_candidate"' "$TMP_DIR/custom-preview.json" >/dev/null

echo "native MoonBit warning gateway/scan/resolve/custom-preview smoke passed"
