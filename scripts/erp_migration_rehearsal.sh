#!/bin/sh
set -eu

# End-to-end read-only ERP migration rehearsal:
#   SQLite backup -> redacted export -> raw staging -> durable company SQLite.
# No command in this wrapper writes to the source ERP database.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DB_PATH=${1:-../erp/erp_new/backup/erp-v0.1.0-snapshot.db}
WORK_DIR=${2:-/tmp/moonproj-erp-migration-rehearsal}
MAPPING_PATH=${3:-}
ACCOUNTING_MAPPING=${4:-}
ADVANCE_OFFSET_MAPPING=${5:-}
TYPED_MAPPING=${6:-}
PAYMENT_ACCOUNTING_MAPPING=${7:-}
CBS_COST_MAPPING=${8:-}
WORKFLOW_ASSIGNMENT_MAPPING=${9:-}
PRODUCTION_MANIFEST=${10:-}
DELIVERY_PROGRESS_MAPPING=${11:-}
BUSINESS_ACCEPTANCE_MANIFEST=${12:-$SCRIPT_DIR/fixtures/business_acceptance_manifest.example.json}
SHADOW_PERIOD_MANIFEST=${13:-$SCRIPT_DIR/fixtures/shadow_period_manifest.example.json}
DELIVERY_RECOGNITION_MAPPING=${14:-}
DELIVERY_RECOGNITION_ACCOUNTING_MAPPING=${15:-}
PRODUCTION_SERVICE_MANIFEST=${16:-}
CONSOLIDATED_REPORT_PLAN=${17:-}
INVESTMENT_BENCHMARK_PLAN=${18:-}
WARNING_PLAN=${19:-}
CBS_BUDGET_PLAN=${20:-}
CBS_BUDGET_SOURCE_MAPPING=${21:-}
WARNING_SOURCE_MAPPING=${22:-}
NOTIFICATION_PLAN=${23:-}
ACCESS_PLAN=${24:-}
ACCOUNTING_POSTING_MAPPING=${25:-}
OPENING_CONTROL_MAPPING=${26:-}
TAX_FILING_MAPPING=${27:-}
BANK_STATEMENT_MAPPING=${28:-}
FINANCING_FACILITY_MAPPING=${29:-}
ASSET_LIFECYCLE_MAPPING=${30:-}
TREASURY_PLAN_DISPATCH_MAPPING=${31:-}
SCHEMA_PATH=${ERP_SCHEMA_PATH:-../erp/erp_new/server/src/db/index.js}
ROUTES_DIR=${ERP_ROUTES_DIR:-../erp/erp_new/server/src/routes}

EXPORT_DIR="$WORK_DIR/export"
STAGING_PATH="$WORK_DIR/raw-staging.ndjson"
TARGET_DB="$WORK_DIR/company.sqlite3"

if [ -n "$PAYMENT_ACCOUNTING_MAPPING" ] && [ -z "$TYPED_MAPPING" ]; then
  echo "payment accounting mapping requires the typed cohort mapping" >&2
  exit 2
fi
if [ -n "$ACCOUNTING_POSTING_MAPPING" ] && [ -z "$ACCOUNTING_MAPPING" ]; then
  echo "accounting posting mapping requires the base accounting mapping" >&2
  exit 2
fi
if [ -n "$DELIVERY_RECOGNITION_ACCOUNTING_MAPPING" ] &&
  [ -z "$DELIVERY_RECOGNITION_MAPPING" ]; then
  echo "delivery recognition accounting mapping requires the delivery recognition mapping" >&2
  exit 2
fi
if [ -n "$PRODUCTION_SERVICE_MANIFEST" ] && [ -z "$PRODUCTION_MANIFEST" ]; then
  echo "production service manifest requires the production deployment manifest" >&2
  exit 2
fi
if [ -n "$CBS_BUDGET_PLAN" ] && [ -n "$CBS_BUDGET_SOURCE_MAPPING" ]; then
  echo "choose either a reviewed CBS budget plan or a source budget mapping" >&2
  exit 2
fi
if [ -n "$CBS_BUDGET_SOURCE_MAPPING" ] && [ -z "$CBS_COST_MAPPING" ]; then
  echo "source CBS budget mapping requires the CBS cost mapping" >&2
  exit 2
fi
if [ -n "$WARNING_PLAN" ] && [ -n "$WARNING_SOURCE_MAPPING" ]; then
  echo "choose either a reviewed warning plan or a source warning mapping" >&2
  exit 2
fi

mkdir -p "$WORK_DIR"
"$SCRIPT_DIR/erp_snapshot_export.sh" "$DB_PATH" "$EXPORT_DIR"
EXPORT_CONTRACT="$WORK_DIR/source-export-contract.json"
python3 "$SCRIPT_DIR/erp_export_contract.py" \
  "$SCHEMA_PATH" "$EXPORT_DIR" "$EXPORT_CONTRACT"
echo "source_export_contract=$EXPORT_CONTRACT"
SCHEMA_GAP="$WORK_DIR/schema-gap.json"
"$SCRIPT_DIR/erp_schema_gap_report.py" "$SCHEMA_PATH" "$EXPORT_DIR/manifest.json" "$SCHEMA_GAP"
echo "schema_gap=$SCHEMA_GAP"
SCHEMA_COHORT_PLAN="$WORK_DIR/schema-cohort-plan.json"
"$SCRIPT_DIR/erp_schema_cohort_plan.py" "$SCHEMA_PATH" "$SCHEMA_GAP" "$SCHEMA_COHORT_PLAN"
echo "schema_cohort_plan=$SCHEMA_COHORT_PLAN"
SOURCE_EXPORT_REQUEST="$WORK_DIR/source-export-request.json"
python3 "$SCRIPT_DIR/erp_source_export_request.py" \
  "$SCHEMA_GAP" "$SCHEMA_COHORT_PLAN" "$SOURCE_EXPORT_REQUEST"
echo "source_export_request=$SOURCE_EXPORT_REQUEST"
FOUNDATION_SCHEMA_MAPPING="$SCRIPT_DIR/fixtures/schema_foundation_security_mapping.json"
FOUNDATION_SCHEMA_RESULT="$WORK_DIR/schema-foundation-security.json"
python3 "$SCRIPT_DIR/erp_schema_cohort_mapping.py" \
  "$SCHEMA_COHORT_PLAN" "$FOUNDATION_SCHEMA_MAPPING" "$FOUNDATION_SCHEMA_RESULT"
echo "foundation_schema_mapping=$FOUNDATION_SCHEMA_RESULT"
WORKFLOW_SCHEMA_MAPPING="$SCRIPT_DIR/fixtures/schema_workflow_control_mapping.json"
WORKFLOW_SCHEMA_RESULT="$WORK_DIR/schema-workflow-control.json"
python3 "$SCRIPT_DIR/erp_schema_cohort_mapping.py" \
  "$SCHEMA_COHORT_PLAN" "$WORKFLOW_SCHEMA_MAPPING" "$WORKFLOW_SCHEMA_RESULT"
echo "workflow_schema_mapping=$WORKFLOW_SCHEMA_RESULT"
COST_SCHEMA_MAPPING="$SCRIPT_DIR/fixtures/schema_cost_investment_mapping.json"
COST_SCHEMA_RESULT="$WORK_DIR/schema-cost-investment.json"
python3 "$SCRIPT_DIR/erp_schema_cohort_mapping.py" \
  "$SCHEMA_COHORT_PLAN" "$COST_SCHEMA_MAPPING" "$COST_SCHEMA_RESULT"
