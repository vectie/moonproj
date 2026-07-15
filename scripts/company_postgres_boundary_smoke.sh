#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4264}
DATABASE=${DATABASE:-moonproj}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-boundary-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-boundary-smoke-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-boundary.XXXXXX")
SERVICE_PID=""

cleanup() {
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" \
PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
PSQL_BIN="$PSQL_BIN" \
"$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" \
  --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

ready=0
for _ in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" \
    -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" \
    >"$TMP_DIR/health.json" 2>/dev/null; then
    ready=1
    break
  fi
  /bin/sleep 1
done
test "$ready" = 1
/usr/bin/jq -e '.capabilities | index("import_batch_candidate") and index("sales_customer_delete_candidate")' "$TMP_DIR/health.json" >/dev/null

SIGNATURE=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/awk '{print $1}')

status=$(/usr/bin/curl -sS -o "$TMP_DIR/import.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Content-Type: application/json' -H 'Idempotency-Key: boundary-import' \
  --data '{"rows":[],"dryRun":true}' \
  "http://127.0.0.1:$PORT/api/company/import/project")
test "$status" = 409
/usr/bin/jq -e '.code == 46001 and .source_kind == "import_batch_candidate" and .persisted == false' "$TMP_DIR/import.json" >/dev/null

status=$(/usr/bin/curl -sS -o "$TMP_DIR/customer.json" -w '%{http_code}' -X DELETE \
  -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' \
  -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" \
  -H 'Idempotency-Key: boundary-customer-delete' \
  "http://127.0.0.1:$PORT/api/company/sales/customers/customer-boundary-1")
test "$status" = 409
/usr/bin/jq -e '.code == 48001 and .source_kind == "sales_customer_delete_candidate" and .data.deleted == false' "$TMP_DIR/customer.json" >/dev/null

/usr/bin/printf '%s\n' 'native PostgreSQL import/customer boundary smoke passed'
