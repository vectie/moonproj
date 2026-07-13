#!/bin/sh
set -eu

# Run the reviewed typed ERP cohorts through both the deterministic SQLite
# rehearsal and the PostgreSQL target adapters.  The source export is read
# only; the PostgreSQL target is selected explicitly by its connection flags.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
USAGE="usage: company_postgres_cohort_rehearsal.sh EXPORT_DIR MAPPING RAW_STAGING [PGDATABASE] [WORK_DIR] [CBS_MAPPING] [WORKFLOW_ASSIGNMENT_MAPPING] [DELIVERY_MAPPING] [ADVANCE_OFFSET_MAPPING] [PAYMENT_ACCOUNTING_MAPPING] [OFFSET_ACCOUNTING_MAPPING] [DELIVERY_RECOGNITION_MAPPING] [DELIVERY_RECOGNITION_ACCOUNTING_MAPPING] [CONSOLIDATED_REPORT_PLAN] [INVESTMENT_BENCHMARK_PLAN] [WARNING_PLAN] [CBS_BUDGET_PLAN] [CBS_BUDGET_SOURCE_MAPPING] [WARNING_SOURCE_MAPPING] [BASE_ACCOUNTING_MAPPING] [NOTIFICATION_PLAN] [ACCESS_PLAN] [ACCOUNTING_POSTING_MAPPING] [OPENING_CONTROL_MAPPING] [TAX_FILING_MAPPING] [BANK_STATEMENT_MAPPING]"
EXPORT_DIR=${1:?$USAGE}
MAPPING_PATH=${2:?$USAGE}
STAGING_PATH=${3:?$USAGE}
PG_DATABASE=${4:-${PGDATABASE:-moonproj}}
WORK_DIR=${5:-/tmp/moonproj-postgres-cohort-rehearsal}
CBS_COST_MAPPING=${6:-}
WORKFLOW_ASSIGNMENT_MAPPING=${7:-}
DELIVERY_PROGRESS_MAPPING=${8:-}
ADVANCE_OFFSET_MAPPING=${9:-}
PAYMENT_ACCOUNTING_MAPPING=${10:-}
OFFSET_ACCOUNTING_MAPPING=${11:-$SCRIPT_DIR/fixtures/accounting_offset_link_mapping.json}
DELIVERY_RECOGNITION_MAPPING=${12:-}
DELIVERY_RECOGNITION_ACCOUNTING_MAPPING=${13:-}
CONSOLIDATED_REPORT_PLAN=${14:-}
INVESTMENT_BENCHMARK_PLAN=${15:-}
WARNING_PLAN=${16:-}
CBS_BUDGET_PLAN=${17:-}
CBS_BUDGET_SOURCE_MAPPING=${18:-}
WARNING_SOURCE_MAPPING=${19:-}
BASE_ACCOUNTING_MAPPING=${20:-}
NOTIFICATION_PLAN=${21:-}
ACCESS_PLAN=${22:-}
ACCOUNTING_POSTING_MAPPING=${23:-}
OPENING_CONTROL_MAPPING=${24:-}
TAX_FILING_MAPPING=${25:-}
BANK_STATEMENT_MAPPING=${26:-}
PG_HOST=${PGHOST:-/tmp}
PG_PORT=${PGPORT:-5432}
PG_USER=${PGUSER:-moonproj}

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
if [ -n "$ACCOUNTING_POSTING_MAPPING" ] && [ -z "$BASE_ACCOUNTING_MAPPING" ]; then
  echo "accounting posting mapping requires the base accounting mapping" >&2
  exit 2
fi

SQLITE_DB="$WORK_DIR/company.sqlite3"
TYPED_WORK_DIR="$WORK_DIR/typed-cohorts"
mkdir -p "$WORK_DIR"

# Keep the SQLite rehearsal isolated to this run while using the same staged
# source envelope that is sent to PostgreSQL.
rm -f "$SQLITE_DB" "$SQLITE_DB.pending"
"$SCRIPT_DIR/company_sqlite_rehearsal.py" "$STAGING_PATH" "$SQLITE_DB" > "$WORK_DIR/sqlite-raw-apply.json"
python3 "$SCRIPT_DIR/company_postgres_target_apply.py" \
  "$STAGING_PATH" --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
  --database "$PG_DATABASE" > "$WORK_DIR/postgres-raw-apply.json"

"$SCRIPT_DIR/erp_typed_cohort_rehearsal.sh" \
  "$EXPORT_DIR" "$MAPPING_PATH" "$SQLITE_DB" "$TYPED_WORK_DIR" > "$WORK_DIR/typed-cohort.log"