echo "cost_investment_schema_mapping=$COST_SCHEMA_RESULT"
PROCUREMENT_SCHEMA_MAPPING="$SCRIPT_DIR/fixtures/schema_procurement_contract_mapping.json"
PROCUREMENT_SCHEMA_RESULT="$WORK_DIR/schema-procurement-contract.json"
python3 "$SCRIPT_DIR/erp_schema_cohort_mapping.py" \
  "$SCHEMA_COHORT_PLAN" "$PROCUREMENT_SCHEMA_MAPPING" "$PROCUREMENT_SCHEMA_RESULT"
echo "procurement_contract_schema_mapping=$PROCUREMENT_SCHEMA_RESULT"
SALES_SCHEMA_MAPPING="$SCRIPT_DIR/fixtures/schema_sales_receivables_mapping.json"
SALES_SCHEMA_RESULT="$WORK_DIR/schema-sales-receivables.json"
python3 "$SCRIPT_DIR/erp_schema_cohort_mapping.py" \
  "$SCHEMA_COHORT_PLAN" "$SALES_SCHEMA_MAPPING" "$SALES_SCHEMA_RESULT"
echo "sales_receivables_schema_mapping=$SALES_SCHEMA_RESULT"
DELIVERY_SCHEMA_MAPPING="$SCRIPT_DIR/fixtures/schema_delivery_treasury_mapping.json"
DELIVERY_SCHEMA_RESULT="$WORK_DIR/schema-delivery-treasury.json"
python3 "$SCRIPT_DIR/erp_schema_cohort_mapping.py" \
  "$SCHEMA_COHORT_PLAN" "$DELIVERY_SCHEMA_MAPPING" "$DELIVERY_SCHEMA_RESULT"
echo "delivery_treasury_schema_mapping=$DELIVERY_SCHEMA_RESULT"
REPORTING_SCHEMA_MAPPING="$SCRIPT_DIR/fixtures/schema_reporting_notification_mapping.json"
REPORTING_SCHEMA_RESULT="$WORK_DIR/schema-reporting-notification.json"
python3 "$SCRIPT_DIR/erp_schema_cohort_mapping.py" \
  "$SCHEMA_COHORT_PLAN" "$REPORTING_SCHEMA_MAPPING" "$REPORTING_SCHEMA_RESULT"
echo "reporting_notification_schema_mapping=$REPORTING_SCHEMA_RESULT"
RELATIONSHIP_AUDIT="$WORK_DIR/relationship-audit.json"
"$SCRIPT_DIR/erp_relationship_audit.py" "$DB_PATH" "$EXPORT_DIR/manifest.json" "$RELATIONSHIP_AUDIT"
echo "relationship_audit=$RELATIONSHIP_AUDIT"
ROUTE_INVENTORY="$WORK_DIR/route-inventory.json"
"$SCRIPT_DIR/erp_route_inventory.py" "$ROUTES_DIR" "$ROUTE_INVENTORY"
echo "route_inventory=$ROUTE_INVENTORY"
"$SCRIPT_DIR/erp_snapshot_stage_raw.sh" "$EXPORT_DIR" "$STAGING_PATH"
"$SCRIPT_DIR/company_sqlite_rehearsal.py" "$STAGING_PATH" "$TARGET_DB"

if [ -n "$MAPPING_PATH" ]; then
  PROMOTION_PLAN="$WORK_DIR/promotion-plan.json"
  "$SCRIPT_DIR/erp_promotion_plan.py" "$EXPORT_DIR" "$MAPPING_PATH" "$PROMOTION_PLAN"
  echo "promotion_plan=$PROMOTION_PLAN"
  DOMAIN_PROMOTION="$WORK_DIR/domain-promotion.json"
  moon run --target native cmd/promote -- "$PROMOTION_PLAN" "$DOMAIN_PROMOTION"
  echo "domain_promotion=$DOMAIN_PROMOTION"
  PROJECTION_APPLY="$WORK_DIR/projection-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$DOMAIN_PROMOTION" "$TARGET_DB" > "$PROJECTION_APPLY"
  echo "projection_apply=$PROJECTION_APPLY"
  PROJECTION_PARITY="$WORK_DIR/projection-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" "$DOMAIN_PROMOTION" "$TARGET_DB" "$PROJECTION_PARITY"
  echo "projection_parity=$PROJECTION_PARITY"
  PROJECTION_REPLAY="$WORK_DIR/projection-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$DOMAIN_PROMOTION" "$TARGET_DB" > "$PROJECTION_REPLAY"
  echo "projection_replay=$PROJECTION_REPLAY"
  if [ -n "$ACCOUNTING_MAPPING" ]; then
    ACCOUNTING_PLAN="$WORK_DIR/accounting-link-plan.json"
    "$SCRIPT_DIR/erp_accounting_link_plan.py" "$DOMAIN_PROMOTION" "$ACCOUNTING_MAPPING" "$ACCOUNTING_PLAN"
    echo "accounting_link_plan=$ACCOUNTING_PLAN"
    ACCOUNTING_RECEIPT="$WORK_DIR/accounting-link-receipt.json"
    moon run --target native cmd/accounting_link -- "$ACCOUNTING_PLAN" "$ACCOUNTING_RECEIPT"
    echo "accounting_link_receipt=$ACCOUNTING_RECEIPT"
    ACCOUNTING_APPLY="$WORK_DIR/accounting-link-apply.json"
    "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" "$ACCOUNTING_RECEIPT" "$TARGET_DB" > "$ACCOUNTING_APPLY"
    echo "accounting_link_apply=$ACCOUNTING_APPLY"
    ACCOUNTING_REPLAY="$WORK_DIR/accounting-link-replay.json"
    "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" "$ACCOUNTING_RECEIPT" "$TARGET_DB" > "$ACCOUNTING_REPLAY"
    echo "accounting_link_replay=$ACCOUNTING_REPLAY"
    ACCOUNTING_RECONCILIATION="$WORK_DIR/accounting-reconciliation.json"
    "$SCRIPT_DIR/company_sqlite_accounting_reconciliation.py" \
      "$DOMAIN_PROMOTION" "$ACCOUNTING_PLAN" "$ACCOUNTING_RECEIPT" "$TARGET_DB" "$ACCOUNTING_RECONCILIATION"
    echo "accounting_reconciliation=$ACCOUNTING_RECONCILIATION"
    if [ -n "$ACCOUNTING_POSTING_MAPPING" ]; then
      ACCOUNTING_POSTING_PLAN="$WORK_DIR/accounting-posting-plan.json"
      python3 "$SCRIPT_DIR/erp_accounting_post_plan.py" \
        "$ACCOUNTING_PLAN" "$ACCOUNTING_RECEIPT" "$ACCOUNTING_POSTING_MAPPING" \
        "$ACCOUNTING_POSTING_PLAN"
      echo "accounting_posting_plan=$ACCOUNTING_POSTING_PLAN"
      ACCOUNTING_POSTING_RECEIPT="$WORK_DIR/accounting-posting-receipt.json"
      moon run --target native cmd/accounting_post -- \
        "$ACCOUNTING_POSTING_PLAN" "$ACCOUNTING_POSTING_RECEIPT"
      echo "accounting_posting_receipt=$ACCOUNTING_POSTING_RECEIPT"
      ACCOUNTING_POSTING_APPLY="$WORK_DIR/accounting-posting-apply.json"
      "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
        "$ACCOUNTING_POSTING_RECEIPT" "$TARGET_DB" > "$ACCOUNTING_POSTING_APPLY"
      echo "accounting_posting_apply=$ACCOUNTING_POSTING_APPLY"
      ACCOUNTING_POSTING_PARITY="$WORK_DIR/accounting-posting-parity.json"
      "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
        "$ACCOUNTING_POSTING_RECEIPT" "$TARGET_DB" "$ACCOUNTING_POSTING_PARITY"
      echo "accounting_posting_parity=$ACCOUNTING_POSTING_PARITY"
      ACCOUNTING_POSTING_REPLAY="$WORK_DIR/accounting-posting-replay.json"
      "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
        "$ACCOUNTING_POSTING_RECEIPT" "$TARGET_DB" > "$ACCOUNTING_POSTING_REPLAY"
      echo "accounting_posting_replay=$ACCOUNTING_POSTING_REPLAY"
    fi
  fi
