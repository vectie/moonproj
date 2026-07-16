#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVICE_PORT=${SERVICE_PORT:-4194}
GATEWAY_PORT=${GATEWAY_PORT:-4193}
TRUSTED_GATEWAY_PORT=${TRUSTED_GATEWAY_PORT:-4195}
TOKEN=${MOONPROJ_SERVICE_TOKEN:-moonproj-gateway-smoke-token}
ACTOR_SECRET=${MOONPROJ_ACTOR_SIGNING_SECRET:-gateway-smoke-actor-secret}
TMP_DIR=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/moonproj-gateway.XXXXXX")
SERVICE_PID=""
GATEWAY_PID=""
TRUSTED_GATEWAY_PID=""

cleanup() {
  if [ -n "$TRUSTED_GATEWAY_PID" ]; then
    kill "$TRUSTED_GATEWAY_PID" 2>/dev/null || true
    wait "$TRUSTED_GATEWAY_PID" 2>/dev/null || true
  fi
  if [ -n "$GATEWAY_PID" ]; then
    kill "$GATEWAY_PID" 2>/dev/null || true
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
  if [ -n "$SERVICE_PID" ]; then
    kill "$SERVICE_PID" 2>/dev/null || true
    wait "$SERVICE_PID" 2>/dev/null || true
  fi
  /bin/rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
PGHOST="${PGHOST:-/tmp}" \
PGPORT="${PGPORT:-5432}" \
PGUSER="${PGUSER:-moonproj}" \
PGPASSWORD="${PGPASSWORD:-520825}" \
PSQL_BIN="${PSQL_BIN:-/Library/PostgreSQL/18/bin/psql}" \
"$ROOT/scripts/company_postgres_service.sh" \
  --port "$SERVICE_PORT" \
  --database "${DATABASE:-moonproj}" \
  --require-forwarded-tls >"$TMP_DIR/service.log" 2>&1 &
SERVICE_PID=$!

MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
MOONPROJ_SESSION_SECRET="gateway-smoke-session-secret" \
MOONPROJ_DEV_USER="gateway-smoke-user" \
MOONPROJ_DEV_PASSWORD="gateway-smoke-password" \
"$ROOT/scripts/company_postgres_gateway.sh" \
  --port "$GATEWAY_PORT" \
  --service-port "$SERVICE_PORT" >"$TMP_DIR/gateway.log" 2>&1 &
GATEWAY_PID=$!

ready=0
i=0
while [ "$i" -lt 30 ]; do
  if /usr/bin/curl --max-time 2 -sS \
    "http://127.0.0.1:$GATEWAY_PORT/api/session" >"$TMP_DIR/session-ready.json" 2>/dev/null; then
    ready=1
    break
  fi
  i=$((i + 1))
  /bin/sleep 1
done
if [ "$ready" -ne 1 ]; then
  /bin/cat "$TMP_DIR/service.log"
  /bin/cat "$TMP_DIR/gateway.log"
  exit 1
fi

/usr/bin/curl --max-time 5 -sS \
  -H 'Content-Type: application/json' \
  -d '{"user_code":"gateway-smoke-user","password":"gateway-smoke-password"}' \
  -c "$TMP_DIR/cookies.txt" \
  "http://127.0.0.1:$GATEWAY_PORT/api/session/login" >"$TMP_DIR/login.json"
/usr/bin/jq -e '.authenticated == true and .identity_source == "development_fixture"' \
  "$TMP_DIR/login.json" >/dev/null

/usr/bin/curl --max-time 5 -sS -b "$TMP_DIR/cookies.txt" \
  "http://127.0.0.1:$GATEWAY_PORT/api/session" >"$TMP_DIR/session.json"
/usr/bin/jq -e '.authenticated == true and .actor_id == "rabbita-user"' \
  "$TMP_DIR/session.json" >/dev/null

gateway_customer_suffix=$(/bin/date +%s)
gateway_customer_id="CUS-GW-SMOKE-$gateway_customer_suffix"
gateway_customer_body="{\"customerGuid\":\"$gateway_customer_id\",\"customerCode\":\"$gateway_customer_id\",\"customerName\":\"gateway customer smoke\",\"phone\":\"13800000000\",\"projGuid\":\"proj-0001\"}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/customer-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-customer-create-$gateway_customer_suffix" \
  --data "$gateway_customer_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/customers")
test "$status" = 200
/usr/bin/jq -e --arg id "$gateway_customer_id" \
  '.success == true and .customer.customerGuid == $id and .persisted == true and .idempotent_replay == false' \
  "$TMP_DIR/customer-create.json" >/dev/null
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/customer-delete.json" -w '%{http_code}' \
  -X DELETE -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-customer-delete-$gateway_customer_suffix" \
  --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/customers/$gateway_customer_id")
test "$status" = 200
/usr/bin/jq -e '.success == true and .customer.state == "deleted" and .cash_effect == false' \
  "$TMP_DIR/customer-delete.json" >/dev/null

