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
