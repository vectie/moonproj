#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4197}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-contract-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-contract-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-contract.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
CONTRACT_ID="CT-MB-SMOKE-$SMOKE_SUFFIX"

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
      -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT$path")
  fi
  if [ "$status" != "$expected" ]; then
    /bin/cat "$TMP_DIR/$name.json"
    /bin/cat "$TMP_DIR/service.log"
    echo "unexpected status for $name: $status (expected $expected)" >&2
    exit 1
  fi
}

create_body="{\"contractGuid\":\"$CONTRACT_ID\",\"contractCode\":\"C-$SMOKE_SUFFIX\",\"contractName\":\"MoonBit contract smoke\",\"buGuid\":\"bu-smoke\",\"buName\":\"Smoke BU\",\"projGuid\":\"proj-smoke\",\"projName\":\"Smoke project\",\"providerGuid\":\"supplier-smoke\",\"yfProviderName\":\"Smoke supplier\",\"signDate\":\"2026-07-15\",\"htAmount\":123.45,\"currency\":\"cny\",\"rCode\":\"R1\",\"l3Code\":\"L3-1\"}"
direct_contract_id="CT-DIRECT-$SMOKE_SUFFIX"
direct_body="{\"contract_id\":\"$direct_contract_id\",\"contract_code\":\"D-$SMOKE_SUFFIX\",\"contract_name\":\"direct MoonBit contract\",\"project_id\":\"proj-direct\",\"project_name\":\"Direct project\",\"supplier_id\":\"supplier-direct\",\"supplier_name\":\"Direct supplier\",\"sign_date\":\"2026-07-15\",\"amount_minor\":7777,\"currency\":\"CNY\"}"
request direct_create POST /api/company/contracts 201 "$direct_body" "contract-direct-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.idempotent_replay == false and .contract.contract_id == "'"$direct_contract_id"'" and .contract.state == "draft"' "$TMP_DIR/direct_create.json" >/dev/null
request direct_replay POST /api/company/contracts 200 "$direct_body" "contract-direct-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.idempotent_replay == true and .contract.state == "draft"' "$TMP_DIR/direct_replay.json" >/dev/null

request create POST /api/company/source/cost/contracts 201 "$create_body" "contract-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .idempotent_replay == false and .data.contractGuid == "'"$CONTRACT_ID"'" and .contract.state == "draft" and .contract.amount_minor == 12345' "$TMP_DIR/create.json" >/dev/null

request replay POST /api/company/source/cost/contracts 200 "$create_body" "contract-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.idempotent_replay == true and .contract.state == "draft"' "$TMP_DIR/replay.json" >/dev/null

request update PUT "/api/company/source/cost/contracts/$CONTRACT_ID" 200 \
  '{"contractName":"MoonBit contract smoke updated","htAmount":124.00}' \
  "contract-update-$SMOKE_SUFFIX"
/usr/bin/jq -e '.contract.state == "draft" and .contract.revision == 2 and .contract.amount_minor == 12400' "$TMP_DIR/update.json" >/dev/null

request submit POST "/api/company/contracts/$CONTRACT_ID/submit" 200 \
  '{"reason":"submit from native smoke"}' "contract-submit-$SMOKE_SUFFIX"
/usr/bin/jq -e '.contract.state == "submitted" and .contract.revision == 3' "$TMP_DIR/submit.json" >/dev/null

request reject POST "/api/company/contracts/$CONTRACT_ID/reject" 200 \
  '{"reason":"native smoke review"}' "contract-reject-$SMOKE_SUFFIX"
/usr/bin/jq -e '.contract.state == "rejected" and .contract.revision == 4' "$TMP_DIR/reject.json" >/dev/null

request resubmit POST "/api/company/contracts/$CONTRACT_ID/resubmit" 200 \
  '{}' "contract-resubmit-$SMOKE_SUFFIX"
/usr/bin/jq -e '.contract.state == "submitted" and .contract.revision == 5' "$TMP_DIR/resubmit.json" >/dev/null

request approve POST "/api/company/contracts/$CONTRACT_ID/approve" 200 \
  '{}' "contract-approve-$SMOKE_SUFFIX"
/usr/bin/jq -e '.contract.state == "approved" and .contract.revision == 6' "$TMP_DIR/approve.json" >/dev/null

request detail GET "/api/company/source/cost/contracts/$CONTRACT_ID" 200
/usr/bin/jq -e '.success == true and .data.contract.contractGuid == "'"$CONTRACT_ID"'" and .data.contract.state == "approved"' "$TMP_DIR/detail.json" >/dev/null

request imported GET /api/company/source/cost/contracts 200
imported_id=$(/usr/bin/jq -r '.data[] | select(.sourceKind == "imported") | .contractGuid' "$TMP_DIR/imported.json" | /usr/bin/head -n 1)
test -n "$imported_id"
request imported_guard PUT "/api/company/source/cost/contracts/$imported_id" 409 \
  '{"contractName":"must remain read only"}' "contract-imported-guard-$SMOKE_SUFFIX"
/usr/bin/jq -e '.error | contains("read-only")' "$TMP_DIR/imported_guard.json" >/dev/null

request void DELETE "/api/company/source/cost/contracts/$CONTRACT_ID" 200 \
  '{"reason":"archive native smoke contract"}' "contract-void-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .contract.state == "deleted" and .contract.revision == 7' "$TMP_DIR/void.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/deleted.json" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/source/cost/contracts/$CONTRACT_ID")
test "$status" = 404

echo "native MoonBit contract source-alias/lifecycle smoke passed"
