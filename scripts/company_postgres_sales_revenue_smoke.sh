#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4242}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-sales-revenue-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-sales-revenue-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-sales-revenue.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
REVENUE_ID="REV-SMOKE-$SMOKE_SUFFIX"
PRINCIPAL="co-sales-revenue-smoke"
SCOPE="project:proj-0001"

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
/usr/bin/jq -e '.capabilities | index("sales_revenue_command") and index("source_sales_revenue_command")' "$TMP_DIR/health.json" >/dev/null

request() {
  name=$1
  method=$2
  path=$3
  expected=$4
  body=${5:-}
  key=${6:-}
  signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
  if [ -n "$body" ]; then
    status=$(/usr/bin/curl -sS -o "$TMP_DIR/$name.json" -w '%{http_code}' \
      -X "$method" -H "Authorization: Bearer $TOKEN" \
      -H 'X-Forwarded-Proto: https' -H "X-Moonproj-Actor: $ACTOR" \
      -H "X-Moonproj-Actor-Signature: $signature" \
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

authority() {
  capability=$1
  max_amount=$2
  /usr/bin/printf '{"active":true,"principal_id":"%s","actor_id":"%s","scope":"%s","capability":"%s","max_amount_minor":%s}' \
    "$PRINCIPAL" "$ACTOR" "$SCOPE" "$capability" "$max_amount"
}

create_body="{\"revenue_id\":\"$REVENUE_ID\",\"revenue_code\":\"SR-SMOKE-$SMOKE_SUFFIX\",\"proj_guid\":\"proj-0001\",\"customer_name\":\"sales revenue smoke customer\",\"amount_minor\":456700,\"receive_date\":\"2026-07-14\",\"status\":\"expected\",\"payment_type\":\"bank\",\"contract_no\":\"SCT-SMOKE-$SMOKE_SUFFIX\",\"remark\":\"source-shaped revenue command smoke\",\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":$(authority sales:revenue:create 500000)}"
create_key="sales-revenue-create-$SMOKE_SUFFIX"
request create POST /api/company/sales/revenues 201 "$create_body" "$create_key"
/usr/bin/jq -e --arg id "$REVENUE_ID" '.revenue.aggregate_id == $id and .revenue.state == "expected" and .idempotent_replay == false' "$TMP_DIR/create.json" >/dev/null

request replay POST /api/company/sales/revenues 200 "$create_body" "$create_key"
/usr/bin/jq -e '.idempotent_replay == true and .revenue.state == "expected"' "$TMP_DIR/replay.json" >/dev/null

update_body="{\"customer_name\":\"sales revenue smoke customer updated\",\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":$(authority sales:revenue:update 0)}"
request update PUT "/api/company/sales/revenues/$REVENUE_ID" 200 "$update_body" "sales-revenue-update-$SMOKE_SUFFIX"
/usr/bin/jq -e '.revenue.state == "expected"' "$TMP_DIR/update.json" >/dev/null

confirm_body="{\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":$(authority sales:revenue:confirm_received 0)}"
request confirm POST "/api/company/sales/revenues/$REVENUE_ID/confirm-received" 200 "$confirm_body" "sales-revenue-confirm-$SMOKE_SUFFIX"
/usr/bin/jq -e '.revenue.state == "received"' "$TMP_DIR/confirm.json" >/dev/null

request read GET '/api/company/source/sales/revenues?projGuid=proj-0001' 200
/usr/bin/jq -e --arg id "$REVENUE_ID" 'any(.data[]; .revenue_guid == $id and .source_kind == "command" and .status == "received")' "$TMP_DIR/read.json" >/dev/null

delete_body="{\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":$(authority sales:revenue:delete 0)}"
request delete DELETE "/api/company/sales/revenues/$REVENUE_ID" 200 "$delete_body" "sales-revenue-delete-$SMOKE_SUFFIX"
/usr/bin/jq -e '.revenue.state == "deleted"' "$TMP_DIR/delete.json" >/dev/null

request read_after GET '/api/company/source/sales/revenues?projGuid=proj-0001' 200
/usr/bin/jq -e --arg id "$REVENUE_ID" 'all(.data[]; .revenue_guid != $id)' "$TMP_DIR/read_after.json" >/dev/null

echo "native MoonBit sales revenue authority/replay/update/confirm/tombstone smoke passed"
