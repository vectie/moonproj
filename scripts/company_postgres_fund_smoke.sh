#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4245}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-fund-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-fund-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-fund.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
PLAN_ID="FP-MB-SMOKE-$SMOKE_SUFFIX"
DISPATCH_ID="FD-MB-SMOKE-$SMOKE_SUFFIX"
PROJECT_ID="proj-0001"
PRINCIPAL="co-fund-smoke"
SCOPE="project:$PROJECT_ID"

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SIGNING_SECRET" \
PSQL_BIN="$PSQL_BIN" \
"$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" \
  --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

ready=0
i=0
while [ "$i" -lt 30 ]; do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" \
    -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >"$TMP_DIR/health.json" 2>/dev/null; then
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
/usr/bin/jq -e '.capabilities | index("fund_command") and index("fund_observation_read")' "$TMP_DIR/health.json" >/dev/null

request() {
  name=$1
  method=$2
  path=$3
  expected=$4
  body=${5:-}
  key=${6:-}
  signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
  if [ -n "$body" ]; then
    status_code=$(/usr/bin/curl -sS -o "$TMP_DIR/$name.json" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
      -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
      -H 'Content-Type: application/json' -H "Idempotency-Key: $key" \
      --data "$body" "http://127.0.0.1:$PORT$path")
  else
    status_code=$(/usr/bin/curl -sS -o "$TMP_DIR/$name.json" -w '%{http_code}' -X "$method" \
      -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
      "http://127.0.0.1:$PORT$path")
  fi
  if [ "$status_code" != "$expected" ]; then
    /bin/cat "$TMP_DIR/$name.json"
    /bin/cat "$TMP_DIR/service.log"
    echo "unexpected status for $name: $status_code (expected $expected)" >&2
    exit 1
  fi
}

plan_body="{\"plan_id\":\"$PLAN_ID\",\"plan_code\":\"FP-CODE-$SMOKE_SUFFIX\",\"project_id\":\"$PROJECT_ID\",\"plan_period\":\"2026-08\",\"direction\":\"out\",\"category\":\"construction\",\"r_code\":\"R0\",\"plan_amount_minor\":1200000,\"remark\":\"native fund smoke\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"fund:plan:create\",\"max_amount_minor\":1200000}}"
plan_key="fund-plan-create-$SMOKE_SUFFIX"
request plan_create POST /api/company/fund/plans 201 "$plan_body" "$plan_key"
/usr/bin/jq -e --arg id "$PLAN_ID" '.plan.plan_id == $id and .plan.state == "planned"' "$TMP_DIR/plan_create.json" >/dev/null
request plan_replay POST /api/company/fund/plans 200 "$plan_body" "$plan_key"
/usr/bin/jq -e '.idempotent_replay == true' "$TMP_DIR/plan_replay.json" >/dev/null

request plan_update PUT "/api/company/fund/plans/$PLAN_ID" 200 '{"remark":"native fund smoke updated"}' "fund-plan-update-$SMOKE_SUFFIX"
/usr/bin/jq -e '.plan.state == "updated"' "$TMP_DIR/plan_update.json" >/dev/null
request plans_read GET "/api/company/fund/plans?projGuid=$PROJECT_ID&direction=out" 200
/usr/bin/jq -e --arg id "$PLAN_ID" 'any(.data[]; .plan_guid == $id and .state == "updated" and .plan_amount == 12000 and .sourceKind == "command")' "$TMP_DIR/plans_read.json" >/dev/null
request gap_read GET "/api/company/fund/gap-analysis?projGuid=$PROJECT_ID" 200
/usr/bin/jq -e '(.data.series | length) >= 1 and .authorizing == false and .persisted == false' "$TMP_DIR/gap_read.json" >/dev/null

dispatch_body="{\"dispatch_id\":\"$DISPATCH_ID\",\"dispatch_code\":\"FD-CODE-$SMOKE_SUFFIX\",\"project_id\":\"$PROJECT_ID\",\"from_project_id\":\"proj-0002\",\"to_project_id\":\"$PROJECT_ID\",\"amount_minor\":500000,\"reason\":\"native dispatch smoke\",\"dispatch_date\":\"2026-08-01\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"fund:dispatch:create\",\"max_amount_minor\":500000}}"
dispatch_key="fund-dispatch-create-$SMOKE_SUFFIX"
request dispatch_create POST /api/company/fund/dispatches 201 "$dispatch_body" "$dispatch_key"
/usr/bin/jq -e --arg id "$DISPATCH_ID" '.dispatch.dispatch_id == $id and .dispatch.state == "pending"' "$TMP_DIR/dispatch_create.json" >/dev/null
approve_body="{\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"fund:dispatch:approve\",\"max_amount_minor\":500000}}"
request dispatch_approve POST "/api/company/fund/dispatches/$DISPATCH_ID/approve" 200 "$approve_body" "fund-dispatch-approve-$SMOKE_SUFFIX"
/usr/bin/jq -e '.dispatch.state == "approved" and .dispatch.cash_effect == false' "$TMP_DIR/dispatch_approve.json" >/dev/null
request dispatch_read GET /api/company/fund/dispatches 200
/usr/bin/jq -e --arg id "$DISPATCH_ID" 'any(.data[]; .dispatch_guid == $id and .state == "approved" and .sourceKind == "command")' "$TMP_DIR/dispatch_read.json" >/dev/null

request plan_delete POST "/api/company/fund/plans/$PLAN_ID/delete" 200 '{"reason":"native fund tombstone smoke"}' "fund-plan-delete-$SMOKE_SUFFIX"
/usr/bin/jq -e '.plan.state == "deleted" and .plan.cash_effect == false' "$TMP_DIR/plan_delete.json" >/dev/null
request plans_after GET "/api/company/fund/plans?projGuid=$PROJECT_ID" 200
/usr/bin/jq -e --arg id "$PLAN_ID" 'all(.data[]; .plan_guid != $id)' "$TMP_DIR/plans_after.json" >/dev/null

echo "native MoonBit fund plan/dispatch source/command lifecycle smoke passed"
