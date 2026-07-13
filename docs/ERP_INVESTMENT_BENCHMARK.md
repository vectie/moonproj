# ERP Investment Benchmark Reconciliation

Recorded: 2026-07-13

`investment/portfolio` now separates a local performance comparison from an
external benchmark observation. An observation is accepted only with a stable
observation ID, benchmark and period identity, source snapshot, mapping
version, and evidence ID. The comparison can then be reconciled with an
explicit basis-point tolerance; differences are retained instead of being
silently rounded away.

`cmd/investment_benchmark` consumes the reviewed plan format
`moonproj.company.investment-benchmark-reconciliation-plan.v1` and emits a
normal domain-promotion receipt. The resulting
`investment_benchmark_reconciliation` projection is analytics evidence only:
it records the observed return, comparison return, active return, difference,
tolerance, and reconciliation state while explicitly keeping
`position_mutated=false`, `accounting_posted=false`, and
`cash_released=false`.

This boundary does not infer benchmark values from portfolio quotes, create a
position, post a journal, or release cash. A source feed, reviewed mapping,
and owner acceptance are still required before a real ERP benchmark cohort can
be supplied; synthetic plans are appropriate only for migration rehearsal.

The eighteenth argument to `scripts/erp_migration_rehearsal.sh`, or the
fifteenth argument to `scripts/company_postgres_cohort_rehearsal.sh`, supplies
the reviewed plan. Both wrappers apply the receipt through their normal
projection parity and idempotent replay checks.
