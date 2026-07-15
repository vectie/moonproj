#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4196}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-expense-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-limingjin}
ACTOR_SIGNING_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-expense-actor-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-expense.XXXXXX")
SERVICE_PID=""
SMOKE_SUFFIX=$(/bin/date +%s)
EXPENSE_ID="EXP-MB-SMOKE-$SMOKE_SUFFIX"

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
  actor_signature=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$ACTOR_SIGNING_SECRET" -hex | /usr/bin/awk '{print $1}')
  if [ -n "$body" ]; then
    status=$(/usr/bin/curl -sS -o "$TMP_DIR/$name.json" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'X-Forwarded-Proto: https' \
      -H "X-Moonproj-Actor: $ACTOR" \
      -H "X-Moonproj-Actor-Signature: $actor_signature" \
      -H 'Content-Type: application/json' \
      -H "Idempotency-Key: ${6:-}" \
      --data "$body" "http://127.0.0.1:$PORT$path")
  else
    status=$(/usr/bin/curl -sS -o "$TMP_DIR/$name.json" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: Bearer $TOKEN" \
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

request imported_expenses GET '/api/company/budget/expenses?userCode=limingjin' 200
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .authorizing == null and .source_coverage.vcb_expense == 0
' "$TMP_DIR/imported_expenses.json" >/dev/null

create_body="{\"expense_id\":\"$EXPENSE_ID\",\"employee_id\":\"$ACTOR\",\"summary\":\"MoonBit expense smoke\",\"amount_minor\":12345,\"currency\":\"CNY\",\"project_id\":\"proj-0001\",\"cost_subject\":\"travel\"}"
request create POST /api/company/expenses 201 "$create_body" "expense-create-$SMOKE_SUFFIX"
/usr/bin/jq -e \
  '.idempotent_replay == false and .expense.expense_id == "'"$EXPENSE_ID"'" and .expense.state == "draft" and .command.result.revision == 1' \
  "$TMP_DIR/create.json" >/dev/null

request replay POST /api/company/expenses 200 "$create_body" "expense-create-$SMOKE_SUFFIX"
/usr/bin/jq -e '.idempotent_replay == true and .expense.state == "draft"' "$TMP_DIR/replay.json" >/dev/null

request update PUT "/api/company/expenses/$EXPENSE_ID" 200 \
  '{"subject":"MoonBit expense smoke updated","amount_minor":12346}' \
  "expense-update-$SMOKE_SUFFIX"
/usr/bin/jq -e '.expense.state == "draft" and .expense.revision == 2' "$TMP_DIR/update.json" >/dev/null

request submit POST "/api/company/expenses/$EXPENSE_ID/submit-for-approval" 200 \
  '{"reason":"submit from native smoke"}' "expense-submit-$SMOKE_SUFFIX"
/usr/bin/jq -e '.expense.state == "submitted" and .expense.revision == 3' "$TMP_DIR/submit.json" >/dev/null

request reject POST "/api/company/expenses/$EXPENSE_ID/reject" 200 \
  '{"reason":"native smoke review"}' "expense-reject-$SMOKE_SUFFIX"
/usr/bin/jq -e '.expense.state == "rejected" and .expense.revision == 4' "$TMP_DIR/reject.json" >/dev/null

request resubmit POST "/api/company/expenses/$EXPENSE_ID/resubmit" 200 \
  '{}' "expense-resubmit-$SMOKE_SUFFIX"
/usr/bin/jq -e '.expense.state == "submitted" and .expense.revision == 5' "$TMP_DIR/resubmit.json" >/dev/null

request approve POST "/api/company/expenses/$EXPENSE_ID/approve" 200 \
  '{}' "expense-approve-$SMOKE_SUFFIX"
/usr/bin/jq -e '.expense.state == "approved" and .expense.revision == 6' "$TMP_DIR/approve.json" >/dev/null

request local_expense GET "/api/company/expenses/$EXPENSE_ID" 200
/usr/bin/jq -e \
  '.expense_id == "'"$EXPENSE_ID"'" and .payload.state == "approved" and .revision == 6 and .payload.amount_minor == 12346' \
  "$TMP_DIR/local_expense.json" >/dev/null

request budget_check POST /api/company/budget-check 200 \
  '{"splits":[{"costSubjectCode":"CB-101","amount":100}]}' ""
/usr/bin/jq -e \
  '.success == true and .calculation_only == true and .persisted == false and .data[0].matched == true and .data[0].willOver == false' \
  "$TMP_DIR/budget_check.json" >/dev/null

echo "native MoonBit expense read/command/budget smoke passed"
