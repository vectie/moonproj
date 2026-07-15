#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4258}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-budget-smoke-token}
ACTOR=${MOONPROJ_ACTOR_ID:-admin}
SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-moonproj-budget-smoke-secret}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-budget.XXXXXX")
PID=""

psql() {
  PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:-520825} "$PSQL_BIN" "$@"
}

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql -v ON_ERROR_STOP=0 -c "DELETE FROM company_record WHERE source_id LIKE '%budget-smoke%'; DELETE FROM company_aggregate_projection WHERE aggregate_id LIKE '%budget-expense-smoke%' OR aggregate_id LIKE '%budget-expense-void-smoke%';" >/dev/null 2>&1 || true
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

psql -v ON_ERROR_STOP=1 -c "INSERT INTO company_record(record_type,record_id,schema_version,payload,source_id) VALUES ('legacy/raw/vcb_loan_simple','budget-smoke-loan',1,'{\"loan_guid\":\"budget-smoke-loan\",\"loan_code\":\"SMOKE-LOAN\",\"applied_by\":\"user-admin-0001\",\"apply_state\":\"Approved\",\"loan_amount\":80,\"balance_amount\":0,\"remain_amount\":80,\"apply_date\":\"2026-07-01\"}'::jsonb,'budget-smoke:loan')" >/dev/null

PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGDATABASE="$DATABASE" PGPASSWORD=${PGPASSWORD:-520825} PSQL_BIN="$PSQL_BIN" MOONPROJ_SERVICE_TOKEN="$TOKEN" MOONPROJ_ACTOR_SIGNING_SECRET="$SECRET" "$ROOT/scripts/company_postgres_service.sh" --port "$PORT" --database "$DATABASE" --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
PID=$!
for i in $(seq 1 30); do
  if /usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then break; fi
  /bin/sleep 1
done

SIGNATURE=$(/usr/bin/printf '%s' "$ACTOR" | /usr/bin/openssl dgst -sha256 -hmac "$SECRET" -hex | /usr/bin/sed 's/^.*= //')
curl_common() {
  /usr/bin/curl -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' -H "X-Moonproj-Actor: $ACTOR" -H "X-Moonproj-Actor-Signature: $SIGNATURE" -H 'Content-Type: application/json' "$@"
}

body='{"expenseGuid":"budget-expense-smoke","subject":"Native Office Expense","expenseAmount":100,"offsetAmount":10,"applyDeptGuid":"bu-tjgs-0001","applyDate":"2026-07-15","payUnit":"CNY","details":[{"summary":"Desk materials","amount":100,"occurDate":"2026-07-14"}],"splits":[{"userGuid":"user-admin-0001","deptGuid":"bu-tjgs-0001","costSubjectCode":"COST-001","amount":90}]}'
status=$(curl_common -sS -o "$TMP_DIR/create.json" -w '%{http_code}' -X POST -H 'Idempotency-Key: budget-smoke-create' --data "$body" "http://127.0.0.1:$PORT/api/company/budget/expenses")
test "$status" = 201
/usr/bin/jq -e '.data.expenseGuid == "budget-expense-smoke" and .data.applyState == "Draft" and .expense_effect == true and .budget_consumption == false and .authorizing == false' "$TMP_DIR/create.json" >/dev/null

status=$(curl_common -sS -o "$TMP_DIR/replay.json" -w '%{http_code}' -X POST -H 'Idempotency-Key: budget-smoke-create' --data "$body" "http://127.0.0.1:$PORT/api/company/budget/expenses")
test "$status" = 200
/usr/bin/jq -e '.idempotent_replay == true and .data.expenseGuid == "budget-expense-smoke"' "$TMP_DIR/replay.json" >/dev/null

/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/budget/expenses?expenseGuid=budget-expense-smoke" | /usr/bin/jq -e '.command_projection == true and .data[0].sourceKind == "command" and .data[0].expenseAmount == 100' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/budget/expenses/budget-expense-smoke" | /usr/bin/jq -e '.command_projection == true and .data.details[0].summary == "Desk materials" and .data.splits[0].amount == 90' >/dev/null