"$SCRIPT_DIR/erp_promotion_plan.py" \
  "$EXPORT_DIR" "$MAPPING_PATH" "$WORK_DIR/promotion-plan.json"
moon run --target native cmd/promote -- \
  "$WORK_DIR/promotion-plan.json" "$WORK_DIR/domain-promotion.json"
python3 "$SCRIPT_DIR/company_postgres_projection_apply.py" \
  "$WORK_DIR/domain-promotion.json" \
  --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
  --database "$PG_DATABASE" > "$WORK_DIR/base-projection-apply.json"
python3 "$SCRIPT_DIR/company_postgres_projection_parity.py" \
  "$WORK_DIR/domain-promotion.json" "$WORK_DIR/base-projection-parity.json" \
  --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
  --database "$PG_DATABASE"
python3 "$SCRIPT_DIR/company_postgres_projection_apply.py" \
  "$WORK_DIR/domain-promotion.json" \
  --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
  --database "$PG_DATABASE" > "$WORK_DIR/base-projection-replay.json"

apply_projection() {
  label=$1
  receipt=$2
  receipt="$TYPED_WORK_DIR/$label-promotion.json"
  if [ "$2" != "" ]; then
    receipt=$2
  fi
  apply="$WORK_DIR/$label-postgres-apply.json"
  parity="$WORK_DIR/$label-postgres-parity.json"
  replay="$WORK_DIR/$label-postgres-replay.json"
  python3 "$SCRIPT_DIR/company_postgres_projection_apply.py" "$receipt" \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" > "$apply"
  python3 "$SCRIPT_DIR/company_postgres_projection_parity.py" "$receipt" "$parity" \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE"
  python3 "$SCRIPT_DIR/company_postgres_projection_apply.py" "$receipt" \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" > "$replay"
}

apply_accounting() {
  label=$1
  receipt=$2
  apply="$WORK_DIR/$label-postgres-apply.json"
  replay="$WORK_DIR/$label-postgres-replay.json"
  python3 "$SCRIPT_DIR/company_postgres_accounting_link_apply.py" "$receipt" \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" > "$apply"
  python3 "$SCRIPT_DIR/company_postgres_accounting_link_apply.py" "$receipt" \
    --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" --database "$PG_DATABASE" > "$replay"
}