fi

if [ -n "$OPENING_CONTROL_MAPPING" ]; then
  OPENING_CONTROL_PLAN="$WORK_DIR/opening-control-plan.json"
  python3 "$SCRIPT_DIR/erp_opening_control_plan.py" \
    "$OPENING_CONTROL_MAPPING" "$OPENING_CONTROL_PLAN"
  echo "opening_control_plan=$OPENING_CONTROL_PLAN"
  OPENING_CONTROL_RECEIPT="$WORK_DIR/opening-control-receipt.json"
  moon run --target native cmd/opening_control -- \
    "$OPENING_CONTROL_PLAN" "$OPENING_CONTROL_RECEIPT"
  echo "opening_control_receipt=$OPENING_CONTROL_RECEIPT"
  OPENING_CONTROL_APPLY="$WORK_DIR/opening-control-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$OPENING_CONTROL_RECEIPT" "$TARGET_DB" > "$OPENING_CONTROL_APPLY"
  echo "opening_control_apply=$OPENING_CONTROL_APPLY"
  OPENING_CONTROL_PARITY="$WORK_DIR/opening-control-parity.json"
  python3 "$SCRIPT_DIR/company_opening_control_parity.py" \
    "$OPENING_CONTROL_RECEIPT" "$OPENING_CONTROL_PARITY" \
    --backend sqlite --database "$TARGET_DB"
  echo "opening_control_parity=$OPENING_CONTROL_PARITY"
  OPENING_CONTROL_REPLAY="$WORK_DIR/opening-control-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$OPENING_CONTROL_RECEIPT" "$TARGET_DB" > "$OPENING_CONTROL_REPLAY"
  echo "opening_control_replay=$OPENING_CONTROL_REPLAY"
fi

if [ -n "$TAX_FILING_MAPPING" ]; then
  TAX_FILING_PLAN="$WORK_DIR/tax-filing-plan.json"
  python3 "$SCRIPT_DIR/erp_tax_filing_plan.py" \
    "$TAX_FILING_MAPPING" "$TAX_FILING_PLAN"
  echo "tax_filing_plan=$TAX_FILING_PLAN"
  TAX_FILING_RECEIPT="$WORK_DIR/tax-filing-receipt.json"
  moon run --target native cmd/tax_filing -- \
    "$TAX_FILING_PLAN" "$TAX_FILING_RECEIPT"
  echo "tax_filing_receipt=$TAX_FILING_RECEIPT"
  TAX_FILING_APPLY="$WORK_DIR/tax-filing-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$TAX_FILING_RECEIPT" "$TARGET_DB" > "$TAX_FILING_APPLY"
  echo "tax_filing_apply=$TAX_FILING_APPLY"
  TAX_FILING_PARITY="$WORK_DIR/tax-filing-parity.json"
  python3 "$SCRIPT_DIR/company_tax_filing_parity.py" \
    "$TAX_FILING_RECEIPT" "$TAX_FILING_PARITY" \
    --backend sqlite --database "$TARGET_DB"
  echo "tax_filing_parity=$TAX_FILING_PARITY"
  TAX_FILING_REPLAY="$WORK_DIR/tax-filing-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$TAX_FILING_RECEIPT" "$TARGET_DB" > "$TAX_FILING_REPLAY"
  echo "tax_filing_replay=$TAX_FILING_REPLAY"
fi

if [ -n "$BANK_STATEMENT_MAPPING" ]; then
  BANK_STATEMENT_PLAN="$WORK_DIR/bank-statement-plan.json"
  python3 "$SCRIPT_DIR/erp_bank_statement_plan.py" \
    "$BANK_STATEMENT_MAPPING" "$BANK_STATEMENT_PLAN"
  echo "bank_statement_plan=$BANK_STATEMENT_PLAN"
  BANK_STATEMENT_RECEIPT="$WORK_DIR/bank-statement-receipt.json"
  moon run --target native cmd/bank_statement -- \
    "$BANK_STATEMENT_PLAN" "$BANK_STATEMENT_RECEIPT"
  echo "bank_statement_receipt=$BANK_STATEMENT_RECEIPT"
  BANK_STATEMENT_APPLY="$WORK_DIR/bank-statement-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$BANK_STATEMENT_RECEIPT" "$TARGET_DB" > "$BANK_STATEMENT_APPLY"
  echo "bank_statement_apply=$BANK_STATEMENT_APPLY"
  BANK_STATEMENT_PARITY="$WORK_DIR/bank-statement-parity.json"
  python3 "$SCRIPT_DIR/company_bank_statement_parity.py" \
    "$BANK_STATEMENT_RECEIPT" "$BANK_STATEMENT_PARITY" \
    --backend sqlite --database "$TARGET_DB"
  echo "bank_statement_parity=$BANK_STATEMENT_PARITY"
  BANK_STATEMENT_REPLAY="$WORK_DIR/bank-statement-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$BANK_STATEMENT_RECEIPT" "$TARGET_DB" > "$BANK_STATEMENT_REPLAY"
  echo "bank_statement_replay=$BANK_STATEMENT_REPLAY"
fi

if [ -n "$FINANCING_FACILITY_MAPPING" ]; then
  FINANCING_FACILITY_PLAN="$WORK_DIR/financing-facility-plan.json"
  python3 "$SCRIPT_DIR/erp_financing_facility_plan.py" \
    "$FINANCING_FACILITY_MAPPING" "$FINANCING_FACILITY_PLAN"
  echo "financing_facility_plan=$FINANCING_FACILITY_PLAN"
  FINANCING_FACILITY_RECEIPT="$WORK_DIR/financing-facility-receipt.json"
  moon run --target native cmd/financing_facility -- \
    "$FINANCING_FACILITY_PLAN" "$FINANCING_FACILITY_RECEIPT"
  echo "financing_facility_receipt=$FINANCING_FACILITY_RECEIPT"
  FINANCING_FACILITY_APPLY="$WORK_DIR/financing-facility-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$FINANCING_FACILITY_RECEIPT" "$TARGET_DB" > "$FINANCING_FACILITY_APPLY"
  echo "financing_facility_apply=$FINANCING_FACILITY_APPLY"
  FINANCING_FACILITY_PARITY="$WORK_DIR/financing-facility-parity.json"
  python3 "$SCRIPT_DIR/company_financing_facility_parity.py" \
    "$FINANCING_FACILITY_RECEIPT" "$FINANCING_FACILITY_PARITY" \
    --backend sqlite --database "$TARGET_DB"
  echo "financing_facility_parity=$FINANCING_FACILITY_PARITY"
  FINANCING_FACILITY_REPLAY="$WORK_DIR/financing-facility-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$FINANCING_FACILITY_RECEIPT" "$TARGET_DB" > "$FINANCING_FACILITY_REPLAY"
  echo "financing_facility_replay=$FINANCING_FACILITY_REPLAY"
fi

