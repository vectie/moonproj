#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4248}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-loan-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-loan-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:?PGPASSWORD is required}
export PGHOST PGPORT PGUSER PGPASSWORD
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-loan.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)-$$
LOAN_ID="LOAN-MB-SMOKE-$SMOKE_SUFFIX"
LOAN_ID_2="LOAN-MB-VOID-$SMOKE_SUFFIX"

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
/usr/bin/jq -e '.capabilities | index("loan_read") and index("loan_command")' "$TMP_DIR/health.json" >/dev/null

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
      -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $signature" \
      "http://127.0.0.1:$PORT$path")
  fi
  if [ "$status_code" != "$expected" ]; then
    /bin/cat "$TMP_DIR/$name.json"
    /bin/cat "$TMP_DIR/service.log"
    echo "unexpected status for $name: $status_code (expected $expected)" >&2
    exit 1
  fi
}

request loans GET /api/company/loans 200
/usr/bin/jq -e '
  (.items | map(select(.loan_id == "loan-001")) | .[0]) as $loan |
  $loan.source_kind == "imported" and
  $loan.loan_amount == 5000 and
  $loan.remain_amount == 3500 and
  ($loan.offsets | length) == 1
' "$TMP_DIR/loans.json" >/dev/null
request loan_detail GET /api/company/loans/loan-001 200
/usr/bin/jq -e '.loan.loan_id == "loan-001" and (.offsets | length) == 1 and .loan.source_table == "vcb_loan_simple"' "$TMP_DIR/loan_detail.json" >/dev/null

loan_body="{\"loan_id\":\"$LOAN_ID\",\"loan_code\":\"JK-$SMOKE_SUFFIX\",\"subject\":\"native employee advance\",\"employee_id\":\"employee-loan-smoke\",\"principal_id\":\"principal-loan-smoke\",\"scope\":\"employee:employee-loan-smoke\",\"currency\":\"CNY\",\"amount_minor\":800000,\"apply_dept_guid\":\"bu-tjgs-0001\",\"apply_date\":\"2026-07-15\",\"pay_unit\":\"finance\",\"proj_guid\":\"proj-0001\",\"evidence_ids\":[\"smoke:loan:001\"],\"authority\":{\"active\":true,\"principal_id\":\"principal-loan-smoke\",\"actor_id\":\"$ACTOR\",\"capability\":\"advance:create\",\"scope\":\"employee:employee-loan-smoke\",\"max_amount_minor\":800000}}"
loan_key="loan-create-$SMOKE_SUFFIX"
request loan_create POST /api/company/loans 201 "$loan_body" "$loan_key"
/usr/bin/jq -e --arg id "$LOAN_ID" '.idempotent_replay == false and .loan.loan_id == $id and .loan.state == "Draft" and .loan.cash_effect == false' "$TMP_DIR/loan_create.json" >/dev/null
request loan_replay POST /api/company/loans 200 "$loan_body" "$loan_key"
/usr/bin/jq -e '.idempotent_replay == true' "$TMP_DIR/loan_replay.json" >/dev/null
request loan_submit POST "/api/company/loans/$LOAN_ID/submit-for-approval" 200 '{"reason":"native loan smoke submit"}' "loan-submit-$SMOKE_SUFFIX"
/usr/bin/jq -e '.loan.state == "Approving" and .idempotent_replay == false' "$TMP_DIR/loan_submit.json" >/dev/null
request loan_offset_before_approval POST "/api/company/loans/$LOAN_ID/offset" 409 '{}' "loan-offset-before-approval-$SMOKE_SUFFIX"
request loan_workflow_gate POST "/api/company/loans/$LOAN_ID/sync-from-workflow" 409 '{}' "loan-workflow-gate-$SMOKE_SUFFIX"

void_body="{\"loan_id\":\"$LOAN_ID_2\",\"loan_code\":\"JK-VOID-$SMOKE_SUFFIX\",\"subject\":\"native voidable advance\",\"employee_id\":\"employee-loan-smoke\",\"principal_id\":\"principal-loan-smoke\",\"scope\":\"employee:employee-loan-smoke\",\"currency\":\"CNY\",\"amount_minor\":100000,\"apply_dept_guid\":\"bu-tjgs-0001\",\"apply_date\":\"2026-07-15\",\"authority\":{\"active\":true,\"principal_id\":\"principal-loan-smoke\",\"actor_id\":\"$ACTOR\",\"capability\":\"advance:create\",\"scope\":\"employee:employee-loan-smoke\",\"max_amount_minor\":100000}}"
request loan_void_create POST /api/company/loans 201 "$void_body" "loan-void-create-$SMOKE_SUFFIX"
request loan_update PUT "/api/company/loans/$LOAN_ID_2" 200 '{"subject":"updated native voidable advance","pay_unit":"treasury","proj_guid":"proj-0001"}' "loan-update-$SMOKE_SUFFIX"
/usr/bin/jq -e '.loan.state == "Draft" and .loan.cash_effect == false' "$TMP_DIR/loan_update.json" >/dev/null
request loan_void DELETE "/api/company/loans/$LOAN_ID_2" 200 '{"reason":"native loan smoke void"}' "loan-void-$SMOKE_SUFFIX"
/usr/bin/jq -e '.loan.state == "Voided" and .loan.cash_effect == false' "$TMP_DIR/loan_void.json" >/dev/null
request loan_void_read GET "/api/company/loans/$LOAN_ID_2" 200
/usr/bin/jq -e --arg id "$LOAN_ID_2" '.loan.loan_id == $id and .loan.apply_state == "Voided"' "$TMP_DIR/loan_void_read.json" >/dev/null

echo "native MoonBit employee-loan read/command smoke passed"
