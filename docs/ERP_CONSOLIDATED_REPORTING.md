# Consolidated Reporting Evidence

Recorded: 2026-07-13

`finance/reporting` and `cmd/consolidated_report` provide a deterministic
control-total projection across already reconciled subreports. The plan binds
the report to one source snapshot, distinct mapping versions, a period,
principal, and exact report scope. Each section must be balanced and use the
same currency; duplicate sections, duplicate mapping versions, currency
mismatches, and unbalanced reports fail closed.

The resulting `consolidated_report` projection retains section totals,
accounting-link counts, and the overall difference. It explicitly records
`cash_released=false`, `period_posted=false`, and `tax_filed=false`. Creating a
report does not post a journal, release cash, file tax, or close a period.

The seventeenth argument to `scripts/erp_migration_rehearsal.sh`, or the
fourteenth argument to `scripts/company_postgres_cohort_rehearsal.sh`, may
supply a reviewed consolidated-report plan. The plan is passed through the
native command and exact projection/parity/replay adapters.