if [ -n "$ASSET_LIFECYCLE_MAPPING" ]; then
  ASSET_LIFECYCLE_PLAN="$WORK_DIR/asset-lifecycle-plan.json"
  python3 "$SCRIPT_DIR/erp_asset_lifecycle_plan.py" \
    "$ASSET_LIFECYCLE_MAPPING" "$ASSET_LIFECYCLE_PLAN"
  echo "asset_lifecycle_plan=$ASSET_LIFECYCLE_PLAN"
  ASSET_LIFECYCLE_RECEIPT="$WORK_DIR/asset-lifecycle-receipt.json"
  moon run --target native cmd/asset_lifecycle -- \
    "$ASSET_LIFECYCLE_PLAN" "$ASSET_LIFECYCLE_RECEIPT"
  echo "asset_lifecycle_receipt=$ASSET_LIFECYCLE_RECEIPT"
  ASSET_LIFECYCLE_APPLY="$WORK_DIR/asset-lifecycle-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$ASSET_LIFECYCLE_RECEIPT" "$TARGET_DB" > "$ASSET_LIFECYCLE_APPLY"
  echo "asset_lifecycle_apply=$ASSET_LIFECYCLE_APPLY"
  ASSET_LIFECYCLE_PARITY="$WORK_DIR/asset-lifecycle-parity.json"
  python3 "$SCRIPT_DIR/company_asset_lifecycle_parity.py" \
    "$ASSET_LIFECYCLE_RECEIPT" "$ASSET_LIFECYCLE_PARITY" \
    --backend sqlite --database "$TARGET_DB"
  echo "asset_lifecycle_parity=$ASSET_LIFECYCLE_PARITY"
  ASSET_LIFECYCLE_REPLAY="$WORK_DIR/asset-lifecycle-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$ASSET_LIFECYCLE_RECEIPT" "$TARGET_DB" > "$ASSET_LIFECYCLE_REPLAY"
  echo "asset_lifecycle_replay=$ASSET_LIFECYCLE_REPLAY"
fi

if [ -n "$TREASURY_PLAN_DISPATCH_MAPPING" ]; then
  TREASURY_PLAN_DISPATCH_PLAN="$WORK_DIR/treasury-plan-dispatch-plan.json"
  python3 "$SCRIPT_DIR/erp_treasury_plan_dispatch_plan.py" \
    "$TREASURY_PLAN_DISPATCH_MAPPING" "$TREASURY_PLAN_DISPATCH_PLAN"
  echo "treasury_plan_dispatch_plan=$TREASURY_PLAN_DISPATCH_PLAN"
  TREASURY_PLAN_DISPATCH_RECEIPT="$WORK_DIR/treasury-plan-dispatch-receipt.json"
  moon run --target native cmd/treasury_plan_dispatch -- \
    "$TREASURY_PLAN_DISPATCH_PLAN" "$TREASURY_PLAN_DISPATCH_RECEIPT"
  echo "treasury_plan_dispatch_receipt=$TREASURY_PLAN_DISPATCH_RECEIPT"
  TREASURY_PLAN_DISPATCH_APPLY="$WORK_DIR/treasury-plan-dispatch-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$TREASURY_PLAN_DISPATCH_RECEIPT" "$TARGET_DB" > "$TREASURY_PLAN_DISPATCH_APPLY"
  echo "treasury_plan_dispatch_apply=$TREASURY_PLAN_DISPATCH_APPLY"
  TREASURY_PLAN_DISPATCH_PARITY="$WORK_DIR/treasury-plan-dispatch-parity.json"
  python3 "$SCRIPT_DIR/company_treasury_plan_dispatch_parity.py" \
    "$TREASURY_PLAN_DISPATCH_RECEIPT" "$TREASURY_PLAN_DISPATCH_PARITY" \
    --backend sqlite --database "$TARGET_DB"
  echo "treasury_plan_dispatch_parity=$TREASURY_PLAN_DISPATCH_PARITY"
  TREASURY_PLAN_DISPATCH_REPLAY="$WORK_DIR/treasury-plan-dispatch-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$TREASURY_PLAN_DISPATCH_RECEIPT" "$TARGET_DB" > "$TREASURY_PLAN_DISPATCH_REPLAY"
  echo "treasury_plan_dispatch_replay=$TREASURY_PLAN_DISPATCH_REPLAY"
fi

if [ -n "$ADVANCE_OFFSET_MAPPING" ]; then
  ADVANCE_OFFSET_PLAN="$WORK_DIR/advance-offset-plan.json"
  "$SCRIPT_DIR/erp_advance_offset_promotion_plan.py" "$EXPORT_DIR" "$ADVANCE_OFFSET_MAPPING" "$ADVANCE_OFFSET_PLAN"
  echo "advance_offset_plan=$ADVANCE_OFFSET_PLAN"
  ADVANCE_OFFSET_PROMOTION="$WORK_DIR/advance-offset-promotion.json"
  moon run --target native cmd/promote -- "$ADVANCE_OFFSET_PLAN" "$ADVANCE_OFFSET_PROMOTION"
  echo "advance_offset_promotion=$ADVANCE_OFFSET_PROMOTION"
  ADVANCE_OFFSET_APPLY="$WORK_DIR/advance-offset-projection-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$ADVANCE_OFFSET_PROMOTION" "$TARGET_DB" > "$ADVANCE_OFFSET_APPLY"
  echo "advance_offset_projection_apply=$ADVANCE_OFFSET_APPLY"
  ADVANCE_OFFSET_PARITY="$WORK_DIR/advance-offset-projection-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" "$ADVANCE_OFFSET_PROMOTION" "$TARGET_DB" "$ADVANCE_OFFSET_PARITY"
  echo "advance_offset_projection_parity=$ADVANCE_OFFSET_PARITY"
  ADVANCE_OFFSET_REPLAY="$WORK_DIR/advance-offset-projection-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$ADVANCE_OFFSET_PROMOTION" "$TARGET_DB" > "$ADVANCE_OFFSET_REPLAY"
  echo "advance_offset_projection_replay=$ADVANCE_OFFSET_REPLAY"
  ADVANCE_OFFSET_ACCOUNTING_PLAN="$WORK_DIR/advance-offset-accounting-link-plan.json"
  "$SCRIPT_DIR/erp_accounting_link_plan.py" "$ADVANCE_OFFSET_PROMOTION" "$ADVANCE_OFFSET_MAPPING" "$ADVANCE_OFFSET_ACCOUNTING_PLAN"
  echo "advance_offset_accounting_plan=$ADVANCE_OFFSET_ACCOUNTING_PLAN"
  ADVANCE_OFFSET_ACCOUNTING_RECEIPT="$WORK_DIR/advance-offset-accounting-link-receipt.json"
  moon run --target native cmd/accounting_link -- "$ADVANCE_OFFSET_ACCOUNTING_PLAN" "$ADVANCE_OFFSET_ACCOUNTING_RECEIPT"
  echo "advance_offset_accounting_receipt=$ADVANCE_OFFSET_ACCOUNTING_RECEIPT"
  ADVANCE_OFFSET_ACCOUNTING_APPLY="$WORK_DIR/advance-offset-accounting-link-apply.json"
  "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" "$ADVANCE_OFFSET_ACCOUNTING_RECEIPT" "$TARGET_DB" > "$ADVANCE_OFFSET_ACCOUNTING_APPLY"
  echo "advance_offset_accounting_apply=$ADVANCE_OFFSET_ACCOUNTING_APPLY"
  ADVANCE_OFFSET_ACCOUNTING_REPLAY="$WORK_DIR/advance-offset-accounting-link-replay.json"
  "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" "$ADVANCE_OFFSET_ACCOUNTING_RECEIPT" "$TARGET_DB" > "$ADVANCE_OFFSET_ACCOUNTING_REPLAY"
  echo "advance_offset_accounting_replay=$ADVANCE_OFFSET_ACCOUNTING_REPLAY"
  ADVANCE_OFFSET_RECONCILIATION="$WORK_DIR/advance-offset-accounting-reconciliation.json"
  "$SCRIPT_DIR/company_sqlite_accounting_reconciliation.py" \
    "$ADVANCE_OFFSET_PROMOTION" "$ADVANCE_OFFSET_ACCOUNTING_PLAN" "$ADVANCE_OFFSET_ACCOUNTING_RECEIPT" "$TARGET_DB" "$ADVANCE_OFFSET_RECONCILIATION"
  echo "advance_offset_accounting_reconciliation=$ADVANCE_OFFSET_RECONCILIATION"
