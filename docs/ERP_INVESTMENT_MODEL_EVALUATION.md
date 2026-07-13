# ERP Investment Model Evaluation Boundary

Recorded: 2026-07-13

The typed `tzsy_version` / `tzsy_plan_index` cohort still preserves every
source value representation. `investment/model` now adds an explicit evaluator
that classifies numeric, date-serial, missing, and unparsed values; checks
parent totals only when parent and children share a unit; and derives four
known basis-point ratios when both operands are explicit numeric values:
gross margin, net margin, tax-to-revenue, and cost-to-revenue.

`cmd/investment_model_eval` consumes the existing native investment promotion
receipt, evaluates the 26-index fixture, and emits a separate
`investment_model_evaluation` projection under a mapping-scoped
`:evaluation-v1` cohort. The projection records source snapshot and mapping
identity, values, parent checks, mismatches, issues, and derived metrics while
keeping `analytics_only=true`, `investment_execution_authorized=false`,
`position_mutated=false`, `accounting_posted=false`, and `cash_released=false`.

The typed-cohort runner applies, parity-checks, and replays this evaluation
receipt after the investment model receipt. It does not create positions,
mandates, cash, journals, or investment approvals. Unknown formula vocabulary,
unit conversions, and full investment accounting remain explicit future gates.
