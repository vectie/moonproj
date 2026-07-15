#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PORT=${PORT:-4187}
DATABASE=${DATABASE:-moonproj}
PGHOST=${PGHOST:-/tmp}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-moonproj}
PGPASSWORD=${PGPASSWORD:-520825}
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
PGHOST="$PGHOST" PGPORT="$PGPORT" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
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

request_allow_error() {
  name=$1
  path=$2
  /usr/bin/curl -sS \
    -H "Authorization: Bearer $TOKEN" \
    -H 'X-Forwarded-Proto: https' \
    "http://127.0.0.1:$PORT$path" >"$TMP_DIR/$name.json" || true
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
request workflow_defs /api/company/workflow/process-defs
request workflow_preview /api/company/workflow/process-defs/expense-approval/preview
request dynamic '/api/company/cost/dynamic-cost?projGuid=proj-0001'
request dynamic_remarks '/api/company/source/cost/dynamic-cost/cost-001/remarks'
request delivery_progress '/api/company/source/delivery/progress?projGuid=proj-0001'
request delivery_outputs '/api/company/source/delivery/outputs?projGuid=proj-0001'
request delivery_overview '/api/company/delivery/overview?project_id=proj-0001'
request projects /api/company/projects
request project_tasks '/api/company/projects/proj-0001/tasks'
request project_detail /api/company/projects/proj-0001
request project_plan_summary /api/company/projects/proj-0001/plan-summary
request project_lifecycle /api/company/projects/proj-0001/lifecycle
request task_detail /api/company/tasks/task-003
request loans /api/company/loans
request loan_detail /api/company/loans/loan-001
request reports /api/company/reports/overview
request report_cost /api/company/reports/cost-summary
request report_ledger /api/company/reports/contract-payment-ledger
request report_supplier /api/company/reports/supplier-analysis
request report_approval /api/company/reports/approval-efficiency
request report_stage /api/company/reports/project-stage-matrix
request investment_versions /api/company/investment/projects/proj-0001/versions
request investment_indices /api/company/investment/versions/tzsy-ver-tjhjy-v1/indices
request investment_profit /api/company/investment/projects/proj-0001/profit-summary
request investment_sensitivity /api/company/investment/projects/proj-0001/sensitivity
request investment_cost_dashboard '/api/company/investment/projects/proj-0001/profit-actual-v2?planVersion=baseline'
request investment_imports /api/company/investment/projects/proj-0001/excel-imports
request investment_plan_lines '/api/company/investment/projects/proj-0001/plan-lines?keyword=cost'
request investment_subject_mappings /api/company/investment/projects/proj-0001/subject-mappings
/usr/bin/curl -sS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/investment/projects/proj-0001/profit-cockpit" >"$TMP_DIR/investment_profit_cockpit.json"
request_allow_error investment_import_detail '/api/company/investment/excel-imports/missing-import'
request_allow_error investment_bridge_plan '/api/company/investment/excel-imports/missing-import/bridge-plan'
request_allow_error investment_index_preview '/api/company/investment/excel-imports/missing-import/index-upsert-preview'
request_allow_error investment_profit_table '/api/company/investment/excel-imports/missing-import/profit-table'
request_allow_error investment_plan_preview '/api/company/investment/excel-imports/missing-import/plan-line-preview'
/usr/bin/curl -sS \
  -H "Authorization: Bearer $TOKEN" \
  -H 'X-Forwarded-Proto: https' \
  "http://127.0.0.1:$PORT/api/company/investment/projects/proj-0001/profit-actual" >"$TMP_DIR/investment_actual.json"
request investment_dimensions /api/company/investment/meta/dimensions
request cashflow_forecast '/api/company/cashflow/forecast?months=6&projGuid=proj-0001'
request cashflow_inflow '/api/company/cashflow/inflow?months=6&projGuid=proj-0001'
request cashflow_detail '/api/company/cashflow/forecast/detail?ym=2026-04&projGuid=proj-0001'
request cbs_dict '/api/company/cbs/dict?projGuid=proj-0001'
request cbs_versions '/api/company/cbs/versions?projGuid=proj-0001'
request cbs_r0 '/api/company/cbs/r0/queue?projGuid=proj-0001'
request_allow_error cbs_f_balance '/api/company/cbs/dict/f-balance?projGuid=proj-0001&l3Code=03.01.01'
request attachment_all /api/company/attachments/all
request attachment_list '/api/company/attachments/list?bizType=contract&bizGuid=ht-tj-001'
request attachment_stats /api/company/attachments/stats
request_allow_error attachment_missing /api/company/attachments/download/no-attachment
request ai_overview '/api/company/ai-stats/overview?period=month'
request ai_activity '/api/company/ai-stats/activity?limit=30'
request ai_badge '/api/company/ai-stats/badge?bizType=contract&bizGuid=HT-CD-260701'
request ai_hub_usage /api/company/ai-hub/usage-stats
request ai_hub_drafts '/api/company/ai-hub/drafts?userCode=admin'
request ai_hub_query '/api/company/ai-hub/query-log?userCode=admin'
request ai_hub_corrections '/api/company/ai-hub/corrections?limit=50'
request ai_hub_correction_stats /api/company/ai-hub/correction-stats
request_allow_error ai_hub_missing '/api/company/ai-hub/drafts/missing-draft?userCode=admin'
request webhook /api/company/webhook/config
request notify_messages '/api/company/notify/messages?userCode=admin&status=unread'
request notify_unread '/api/company/notify/messages/unread-count?userCode=admin'
request notify_subscriptions '/api/company/notify/subscriptions?userCode=admin'
request notify_config /api/company/notify/config
request notify_email /api/company/notify/email-outbox
request notify_preview /api/company/notify/digest/preview
request notify_log /api/company/notify/digest/log
request notify_llm /api/company/notify/llm-providers
request admin_ocr /api/company/admin/ocr/status
request admin_error '/api/company/admin/error-log?limit=100'
request admin_groups /api/company/admin/dict/groups
request admin_options '/api/company/admin/dict/options?groupName=cost_subject'
request admin_health '/api/company/admin/health/full'
request admin_quality /api/company/admin/quality/overview
request admin_llm /api/company/admin/llm/status
request admin_diag /api/company/admin/ai/diag
request_allow_error admin_backup /api/company/admin/backup/db
request rbac_users /api/company/rbac/users
request rbac_me '/api/company/rbac/me?userCode=admin'
request rbac_roles /api/company/rbac/roles
request rbac_catalog /api/company/rbac/permission-catalog
request report_templates /api/company/reports/templates
request warning_badge /api/company/warning/badge
request warning_list '/api/company/warning?status=all'
request warning_rules /api/company/warning/rules
request warning_scans /api/company/warning/scans
request warning_custom /api/company/warning/custom-rules
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
  (.items | length) == 2 and
  .source_coverage.wf_process_def == 2 and
  .source_coverage.wf_step_def == 12 and
  .source_coverage.wf_step_assignee == 6 and
  .instances_available == 0 and .actions_available == 0 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/workflow_defs.json" >/dev/null
/usr/bin/jq -e '
  .process_key == "expense-approval" and
  (.steps | length) == 7 and .instances_available == 0 and
  .actions_available == 0 and .authorizing == false
' "$TMP_DIR/workflow_preview.json" >/dev/null
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
  (.tasks | length) >= 1 and (.reports | length) >= 1 and
  .authorizing == false and .cash_effect == false and
  .accounting_effect == false and .tax_effect == false
' "$TMP_DIR/delivery_overview.json" >/dev/null
/usr/bin/jq -e '
  (.items | length) == 2 and
  (.items | map(select(.source_kind == "imported")) | length) == 2 and
  .command_projection == false and .authorizing == false
' "$TMP_DIR/projects.json" >/dev/null
/usr/bin/jq -e '
  (.items | map(select(.sourceKind == "imported")) | length) == 7 and
  .authorizing == false
' "$TMP_DIR/project_tasks.json" >/dev/null
/usr/bin/jq -e '
  .project_id == "proj-0001" and (.lifecycle | length) == 7 and
  .source_kind == "imported"
' "$TMP_DIR/project_detail.json" >/dev/null
/usr/bin/jq -e '
  .data.summary.total >= 1 and .authorizing == false and
  .source_kind == "imported_or_command"
' "$TMP_DIR/project_plan_summary.json" >/dev/null
/usr/bin/jq -e '
  (.data.stages | length) == 7 and .authorizing == false and
  .source_kind == "imported"
' "$TMP_DIR/project_lifecycle.json" >/dev/null
/usr/bin/jq -e '
  .data.task.taskGuid == "task-003" and (.data.reports | length) >= 1 and
  .authorizing == false
' "$TMP_DIR/task_detail.json" >/dev/null
/usr/bin/jq -e '
  (.items | map(select(.loan_id == "loan-001")) | .[0]) as $loan |
  $loan.loan_amount == 5000 and $loan.remain_amount == 3500 and
  ($loan.offsets | length) == 1 and $loan.source_kind == "imported"
' "$TMP_DIR/loans.json" >/dev/null
/usr/bin/jq -e '
  .loan.loan_id == "loan-001" and (.offsets | length) == 1 and
  .loan.source_kind == "imported"
' "$TMP_DIR/loan_detail.json" >/dev/null
/usr/bin/jq -e '
  (.cost_summary.rows | length) == 2 and
  (.contract_payment_ledger | length) == 2 and
  (.project_stage_matrix.projects | length) == 2 and
  .source_kind == "imported" and
  .source_coverage.cb_cost == 7 and
  .source_coverage.cb_contract == 2
' "$TMP_DIR/reports.json" >/dev/null
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

/usr/bin/jq -e '
  (.rows | length) == 2 and .source_kind == "imported" and
  .rows[0].dynamicCost == 36350000
' "$TMP_DIR/report_cost.json" >/dev/null
/usr/bin/jq -e '
  (. | length) == 2 and .[0].source_kind == "imported"
' "$TMP_DIR/report_ledger.json" >/dev/null
/usr/bin/jq -e '(. | length) == 0' "$TMP_DIR/report_supplier.json" >/dev/null
/usr/bin/jq -e '
  (.byType | length) == 0 and .source_kind == "imported"
' "$TMP_DIR/report_approval.json" >/dev/null
/usr/bin/jq -e '
  (.projects | length) == 2 and (.stages | length) == 7 and
  .source_kind == "imported"
' "$TMP_DIR/report_stage.json" >/dev/null
/usr/bin/jq -e '
  (.data | length) == 1 and .data[0].versionGuid == "tzsy-ver-tjhjy-v1" and
  .data[0].isCurrent == true and .authorizing == false
' "$TMP_DIR/investment_versions.json" >/dev/null
/usr/bin/jq -e '
  (.data | length) == 5 and ([.data[].items | length] | add) == 26 and
  .source_coverage.tzsy_plan_index == 26
' "$TMP_DIR/investment_indices.json" >/dev/null
/usr/bin/jq -e '
  .data.revenue == 18500 and .data.netProfit == 2890 and .data.irr == 14.8
' "$TMP_DIR/investment_profit.json" >/dev/null
/usr/bin/jq -e '
  (.data.cases | length) == 6 and .authorizing == false and .persisted == false
' "$TMP_DIR/investment_sensitivity.json" >/dev/null
/usr/bin/jq -e '
  .success == false and .code == 41002 and .simulation == false and
  .source_coverage.tzsy_excel_import == 0 and .authorizing == false
' "$TMP_DIR/investment_actual.json" >/dev/null
/usr/bin/jq -e '
  (.data | length) == 5 and .data[0].code == "key_point" and .authorizing == false
' "$TMP_DIR/investment_dimensions.json" >/dev/null
/usr/bin/jq -e '
  (.data.series | length) == 6 and .source_coverage.cb_htfkplan == 4 and
  .authorizing == false and .persisted == false
' "$TMP_DIR/cashflow_forecast.json" >/dev/null
/usr/bin/jq -e '
  (.data.series | length) == 9 and .data.totals.totalInflow == 0 and
  .source_coverage.sale_revenue == 0 and .authorizing == false
' "$TMP_DIR/cashflow_inflow.json" >/dev/null
/usr/bin/jq -e '
  .data.ym == "2026-04" and (.data.plans | length) == 1 and
  .source_coverage.cb_htfkplan == 4 and .authorizing == false
' "$TMP_DIR/cashflow_detail.json" >/dev/null
/usr/bin/jq -e '
  .data.planVersion == "baseline" and (.data.items | length) == 0 and
  .source_coverage.cb_subject_dict == 0 and .authorizing == false
' "$TMP_DIR/cbs_dict.json" >/dev/null
/usr/bin/jq -e '
  (.data | length) == 0 and .source_coverage.cb_plan_version == 0 and
  .authorizing == false
' "$TMP_DIR/cbs_versions.json" >/dev/null
/usr/bin/jq -e '
  (.data.items | length) == 2 and .source_coverage.cb_contract == 2 and
  .authorizing == false
' "$TMP_DIR/cbs_r0.json" >/dev/null
/usr/bin/jq -e '
  .success == false and .code == 43001 and .data == null and
  .source_coverage.cb_subject_dict == 0 and .authorizing == false
' "$TMP_DIR/cbs_f_balance.json" >/dev/null
/usr/bin/jq -e '
  .data.total == 0 and .data.rows == [] and .source_coverage.attachment == 0 and
  .source_coverage.sys_user == 5 and .downloadable == false and .binary_storage == "not_imported"
' "$TMP_DIR/attachment_all.json" >/dev/null
/usr/bin/jq -e '.data == [] and .source_coverage.attachment == 0 and .authorizing == false' "$TMP_DIR/attachment_list.json" >/dev/null
/usr/bin/jq -e '.data.total == {"count":0,"bytes":0} and .data.byBizType == [] and .data.byAiStatus == []' "$TMP_DIR/attachment_stats.json" >/dev/null
/usr/bin/jq -e '.success == false and .code == 43001 and .downloadable == false and .binary_storage == "not_imported"' "$TMP_DIR/attachment_missing.json" >/dev/null
/usr/bin/jq -e '.data.kpi.intakeTotal == 0 and .data.kpi.queryTotal == 0 and .source_coverage.ai_draft == 0 and .provider_execution == false' "$TMP_DIR/ai_overview.json" >/dev/null
/usr/bin/jq -e '.data == [] and .source_coverage.ai_draft == 0 and .provider_execution == false' "$TMP_DIR/ai_activity.json" >/dev/null
/usr/bin/jq -e '.data.byAi == false and .source_coverage.ai_draft == 0 and .authorizing == false' "$TMP_DIR/ai_badge.json" >/dev/null
/usr/bin/jq -e '.data.monthlyTotalCalls == 0 and .data.minutesSaved == 0 and .source_coverage.ai_query_turn == 0' "$TMP_DIR/ai_hub_usage.json" >/dev/null
/usr/bin/jq -e '.data == [] and .source_coverage.ai_draft == 0 and .persisted == false' "$TMP_DIR/ai_hub_drafts.json" >/dev/null
/usr/bin/jq -e '.data == [] and .source_coverage.ai_query_log == 0 and .query_execution == false' "$TMP_DIR/ai_hub_query.json" >/dev/null
/usr/bin/jq -e '.data == [] and .source_coverage.ai_correction_log == 0' "$TMP_DIR/ai_hub_corrections.json" >/dev/null
/usr/bin/jq -e '.data.byField == [] and .data.total == 0 and .source_coverage.ai_correction_log == 0' "$TMP_DIR/ai_hub_correction_stats.json" >/dev/null
/usr/bin/jq -e '.success == false and .code == 43001 and .data == null' "$TMP_DIR/ai_hub_missing.json" >/dev/null
/usr/bin/jq -e '(.data | keys) == ["dingtalk","feishu","wecom"] and .source_coverage.sys_param == 0 and .secret_values_redacted == true' "$TMP_DIR/webhook.json" >/dev/null
/usr/bin/jq -e '.data.total == 0 and .data.rows == [] and .source_coverage.sys_message == 0 and .source_coverage.sys_user == 5' "$TMP_DIR/notify_messages.json" >/dev/null
/usr/bin/jq -e '.data.count == 0 and .source_coverage.sys_message == 0' "$TMP_DIR/notify_unread.json" >/dev/null
/usr/bin/jq -e '.data == [] and .source_coverage.sys_warning_subscription == 0' "$TMP_DIR/notify_subscriptions.json" >/dev/null
/usr/bin/jq -e '.data.configured == [] and .source_coverage.sys_param == 0' "$TMP_DIR/notify_config.json" >/dev/null
/usr/bin/jq -e '.data == [] and .source_coverage.sys_user == 5 and .provider_execution == false' "$TMP_DIR/notify_email.json" >/dev/null
/usr/bin/jq -e '.data.total == 0 and .data.rows == [] and .source_coverage.sys_user == 5' "$TMP_DIR/notify_preview.json" >/dev/null
/usr/bin/jq -e '.data == [] and .source_coverage.sys_user == 5' "$TMP_DIR/notify_log.json" >/dev/null
/usr/bin/jq -e '.data == [] and .source_coverage.sys_user == 5' "$TMP_DIR/notify_llm.json" >/dev/null
/usr/bin/jq -e '.data.provider == "mock" and (.data.providers | length) == 6 and .source_coverage.sys_param == 0' "$TMP_DIR/admin_ocr.json" >/dev/null
/usr/bin/jq -e '.data.total == 0 and .data.rows == [] and .source_coverage.sys_error_log == 0 and .network_fields_redacted == true' "$TMP_DIR/admin_error.json" >/dev/null
/usr/bin/jq -e '.data[0].groupName == "cost_subject" and .data[0].enabled == 5 and .source_coverage.my_biz_param_option == 5' "$TMP_DIR/admin_groups.json" >/dev/null
/usr/bin/jq -e '(.data | length) == 5 and .data[0].groupName == "cost_subject" and .source_coverage.my_biz_param_option == 5' "$TMP_DIR/admin_options.json" >/dev/null
/usr/bin/jq -e '(.data.tables | length) == 29 and .data.runtimeMetricsAvailable == false and .data.db.name == "moonproj"' "$TMP_DIR/admin_health.json" >/dev/null
/usr/bin/jq -e '.data.summary.totalRules == 12 and .data.summary.evaluatedRules == 8 and .data.summary.unavailableRules == 4 and .data.summary.failed == 1 and (.data.rules | length) == 12' "$TMP_DIR/admin_quality.json" >/dev/null
/usr/bin/jq -e '.data.provider == "mock" and .data.providers == [] and .provider_execution == false' "$TMP_DIR/admin_llm.json" >/dev/null
/usr/bin/jq -e '.data.pingResult == null and .provider_execution == false' "$TMP_DIR/admin_diag.json" >/dev/null
/usr/bin/jq -e '.success == false and .code == 43032 and .backup_status == "gated" and .format == "postgresql"' "$TMP_DIR/admin_backup.json" >/dev/null
/usr/bin/jq -e '(.data | length) == 5 and .data[0].userCode == "admin" and .data[0].isSuperUser == true and .source_coverage.sys_user == 5' "$TMP_DIR/rbac_users.json" >/dev/null
/usr/bin/jq -e '.data.userId == "user-admin-0001" and .data.roles == [] and .data.permissions == [] and .source_coverage.sys_role == 0' "$TMP_DIR/rbac_me.json" >/dev/null
/usr/bin/jq -e '.data == [] and .source_coverage.sys_role == 0 and .source_coverage.sys_user == 5' "$TMP_DIR/rbac_roles.json" >/dev/null
/usr/bin/jq -e '(.data | length) == 11 and .data[0].module == "驾驶舱"' "$TMP_DIR/rbac_catalog.json" >/dev/null
/usr/bin/jq -e '.data == [] and .source_coverage.sys_report_template == 0 and .persisted == false' "$TMP_DIR/report_templates.json" >/dev/null
/usr/bin/jq -e '.data.openTotal == 1 and .data.top[0].ruleCode == "W005" and .authorizing == false and .persisted == false' "$TMP_DIR/warning_badge.json" >/dev/null
/usr/bin/jq -e '.data.total == 1 and .data.rows[0].ruleCode == "W005" and .source_coverage.ep_project == 2 and .authorizing == false' "$TMP_DIR/warning_list.json" >/dev/null
/usr/bin/jq -e '(.data | length) == 12 and ([.data[] | select(.ruleCode == "W005")][0].openCount) == 1 and .persisted == false' "$TMP_DIR/warning_rules.json" >/dev/null
/usr/bin/jq -e '.data == [] and .authorizing == false and .persisted == false' "$TMP_DIR/warning_scans.json" >/dev/null
/usr/bin/jq -e '.data == [] and .authorizing == false and .persisted == false' "$TMP_DIR/warning_custom.json" >/dev/null
/usr/bin/jq -e '.success == true and .data.rows == [] and .data.summary.targetCost == 0 and .data.counts.leaves == 0 and .source_coverage.cb_subject_dict == 0 and .source_coverage.cb_plan_version == 0 and (.missing_or_empty_source_tables | index("cb_subject_dict")) != null and .authorizing == false' "$TMP_DIR/investment_cost_dashboard.json" >/dev/null
/usr/bin/jq -e '.success == true and .data == [] and .source_coverage.tzsy_excel_import == 0 and .authorizing == false' "$TMP_DIR/investment_imports.json" >/dev/null
/usr/bin/jq -e '.success == true and .data.lines == [] and .data.summary.count == 0 and .source_coverage.tzsy_plan_line == 0 and .authorizing == false' "$TMP_DIR/investment_plan_lines.json" >/dev/null
/usr/bin/jq -e '.success == true and .data.groups == {} and .source_coverage.tzsy_subject_mapping == 0 and .authorizing == false' "$TMP_DIR/investment_subject_mappings.json" >/dev/null
/usr/bin/jq -e '.success == false and .code == 41002 and .authorizing == false' "$TMP_DIR/investment_profit_cockpit.json" >/dev/null
/usr/bin/jq -e '.success == false and .code == 43001' "$TMP_DIR/investment_import_detail.json" >/dev/null
/usr/bin/jq -e '.success == false and .code == 43001' "$TMP_DIR/investment_bridge_plan.json" >/dev/null
/usr/bin/jq -e '.success == false and .code == 43001' "$TMP_DIR/investment_index_preview.json" >/dev/null
/usr/bin/jq -e '.success == false and .code == 43001' "$TMP_DIR/investment_profit_table.json" >/dev/null
/usr/bin/jq -e '.success == false and .code == 43001' "$TMP_DIR/investment_plan_preview.json" >/dev/null

echo "native source contract/payment/budget/workflow/dynamic-cost/delivery/receivable/invoice/sales/tender/marketing/fund/supplier/admin/notification/AI/RBAC/attachment/warning/investment/cost-dashboard read smoke passed"