fi

if [ -n "$TYPED_MAPPING" ]; then
  TYPED_WORK_DIR="$WORK_DIR/typed-cohorts"
  "$SCRIPT_DIR/erp_typed_cohort_rehearsal.sh" "$EXPORT_DIR" "$TYPED_MAPPING" "$TARGET_DB" "$TYPED_WORK_DIR"
fi

if [ -n "$PAYMENT_ACCOUNTING_MAPPING" ]; then
  PAYMENT_PROMOTION="$TYPED_WORK_DIR/payment-promotion.json"
  PAYMENT_ACCOUNTING_PLAN="$WORK_DIR/payment-accounting-link-plan.json"
  "$SCRIPT_DIR/erp_accounting_link_plan.py" "$PAYMENT_PROMOTION" "$PAYMENT_ACCOUNTING_MAPPING" "$PAYMENT_ACCOUNTING_PLAN"
  echo "payment_accounting_plan=$PAYMENT_ACCOUNTING_PLAN"
  PAYMENT_ACCOUNTING_RECEIPT="$WORK_DIR/payment-accounting-link-receipt.json"
  moon run --target native cmd/accounting_link -- "$PAYMENT_ACCOUNTING_PLAN" "$PAYMENT_ACCOUNTING_RECEIPT"
  echo "payment_accounting_receipt=$PAYMENT_ACCOUNTING_RECEIPT"
  PAYMENT_ACCOUNTING_APPLY="$WORK_DIR/payment-accounting-link-apply.json"
  "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" "$PAYMENT_ACCOUNTING_RECEIPT" "$TARGET_DB" > "$PAYMENT_ACCOUNTING_APPLY"
  echo "payment_accounting_apply=$PAYMENT_ACCOUNTING_APPLY"
  PAYMENT_ACCOUNTING_REPLAY="$WORK_DIR/payment-accounting-link-replay.json"
  "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" "$PAYMENT_ACCOUNTING_RECEIPT" "$TARGET_DB" > "$PAYMENT_ACCOUNTING_REPLAY"
  echo "payment_accounting_replay=$PAYMENT_ACCOUNTING_REPLAY"
  PAYMENT_RECONCILIATION="$WORK_DIR/payment-accounting-reconciliation.json"
  "$SCRIPT_DIR/company_sqlite_accounting_reconciliation.py" \
    "$PAYMENT_PROMOTION" "$PAYMENT_ACCOUNTING_PLAN" "$PAYMENT_ACCOUNTING_RECEIPT" "$TARGET_DB" "$PAYMENT_RECONCILIATION"
  echo "payment_accounting_reconciliation=$PAYMENT_RECONCILIATION"
fi

if [ -n "$CBS_COST_MAPPING" ]; then
  CBS_COST_PLAN="$WORK_DIR/cbs-cost-link-plan.json"
  "$SCRIPT_DIR/erp_cbs_cost_link_plan.py" "$EXPORT_DIR" "$CBS_COST_MAPPING" "$CBS_COST_PLAN"
  echo "cbs_cost_link_plan=$CBS_COST_PLAN"
  CBS_COST_RECEIPT="$WORK_DIR/cbs-cost-link-receipt.json"
  moon run --target native cmd/cbs_link -- "$CBS_COST_PLAN" "$CBS_COST_RECEIPT"
  echo "cbs_cost_link_receipt=$CBS_COST_RECEIPT"
  CBS_COST_APPLY="$WORK_DIR/cbs-cost-link-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$CBS_COST_RECEIPT" "$TARGET_DB" > "$CBS_COST_APPLY"
  echo "cbs_cost_link_apply=$CBS_COST_APPLY"
  CBS_COST_PARITY="$WORK_DIR/cbs-cost-link-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" "$CBS_COST_RECEIPT" "$TARGET_DB" "$CBS_COST_PARITY"
  echo "cbs_cost_link_parity=$CBS_COST_PARITY"
  CBS_COST_REPLAY="$WORK_DIR/cbs-cost-link-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$CBS_COST_RECEIPT" "$TARGET_DB" > "$CBS_COST_REPLAY"
  echo "cbs_cost_link_replay=$CBS_COST_REPLAY"
fi

if [ -n "$CBS_BUDGET_PLAN" ]; then
  CBS_BUDGET_RECEIPT="$WORK_DIR/cbs-budget-receipt.json"
  moon run --target native cmd/cbs_budget -- \
    "$CBS_BUDGET_PLAN" "$CBS_BUDGET_RECEIPT"
  echo "cbs_budget_receipt=$CBS_BUDGET_RECEIPT"
  CBS_BUDGET_APPLY="$WORK_DIR/cbs-budget-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$CBS_BUDGET_RECEIPT" "$TARGET_DB" > "$CBS_BUDGET_APPLY"
  echo "cbs_budget_apply=$CBS_BUDGET_APPLY"
  CBS_BUDGET_PARITY="$WORK_DIR/cbs-budget-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
    "$CBS_BUDGET_RECEIPT" "$TARGET_DB" "$CBS_BUDGET_PARITY"
  echo "cbs_budget_parity=$CBS_BUDGET_PARITY"
  CBS_BUDGET_REPLAY="$WORK_DIR/cbs-budget-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$CBS_BUDGET_RECEIPT" "$TARGET_DB" > "$CBS_BUDGET_REPLAY"
  echo "cbs_budget_replay=$CBS_BUDGET_REPLAY"
fi

if [ -n "$CBS_BUDGET_SOURCE_MAPPING" ]; then
  CBS_BUDGET_SOURCE_PLAN="$WORK_DIR/cbs-budget-source-plan.json"
  python3 "$SCRIPT_DIR/erp_cbs_budget_plan.py" \
    "$EXPORT_DIR" "$CBS_COST_MAPPING" "$CBS_BUDGET_SOURCE_MAPPING" \
    "$CBS_BUDGET_SOURCE_PLAN"
  echo "cbs_budget_source_plan=$CBS_BUDGET_SOURCE_PLAN"
  CBS_BUDGET_SOURCE_RECEIPT="$WORK_DIR/cbs-budget-source-receipt.json"
  moon run --target native cmd/cbs_budget -- \
    "$CBS_BUDGET_SOURCE_PLAN" "$CBS_BUDGET_SOURCE_RECEIPT"
  echo "cbs_budget_source_receipt=$CBS_BUDGET_SOURCE_RECEIPT"
  CBS_BUDGET_SOURCE_APPLY="$WORK_DIR/cbs-budget-source-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$CBS_BUDGET_SOURCE_RECEIPT" "$TARGET_DB" > "$CBS_BUDGET_SOURCE_APPLY"
  echo "cbs_budget_source_apply=$CBS_BUDGET_SOURCE_APPLY"
  CBS_BUDGET_SOURCE_PARITY="$WORK_DIR/cbs-budget-source-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
    "$CBS_BUDGET_SOURCE_RECEIPT" "$TARGET_DB" "$CBS_BUDGET_SOURCE_PARITY"
  echo "cbs_budget_source_parity=$CBS_BUDGET_SOURCE_PARITY"
  CBS_BUDGET_SOURCE_REPLAY="$WORK_DIR/cbs-budget-source-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$CBS_BUDGET_SOURCE_RECEIPT" "$TARGET_DB" > "$CBS_BUDGET_SOURCE_REPLAY"
  echo "cbs_budget_source_replay=$CBS_BUDGET_SOURCE_REPLAY"
fi