gateway_subscription_suffix=$(/bin/date +%s)
gateway_subscription_id="SUB-GW-SMOKE-$gateway_subscription_suffix"
gateway_subscription_body="{\"subGuid\":\"$gateway_subscription_id\",\"subCode\":\"$gateway_subscription_id\",\"customerGuid\":\"CUS-GW-SUB-$gateway_subscription_suffix\",\"projGuid\":\"proj-0001\",\"buildingNo\":\"2\",\"unitNo\":\"1802\",\"area\":128.6,\"unitPrice\":18600,\"totalPrice\":2391960,\"subAmount\":60000}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/subscription-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-subscription-create-$gateway_subscription_suffix" \
  --data "$gateway_subscription_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/subscriptions")
test "$status" = 200
/usr/bin/jq -e --arg id "$gateway_subscription_id" \
  '.success == true and .subscription.subGuid == $id and .subscription.state == "subscribed" and .persisted == true' \
  "$TMP_DIR/subscription-create.json" >/dev/null

gateway_mortgage_suffix=$(/bin/date +%s)
gateway_mortgage_id="MTG-GW-SMOKE-$gateway_mortgage_suffix"
gateway_mortgage_body="{\"mortgageGuid\":\"$gateway_mortgage_id\",\"mortgageCode\":\"$gateway_mortgage_id\",\"scontractGuid\":\"SCT-GW-SMOKE-$gateway_mortgage_suffix\",\"customerGuid\":\"CUS-GW-SUB-$gateway_mortgage_suffix\",\"bankName\":\"gateway bank\",\"loanAmount\":1000000,\"loanYears\":30,\"rate\":0.0345,\"applyDate\":\"2026-07-16\"}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/mortgage-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-mortgage-create-$gateway_mortgage_suffix" \
  --data "$gateway_mortgage_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/mortgages")
test "$status" = 200
/usr/bin/jq -e --arg id "$gateway_mortgage_id" \
  '.success == true and .mortgage.mortgageGuid == $id and .mortgage.state == "applying" and .persisted == true' \
  "$TMP_DIR/mortgage-create.json" >/dev/null
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/mortgage-approve.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-mortgage-approve-$gateway_mortgage_suffix" \
  --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/mortgages/$gateway_mortgage_id/approve")
test "$status" = 200
/usr/bin/jq -e '.success == true and .mortgage.state == "approved"' "$TMP_DIR/mortgage-approve.json" >/dev/null
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/mortgage-release.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-mortgage-release-$gateway_mortgage_suffix" \
  --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/mortgages/$gateway_mortgage_id/release")
test "$status" = 200
/usr/bin/jq -e '.success == true and .mortgage.state == "released" and .mortgage.revenue_pending == true' "$TMP_DIR/mortgage-release.json" >/dev/null

gateway_refund_suffix=$(/bin/date +%s)
gateway_refund_id="RF-GW-SMOKE-$gateway_refund_suffix"
gateway_refund_body="{\"refundGuid\":\"$gateway_refund_id\",\"refundCode\":\"$gateway_refund_id\",\"scontractGuid\":\"SCT-GW-SMOKE-$gateway_refund_suffix\",\"customerGuid\":\"CUS-GW-SUB-$gateway_refund_suffix\",\"reason\":\"gateway refund smoke\",\"refundAmount\":12.5,\"refundDate\":\"2026-07-16\"}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/refund-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-refund-create-$gateway_refund_suffix" \
  --data "$gateway_refund_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/refunds")
test "$status" = 200
/usr/bin/jq -e --arg id "$gateway_refund_id" \
  '.success == true and .refund.refundGuid == $id and .refund.state == "applying" and .provider_execution == false and .cash_effect == false' \
  "$TMP_DIR/refund-create.json" >/dev/null
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/refund-approve.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-refund-approve-$gateway_refund_suffix" \
  --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/refunds/$gateway_refund_id/approve")
test "$status" = 200
/usr/bin/jq -e \
  '.success == true and .refund.state == "approved" and .refund.contract_pending == true and .refund.revenue_pending == true and .refund.contract_updated == false and .refund.revenue_updated == false' \
  "$TMP_DIR/refund-approve.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/ai-hub-explain.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{"title":"gateway AI Hub smoke","focus":"source rows","table":[{"id":"one"}]}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/ai-hub/explain")
test "$status" = 200
/usr/bin/jq -e \
  '.success == true and .data.provider == "native-deterministic" and .data.rowCount == 1 and .provider_execution == false and .persisted == false and .authorizing == false' \
  "$TMP_DIR/ai-hub-explain.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/cashflow-explain.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{"series":[{"month":"2026-08","net":-1200000}],"gapWeeks":[{"week":"2026-W33","gap":1200000}]}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/cashflow/ai-explain")
test "$status" = 200
/usr/bin/jq -e \
  '.success == true and .data.provider == "native-deterministic" and .data.seriesCount == 1 and .data.gapWeekCount == 1 and .data.totalGap == 1200000 and .provider_execution == false and .persisted == false and .authorizing == false' \
  "$TMP_DIR/cashflow-explain.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/investment-explain.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/projects/proj-0001/ai-explain")