if [ -n "$BASE_ACCOUNTING_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_accounting_link_plan.py" \
    "$WORK_DIR/domain-promotion.json" "$BASE_ACCOUNTING_MAPPING" \
    "$WORK_DIR/base-accounting-link-plan.json"
  moon run --target native cmd/accounting_link -- \
    "$WORK_DIR/base-accounting-link-plan.json" \
    "$WORK_DIR/base-accounting-link-receipt.json"
  apply_accounting base-accounting "$WORK_DIR/base-accounting-link-receipt.json"
  if [ -n "$ACCOUNTING_POSTING_MAPPING" ]; then
    python3 "$SCRIPT_DIR/erp_accounting_post_plan.py" \
      "$WORK_DIR/base-accounting-link-plan.json" \
      "$WORK_DIR/base-accounting-link-receipt.json" \
      "$ACCOUNTING_POSTING_MAPPING" "$WORK_DIR/accounting-posting-plan.json"
    moon run --target native cmd/accounting_post -- \
      "$WORK_DIR/accounting-posting-plan.json" \
      "$WORK_DIR/accounting-posting-receipt.json"
    apply_projection accounting-posting "$WORK_DIR/accounting-posting-receipt.json"
  fi
fi

for label in workflow lifecycle task-structure task-state-project2 evidence investment payment users audit parameter
do
  apply_projection "$label" ""
done

if [ -f "$TYPED_WORK_DIR/investment-evaluation-promotion.json" ]; then
  apply_projection investment-evaluation \
    "$TYPED_WORK_DIR/investment-evaluation-promotion.json"
fi

if [ -n "$CBS_COST_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_cbs_cost_link_plan.py" "$EXPORT_DIR" "$CBS_COST_MAPPING" "$WORK_DIR/cbs-cost-plan.json"
  moon run --target native cmd/cbs_link -- "$WORK_DIR/cbs-cost-plan.json" "$WORK_DIR/cbs-cost-receipt.json"
  apply_projection cbs-cost "$WORK_DIR/cbs-cost-receipt.json"
fi

if [ -n "$CBS_BUDGET_PLAN" ]; then
  moon run --target native cmd/cbs_budget -- \
    "$CBS_BUDGET_PLAN" "$WORK_DIR/cbs-budget-receipt.json"
  apply_projection cbs-budget "$WORK_DIR/cbs-budget-receipt.json"
fi

if [ -n "$CBS_BUDGET_SOURCE_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_cbs_budget_plan.py" \
    "$EXPORT_DIR" "$CBS_COST_MAPPING" "$CBS_BUDGET_SOURCE_MAPPING" \
    "$WORK_DIR/cbs-budget-source-plan.json"
  moon run --target native cmd/cbs_budget -- \
    "$WORK_DIR/cbs-budget-source-plan.json" \
    "$WORK_DIR/cbs-budget-source-receipt.json"
  apply_projection cbs-budget-source "$WORK_DIR/cbs-budget-source-receipt.json"
fi

if [ -n "$WORKFLOW_ASSIGNMENT_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_workflow_assignment_plan.py" "$EXPORT_DIR" "$WORKFLOW_ASSIGNMENT_MAPPING" "$WORK_DIR/workflow-assignment-plan.json"
  moon run --target native cmd/workflow_assignment -- "$WORK_DIR/workflow-assignment-plan.json" "$WORK_DIR/workflow-assignment-receipt.json"
  apply_projection workflow-assignment "$WORK_DIR/workflow-assignment-receipt.json"
fi

if [ -n "$DELIVERY_PROGRESS_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_delivery_progress_plan.py" "$EXPORT_DIR" "$DELIVERY_PROGRESS_MAPPING" "$WORK_DIR/delivery-progress-plan.json"
  moon run --target native cmd/delivery_progress -- "$WORK_DIR/delivery-progress-plan.json" "$WORK_DIR/delivery-progress-receipt.json"
  apply_projection delivery-progress "$WORK_DIR/delivery-progress-receipt.json"
fi

if [ -n "$DELIVERY_RECOGNITION_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_delivery_recognition_plan.py" \
    "$EXPORT_DIR" "$DELIVERY_RECOGNITION_MAPPING" \
    "$WORK_DIR/delivery-recognition-plan.json"
  moon run --target native cmd/delivery_recognition -- \
    "$WORK_DIR/delivery-recognition-plan.json" \
    "$WORK_DIR/delivery-recognition-receipt.json"
  apply_projection delivery-recognition "$WORK_DIR/delivery-recognition-receipt.json"
  if [ -n "$DELIVERY_RECOGNITION_ACCOUNTING_MAPPING" ]; then
    python3 "$SCRIPT_DIR/erp_accounting_link_plan.py" \
      "$WORK_DIR/delivery-recognition-receipt.json" \
      "$DELIVERY_RECOGNITION_ACCOUNTING_MAPPING" \
      "$WORK_DIR/delivery-recognition-accounting-plan.json"
    moon run --target native cmd/accounting_link -- \
      "$WORK_DIR/delivery-recognition-accounting-plan.json" \
      "$WORK_DIR/delivery-recognition-accounting-receipt.json"
    apply_accounting delivery-recognition-accounting \
      "$WORK_DIR/delivery-recognition-accounting-receipt.json"
  fi
fi

if [ -n "$CONSOLIDATED_REPORT_PLAN" ]; then
  moon run --target native cmd/consolidated_report -- \
    "$CONSOLIDATED_REPORT_PLAN" "$WORK_DIR/consolidated-report-receipt.json"
  apply_projection consolidated-report "$WORK_DIR/consolidated-report-receipt.json"
fi

if [ -n "$INVESTMENT_BENCHMARK_PLAN" ]; then
  moon run --target native cmd/investment_benchmark -- \
    "$INVESTMENT_BENCHMARK_PLAN" "$WORK_DIR/investment-benchmark-receipt.json"
  apply_projection investment-benchmark \
    "$WORK_DIR/investment-benchmark-receipt.json"
fi

if [ -n "$WARNING_PLAN" ]; then
  moon run --target native cmd/warning -- \
    "$WARNING_PLAN" "$WORK_DIR/warning-receipt.json"
  apply_projection warning "$WORK_DIR/warning-receipt.json"
fi

if [ -n "$WARNING_SOURCE_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_warning_plan.py" \
    "$EXPORT_DIR" "$WARNING_SOURCE_MAPPING" \
    "$WORK_DIR/warning-source-plan.json"
  moon run --target native cmd/warning -- \
    "$WORK_DIR/warning-source-plan.json" \
    "$WORK_DIR/warning-source-receipt.json"
  apply_projection warning-source "$WORK_DIR/warning-source-receipt.json"
fi

if [ -n "$NOTIFICATION_PLAN" ]; then
  moon run --target native cmd/notification -- \
    "$NOTIFICATION_PLAN" "$WORK_DIR/notification-receipt.json"
  apply_projection notification "$WORK_DIR/notification-receipt.json"
fi

if [ -n "$ACCESS_PLAN" ]; then
  moon run --target native cmd/access_import -- \
    "$ACCESS_PLAN" "$WORK_DIR/access-receipt.json"
  apply_projection access "$WORK_DIR/access-receipt.json"
fi

if [ -n "$ADVANCE_OFFSET_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_advance_offset_promotion_plan.py" "$EXPORT_DIR" "$ADVANCE_OFFSET_MAPPING" "$WORK_DIR/advance-offset-plan.json"
  moon run --target native cmd/promote -- "$WORK_DIR/advance-offset-plan.json" "$WORK_DIR/advance-offset-promotion.json"
  apply_projection advance-offset "$WORK_DIR/advance-offset-promotion.json"
  python3 "$SCRIPT_DIR/erp_accounting_link_plan.py" "$WORK_DIR/advance-offset-promotion.json" "$OFFSET_ACCOUNTING_MAPPING" "$WORK_DIR/advance-offset-accounting-plan.json"
  moon run --target native cmd/accounting_link -- "$WORK_DIR/advance-offset-accounting-plan.json" "$WORK_DIR/advance-offset-accounting-receipt.json"
  apply_accounting advance-offset-accounting "$WORK_DIR/advance-offset-accounting-receipt.json"
fi

if [ -n "$PAYMENT_ACCOUNTING_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_accounting_link_plan.py" "$TYPED_WORK_DIR/payment-promotion.json" "$PAYMENT_ACCOUNTING_MAPPING" "$WORK_DIR/payment-accounting-plan.json"
  moon run --target native cmd/accounting_link -- "$WORK_DIR/payment-accounting-plan.json" "$WORK_DIR/payment-accounting-receipt.json"
  apply_accounting payment-accounting "$WORK_DIR/payment-accounting-receipt.json"
fi

if [ -n "$OPENING_CONTROL_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_opening_control_plan.py" \
    "$OPENING_CONTROL_MAPPING" "$WORK_DIR/opening-control-plan.json"
  moon run --target native cmd/opening_control -- \
    "$WORK_DIR/opening-control-plan.json" "$WORK_DIR/opening-control-receipt.json"
  apply_projection opening-control "$WORK_DIR/opening-control-receipt.json"
  python3 "$SCRIPT_DIR/company_opening_control_parity.py" \
    "$WORK_DIR/opening-control-receipt.json" \
    "$WORK_DIR/opening-control-postgres-exact-parity.json" \
    --backend postgres --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
    --database "$PG_DATABASE"
fi

if [ -n "$TAX_FILING_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_tax_filing_plan.py" \
    "$TAX_FILING_MAPPING" "$WORK_DIR/tax-filing-plan.json"
  moon run --target native cmd/tax_filing -- \
    "$WORK_DIR/tax-filing-plan.json" "$WORK_DIR/tax-filing-receipt.json"
  apply_projection tax-filing "$WORK_DIR/tax-filing-receipt.json"
  python3 "$SCRIPT_DIR/company_tax_filing_parity.py" \
    "$WORK_DIR/tax-filing-receipt.json" \
    "$WORK_DIR/tax-filing-postgres-exact-parity.json" \
    --backend postgres --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
    --database "$PG_DATABASE"
fi

if [ -n "$BANK_STATEMENT_MAPPING" ]; then
  python3 "$SCRIPT_DIR/erp_bank_statement_plan.py" \
    "$BANK_STATEMENT_MAPPING" "$WORK_DIR/bank-statement-plan.json"
  moon run --target native cmd/bank_statement -- \
    "$WORK_DIR/bank-statement-plan.json" "$WORK_DIR/bank-statement-receipt.json"
  apply_projection bank-statement "$WORK_DIR/bank-statement-receipt.json"
  python3 "$SCRIPT_DIR/company_bank_statement_parity.py" \
    "$WORK_DIR/bank-statement-receipt.json" \
    "$WORK_DIR/bank-statement-postgres-exact-parity.json" \
    --backend postgres --host "$PG_HOST" --port "$PG_PORT" --user "$PG_USER" \
    --database "$PG_DATABASE"
fi

echo "postgres_target=$PG_DATABASE"
echo "work_dir=$WORK_DIR"
echo "typed_work_dir=$TYPED_WORK_DIR"