if [ -n "$WORKFLOW_ASSIGNMENT_MAPPING" ]; then
  WORKFLOW_ASSIGNMENT_PLAN="$WORK_DIR/workflow-assignment-plan.json"
  "$SCRIPT_DIR/erp_workflow_assignment_plan.py" "$EXPORT_DIR" "$WORKFLOW_ASSIGNMENT_MAPPING" "$WORKFLOW_ASSIGNMENT_PLAN"
  echo "workflow_assignment_plan=$WORKFLOW_ASSIGNMENT_PLAN"
  WORKFLOW_ASSIGNMENT_RECEIPT="$WORK_DIR/workflow-assignment-receipt.json"
  moon run --target native cmd/workflow_assignment -- "$WORKFLOW_ASSIGNMENT_PLAN" "$WORKFLOW_ASSIGNMENT_RECEIPT"
  echo "workflow_assignment_receipt=$WORKFLOW_ASSIGNMENT_RECEIPT"
  WORKFLOW_ASSIGNMENT_APPLY="$WORK_DIR/workflow-assignment-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$WORKFLOW_ASSIGNMENT_RECEIPT" "$TARGET_DB" > "$WORKFLOW_ASSIGNMENT_APPLY"
  echo "workflow_assignment_apply=$WORKFLOW_ASSIGNMENT_APPLY"
  WORKFLOW_ASSIGNMENT_PARITY="$WORK_DIR/workflow-assignment-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" "$WORKFLOW_ASSIGNMENT_RECEIPT" "$TARGET_DB" "$WORKFLOW_ASSIGNMENT_PARITY"
  echo "workflow_assignment_parity=$WORKFLOW_ASSIGNMENT_PARITY"
  WORKFLOW_ASSIGNMENT_REPLAY="$WORK_DIR/workflow-assignment-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$WORKFLOW_ASSIGNMENT_RECEIPT" "$TARGET_DB" > "$WORKFLOW_ASSIGNMENT_REPLAY"
  echo "workflow_assignment_replay=$WORKFLOW_ASSIGNMENT_REPLAY"
fi

if [ -n "$DELIVERY_PROGRESS_MAPPING" ]; then
  DELIVERY_PROGRESS_PLAN="$WORK_DIR/delivery-progress-plan.json"
  "$SCRIPT_DIR/erp_delivery_progress_plan.py" "$EXPORT_DIR" "$DELIVERY_PROGRESS_MAPPING" "$DELIVERY_PROGRESS_PLAN"
  echo "delivery_progress_plan=$DELIVERY_PROGRESS_PLAN"
  DELIVERY_PROGRESS_RECEIPT="$WORK_DIR/delivery-progress-receipt.json"
  moon run --target native cmd/delivery_progress -- "$DELIVERY_PROGRESS_PLAN" "$DELIVERY_PROGRESS_RECEIPT"
  echo "delivery_progress_receipt=$DELIVERY_PROGRESS_RECEIPT"
  DELIVERY_PROGRESS_APPLY="$WORK_DIR/delivery-progress-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$DELIVERY_PROGRESS_RECEIPT" "$TARGET_DB" > "$DELIVERY_PROGRESS_APPLY"
  echo "delivery_progress_apply=$DELIVERY_PROGRESS_APPLY"
  DELIVERY_PROGRESS_PARITY="$WORK_DIR/delivery-progress-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" "$DELIVERY_PROGRESS_RECEIPT" "$TARGET_DB" "$DELIVERY_PROGRESS_PARITY"
  echo "delivery_progress_parity=$DELIVERY_PROGRESS_PARITY"
  DELIVERY_PROGRESS_REPLAY="$WORK_DIR/delivery-progress-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$DELIVERY_PROGRESS_RECEIPT" "$TARGET_DB" > "$DELIVERY_PROGRESS_REPLAY"
  echo "delivery_progress_replay=$DELIVERY_PROGRESS_REPLAY"
fi

if [ -n "$DELIVERY_RECOGNITION_MAPPING" ]; then
  DELIVERY_RECOGNITION_PLAN="$WORK_DIR/delivery-recognition-plan.json"
  "$SCRIPT_DIR/erp_delivery_recognition_plan.py" \
    "$EXPORT_DIR" "$DELIVERY_RECOGNITION_MAPPING" "$DELIVERY_RECOGNITION_PLAN"
  echo "delivery_recognition_plan=$DELIVERY_RECOGNITION_PLAN"
  DELIVERY_RECOGNITION_RECEIPT="$WORK_DIR/delivery-recognition-receipt.json"
  moon run --target native cmd/delivery_recognition -- \
    "$DELIVERY_RECOGNITION_PLAN" "$DELIVERY_RECOGNITION_RECEIPT"
  echo "delivery_recognition_receipt=$DELIVERY_RECOGNITION_RECEIPT"
  DELIVERY_RECOGNITION_APPLY="$WORK_DIR/delivery-recognition-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$DELIVERY_RECOGNITION_RECEIPT" "$TARGET_DB" > "$DELIVERY_RECOGNITION_APPLY"
  echo "delivery_recognition_apply=$DELIVERY_RECOGNITION_APPLY"
  DELIVERY_RECOGNITION_PARITY="$WORK_DIR/delivery-recognition-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
    "$DELIVERY_RECOGNITION_RECEIPT" "$TARGET_DB" "$DELIVERY_RECOGNITION_PARITY"
  echo "delivery_recognition_parity=$DELIVERY_RECOGNITION_PARITY"
  DELIVERY_RECOGNITION_REPLAY="$WORK_DIR/delivery-recognition-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$DELIVERY_RECOGNITION_RECEIPT" "$TARGET_DB" > "$DELIVERY_RECOGNITION_REPLAY"
  echo "delivery_recognition_replay=$DELIVERY_RECOGNITION_REPLAY"
  if [ -n "$DELIVERY_RECOGNITION_ACCOUNTING_MAPPING" ]; then
    DELIVERY_RECOGNITION_ACCOUNTING_PLAN="$WORK_DIR/delivery-recognition-accounting-link-plan.json"
    "$SCRIPT_DIR/erp_accounting_link_plan.py" \
      "$DELIVERY_RECOGNITION_RECEIPT" \
      "$DELIVERY_RECOGNITION_ACCOUNTING_MAPPING" \
      "$DELIVERY_RECOGNITION_ACCOUNTING_PLAN"
    echo "delivery_recognition_accounting_plan=$DELIVERY_RECOGNITION_ACCOUNTING_PLAN"
    DELIVERY_RECOGNITION_ACCOUNTING_RECEIPT="$WORK_DIR/delivery-recognition-accounting-link-receipt.json"
    moon run --target native cmd/accounting_link -- \
      "$DELIVERY_RECOGNITION_ACCOUNTING_PLAN" \
      "$DELIVERY_RECOGNITION_ACCOUNTING_RECEIPT"
    echo "delivery_recognition_accounting_receipt=$DELIVERY_RECOGNITION_ACCOUNTING_RECEIPT"
    DELIVERY_RECOGNITION_ACCOUNTING_APPLY="$WORK_DIR/delivery-recognition-accounting-link-apply.json"
    "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" \
      "$DELIVERY_RECOGNITION_ACCOUNTING_RECEIPT" "$TARGET_DB" > "$DELIVERY_RECOGNITION_ACCOUNTING_APPLY"
    echo "delivery_recognition_accounting_apply=$DELIVERY_RECOGNITION_ACCOUNTING_APPLY"
    DELIVERY_RECOGNITION_ACCOUNTING_REPLAY="$WORK_DIR/delivery-recognition-accounting-link-replay.json"
    "$SCRIPT_DIR/company_sqlite_accounting_link_apply.py" \
      "$DELIVERY_RECOGNITION_ACCOUNTING_RECEIPT" "$TARGET_DB" > "$DELIVERY_RECOGNITION_ACCOUNTING_REPLAY"
    echo "delivery_recognition_accounting_replay=$DELIVERY_RECOGNITION_ACCOUNTING_REPLAY"
    DELIVERY_RECOGNITION_RECONCILIATION="$WORK_DIR/delivery-recognition-accounting-reconciliation.json"
    "$SCRIPT_DIR/company_sqlite_accounting_reconciliation.py" \
      "$DELIVERY_RECOGNITION_RECEIPT" \
      "$DELIVERY_RECOGNITION_ACCOUNTING_PLAN" \
      "$DELIVERY_RECOGNITION_ACCOUNTING_RECEIPT" \
      "$TARGET_DB" "$DELIVERY_RECOGNITION_RECONCILIATION"
    echo "delivery_recognition_reconciliation=$DELIVERY_RECOGNITION_RECONCILIATION"
  fi
