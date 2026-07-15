#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4200}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-milestone-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-milestone-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-milestone.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
CONTRACT_ID="CT-MS-SMOKE-$SMOKE_SUFFIX"
MILESTONE_ID="MS-MS-SMOKE-$SMOKE_SUFFIX"

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
"$ROOT/scripts/company_postgres_service.sh" \
  --port "$PORT" \
  --database "$DATABASE" \
  --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

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
/usr/bin/jq -e '.capabilities | index("contract_milestone_command") and index("source_contract_milestone_command")' "$TMP_DIR/health.json" >/dev/null

request() {
  name=$1
  method=$2
  path=$3
  expected=$4
  body=${5:-}
  key=${6:-}
  actor_signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
  if [ -n "$body" ]; then
    status=$(/usr/bin/curl -sS -o "$TMP_DIR/$name.json" -w '%{http_code}' \
      -X "$method" -H "Authorization: Bearer $TOKEN" \
      -H 'X-Forwarded-Proto: https' -H "X-Moonproj-Actor: $ACTOR" \
      -H "X-Moonproj-Actor-Signature: $actor_signature" \
      -H 'Content-Type: application/json' -H "Idempotency-Key: $key" \
      --data "$body" "http://127.0.0.1:$PORT$path")
  else
    status=$(/usr/bin/curl -sS -o "$TMP_DIR/$name.json" -w '%{http_code}' \
      -X "$method" -H "Authorization: Bearer $TOKEN" \
      -H 'X-Forwarded-Proto: https' \
      "http://127.0.0.1:$PORT$path")
  fi
  if [ "$status" != "$expected" ]; then
    /bin/cat "$TMP_DIR/$name.json"
    /bin/cat "$TMP_DIR/service.log"
    echo "unexpected status for $name: $status (expected $expected)" >&2
    exit 1
  fi
}

contract_body="{\"contractGuid\":\"$CONTRACT_ID\",\"contractCode\":\"C-MS-$SMOKE_SUFFIX\",\"contractName\":\"MoonBit milestone smoke\",\"buGuid\":\"bu-ms-smoke\",\"projGuid\":\"proj-0001\",\"providerGuid\":\"supplier-ms-smoke\",\"signDate\":\"2026-07-15\",\"htAmount\":1000.00,\"currency\":\"CNY\"}"
request contract POST /api/company/source/cost/contracts 201 "$contract_body" "milestone-contract-$SMOKE_SUFFIX"

milestone_body="{\"milestoneGuid\":\"$MILESTONE_ID\",\"nodeName\":\"Design approval\",\"triggerType\":\"event\",\"planPct\":25.5,\"notes\":\"native milestone\"}"
request create POST "/api/company/source/cost/contracts/$CONTRACT_ID/milestones" 201 "$milestone_body" "milestone-create-$SMOKE_SUFFIX"
/usr/bin/jq -e --arg id "$MILESTONE_ID" '.success == true and .idempotent_replay == false and .data.milestoneGuid == $id and (.milestone.created | length) == 1' "$TMP_DIR/create.json" >/dev/null

request replay POST "/api/company/source/cost/contracts/$CONTRACT_ID/milestones" 200 "$milestone_body" "milestone-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.idempotent_replay == true and (.milestone.created | length) == 1' "$TMP_DIR/replay.json" >/dev/null

request collision POST "/api/company/source/cost/contracts/$CONTRACT_ID/milestones" 409 \
  "{\"milestoneGuid\":\"$MILESTONE_ID\",\"nodeName\":\"different request\",\"triggerType\":\"event\"}" \
  "milestone-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.error | contains("already used")' "$TMP_DIR/collision.json" >/dev/null

request detail GET "/api/company/source/cost/contracts/$CONTRACT_ID" 200
/usr/bin/jq -e --arg id "$MILESTONE_ID" '.data.milestones[] | select(.milestoneGuid == $id) | (.sourceKind == "command" and .planPct == 25.5 and .state == "pending")' "$TMP_DIR/detail.json" >/dev/null

request update PUT "/api/company/source/cost/milestones/$MILESTONE_ID" 200 \
  '{"nodeName":"Design approval updated","planAmount":125.00}' \
  "milestone-update-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .milestone.state == "pending" and .milestone.revision == 2' "$TMP_DIR/update.json" >/dev/null

request trigger POST "/api/company/source/cost/milestones/$MILESTONE_ID/trigger-event" 200 \
  '{}' "milestone-trigger-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .milestone.state == "reached" and .milestone.revision == 3' "$TMP_DIR/trigger.json" >/dev/null

request delete DELETE "/api/company/source/cost/milestones/$MILESTONE_ID" 200 \
  '{"reason":"archive native milestone"}' "milestone-delete-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .milestone.state == "deleted" and .milestone.revision == 4' "$TMP_DIR/delete.json" >/dev/null

request detail_deleted GET "/api/company/source/cost/contracts/$CONTRACT_ID" 200
/usr/bin/jq -e --arg id "$MILESTONE_ID" '([.data.milestones[] | select(.milestoneGuid == $id)] | length) == 0' "$TMP_DIR/detail_deleted.json" >/dev/null

echo "native MoonBit contract milestone source-alias/lifecycle smoke passed"
