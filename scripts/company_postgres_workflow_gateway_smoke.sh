#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE_PORT=${SERVICE_PORT:-4308}
GATEWAY_PORT=${GATEWAY_PORT:-4309}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-workflow-gateway-smoke-token}
ACTOR_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-workflow-gateway-secret}
USER_CODE=${MOONPROJ_DEV_USER:-workflow-gateway-user}
PASSWORD=${MOONPROJ_DEV_PASSWORD:-workflow-gateway-password}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
export PGHOST PGPORT PGUSER PGPASSWORD PSQL_BIN

TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-workflow-gateway.XXXXXX")
SERVICE_PID=""
GATEWAY_PID=""
SUFFIX=$(/bin/date +%s)
START_KEY="workflow-gateway-start-$SUFFIX"
APPROVE_KEY="workflow-gateway-approve-$SUFFIX"
INSTANCE_ID="wf-$START_KEY"

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
    "DELETE FROM company_aggregate_projection WHERE aggregate_id IN ('$INSTANCE_ID', 'wf-action-$START_KEY', 'wf-action-$APPROVE_KEY'); DELETE FROM company_record WHERE source_id LIKE '%$SUFFIX%';" \
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
MOONPROJ_SESSION_SECRET="workflow-gateway-session" \
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

start_body="{\"processKey\":\"expense-approval\",\"bizType\":\"Expense\",\"bizDataGuid\":\"WF-GW-$SUFFIX\"}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/start.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $START_KEY" --data "$start_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/workflow/instances")
test "$status" = 201
/usr/bin/jq -e --arg id "$INSTANCE_ID" \
  '.idempotent_replay == false and .workflow.processInstanceGuid == $id and .workflow.status == "Running" and .workflow.authorizing == true and .workflow.provider_execution == false and .workflow.cash_effect == false' \
  "$TMP_DIR/start.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/start-replay.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $START_KEY" --data "$start_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/workflow/instances")
test "$status" = 200
/usr/bin/jq -e --arg id "$INSTANCE_ID" \
  '.idempotent_replay == true and .workflow.processInstanceGuid == $id' "$TMP_DIR/start-replay.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/approve.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $APPROVE_KEY" --data '{"comment":"gateway workflow approval"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/workflow/instances/$INSTANCE_ID/approve")
test "$status" = 200
/usr/bin/jq -e --arg id "$INSTANCE_ID" \
  '.idempotent_replay == false and .workflow.processInstanceGuid == $id and .workflow.status == "Completed" and .workflow.decision == "APPROVED" and .workflow.workflow_effect == true and .workflow.provider_execution == false and .workflow.cash_effect == false' \
  "$TMP_DIR/approve.json" >/dev/null

echo "native MoonBit workflow gateway/start/replay/approve smoke passed"