fi

if [ -n "$CONSOLIDATED_REPORT_PLAN" ]; then
  CONSOLIDATED_REPORT_RECEIPT="$WORK_DIR/consolidated-report-receipt.json"
  moon run --target native cmd/consolidated_report -- \
    "$CONSOLIDATED_REPORT_PLAN" "$CONSOLIDATED_REPORT_RECEIPT"
  echo "consolidated_report_receipt=$CONSOLIDATED_REPORT_RECEIPT"
  CONSOLIDATED_REPORT_APPLY="$WORK_DIR/consolidated-report-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$CONSOLIDATED_REPORT_RECEIPT" "$TARGET_DB" > "$CONSOLIDATED_REPORT_APPLY"
  echo "consolidated_report_apply=$CONSOLIDATED_REPORT_APPLY"
  CONSOLIDATED_REPORT_PARITY="$WORK_DIR/consolidated-report-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
    "$CONSOLIDATED_REPORT_RECEIPT" "$TARGET_DB" "$CONSOLIDATED_REPORT_PARITY"
  echo "consolidated_report_parity=$CONSOLIDATED_REPORT_PARITY"
  CONSOLIDATED_REPORT_REPLAY="$WORK_DIR/consolidated-report-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$CONSOLIDATED_REPORT_RECEIPT" "$TARGET_DB" > "$CONSOLIDATED_REPORT_REPLAY"
  echo "consolidated_report_replay=$CONSOLIDATED_REPORT_REPLAY"
fi

if [ -n "$INVESTMENT_BENCHMARK_PLAN" ]; then
  INVESTMENT_BENCHMARK_RECEIPT="$WORK_DIR/investment-benchmark-receipt.json"
  moon run --target native cmd/investment_benchmark -- \
    "$INVESTMENT_BENCHMARK_PLAN" "$INVESTMENT_BENCHMARK_RECEIPT"
  echo "investment_benchmark_receipt=$INVESTMENT_BENCHMARK_RECEIPT"
  INVESTMENT_BENCHMARK_APPLY="$WORK_DIR/investment-benchmark-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$INVESTMENT_BENCHMARK_RECEIPT" "$TARGET_DB" > "$INVESTMENT_BENCHMARK_APPLY"
  echo "investment_benchmark_apply=$INVESTMENT_BENCHMARK_APPLY"
  INVESTMENT_BENCHMARK_PARITY="$WORK_DIR/investment-benchmark-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
    "$INVESTMENT_BENCHMARK_RECEIPT" "$TARGET_DB" "$INVESTMENT_BENCHMARK_PARITY"
  echo "investment_benchmark_parity=$INVESTMENT_BENCHMARK_PARITY"
  INVESTMENT_BENCHMARK_REPLAY="$WORK_DIR/investment-benchmark-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$INVESTMENT_BENCHMARK_RECEIPT" "$TARGET_DB" > "$INVESTMENT_BENCHMARK_REPLAY"
  echo "investment_benchmark_replay=$INVESTMENT_BENCHMARK_REPLAY"
fi

if [ -n "$WARNING_PLAN" ]; then
  WARNING_RECEIPT="$WORK_DIR/warning-receipt.json"
  moon run --target native cmd/warning -- "$WARNING_PLAN" "$WARNING_RECEIPT"
  echo "warning_receipt=$WARNING_RECEIPT"
  WARNING_APPLY="$WORK_DIR/warning-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$WARNING_RECEIPT" "$TARGET_DB" > "$WARNING_APPLY"
  echo "warning_apply=$WARNING_APPLY"
  WARNING_PARITY="$WORK_DIR/warning-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
    "$WARNING_RECEIPT" "$TARGET_DB" "$WARNING_PARITY"
  echo "warning_parity=$WARNING_PARITY"
  WARNING_REPLAY="$WORK_DIR/warning-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$WARNING_RECEIPT" "$TARGET_DB" > "$WARNING_REPLAY"
  echo "warning_replay=$WARNING_REPLAY"
fi

if [ -n "$WARNING_SOURCE_MAPPING" ]; then
  WARNING_SOURCE_PLAN="$WORK_DIR/warning-source-plan.json"
  python3 "$SCRIPT_DIR/erp_warning_plan.py" \
    "$EXPORT_DIR" "$WARNING_SOURCE_MAPPING" "$WARNING_SOURCE_PLAN"
  echo "warning_source_plan=$WARNING_SOURCE_PLAN"
  WARNING_SOURCE_RECEIPT="$WORK_DIR/warning-source-receipt.json"
  moon run --target native cmd/warning -- \
    "$WARNING_SOURCE_PLAN" "$WARNING_SOURCE_RECEIPT"
  echo "warning_source_receipt=$WARNING_SOURCE_RECEIPT"
  WARNING_SOURCE_APPLY="$WORK_DIR/warning-source-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$WARNING_SOURCE_RECEIPT" "$TARGET_DB" > "$WARNING_SOURCE_APPLY"
  echo "warning_source_apply=$WARNING_SOURCE_APPLY"
  WARNING_SOURCE_PARITY="$WORK_DIR/warning-source-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
    "$WARNING_SOURCE_RECEIPT" "$TARGET_DB" "$WARNING_SOURCE_PARITY"
  echo "warning_source_parity=$WARNING_SOURCE_PARITY"
  WARNING_SOURCE_REPLAY="$WORK_DIR/warning-source-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$WARNING_SOURCE_RECEIPT" "$TARGET_DB" > "$WARNING_SOURCE_REPLAY"
  echo "warning_source_replay=$WARNING_SOURCE_REPLAY"
fi

if [ -n "$NOTIFICATION_PLAN" ]; then
  NOTIFICATION_RECEIPT="$WORK_DIR/notification-receipt.json"
  moon run --target native cmd/notification -- \
    "$NOTIFICATION_PLAN" "$NOTIFICATION_RECEIPT"
  echo "notification_receipt=$NOTIFICATION_RECEIPT"
  NOTIFICATION_APPLY="$WORK_DIR/notification-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$NOTIFICATION_RECEIPT" "$TARGET_DB" > "$NOTIFICATION_APPLY"
  echo "notification_apply=$NOTIFICATION_APPLY"
  NOTIFICATION_PARITY="$WORK_DIR/notification-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
    "$NOTIFICATION_RECEIPT" "$TARGET_DB" "$NOTIFICATION_PARITY"
  echo "notification_parity=$NOTIFICATION_PARITY"
  NOTIFICATION_REPLAY="$WORK_DIR/notification-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$NOTIFICATION_RECEIPT" "$TARGET_DB" > "$NOTIFICATION_REPLAY"
  echo "notification_replay=$NOTIFICATION_REPLAY"
fi