test "$status" = 200
/usr/bin/jq -e \
  '.success == true and .data.provider == "native-deterministic" and .data.revenue == 18500 and .data.netProfit == 2890 and .provider_execution == false and .persisted == false and .authorizing == false' \
  "$TMP_DIR/investment-explain.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/investment-subject-mappings.json" -w '%{http_code}' \
  -X PUT -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{"idempotency_key":"gateway-investment-subject-mappings-smoke","dryRun":true,"items":[{"group":"revenue","subjectCode":"INV-REVENUE","subjectName":"项目销售收入"}]}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/projects/proj-0001/subject-mappings")
test "$status" = 200
/usr/bin/jq -e \
  '.success == true and .data.dryRun == true and .data.wouldUpdate == 1 and .persisted == false and .provider_execution == false and .authorizing == false' \
  "$TMP_DIR/investment-subject-mappings.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/investment-plan-line-update.json" -w '%{http_code}' \
  -X PUT -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{"idempotency_key":"gateway-investment-plan-line-update-smoke","dryRun":true,"subject":"项目销售收入","status":"adjusted"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/plan-lines/PLAN-RABBITA-LOCAL")
test "$status" = 404
/usr/bin/jq -e \
  '.code == 43001 and .persisted == false' \
  "$TMP_DIR/investment-plan-line-update.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/investment-index-upsert.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{"idempotency_key":"gateway-investment-index-upsert-smoke","dryRun":true,"force":false}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/excel-imports/IMPORT-RABBITA-LOCAL/index-upsert")
test "$status" = 404
/usr/bin/jq -e \
  '.code == 43001 and .persisted == false and .provider_execution == false and .authorizing == false' \
  "$TMP_DIR/investment-index-upsert.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/investment-plan-line-import.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{"idempotency_key":"gateway-investment-plan-line-import-smoke","dryRun":true,"replaceExisting":false}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/investment/excel-imports/IMPORT-RABBITA-LOCAL/plan-lines/import")
test "$status" = 404
/usr/bin/jq -e \
  '.code == 43001 and .persisted == false and .provider_execution == false and .authorizing == false' \
  "$TMP_DIR/investment-plan-line-import.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/plan-ai-suggest.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  --data '{"projType":"住宅","scale":"中型","region":"全国","beginDate":"2026-08-01"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/plan/ai-suggest-plan")
test "$status" = 200
/usr/bin/jq -e \
  '.success == true and (.data.nodes | length) == 7 and .data.nodes[0].planEndDate == "2026-08-01" and .data.nodes[6].planEndDate == "2027-08-01" and .data.providerExecution == false and .data.persisted == false and .data.authorizing == false' \
  "$TMP_DIR/plan-ai-suggest.json" >/dev/null

/usr/bin/curl --max-time 5 -sS -b "$TMP_DIR/cookies.txt" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/summary" >"$TMP_DIR/summary.json"
/usr/bin/jq -e '.product == "moonproj-company" and .target == "postgresql" and .read_only == true' \
  "$TMP_DIR/summary.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/no_session.json" -w '%{http_code}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/summary")
test "$status" = 401
/usr/bin/jq -e '.authenticated == false and .error == "session required"' \
  "$TMP_DIR/no_session.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/not_allowed.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/summary")
test "$status" = 404

gateway_expense_suffix=$(/bin/date +%s)
gateway_expense_id="EXP-GW-SMOKE-$gateway_expense_suffix"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/expense-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-expense-create-$gateway_expense_suffix" \
  --data "{\"expense_id\":\"$gateway_expense_id\",\"employee_id\":\"rabbita-user\",\"summary\":\"gateway smoke expense\",\"amount_minor\":3210,\"currency\":\"CNY\"}" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/expenses")
test "$status" = 201
/usr/bin/jq -e \
  '.idempotent_replay == false and .expense.expense_id == "'"$gateway_expense_id"'" and .expense.state == "draft"' \
  "$TMP_DIR/expense-create.json" >/dev/null

gateway_contract_suffix=$(/bin/date +%s)
gateway_contract_id="CT-GW-SMOKE-$gateway_contract_suffix"
gateway_contract_body="{\"contractGuid\":\"$gateway_contract_id\",\"contractCode\":\"C-GW-$gateway_contract_suffix\",\"contractName\":\"gateway smoke contract\",\"buGuid\":\"bu-gateway\",\"projGuid\":\"proj-gateway\",\"providerGuid\":\"supplier-gateway\",\"signDate\":\"2026-07-15\",\"htAmount\":88.80,\"rCode\":\"R1\",\"l3Code\":\"L3-GW\"}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/contract-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-contract-create-$gateway_contract_suffix" \
  --data "$gateway_contract_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/cost/contracts")
