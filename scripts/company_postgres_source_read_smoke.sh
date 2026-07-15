#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4187}
DATABASE=${DATABASE:-moonproj}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-source-read-smoke-token}
PSQL_BIN=${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-source-read.XXXXXX")
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
  path=$2
  /usr/bin/curl -fsS \
    -H "Authorization: Bearer $TOKEN" \
    -H 'X-Forwarded-Proto: https' \
    "http://127.0.0.1:$PORT$path" >"$TMP_DIR/$name.json"
}

request contracts /api/company/source/cost/contracts
request detail /api/company/source/cost/contracts/ht-tj-001
request milestones /api/company/source/cost/contracts/ht-tj-001/milestones
request payments '/api/company/source/cost/payment-applies?view=all'
request keyword '/api/company/source/cost/contracts?keyword=%E5%B9%95%E5%A2%99'
request budget_users '/api/company/source/budget/users-in-bu?buGuid=bu-tjgs-0001'
request budget_loan '/api/company/source/budget/my-loan-balance?userCode=limingjin'
request workflow_mine '/api/company/source/workflow/tasks/mine?userId=user-lmj-0001'
request workflow_initiated '/api/company/source/workflow/tasks/initiated?userId=user-lmj-0001'
request workflow_history '/api/company/source/workflow/tasks/my-history?userId=user-lmj-0001'
request workflow_biz '/api/company/source/workflow/instances/by-biz?bizType=contract&bizDataGuid=ht-tj-001'

/usr/bin/jq -e '
  .success == true and
  (.data | map(select(.sourceKind == "imported")) | length) == 2 and
  .source_coverage.cb_contract == 2 and
  .authorizing == false
' "$TMP_DIR/contracts.json" >/dev/null
/usr/bin/jq -e '
  .success == true and
  .data.contract.contractGuid == "ht-tj-001" and
  .data.contract.paid_amount_display == "¥3,600,000.00" and
  (.data.plans | length) == 3 and
  (.data.applies | length) == 2
' "$TMP_DIR/detail.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.cb_contract_milestone == 0 and
  .authorizing == false
' "$TMP_DIR/milestones.json" >/dev/null
/usr/bin/jq -e '
  .success == true and
  (.data | map(select(.sourceKind == "imported")) | length) == 3 and
  .source_coverage.cb_htfk_apply == 3 and
  .authorizing == false
' "$TMP_DIR/payments.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 1 and
  .data[0].contractGuid == "ht-tj-002"
' "$TMP_DIR/keyword.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 4 and
  .source_coverage.sys_user == 5 and
  .scope_applied == true and .authorizing == false
' "$TMP_DIR/budget_users.json" >/dev/null
/usr/bin/jq -e '
  .success == true and .data.total == 3500 and
  (.data.loans | length) == 1 and
  .source_coverage.vcb_loan_simple == 1 and
  .scope_applied == true and .authorizing == false
' "$TMP_DIR/budget_loan.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.wf_process_instance == 0 and
  .source_coverage.wf_step_action == 0 and
  .scope_applied == true and .authorizing == false
' "$TMP_DIR/workflow_mine.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  ((.missing_or_empty_source_tables | index("wf_process_instance")) != null) and
  .scope_applied == true and .authorizing == false
' "$TMP_DIR/workflow_initiated.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .scope_applied == true and .authorizing == false
' "$TMP_DIR/workflow_history.json" >/dev/null
/usr/bin/jq -e '
  .success == true and .data == null and
  .source_coverage.wf_process_instance == 0 and .authorizing == false
' "$TMP_DIR/workflow_biz.json" >/dev/null

echo "native source contract/payment/budget/workflow read smoke passed"