if [ -n "$ACCESS_PLAN" ]; then
  ACCESS_RECEIPT="$WORK_DIR/access-receipt.json"
  moon run --target native cmd/access_import -- \
    "$ACCESS_PLAN" "$ACCESS_RECEIPT"
  echo "access_receipt=$ACCESS_RECEIPT"
  ACCESS_APPLY="$WORK_DIR/access-apply.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$ACCESS_RECEIPT" "$TARGET_DB" > "$ACCESS_APPLY"
  echo "access_apply=$ACCESS_APPLY"
  ACCESS_PARITY="$WORK_DIR/access-parity.json"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" \
    "$ACCESS_RECEIPT" "$TARGET_DB" "$ACCESS_PARITY"
  echo "access_parity=$ACCESS_PARITY"
  ACCESS_REPLAY="$WORK_DIR/access-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" \
    "$ACCESS_RECEIPT" "$TARGET_DB" > "$ACCESS_REPLAY"
  echo "access_replay=$ACCESS_REPLAY"
fi

ROW_COVERAGE="$WORK_DIR/row-coverage.json"
python3 "$SCRIPT_DIR/erp_row_coverage.py" "$EXPORT_DIR" "$WORK_DIR" "$ROW_COVERAGE"
echo "row_coverage=$ROW_COVERAGE"
BUSINESS_ACCEPTANCE="$WORK_DIR/business-acceptance.json"
python3 "$SCRIPT_DIR/company_business_acceptance_check.py" \
  "$WORK_DIR" "$BUSINESS_ACCEPTANCE_MANIFEST" "$BUSINESS_ACCEPTANCE"
echo "business_acceptance=$BUSINESS_ACCEPTANCE"
SHADOW_PERIOD="$WORK_DIR/shadow-period.json"
python3 "$SCRIPT_DIR/company_shadow_period_check.py" \
  "$WORK_DIR" "$SHADOW_PERIOD_MANIFEST" "$SHADOW_PERIOD"
echo "shadow_period=$SHADOW_PERIOD"

if [ -n "$PRODUCTION_MANIFEST" ]; then
  PRODUCTION_DEPLOYMENT_GATE="$WORK_DIR/production-deployment-gate.json"
  "$SCRIPT_DIR/company_production_deployment_check.py" \
    "$PRODUCTION_MANIFEST" "$PRODUCTION_DEPLOYMENT_GATE"
  echo "production_deployment_gate=$PRODUCTION_DEPLOYMENT_GATE"
  if [ -n "$PRODUCTION_SERVICE_MANIFEST" ]; then
    PRODUCTION_SERVICE_GATE="$WORK_DIR/production-service-gate.json"
    python3 "$SCRIPT_DIR/company_production_service_check.py" \
      "$PRODUCTION_SERVICE_MANIFEST" "$PRODUCTION_DEPLOYMENT_GATE" \
      "$PRODUCTION_SERVICE_GATE"
    echo "production_service_gate=$PRODUCTION_SERVICE_GATE"
  fi
fi

if [ -n "$ACCOUNTING_MAPPING" ]; then
  PERIOD_CLOSE_CONTROL="$WORK_DIR/period-close-control.json"
  "$SCRIPT_DIR/company_period_close_control.py" "$WORK_DIR" "$PERIOD_CLOSE_CONTROL"
  echo "period_close_control=$PERIOD_CLOSE_CONTROL"
fi

DRIVER_SMOKE="$WORK_DIR/driver-smoke.json"
"$SCRIPT_DIR/company_sqlite_driver_smoke.py" "$WORK_DIR/driver-smoke.sqlite3" > "$DRIVER_SMOKE"
echo "driver_smoke=$DRIVER_SMOKE"

BACKUP_RESTORE="$WORK_DIR/backup-restore.json"
"$SCRIPT_DIR/company_sqlite_backup_restore.py" --overwrite "$TARGET_DB" "$WORK_DIR/company-backup.sqlite3" > "$BACKUP_RESTORE"
echo "backup_restore=$BACKUP_RESTORE"

if [ -n "$TYPED_MAPPING" ]; then
  CUTOVER_GATE="$WORK_DIR/cutover-gate.json"
  EXPECTED_LINKS=4
  EXPECTED_PROJECTIONS=96
  if [ -n "$PAYMENT_ACCOUNTING_MAPPING" ]; then
    EXPECTED_LINKS=7
  fi
  if [ -n "$CBS_COST_MAPPING" ]; then
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + 8))
  fi
  if [ -n "$WORKFLOW_ASSIGNMENT_MAPPING" ]; then
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + 6))
  fi
  if [ -n "$DELIVERY_PROGRESS_MAPPING" ]; then
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + 1))
  fi
  if [ -n "$DELIVERY_RECOGNITION_MAPPING" ]; then
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + 1))
  fi
  if [ -n "$INVESTMENT_BENCHMARK_PLAN" ]; then
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + 1))
  fi
  if [ -n "$WARNING_PLAN" ] || [ -n "$WARNING_SOURCE_MAPPING" ]; then
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + 1))
  fi
  if [ -n "$CBS_BUDGET_PLAN" ] || [ -n "$CBS_BUDGET_SOURCE_MAPPING" ]; then
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + 1))
  fi
  if [ -n "$NOTIFICATION_PLAN" ]; then
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + 1))
  fi
  if [ -n "$ACCESS_PLAN" ]; then
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + 1))
  fi
  if [ -n "$ACCOUNTING_POSTING_MAPPING" ]; then
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + 2))
  fi
  if [ -n "$OPENING_CONTROL_MAPPING" ]; then
    OPENING_CONTROL_COUNT=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["controls"]))' "$WORK_DIR/opening-control-plan.json")
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + OPENING_CONTROL_COUNT))
  fi
  if [ -n "$TAX_FILING_MAPPING" ]; then
    TAX_FILING_COUNT=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["filings"]))' "$WORK_DIR/tax-filing-plan.json")
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + TAX_FILING_COUNT))
  fi
  if [ -n "$BANK_STATEMENT_MAPPING" ]; then
    BANK_STATEMENT_COUNT=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["statements"]))' "$WORK_DIR/bank-statement-plan.json")
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + BANK_STATEMENT_COUNT))
  fi
  if [ -n "$FINANCING_FACILITY_MAPPING" ]; then
    FINANCING_FACILITY_COUNT=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["facilities"]))' "$WORK_DIR/financing-facility-plan.json")
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + FINANCING_FACILITY_COUNT))
  fi
  if [ -n "$ASSET_LIFECYCLE_MAPPING" ]; then
    ASSET_LIFECYCLE_COUNT=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["assets"]))' "$WORK_DIR/asset-lifecycle-plan.json")
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + ASSET_LIFECYCLE_COUNT))
  fi
  if [ -n "$TREASURY_PLAN_DISPATCH_MAPPING" ]; then
    TREASURY_PLAN_DISPATCH_COUNT=$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print(len(p["cash_plans"]) + len(p["fund_dispatches"]))' "$WORK_DIR/treasury-plan-dispatch-plan.json")
    EXPECTED_PROJECTIONS=$((EXPECTED_PROJECTIONS + TREASURY_PLAN_DISPATCH_COUNT))
  fi
  if [ -n "$DELIVERY_RECOGNITION_ACCOUNTING_MAPPING" ]; then
    EXPECTED_LINKS=$((EXPECTED_LINKS + 1))
  fi
  if [ -n "$MAPPING_PATH" ] && [ -n "$ACCOUNTING_MAPPING" ] && [ -n "$ADVANCE_OFFSET_MAPPING" ]; then
    "$SCRIPT_DIR/company_migration_cutover_gate.py" "$WORK_DIR" "$CUTOVER_GATE" \
      --expected-raw 120 --expected-projections "$EXPECTED_PROJECTIONS" --expected-links "$EXPECTED_LINKS" || true
  else
    "$SCRIPT_DIR/company_migration_cutover_gate.py" "$WORK_DIR" "$CUTOVER_GATE" \
      --expected-raw 120 || true
  fi
  echo "cutover_gate=$CUTOVER_GATE"
fi

echo "work_dir=$WORK_DIR"
echo "target_db=$TARGET_DB"