test "$status" = 201
/usr/bin/jq -e \
  '.success == true and .idempotent_replay == false and .data.contractGuid == "'"$gateway_contract_id"'" and .contract.state == "draft"' \
  "$TMP_DIR/contract-create.json" >/dev/null

gateway_milestone_suffix=$(/bin/date +%s)
gateway_milestone_id="MS-GW-SMOKE-$gateway_milestone_suffix"
gateway_milestone_body="{\"milestoneGuid\":\"$gateway_milestone_id\",\"nodeName\":\"gateway design approval\",\"triggerType\":\"event\",\"planPct\":10.00}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/milestone-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-milestone-create-$gateway_milestone_suffix" \
  --data "$gateway_milestone_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/cost/contracts/$gateway_contract_id/milestones")
test "$status" = 201
/usr/bin/jq -e \
  '.success == true and .idempotent_replay == false and .data.milestoneGuid == "'"$gateway_milestone_id"'" and .milestone.state == "pending"' \
  "$TMP_DIR/milestone-create.json" >/dev/null

gateway_supplier_suffix=$(/bin/date +%s)
gateway_supplier_id="SUP-GW-SMOKE-$gateway_supplier_suffix"
gateway_supplier_body="{\"providerGuid\":\"$gateway_supplier_id\",\"providerCode\":\"SUP-GW-$gateway_supplier_suffix\",\"providerName\":\"gateway smoke supplier\",\"mainCategoryCode\":\"CAT-GW\"}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/supplier-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-supplier-create-$gateway_supplier_suffix" \
  --data "$gateway_supplier_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/srm/providers")
test "$status" = 201
/usr/bin/jq -e \
  '.success == true and .idempotent_replay == false and .data.providerGuid == "'"$gateway_supplier_id"'" and .provider.sourceKind == "command"' \
  "$TMP_DIR/supplier-create.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/supplier-rescore.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-supplier-rescore-$gateway_supplier_suffix" \
  --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/srm/providers/rescore-all")
test "$status" = 200
/usr/bin/jq -e \
  '.success == true and .idempotent_replay == false and .data.updated >= 1 and .data.wouldUpdate >= 1 and .data.dryRun == false and .data.providerExecution == false and .persisted == true and .authorizing == false' \
  "$TMP_DIR/supplier-rescore.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/supplier-rescore-replay.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-supplier-rescore-$gateway_supplier_suffix" \
  --data '{}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/srm/providers/rescore-all")
test "$status" = 200
/usr/bin/jq -e \
  '.success == true and .idempotent_replay == true and .data.dryRun == false and .data.providerExecution == false' \
  "$TMP_DIR/supplier-rescore-replay.json" >/dev/null

gateway_invoice_suffix=$(/bin/date +%s)
gateway_invoice_id="INV-GW-SMOKE-$gateway_invoice_suffix"
gateway_invoice_principal="co-gateway-invoice-smoke"
gateway_invoice_scope="project:proj-0001"
gateway_invoice_body="{\"invoiceGuid\":\"$gateway_invoice_id\",\"invoiceNo\":\"INV-GW-SMOKE-$gateway_invoice_suffix\",\"projGuid\":\"proj-0001\",\"customerName\":\"gateway invoice smoke\",\"invoiceDate\":\"2026-07-15\",\"totalAmount\":\"5.00\",\"taxRate\":\"0.06\",\"principal_id\":\"$gateway_invoice_principal\",\"scope\":\"$gateway_invoice_scope\",\"authority\":{\"active\":true,\"principal_id\":\"$gateway_invoice_principal\",\"actor_id\":\"rabbita-user\",\"scope\":\"$gateway_invoice_scope\",\"capability\":\"invoice:out:create\",\"max_amount_minor\":500}}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/invoice-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-invoice-create-$gateway_invoice_suffix" \
  --data "$gateway_invoice_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/invoice/out")
test "$status" = 201
/usr/bin/jq -e \
  '.invoice.invoiceGuid == "'"$gateway_invoice_id"'" and .invoice.state == "issued" and .idempotent_replay == false' \
  "$TMP_DIR/invoice-create.json" >/dev/null
gateway_invoice_delete_body="{\"principal_id\":\"$gateway_invoice_principal\",\"scope\":\"$gateway_invoice_scope\",\"authority\":{\"active\":true,\"principal_id\":\"$gateway_invoice_principal\",\"actor_id\":\"rabbita-user\",\"scope\":\"$gateway_invoice_scope\",\"capability\":\"invoice:out:delete\",\"max_amount_minor\":0}}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/invoice-delete.json" -w '%{http_code}' \
  -X DELETE -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-invoice-delete-$gateway_invoice_suffix" \
  --data "$gateway_invoice_delete_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/invoice/out/$gateway_invoice_id")
test "$status" = 200
/usr/bin/jq -e '.invoice.state == "deleted"' "$TMP_DIR/invoice-delete.json" >/dev/null

