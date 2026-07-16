#!/bin/sh
set -eu

# Promote typed ERP cohorts through the native domain boundary, then persist
# each receipt as a separately versioned SQLite projection and require exact
# source/target parity. The target database must already contain the raw
# rehearsal schema; this script never writes to the source ERP.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
EXPORT_DIR=${1:?usage: erp_typed_cohort_rehearsal.sh EXPORT_DIR MAPPING TARGET_DB WORK_DIR}
MAPPING_PATH=${2:?usage: erp_typed_cohort_rehearsal.sh EXPORT_DIR MAPPING TARGET_DB WORK_DIR}
TARGET_DB=${3:?usage: erp_typed_cohort_rehearsal.sh EXPORT_DIR MAPPING TARGET_DB WORK_DIR}
WORK_DIR=${4:-/tmp/moonproj-typed-cohort-rehearsal}

mkdir -p "$WORK_DIR"

run_cohort() {
  label=$1
  planner=$2
  variant="$WORK_DIR/$label-mapping.json"
  plan="$WORK_DIR/$label-plan.json"
  receipt="$WORK_DIR/$label-promotion.json"
  apply="$WORK_DIR/$label-projection-apply.json"
  parity="$WORK_DIR/$label-projection-parity.json"

  "$SCRIPT_DIR/erp_mapping_variant.sh" \
    "$MAPPING_PATH" "$variant" "erp-typed-$label-v1-review-001" >/dev/null
  "$SCRIPT_DIR/$planner" "$EXPORT_DIR" "$variant" "$plan"
  echo "${label}_plan=$plan"
  moon run --target native cmd/promote -- "$plan" "$receipt"
  echo "${label}_promotion=$receipt"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$receipt" "$TARGET_DB" > "$apply"
  echo "${label}_projection_apply=$apply"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" "$receipt" "$TARGET_DB" "$parity"
  echo "${label}_projection_parity=$parity"
  replay="$WORK_DIR/$label-projection-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$receipt" "$TARGET_DB" > "$replay"
  echo "${label}_projection_replay=$replay"
}

run_cohort workflow erp_workflow_promotion_plan.sh
run_cohort lifecycle erp_lifecycle_promotion_plan.sh
run_cohort task-structure erp_task_promotion_plan.sh

run_task_state_clean() {
  label=task-state-project2
  variant="$WORK_DIR/$label-mapping.json"
  plan="$WORK_DIR/$label-plan.json"
  receipt="$WORK_DIR/$label-promotion.json"
  apply="$WORK_DIR/$label-projection-apply.json"
  parity="$WORK_DIR/$label-projection-parity.json"

  "$SCRIPT_DIR/erp_mapping_variant.sh" \
    "$MAPPING_PATH" "$variant" "erp-typed-task-state-project2-v1-review-001" >/dev/null
  "$SCRIPT_DIR/erp_task_state_promotion_plan.sh" \
    "$EXPORT_DIR" "$variant" "$plan" --project-id proj-0002
  echo "${label}_plan=$plan"
  moon run --target native cmd/promote -- "$plan" "$receipt"
  echo "${label}_promotion=$receipt"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$receipt" "$TARGET_DB" > "$apply"
  echo "${label}_projection_apply=$apply"
  "$SCRIPT_DIR/company_sqlite_projection_parity.py" "$receipt" "$TARGET_DB" "$parity"
  echo "${label}_projection_parity=$parity"
  replay="$WORK_DIR/$label-projection-replay.json"
  "$SCRIPT_DIR/company_sqlite_projection_apply.py" "$receipt" "$TARGET_DB" > "$replay"
  echo "${label}_projection_replay=$replay"
}

run_task_state_clean

# Produce a review artifact for the full task-state cohort. The target task
# state remains untouched, but the undecided conflict is durably preserved as
# non-authorizing evidence so the migration does not lose the source context.
TASK_STATE_EVIDENCE_MAPPING="$WORK_DIR/task-state-exception-evidence-mapping.json"
  "$SCRIPT_DIR/erp_mapping_variant.sh" \
  "$MAPPING_PATH" "$TASK_STATE_EVIDENCE_MAPPING" \
  "erp-typed-task-state-exception-evidence-v1-review-001" >/dev/null
TASK_STATE_REVIEW_PLAN="$WORK_DIR/task-state-review-plan.json"
  "$SCRIPT_DIR/erp_task_state_promotion_plan.sh" \
  "$EXPORT_DIR" "$TASK_STATE_EVIDENCE_MAPPING" "$TASK_STATE_REVIEW_PLAN"
