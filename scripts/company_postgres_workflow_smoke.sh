#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4224}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-workflow-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-workflow-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-workflow.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
START_KEY="workflow-start-$SMOKE_SUFFIX"
APPROVE_KEY="workflow-approve-$SMOKE_SUFFIX"
REJECT_START_KEY="workflow-reject-start-$SMOKE_SUFFIX"
REJECT_KEY="workflow-reject-$SMOKE_SUFFIX"
COSIGN_START_KEY="workflow-cosign-start-$SMOKE_SUFFIX"
COSIGN_KEY="workflow-cosign-$SMOKE_SUFFIX"
TRANSFER_KEY="workflow-transfer-$SMOKE_SUFFIX"
APPROVE_BIZ="WF-SMOKE-$SMOKE_SUFFIX"
REJECT_BIZ="WF-REJECT-$SMOKE_SUFFIX"
COSIGN_BIZ="WF-COSIGN-$SMOKE_SUFFIX"

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
    "$PSQL_BIN" -v ON_ERROR_STOP=0 -d "$DATABASE" -c \
    "DELETE FROM company_aggregate_projection WHERE aggregate_type IN ('workflow_instance', 'workflow_action') AND (aggregate_id LIKE 'wf-$START_KEY%' OR aggregate_id LIKE 'wf-$REJECT_START_KEY%' OR aggregate_id LIKE 'wf-$COSIGN_START_KEY%' OR aggregate_id LIKE 'wf-action-$START_KEY%' OR aggregate_id LIKE 'wf-action-$APPROVE_KEY%' OR aggregate_id LIKE 'wf-action-$REJECT_START_KEY%' OR aggregate_id LIKE 'wf-action-$REJECT_KEY%' OR aggregate_id LIKE 'wf-action-$COSIGN_START_KEY%' OR aggregate_id LIKE 'wf-action-$COSIGN_KEY%' OR aggregate_id LIKE 'wf-action-$TRANSFER_KEY%'); DELETE FROM company_record WHERE source_id LIKE 'moonproj:command:workflow-%$SMOKE_SUFFIX' OR source_id LIKE 'moonproj:audit:workflow:%$SMOKE_SUFFIX%';" \
    >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SIGNING_SECRET" \
PSQL_BIN="$PSQL_BIN" \
PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
"$ROOT/scripts/company_postgres_service.sh" \
  --port "$PORT" \
  --database "$DATABASE" \
  --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/sed 's/^.*= //')
ready=0
i=0
while [ "$i" -lt 30 ]; do
  if /usr/bin/curl -fsS \
    -H "Authorization: Bearer $TOKEN" \
    -H 'X-Forwarded-Proto: https' \
    "http://127.0.0.1:$PORT/api/health" >"$TMP_DIR/health.json" 2>/dev/null; then
    ready=1
    break
  fi
  i=$((i + 1))
  /bin/sleep 1
done
if [ "$ready" -ne 1 ]; then
  /bin/cat "$TMP_DIR/service.log"
  exit 1
fi

start_body="{\"processKey\":\"expense-approval\",\"bizType\":\"Expense\",\"bizDataGuid\":\"$APPROVE_BIZ\"}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/start.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $START_KEY" \
  --data "$start_body" \
  "http://127.0.0.1:$PORT/api/company/source/workflow/instances")
if [ "$status" != "201" ]; then
  /bin/cat "$TMP_DIR/start.json" "$TMP_DIR/service.log"
  exit 1
fi
/usr/bin/jq -e '.idempotent_replay == false and .workflow.status == "Running" and .workflow.authorizing == true and .workflow.workflow_effect == true and .workflow.provider_execution == false and .workflow.cash_effect == false' "$TMP_DIR/start.json" >/dev/null
INSTANCE_ID=$(/usr/bin/jq -r '.workflow.processInstanceGuid' "$TMP_DIR/start.json")

status=$(/usr/bin/curl -sS -o "$TMP_DIR/start-replay.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $START_KEY" \
  --data "$start_body" \
  "http://127.0.0.1:$PORT/api/company/workflow/instances")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .workflow.processInstanceGuid == "'$INSTANCE_ID'"' "$TMP_DIR/start-replay.json" >/dev/null