gateway_sales_revenue_suffix=$(/bin/date +%s)
gateway_sales_revenue_id="REV-GW-SMOKE-$gateway_sales_revenue_suffix"
gateway_sales_revenue_principal="co-gateway-sales-revenue-smoke"
gateway_sales_revenue_scope="project:proj-0001"
gateway_sales_revenue_create_body="{\"revenue_id\":\"$gateway_sales_revenue_id\",\"revenue_code\":\"SR-GW-SMOKE-$gateway_sales_revenue_suffix\",\"proj_guid\":\"proj-0001\",\"customer_name\":\"gateway sales revenue smoke\",\"amount_minor\":123450,\"receive_date\":\"2026-07-15\",\"status\":\"expected\",\"principal_id\":\"$gateway_sales_revenue_principal\",\"scope\":\"$gateway_sales_revenue_scope\",\"authority\":{\"active\":true,\"principal_id\":\"$gateway_sales_revenue_principal\",\"actor_id\":\"rabbita-user\",\"scope\":\"$gateway_sales_revenue_scope\",\"capability\":\"sales:revenue:create\",\"max_amount_minor\":150000}}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/sales-revenue-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-sales-revenue-create-$gateway_sales_revenue_suffix" \
  --data "$gateway_sales_revenue_create_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/revenues")
test "$status" = 201
/usr/bin/jq -e --arg id "$gateway_sales_revenue_id" \
  '.revenue.aggregate_id == $id and .revenue.state == "expected" and .idempotent_replay == false' \
  "$TMP_DIR/sales-revenue-create.json" >/dev/null

gateway_sales_revenue_update_body="{\"customer_name\":\"gateway sales revenue smoke updated\",\"principal_id\":\"$gateway_sales_revenue_principal\",\"scope\":\"$gateway_sales_revenue_scope\",\"authority\":{\"active\":true,\"principal_id\":\"$gateway_sales_revenue_principal\",\"actor_id\":\"rabbita-user\",\"scope\":\"$gateway_sales_revenue_scope\",\"capability\":\"sales:revenue:update\",\"max_amount_minor\":0}}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/sales-revenue-update.json" -w '%{http_code}' \
  -X PUT -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-sales-revenue-update-$gateway_sales_revenue_suffix" \
  --data "$gateway_sales_revenue_update_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/revenues/$gateway_sales_revenue_id")
test "$status" = 200
/usr/bin/jq -e '.revenue.state == "expected"' "$TMP_DIR/sales-revenue-update.json" >/dev/null

gateway_sales_revenue_confirm_body="{\"principal_id\":\"$gateway_sales_revenue_principal\",\"scope\":\"$gateway_sales_revenue_scope\",\"authority\":{\"active\":true,\"principal_id\":\"$gateway_sales_revenue_principal\",\"actor_id\":\"rabbita-user\",\"scope\":\"$gateway_sales_revenue_scope\",\"capability\":\"sales:revenue:confirm_received\",\"max_amount_minor\":0}}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/sales-revenue-confirm.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-sales-revenue-confirm-$gateway_sales_revenue_suffix" \
  --data "$gateway_sales_revenue_confirm_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/revenues/$gateway_sales_revenue_id/confirm-received")
test "$status" = 200
/usr/bin/jq -e '.revenue.state == "received"' "$TMP_DIR/sales-revenue-confirm.json" >/dev/null

gateway_sales_revenue_delete_body="{\"principal_id\":\"$gateway_sales_revenue_principal\",\"scope\":\"$gateway_sales_revenue_scope\",\"authority\":{\"active\":true,\"principal_id\":\"$gateway_sales_revenue_principal\",\"actor_id\":\"rabbita-user\",\"scope\":\"$gateway_sales_revenue_scope\",\"capability\":\"sales:revenue:delete\",\"max_amount_minor\":0}}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/sales-revenue-delete.json" -w '%{http_code}' \
  -X DELETE -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-sales-revenue-delete-$gateway_sales_revenue_suffix" \
  --data "$gateway_sales_revenue_delete_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/sales/revenues/$gateway_sales_revenue_id")
test "$status" = 200
/usr/bin/jq -e '.revenue.state == "deleted"' "$TMP_DIR/sales-revenue-delete.json" >/dev/null

gateway_tender_suffix=$(/bin/date +%s)
gateway_tender_id="TD-GW-SMOKE-$gateway_tender_suffix"
gateway_tender_body="{\"tenderGuid\":\"$gateway_tender_id\",\"projGuid\":\"CD-HJL\",\"tenderName\":\"gateway tender smoke\",\"category\":\"construction\",\"estimatedAmount\":\"123.45\",\"planPublishDate\":\"2026-07-15\"}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/tender-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-tender-create-$gateway_tender_suffix" \
  --data "$gateway_tender_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/tender/tenders")
test "$status" = 201
/usr/bin/jq -e --arg id "$gateway_tender_id" \
  '.success == true and .data.tenderGuid == $id and .source_kind == "command"' \
  "$TMP_DIR/tender-create.json" >/dev/null

