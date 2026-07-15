#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4198}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-payment-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-payment-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-payment.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
CONTRACT_ID="CT-PAY-SMOKE-$SMOKE_SUFFIX"
PAYMENT_ID="PAY-PAY-SMOKE-$SMOKE_SUFFIX"

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

contract_body="{\"contractGuid\":\"$CONTRACT_ID\",\"contractCode\":\"C-PAY-$SMOKE_SUFFIX\",\"contractName\":\"payment smoke contract\",\"buGuid\":\"bu-payment\",\"projGuid\":\"proj-payment\",\"providerGuid\":\"supplier-payment\",\"signDate\":\"2026-07-15\",\"htAmount\":1000.00,\"rCode\":\"R1\",\"l3Code\":\"L3-PAY\"}"
request contract POST /api/company/source/cost/contracts 201 "$contract_body" "payment-contract-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .contract.state == "draft"' "$TMP_DIR/contract.json" >/dev/null

payment_body="{\"htfkApplyGuid\":\"$PAYMENT_ID\",\"applyCode\":\"PA-$SMOKE_SUFFIX\",\"contractGuid\":\"$CONTRACT_ID\",\"subject\":\"payment smoke application\",\"applyAmount\":123.45,\"applyTypeCode\":\"WORK_PROGRESS\",\"currency\":\"CNY\",\"applyDate\":\"2026-07-15\"}"
request create POST /api/company/source/cost/payment-applies 201 "$payment_body" "payment-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .idempotent_replay == false and .data.htfkApplyGuid == "'"$PAYMENT_ID"'" and .payment_application.state == "submitted"' "$TMP_DIR/create.json" >/dev/null

request replay POST /api/company/source/cost/payment-applies 200 "$payment_body" "payment-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.idempotent_replay == true and .payment_application.state == "submitted"' "$TMP_DIR/replay.json" >/dev/null

request update PUT "/api/company/source/cost/payment-applies/$PAYMENT_ID" 200 \
  '{"subject":"updated payment smoke application","applyAmount":125.00}' \
  "payment-update-$SMOKE_SUFFIX"
/usr/bin/jq -e '.payment_application.state == "submitted" and .payment_application.revision == 3' "$TMP_DIR/update.json" >/dev/null

request reject POST "/api/company/payment-applies/$PAYMENT_ID/reject" 200 \
  '{"reason":"payment smoke review"}' "payment-reject-$SMOKE_SUFFIX"
/usr/bin/jq -e '.payment_application.state == "rejected" and .payment_application.revision == 4' "$TMP_DIR/reject.json" >/dev/null

request resubmit POST "/api/company/payment-applies/$PAYMENT_ID/resubmit" 200 \
  '{}' "payment-resubmit-$SMOKE_SUFFIX"
/usr/bin/jq -e '.payment_application.state == "submitted" and .payment_application.revision == 5' "$TMP_DIR/resubmit.json" >/dev/null

request approve POST "/api/company/payment-applies/$PAYMENT_ID/approve" 200 \
  '{}' "payment-approve-$SMOKE_SUFFIX"
/usr/bin/jq -e '.payment_application.state == "approved" and .payment_application.revision == 6' "$TMP_DIR/approve.json" >/dev/null

request imported GET /api/company/source/cost/payment-applies 200
imported_id=$(/usr/bin/jq -r '.data[] | select(.sourceKind == "imported") | .htfkApplyGuid' "$TMP_DIR/imported.json" | /usr/bin/head -n 1)
test -n "$imported_id"
request imported_guard PUT "/api/company/source/cost/payment-applies/$imported_id" 409 \
  '{"subject":"must remain read only"}' "payment-imported-guard-$SMOKE_SUFFIX"
/usr/bin/jq -e '.error | contains("read-only")' "$TMP_DIR/imported_guard.json" >/dev/null

request void DELETE "/api/company/source/cost/payment-applies/$PAYMENT_ID" 200 \
  '{"reason":"archive payment smoke application"}' "payment-void-$SMOKE_SUFFIX"
/usr/bin/jq -e '.success == true and .payment_application.state == "voided" and .payment_application.revision == 7' "$TMP_DIR/void.json" >/dev/null

echo "native MoonBit payment application source-alias/lifecycle smoke passed"
