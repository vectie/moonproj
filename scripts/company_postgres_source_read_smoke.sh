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
request dynamic '/api/company/cost/dynamic-cost?projGuid=proj-0001'
request dynamic_remarks '/api/company/source/cost/dynamic-cost/cost-001/remarks'
request delivery_progress '/api/company/source/delivery/progress?projGuid=proj-0001'
request delivery_outputs '/api/company/source/delivery/outputs?projGuid=proj-0001'
request receivables /api/company/receivables
/usr/bin/curl -sS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/receivables/does-not-exist" >"$TMP_DIR/receivable_missing.json"
request invoices /api/company/invoices
request invoice_in '/api/company/source/invoice/in'
request invoice_out '/api/company/source/invoice/out'
request invoice_tax '/api/company/source/invoice/tax-ledger'
request sales_customers '/api/company/source/sales/customers'
request sales_subscriptions '/api/company/source/sales/subscriptions'
request sales_contracts '/api/company/source/sales/contracts'
request sales_mortgages '/api/company/source/sales/mortgages'
request sales_refunds '/api/company/source/sales/refunds'
request sales_revenues '/api/company/source/sales/revenues'
request tender_plans '/api/company/source/tender/tenders'
request tender_awards '/api/company/source/tender/awards'
request tender_splits '/api/company/source/tender/splits'
request marketing_campaigns '/api/company/marketing/campaigns?projGuid=proj-0001'
request marketing_placements '/api/company/marketing/placements'
request marketing_channels '/api/company/marketing/channels'
request marketing_materials '/api/company/marketing/materials?projGuid=proj-0001'
request fund_plans '/api/company/fund/plans?projGuid=proj-0001'
request fund_gap '/api/company/fund/gap-analysis?projGuid=proj-0001'
request fund_dispatches '/api/company/fund/dispatches'
request supplier_categories '/api/company/source/srm/categories'
request supplier_eval '/api/company/source/srm/dict/eval-results'
request supplier_sources '/api/company/source/srm/dict/sources'
request supplier_providers '/api/company/srm/providers'
request supplier_provider_detail '/api/company/srm/providers/SUP-SOURCE-SMOKE-4f8d3f5b34'
/usr/bin/curl -sS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/srm/providers/SUP-SOURCE-SMOKE-4f8d3f5b34/risk" >"$TMP_DIR/supplier_provider_risk.json"
/usr/bin/curl -sS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/srm/providers/does-not-exist/risk" >"$TMP_DIR/supplier_provider_missing_risk.json"

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
/usr/bin/jq -e '
  .success == true and
  ((.data.items | map(select(.sourceKind == "imported")) | length) == 7) and
  ((.data.items | map(select(.sourceKind == "imported" and .isEndCost == true) | .A_targetCost) | add) == 35900000) and
  ((.data.items | map(select(.sourceKind == "imported" and .isEndCost == true) | .B_dtCost) | add) == 36350000) and
  ((.data.items | map(select(.sourceKind == "imported" and .isEndCost == true)) | length) == 6) and
  .source_coverage.cb_cost == 7 and .authorizing == false
' "$TMP_DIR/dynamic.json" >/dev/null
/usr/bin/jq -e '
  .success == true and .data.costCode == "CB-101" and
  .data.costName == "建安工程" and
  .source_coverage.cb_cost == 7 and
  .persisted == false and .authorizing == false
' "$TMP_DIR/dynamic_remarks.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.proj_progress == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/delivery_progress.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.proj_output == 0 and
  .source_coverage.cb_contract == 2 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/delivery_outputs.json" >/dev/null
/usr/bin/jq -e '
  (.items | length) == 84 and
  .items[0].aggregate_type == "receivable" and
  .items[0].amount_display == "¥10,000.00"
' "$TMP_DIR/receivables.json" >/dev/null
/usr/bin/jq -e '.error == "receivable not found"' "$TMP_DIR/receivable_missing.json" >/dev/null
/usr/bin/jq -e '(.items | length) == 0' "$TMP_DIR/invoices.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | map(select(.sourceKind == "imported")) | length) == 0 and
  .source_coverage.invoice_in == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/invoice_in.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | map(select(.sourceKind == "imported")) | length) == 0 and
  .source_coverage.invoice_out == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/invoice_out.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data.rows | length) == 0 and
  .source_coverage.invoice_in == 0 and
  .source_coverage.invoice_out == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/invoice_tax.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.sale_customer == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/sales_customers.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.sale_subscription == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/sales_subscriptions.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.sale_contract == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/sales_contracts.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.sale_mortgage == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/sales_mortgages.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.sale_refund == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/sales_refunds.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.sale_revenue == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/sales_revenues.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) >= 1 and
  .source_coverage.tender_plan == 0 and
  ((.data | map(select(.source_kind == "command")) | length) == (.data | length)) and
  .authorizing == false and .persisted == false