gateway_split_id="SPLIT-GW-SMOKE-$gateway_tender_suffix"
gateway_split_body="{\"splitGuid\":\"$gateway_split_id\",\"parentContractGuid\":\"ht-tj-001\",\"splitName\":\"gateway split smoke\",\"splitAmount\":\"12.34\",\"splitPct\":\"10.00\"}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/tender-split-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-tender-split-create-$gateway_tender_suffix" \
  --data "$gateway_split_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/tender/splits")
test "$status" = 201
/usr/bin/jq -e --arg id "$gateway_split_id" \
  '.success == true and .data.splitGuid == $id and .source_kind == "command"' \
  "$TMP_DIR/tender-split-create.json" >/dev/null

status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/tender-delete.json" -w '%{http_code}' \
  -X DELETE -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-tender-delete-$gateway_tender_suffix" \
  --data '{"reason":"gateway tender tombstone smoke"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/tender/tenders/$gateway_tender_id")
test "$status" = 200
/usr/bin/jq -e '.success == true and .tender.state == "deleted"' "$TMP_DIR/tender-delete.json" >/dev/null

gateway_marketing_suffix=$(/bin/date +%s)
gateway_marketing_id="CAMP-GW-SMOKE-$gateway_marketing_suffix"
gateway_marketing_principal="co-gateway-marketing-smoke"
gateway_marketing_scope="project:CD-HJL"
gateway_marketing_body="{\"campaignGuid\":\"$gateway_marketing_id\",\"projGuid\":\"CD-HJL\",\"name\":\"gateway marketing smoke\",\"budget\":\"12.34\",\"principal_id\":\"$gateway_marketing_principal\",\"scope\":\"$gateway_marketing_scope\",\"authority\":{\"active\":true,\"principal_id\":\"$gateway_marketing_principal\",\"actor_id\":\"rabbita-user\",\"scope\":\"$gateway_marketing_scope\",\"capability\":\"marketing:campaign:create\",\"max_amount_minor\":2000}}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/marketing-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-marketing-create-$gateway_marketing_suffix" \
  --data "$gateway_marketing_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/marketing/campaigns")
test "$status" = 201
/usr/bin/jq -e --arg id "$gateway_marketing_id" \
  '.campaign.aggregate_id == $id and .campaign.state == "planning" and .idempotent_replay == false' \
  "$TMP_DIR/marketing-create.json" >/dev/null
gateway_marketing_delete_body="{\"principal_id\":\"$gateway_marketing_principal\",\"scope\":\"$gateway_marketing_scope\",\"authority\":{\"active\":true,\"principal_id\":\"$gateway_marketing_principal\",\"actor_id\":\"rabbita-user\",\"scope\":\"$gateway_marketing_scope\",\"capability\":\"marketing:campaign:delete\",\"max_amount_minor\":0}}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/marketing-delete.json" -w '%{http_code}' \
  -X DELETE -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-marketing-delete-$gateway_marketing_suffix" \
  --data "$gateway_marketing_delete_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/marketing/campaigns/$gateway_marketing_id")
test "$status" = 200
/usr/bin/jq -e '.campaign.state == "deleted"' "$TMP_DIR/marketing-delete.json" >/dev/null

gateway_fund_suffix=$(/bin/date +%s)
gateway_fund_id="FP-GW-SMOKE-$gateway_fund_suffix"
gateway_fund_principal="co-gateway-fund-smoke"
gateway_fund_scope="project:proj-0001"
gateway_fund_body="{\"plan_id\":\"$gateway_fund_id\",\"plan_code\":\"FP-GW-$gateway_fund_suffix\",\"project_id\":\"proj-0001\",\"plan_period\":\"2026-08\",\"direction\":\"out\",\"plan_amount_minor\":300000,\"authority\":{\"active\":true,\"principal_id\":\"$gateway_fund_principal\",\"actor_id\":\"rabbita-user\",\"scope\":\"$gateway_fund_scope\",\"capability\":\"fund:plan:create\",\"max_amount_minor\":300000}}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/fund-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-fund-create-$gateway_fund_suffix" \
  --data "$gateway_fund_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/fund/plans")
test "$status" = 201
/usr/bin/jq -e --arg id "$gateway_fund_id" \
  '.plan.plan_id == $id and .plan.state == "planned" and .idempotent_replay == false' \
  "$TMP_DIR/fund-create.json" >/dev/null
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/fund-delete.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-fund-delete-$gateway_fund_suffix" \
  --data '{"reason":"gateway fund tombstone smoke"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/fund/plans/$gateway_fund_id/delete")
test "$status" = 200
/usr/bin/jq -e '.plan.state == "deleted" and .plan.cash_effect == false' "$TMP_DIR/fund-delete.json" >/dev/null