curl_common -fsS -X POST -H 'Idempotency-Key: budget-smoke-auto-offset' --data '{}' "http://127.0.0.1:$PORT/api/company/budget/expenses/budget-expense-smoke/auto-offset" | /usr/bin/jq -e '.data.expenseGuid == "budget-expense-smoke" and .data.totalOffset == 80 and .data.payAmount == 20 and (.data.offsetPlan | length) == 1 and .data.offsetPlan[0].loanGuid == "budget-smoke-loan" and .loan_balance_effect == false and .budget_consumption == false' >/dev/null
curl_common -fsS -X POST -H 'Idempotency-Key: budget-smoke-auto-offset' --data '{}' "http://127.0.0.1:$PORT/api/company/budget/expenses/budget-expense-smoke/auto-offset" | /usr/bin/jq -e '.idempotent_replay == true and .data.totalOffset == 80' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/budget/expenses?expenseGuid=budget-expense-smoke" | /usr/bin/jq -e '.data[0].offsetAmount == 80 and .data[0].payAmount == 20' >/dev/null

curl_common -fsS -X PUT -H 'Idempotency-Key: budget-smoke-update' --data '{"subject":"Updated Office Expense","expenseAmount":110,"offsetAmount":20,"payUnit":"CNY"}' "http://127.0.0.1:$PORT/api/company/budget/expenses/budget-expense-smoke" | /usr/bin/jq -e '.data.expenseGuid == "budget-expense-smoke" and .data.applyState == "Draft" and .budget_consumption == false' >/dev/null
curl_common -fsS -X POST -H 'Idempotency-Key: budget-smoke-submit' --data '{}' "http://127.0.0.1:$PORT/api/company/budget/expenses/budget-expense-smoke/submit-for-approval" | /usr/bin/jq -e '.data.expenseGuid == "budget-expense-smoke" and .data.applyState == "Approving" and .workflow_synchronization == false' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/budget/expenses?expenseGuid=budget-expense-smoke" | /usr/bin/jq -e '.data[0].applyState == "Approving" and .data[0].subject == "Updated Office Expense"' >/dev/null
status=$(curl_common -sS -o "$TMP_DIR/workflow-gate.json" -w '%{http_code}' -X POST -H 'Idempotency-Key: budget-smoke-workflow-gate' --data '{}' "http://127.0.0.1:$PORT/api/company/budget/expenses/budget-expense-smoke/sync-from-workflow")
test "$status" = 409
/usr/bin/jq -e '.error == "workflow synchronization is gated until wf_process_instance source rows are available"' "$TMP_DIR/workflow-gate.json" >/dev/null

second='{"expenseGuid":"budget-expense-void-smoke","subject":"Voidable Expense","expenseAmount":10,"applyDeptGuid":"bu-tjgs-0001","applyDate":"2026-07-15","splits":[{"userGuid":"user-admin-0001","deptGuid":"bu-tjgs-0001","costSubjectCode":"COST-001","amount":10}]}'
curl_common -fsS -X POST -H 'Idempotency-Key: budget-smoke-second' --data "$second" "http://127.0.0.1:$PORT/api/company/budget/expenses" | /usr/bin/jq -e '.data.applyState == "Draft"' >/dev/null
curl_common -fsS -X DELETE -H 'Idempotency-Key: budget-smoke-void' "http://127.0.0.1:$PORT/api/company/budget/expenses/budget-expense-void-smoke" | /usr/bin/jq -e '.data.applyState == "Voided" and .expense_effect == true' >/dev/null
/usr/bin/curl -fsS -H "Authorization: Bearer $TOKEN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$PORT/api/company/budget/expenses" | /usr/bin/jq -e '([.data[] | select(.expenseGuid == "budget-expense-void-smoke")] | length) == 0 and ([.data[] | select(.expenseGuid == "budget-expense-smoke")] | length) == 1' >/dev/null

/usr/bin/printf '%s\n' 'native PostgreSQL budget expense command smoke passed'
