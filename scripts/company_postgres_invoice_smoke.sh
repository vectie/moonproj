#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4241}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-invoice-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-invoice-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-invoice.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
PRINCIPAL="co-invoice-smoke"
SCOPE="project:proj-0001"
IN_KEY="invoice-in-create-$SMOKE_SUFFIX"
IN_ID="INV-IN-$IN_KEY"
OUT_ID="INV-OUT-SMOKE-$SMOKE_SUFFIX"

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
/usr/bin/jq -e '.capabilities | index("invoice_command") and index("source_invoice_command")' "$TMP_DIR/health.json" >/dev/null

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

in_body="{\"invoiceNo\":\"INV-IN-SMOKE-$SMOKE_SUFFIX\",\"projGuid\":\"proj-0001\",\"contractGuid\":\"ht-tj-001\",\"providerName\":\"invoice provider smoke\",\"invoiceDate\":\"2026-07-14\",\"totalAmount\":\"123.45\",\"taxRate\":\"0.13\",\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"invoice:in:create\",\"max_amount_minor\":20000}}"
request incoming POST /api/company/source/invoice/in 201 "$in_body" "$IN_KEY"
/usr/bin/jq -e --arg id "$IN_ID" '.invoice.invoiceGuid == $id and .invoice.state == "received" and .idempotent_replay == false' "$TMP_DIR/incoming.json" >/dev/null

request incoming_replay POST /api/company/source/invoice/in 200 "$in_body" "$IN_KEY"
/usr/bin/jq -e '.idempotent_replay == true and .invoice.state == "received"' "$TMP_DIR/incoming_replay.json" >/dev/null

request collision POST /api/company/source/invoice/in 409 \
  "{\"invoiceNo\":\"different\",\"totalAmount\":\"1.00\",\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"invoice:in:create\",\"max_amount_minor\":20000}}" "$IN_KEY"
/usr/bin/jq -e '.error | contains("already used")' "$TMP_DIR/collision.json" >/dev/null

out_body="{\"invoiceGuid\":\"$OUT_ID\",\"invoiceNo\":\"INV-OUT-SMOKE-$SMOKE_SUFFIX\",\"projGuid\":\"proj-0001\",\"customerName\":\"invoice customer smoke\",\"invoiceDate\":\"2026-07-14\",\"totalAmount\":\"200.00\",\"taxRate\":\"0.06\",\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"invoice:out:create\",\"max_amount_minor\":30000}}"
request outgoing POST /api/company/source/invoice/out 201 "$out_body" "invoice-out-create-$SMOKE_SUFFIX"
/usr/bin/jq -e --arg id "$OUT_ID" '.invoice.invoiceGuid == $id and .invoice.state == "issued"' "$TMP_DIR/outgoing.json" >/dev/null

request read_in GET '/api/company/source/invoice/in?projGuid=proj-0001' 200
/usr/bin/jq -e --arg id "$IN_ID" 'any(.data[]; .invoiceGuid == $id and .sourceKind == "command" and .totalAmount == 123.45)' "$TMP_DIR/read_in.json" >/dev/null
request read_out GET '/api/company/source/invoice/out?projGuid=proj-0001' 200
/usr/bin/jq -e --arg id "$OUT_ID" 'any(.data[]; .invoiceGuid == $id and .sourceKind == "command" and .totalAmount == 200)' "$TMP_DIR/read_out.json" >/dev/null
request tax GET '/api/company/source/invoice/tax-ledger?projGuid=proj-0001' 200
/usr/bin/jq -e 'any(.data.rows[]; .period == "2026-07" and .totalIn >= 123.45 and .totalOut >= 200)' "$TMP_DIR/tax.json" >/dev/null

delete_in_body="{\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"invoice:in:delete\",\"max_amount_minor\":0}}"
request delete_in DELETE "/api/company/source/invoice/in/$IN_ID" 200 "$delete_in_body" "invoice-in-delete-$SMOKE_SUFFIX"
/usr/bin/jq -e '.invoice.state == "deleted"' "$TMP_DIR/delete_in.json" >/dev/null
delete_out_body="{\"principal_id\":\"$PRINCIPAL\",\"scope\":\"$SCOPE\",\"authority\":{\"active\":true,\"principal_id\":\"$PRINCIPAL\",\"actor_id\":\"$ACTOR\",\"scope\":\"$SCOPE\",\"capability\":\"invoice:out:delete\",\"max_amount_minor\":0}}"
request delete_out DELETE "/api/company/source/invoice/out/$OUT_ID" 200 "$delete_out_body" "invoice-out-delete-$SMOKE_SUFFIX"
/usr/bin/jq -e '.invoice.state == "deleted"' "$TMP_DIR/delete_out.json" >/dev/null

request read_after GET '/api/company/source/invoice/in?projGuid=proj-0001' 200
/usr/bin/jq -e --arg id "$IN_ID" 'all(.data[]; .invoiceGuid != $id)' "$TMP_DIR/read_after.json" >/dev/null

echo "native MoonBit invoice in/out authority/replay/tax/tombstone smoke passed"