gateway_delivery_suffix=$(/bin/date +%s)
gateway_delivery_id="PR-GW-SMOKE-$gateway_delivery_suffix"
gateway_delivery_body="{\"progress_id\":\"$gateway_delivery_id\",\"project_id\":\"proj-0001\",\"principal_id\":\"co-gateway-delivery\",\"project_scope\":\"project:proj-0001\",\"stage\":\"主体结构\",\"plan_pct\":60,\"completed_value_minor\":100000,\"currency\":\"CNY\",\"evidence_ids\":[\"gateway:delivery:evidence-001\"]}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/delivery-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-delivery-create-$gateway_delivery_suffix" \
  --data "$gateway_delivery_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/delivery/progress")
test "$status" = 201
/usr/bin/jq -e --arg id "$gateway_delivery_id" \
  '.progress.aggregate_id == $id and .progress.state == "draft" and .idempotent_replay == false' \
  "$TMP_DIR/delivery-create.json" >/dev/null
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/delivery-delete.json" -w '%{http_code}' \
  -X DELETE -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-delivery-delete-$gateway_delivery_suffix" \
  --data '{"reason":"gateway delivery tombstone smoke"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/delivery/progress/$gateway_delivery_id")
test "$status" = 200
/usr/bin/jq -e '.progress.state == "deleted" and .progress.delivery_effect == false' "$TMP_DIR/delivery-delete.json" >/dev/null

gateway_payment_suffix=$(/bin/date +%s)
gateway_payment_id="PAY-GW-SMOKE-$gateway_payment_suffix"
gateway_payment_body="{\"htfkApplyGuid\":\"$gateway_payment_id\",\"applyCode\":\"PA-GW-$gateway_payment_suffix\",\"contractGuid\":\"$gateway_contract_id\",\"subject\":\"gateway smoke payment\",\"applyAmount\":12.34,\"applyDate\":\"2026-07-15\"}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/payment-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-payment-create-$gateway_payment_suffix" \
  --data "$gateway_payment_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/source/cost/payment-applies")
test "$status" = 201
/usr/bin/jq -e \
  '.success == true and .idempotent_replay == false and .data.htfkApplyGuid == "'"$gateway_payment_id"'" and .payment_application.state == "submitted"' \
  "$TMP_DIR/payment-create.json" >/dev/null

gateway_dynamic_cost_suffix=$(/bin/date +%s)
gateway_dynamic_cost_id="COST-GW-SMOKE-$gateway_dynamic_cost_suffix"
gateway_dynamic_cost_body="{\"costGuid\":\"$gateway_dynamic_cost_id\",\"projGuid\":\"proj-0001\",\"costCode\":\"DC-GW-$gateway_dynamic_cost_suffix\",\"costName\":\"gateway smoke dynamic cost\",\"targetCost\":50.00,\"htAlterAmount\":5.00,\"ztCost\":2.00,\"dfsBudget\":1.00,\"ygAlter\":0.50}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/dynamic-cost-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-dynamic-cost-create-$gateway_dynamic_cost_suffix" \
  --data "$gateway_dynamic_cost_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/cost/dynamic-cost")
test "$status" = 201
/usr/bin/jq -e \
  '.success == true and .idempotent_replay == false and .data.costGuid == "'"$gateway_dynamic_cost_id"'" and .dynamic_cost.state == "active"' \
  "$TMP_DIR/dynamic-cost-create.json" >/dev/null

gateway_plan_suffix=$(/bin/date +%s)
gateway_plan_id="PT-GW-SMOKE-$gateway_plan_suffix"
gateway_plan_body="{\"task_id\":\"$gateway_plan_id\",\"task_code\":\"PT-GW-$gateway_plan_suffix\",\"task_name\":\"gateway smoke project task\",\"project_id\":\"proj-0001\",\"task_type\":\"task\",\"plan_begin_date\":\"2026-08-01\",\"plan_end_date\":\"2026-08-15\",\"authority\":{\"active\":true,\"principal_id\":\"co-gateway-plan\",\"actor_id\":\"rabbita-user\",\"capability\":\"project:task:create\",\"scope\":\"project:proj-0001\"}}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/plan-task-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-plan-task-create-$gateway_plan_suffix" \
  --data "$gateway_plan_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/plan/tasks")
test "$status" = 201
/usr/bin/jq -e --arg id "$gateway_plan_id" \
  '.idempotent_replay == false and .task.taskGuid == $id and .task.state == "pending"' \
  "$TMP_DIR/plan-task-create.json" >/dev/null
gateway_plan_delete_body='{"reason":"gateway project task tombstone smoke","authority":{"active":true,"principal_id":"co-gateway-plan","actor_id":"rabbita-user","capability":"project:task:delete","scope":"project:proj-0001"}}'
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/plan-task-delete.json" -w '%{http_code}' \
  -X DELETE -b "$TMP_DIR/cookies.txt" \
  -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-plan-task-delete-$gateway_plan_suffix" \
  --data "$gateway_plan_delete_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/plan/tasks/$gateway_plan_id")
test "$status" = 200
/usr/bin/jq -e '.task.state == "deleted" and .task.cash_effect == false' \
  "$TMP_DIR/plan-task-delete.json" >/dev/null

