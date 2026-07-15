#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4199}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-dynamic-cost-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-dynamic-cost-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-dynamic-cost.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
COST_ID="COST-MB-SMOKE-$SMOKE_SUFFIX"
PROJECT_ID=${PROJECT_ID:-proj-0001}

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

create_body="{\"costGuid\":\"$COST_ID\",\"projGuid\":\"$PROJECT_ID\",\"costCode\":\"DC-$SMOKE_SUFFIX\",\"costName\":\"MoonBit dynamic cost smoke\",\"costLevel\":2,\"parentCostGuid\":\"\",\"isEndCost\":true,\"targetCost\":100.00,\"htAlterAmount\":10.50,\"ztCost\":20.00,\"dfsBudget\":3.25,\"ygAlter\":1.25,\"remarks\":\"native dynamic cost\"}"
request create POST /api/company/cost/dynamic-cost 201 "$create_body" "dynamic-cost-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .idempotent_replay == false and .data.costGuid == "'"$COST_ID"'" and .dynamic_cost.state == "active" and .dynamic_cost.revision == 1' "$TMP_DIR/create.json" >/dev/null

request replay POST /api/company/cost/dynamic-cost 200 "$create_body" "dynamic-cost-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.idempotent_replay == true and .dynamic_cost.state == "active" and .dynamic_cost.revision == 1' "$TMP_DIR/replay.json" >/dev/null

request read GET "/api/company/cost/dynamic-cost?projGuid=$PROJECT_ID" 200
/usr/bin/jq -e --arg cost_id "$COST_ID" '.data.items[] | select(.costGuid == $cost_id) | (.B_dtCost == 35 and .sourceKind == "command")' "$TMP_DIR/read.json" >/dev/null

request remarks GET "/api/company/source/cost/dynamic-cost/$COST_ID/remarks" 200
/usr/bin/jq -e --arg cost_code "DC-$SMOKE_SUFFIX" '.success == true and .data.costCode == $cost_code and .data.remarks == "native dynamic cost" and .source_kind == "command"' "$TMP_DIR/remarks.json" >/dev/null

request update PUT "/api/company/source/cost/dynamic-cost/$COST_ID" 200 \
  '{"costName":"Updated dynamic cost","dfsBudget":4.25,"remarks":"updated native dynamic cost"}' \
  "dynamic-cost-update-$SMOKE_SUFFIX"
/usr/bin/jq -e --arg cost_code "DC-$SMOKE_SUFFIX" '.success == true and .dynamic_cost.state == "active" and .dynamic_cost.revision == 2 and .dynamic_cost.cost_code == $cost_code' "$TMP_DIR/update.json" >/dev/null

request read_updated GET "/api/company/cost/dynamic-cost?projGuid=$PROJECT_ID" 200
/usr/bin/jq -e --arg cost_id "$COST_ID" '.data.items[] | select(.costGuid == $cost_id) | (.B_dtCost == 36 and .remarks == "updated native dynamic cost")' "$TMP_DIR/read_updated.json" >/dev/null

request imported GET "/api/company/cost/dynamic-cost?projGuid=$PROJECT_ID" 200
imported_id=$(/usr/bin/jq -r '.data.items[] | select(.sourceKind == "imported") | .costGuid' "$TMP_DIR/imported.json" | /usr/bin/head -n 1)
test -n "$imported_id"
request imported_guard PUT "/api/company/source/cost/dynamic-cost/$imported_id" 409 \
  '{"costName":"must remain read only"}' "dynamic-cost-imported-guard-$SMOKE_SUFFIX"
/usr/bin/jq -e '.error | contains("read-only")' "$TMP_DIR/imported_guard.json" >/dev/null

request void DELETE "/api/company/source/cost/dynamic-cost/$COST_ID" 200 \
  '{"reason":"archive native dynamic cost"}' "dynamic-cost-void-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .dynamic_cost.state == "deleted" and .dynamic_cost.revision == 3' "$TMP_DIR/void.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/deleted-remarks.json" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/source/cost/dynamic-cost/$COST_ID/remarks")
test "$status" = 404

echo "native MoonBit dynamic-cost source-alias/lifecycle smoke passed"