/usr/bin/curl -fsS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/source/workflow/tasks/mine?userCode=$ACTOR" >"$TMP_DIR/mine.json"
/usr/bin/jq -e '.command_projection == true and (.data | any(.[]; .processInstanceGuid == "'$INSTANCE_ID'"))' "$TMP_DIR/mine.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/approve.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $APPROVE_KEY" \
  --data '{"comment":"native workflow smoke approval"}' \
  "http://127.0.0.1:$PORT/api/company/source/workflow/instances/$INSTANCE_ID/approve")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == false and .workflow.status == "Completed" and .workflow.decision == "APPROVED" and .workflow.workflow_effect == true and .workflow.cash_effect == false' "$TMP_DIR/approve.json" >/dev/null

/usr/bin/curl -fsS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/source/workflow/instances/$INSTANCE_ID" >"$TMP_DIR/detail.json"
/usr/bin/jq -e '.data.instance.status == "Completed" and (.data.actions | any(.[]; .decision == "APPROVED")) and .command_projection_count >= 3' "$TMP_DIR/detail.json" >/dev/null

reject_start_body="{\"processKey\":\"expense-approval\",\"bizType\":\"Expense\",\"bizDataGuid\":\"$REJECT_BIZ\"}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/reject-start.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $REJECT_START_KEY" \
  --data "$reject_start_body" \
  "http://127.0.0.1:$PORT/api/company/source/workflow/instances")
test "$status" = 201
REJECT_INSTANCE_ID=$(/usr/bin/jq -r '.workflow.processInstanceGuid' "$TMP_DIR/reject-start.json")

status=$(/usr/bin/curl -sS -o "$TMP_DIR/reject.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $REJECT_KEY" \
  --data '{"comment":"native workflow smoke rejection","mode":"cancel"}' \
  "http://127.0.0.1:$PORT/api/company/workflow/instances/$REJECT_INSTANCE_ID/reject")
test "$status" = 200
/usr/bin/jq -e '.workflow.status == "Rejected" and .workflow.decision == "REJECTED" and .workflow.tax_effect == false' "$TMP_DIR/reject.json" >/dev/null

cosign_start_body="{\"processKey\":\"expense-approval\",\"bizType\":\"Expense\",\"bizDataGuid\":\"$COSIGN_BIZ\"}"
status=$(/usr/bin/curl -sS -o "$TMP_DIR/cosign-start.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $COSIGN_START_KEY" \
  --data "$cosign_start_body" \
  "http://127.0.0.1:$PORT/api/company/workflow/instances")
test "$status" = 201
COSIGN_INSTANCE_ID=$(/usr/bin/jq -r '.workflow.processInstanceGuid' "$TMP_DIR/cosign-start.json")

status=$(/usr/bin/curl -sS -o "$TMP_DIR/cosign.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $COSIGN_KEY" \
  --data '{"cosigners":["admin"]}' \
  "http://127.0.0.1:$PORT/api/company/source/workflow/instances/$COSIGN_INSTANCE_ID/cosigners")
test "$status" = 200
/usr/bin/jq -e '.workflow.status == "Running" and .workflow.decision == "COSIGNED" and .workflow.workflow_effect == true and .workflow.provider_execution == false' "$TMP_DIR/cosign.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/transfer.json" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" \
  -H "X-Moonproj-Actor-Signature: $signature" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $TRANSFER_KEY" \
  --data '{"toUserId":"admin"}' \
  "http://127.0.0.1:$PORT/api/company/workflow/instances/$COSIGN_INSTANCE_ID/transfer")
test "$status" = 200
/usr/bin/jq -e '.workflow.status == "Running" and .workflow.decision == "TRANSFERRED" and .workflow.workflow_effect == true and .workflow.provider_execution == false' "$TMP_DIR/transfer.json" >/dev/null

echo "native MoonBit workflow start/approve/reject/cosign/transfer/idempotency/readback smoke passed"