gateway_loan_suffix=$(/bin/date +%s)
gateway_loan_id="LOAN-GW-SMOKE-$gateway_loan_suffix"
gateway_loan_principal="co-gateway-loan"
gateway_loan_scope="employee:employee-gateway-loan"
gateway_loan_body="{\"loan_id\":\"$gateway_loan_id\",\"loan_code\":\"JK-GW-$gateway_loan_suffix\",\"subject\":\"gateway employee advance\",\"employee_id\":\"employee-gateway-loan\",\"principal_id\":\"$gateway_loan_principal\",\"scope\":\"$gateway_loan_scope\",\"currency\":\"CNY\",\"amount_minor\":250000,\"apply_dept_guid\":\"bu-tjgs-0001\",\"apply_date\":\"2026-07-15\",\"authority\":{\"active\":true,\"principal_id\":\"$gateway_loan_principal\",\"actor_id\":\"rabbita-user\",\"capability\":\"advance:create\",\"scope\":\"$gateway_loan_scope\",\"max_amount_minor\":250000}}"
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/loan-create.json" -w '%{http_code}' \
  -X POST -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-loan-create-$gateway_loan_suffix" \
  --data "$gateway_loan_body" \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/loans")
test "$status" = 201
/usr/bin/jq -e --arg id "$gateway_loan_id" \
  '.loan.loan_id == $id and .loan.state == "Draft" and .idempotent_replay == false' \
  "$TMP_DIR/loan-create.json" >/dev/null
status=$(/usr/bin/curl --max-time 5 -sS -o "$TMP_DIR/loan-delete.json" -w '%{http_code}' \
  -X DELETE -b "$TMP_DIR/cookies.txt" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: gateway-loan-delete-$gateway_loan_suffix" \
  --data '{"reason":"gateway loan tombstone smoke"}' \
  "http://127.0.0.1:$GATEWAY_PORT/api/company/loans/$gateway_loan_id")
test "$status" = 200
/usr/bin/jq -e '.loan.state == "Voided" and .loan.cash_effect == false' "$TMP_DIR/loan-delete.json" >/dev/null

/usr/bin/curl --max-time 5 -sS -b "$TMP_DIR/cookies.txt" -c "$TMP_DIR/cookies.txt" \
  -X POST "http://127.0.0.1:$GATEWAY_PORT/api/session/logout" >"$TMP_DIR/logout.json"
/usr/bin/jq -e '.authenticated == false' "$TMP_DIR/logout.json" >/dev/null

IDENTITY_SECRET="gateway-smoke-identity-secret"
MOONPROJ_SERVICE_TOKEN="$TOKEN" \
MOONPROJ_ACTOR_SIGNING_SECRET="$ACTOR_SECRET" \
MOONPROJ_SESSION_SECRET="gateway-smoke-session-secret" \
MOONPROJ_UPSTREAM_IDENTITY_SECRET="$IDENTITY_SECRET" \
"$ROOT/scripts/company_postgres_gateway.sh" \
  --port "$TRUSTED_GATEWAY_PORT" \
  --service-port "$SERVICE_PORT" \
  --trusted-identity-secret-env MOONPROJ_UPSTREAM_IDENTITY_SECRET \
  >"$TMP_DIR/trusted-gateway.log" 2>&1 &
TRUSTED_GATEWAY_PID=$!

ready=0
i=0
while [ "$i" -lt 30 ]; do
  if /usr/bin/curl --max-time 2 -sS \
    "http://127.0.0.1:$TRUSTED_GATEWAY_PORT/api/session" >"$TMP_DIR/trusted-ready.json" 2>/dev/null; then
    ready=1
    break
  fi
  i=$((i + 1))
  /bin/sleep 1
done
if [ "$ready" -ne 1 ]; then
  /bin/cat "$TMP_DIR/trusted-gateway.log"
  exit 1
fi

timestamp=$(/bin/date +%s)
signature=$(
  /usr/bin/printf '%s:%s' limingjin "$timestamp" |
    /usr/bin/openssl dgst -sha256 -hmac "$IDENTITY_SECRET" -hex |
    /usr/bin/awk '{print $1}'
)
/usr/bin/curl --max-time 5 -sS -D "$TMP_DIR/trusted-headers.txt" \
  -X POST \
  -H "X-Moonproj-Identity: limingjin" \
  -H "X-Moonproj-Identity-Timestamp: $timestamp" \
  -H "X-Moonproj-Identity-Signature: $signature" \
  "http://127.0.0.1:$TRUSTED_GATEWAY_PORT/api/session/login" >"$TMP_DIR/trusted-login.json"
/usr/bin/jq -e '.authenticated == true and .actor_id == "limingjin" and .identity_source == "trusted_upstream"' \
  "$TMP_DIR/trusted-login.json" >/dev/null
/usr/bin/grep -qi 'set-cookie: moonproj_session=.*secure' "$TMP_DIR/trusted-headers.txt"

echo "native MoonBit gateway session/proxy/trusted-identity smoke passed"