echo "task_state_review_plan=$TASK_STATE_REVIEW_PLAN"
TASK_STATE_EXCEPTION_REVIEW="$WORK_DIR/task-state-exception-review.json"
  "$SCRIPT_DIR/erp_task_state_exception_review.sh" \
  "$TASK_STATE_REVIEW_PLAN" "$TASK_STATE_EXCEPTION_REVIEW"
echo "task_state_exception_review=$TASK_STATE_EXCEPTION_REVIEW"
TASK_STATE_EVIDENCE_RECEIPT="$WORK_DIR/task-state-exception-evidence-promotion.json"
moon run --target native cmd/task_state_evidence -- \
  "$TASK_STATE_EXCEPTION_REVIEW" "$TASK_STATE_EVIDENCE_RECEIPT"
echo "task_state_exception_evidence_promotion=$TASK_STATE_EVIDENCE_RECEIPT"
TASK_STATE_EVIDENCE_APPLY="$WORK_DIR/task-state-exception-evidence-projection-apply.json"
"$SCRIPT_DIR/company_sqlite_projection_apply.py" \
  "$TASK_STATE_EVIDENCE_RECEIPT" "$TARGET_DB" > "$TASK_STATE_EVIDENCE_APPLY"
echo "task_state_exception_evidence_projection_apply=$TASK_STATE_EVIDENCE_APPLY"
TASK_STATE_EVIDENCE_PARITY="$WORK_DIR/task-state-exception-evidence-projection-parity.json"
"$SCRIPT_DIR/company_sqlite_projection_parity.py" \
  "$TASK_STATE_EVIDENCE_RECEIPT" "$TARGET_DB" "$TASK_STATE_EVIDENCE_PARITY"
echo "task_state_exception_evidence_projection_parity=$TASK_STATE_EVIDENCE_PARITY"
TASK_STATE_EVIDENCE_REPLAY="$WORK_DIR/task-state-exception-evidence-projection-replay.json"
"$SCRIPT_DIR/company_sqlite_projection_apply.py" \
  "$TASK_STATE_EVIDENCE_RECEIPT" "$TARGET_DB" > "$TASK_STATE_EVIDENCE_REPLAY"
echo "task_state_exception_evidence_projection_replay=$TASK_STATE_EVIDENCE_REPLAY"

run_cohort evidence erp_typed_evidence_promotion_plan.sh
run_cohort investment erp_investment_promotion_plan.py

INVESTMENT_EVALUATION_RECEIPT="$WORK_DIR/investment-evaluation-promotion.json"
moon run --target native cmd/investment_model_eval -- \
  "$WORK_DIR/investment-promotion.json" "$INVESTMENT_EVALUATION_RECEIPT"
echo "investment_evaluation_promotion=$INVESTMENT_EVALUATION_RECEIPT"
INVESTMENT_EVALUATION_APPLY="$WORK_DIR/investment-evaluation-projection-apply.json"
"$SCRIPT_DIR/company_sqlite_projection_apply.py" \
  "$INVESTMENT_EVALUATION_RECEIPT" "$TARGET_DB" > "$INVESTMENT_EVALUATION_APPLY"
echo "investment_evaluation_projection_apply=$INVESTMENT_EVALUATION_APPLY"
INVESTMENT_EVALUATION_PARITY="$WORK_DIR/investment-evaluation-projection-parity.json"
"$SCRIPT_DIR/company_sqlite_projection_parity.py" \
  "$INVESTMENT_EVALUATION_RECEIPT" "$TARGET_DB" "$INVESTMENT_EVALUATION_PARITY"
echo "investment_evaluation_projection_parity=$INVESTMENT_EVALUATION_PARITY"
INVESTMENT_EVALUATION_REPLAY="$WORK_DIR/investment-evaluation-projection-replay.json"
"$SCRIPT_DIR/company_sqlite_projection_apply.py" \
  "$INVESTMENT_EVALUATION_RECEIPT" "$TARGET_DB" > "$INVESTMENT_EVALUATION_REPLAY"
echo "investment_evaluation_projection_replay=$INVESTMENT_EVALUATION_REPLAY"

run_cohort payment erp_payment_promotion_plan.py
run_cohort users erp_user_promotion_plan.sh
run_cohort audit erp_audit_promotion_plan.sh
run_cohort parameter erp_parameter_promotion_plan.py

echo "typed_cohort_work_dir=$WORK_DIR"