' "$TMP_DIR/tender_plans.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.tender_award == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/tender_awards.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) >= 1 and
  .source_coverage.contract_split == 0 and
  ((.data | map(select(.source_kind == "command")) | length) == (.data | length)) and
  .authorizing == false and .persisted == false
' "$TMP_DIR/tender_splits.json" >/dev/null
/usr/bin/jq -e '
  .success == true and
  .source_coverage.mkt_campaign == 0 and
  ((.data | map(select(.sourceKind == "command")) | length) == (.data | length)) and
  .authorizing == false and .persisted == false
' "$TMP_DIR/marketing_campaigns.json" >/dev/null
/usr/bin/jq -e '
  .success == true and
  .source_coverage.mkt_placement == 0 and
  ((.data | map(select(.sourceKind == "command")) | length) == (.data | length)) and
  .authorizing == false and .persisted == false
' "$TMP_DIR/marketing_placements.json" >/dev/null
/usr/bin/jq -e '
  .success == true and
  .source_coverage.mkt_channel == 0 and
  ((.data | map(select(.sourceKind == "command")) | length) == (.data | length)) and
  .authorizing == false and .persisted == false
' "$TMP_DIR/marketing_channels.json" >/dev/null
/usr/bin/jq -e '
  .success == true and
  .source_coverage.mkt_material == 0 and
  ((.data | map(select(.sourceKind == "command")) | length) == (.data | length)) and
  .authorizing == false and .persisted == false
' "$TMP_DIR/marketing_materials.json" >/dev/null
/usr/bin/jq -e '
  .success == true and
  .source_coverage.fund_plan == 0 and
  ((.data | map(select(.sourceKind != "command")) | length) == 0) and
  .authorizing == false and .persisted == false
' "$TMP_DIR/fund_plans.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data.series | type) == "array" and
  .source_coverage.fund_plan == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/fund_gap.json" >/dev/null
/usr/bin/jq -e '
  .success == true and
  .source_coverage.fund_dispatch == 0 and
  ((.data | map(select(.sourceKind != "command")) | length) == 0) and
  .authorizing == false and .persisted == false
' "$TMP_DIR/fund_dispatches.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 0 and
  .source_coverage.srm_category == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/supplier_categories.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 6 and
  .source_kind == "definition" and .authorizing == false
' "$TMP_DIR/supplier_eval.json" >/dev/null
/usr/bin/jq -e '
  .success == true and (.data | length) == 4 and
  .source_kind == "definition" and .authorizing == false
' "$TMP_DIR/supplier_sources.json" >/dev/null
/usr/bin/jq -e '
  .success == true and
  (.data | map(select(.providerGuid == "SUP-SOURCE-SMOKE-4f8d3f5b34" and .sourceKind == "command")) | length) == 1 and
  .source_coverage.srm_provider == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/supplier_providers.json" >/dev/null
/usr/bin/jq -e '
  .success == true and .data.provider.providerGuid == "SUP-SOURCE-SMOKE-4f8d3f5b34" and
  .data.provider.sourceKind == "command" and .authorizing == false
' "$TMP_DIR/supplier_provider_detail.json" >/dev/null
/usr/bin/jq -e '
  .success == false and .code == 43001 and .data == null and
  .source_kind == "imported_or_command" and
  .source_coverage.cb_contract == 2 and
  .source_coverage.srm_provider == 0 and
  (.missing_or_empty_source_tables | index("srm_provider")) != null and
  .provider_execution == false and .cash_effect == false and
  .accounting_effect == false and .tax_effect == false
' "$TMP_DIR/supplier_provider_missing_risk.json" >/dev/null
/usr/bin/jq -e '
  .success == false and .code == 43001 and .data == null and
  .source_kind == "imported_or_command" and
  .source_coverage.cb_contract == 2 and
  .source_coverage.srm_provider == 0 and
  (.missing_or_empty_source_tables | index("srm_provider")) != null and
  .provider_execution == false
' "$TMP_DIR/supplier_provider_risk.json" >/dev/null

echo "native source contract/payment/budget/workflow/dynamic-cost/delivery/receivable/invoice/sales/tender/marketing/fund/supplier read smoke passed"
