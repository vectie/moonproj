# ERP Budget Dictionary Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The ERP expense form reads enabled cost-subject options and proceedings from
the budget route before a user can allocate an expense. The available
credential-safe export contains five enabled `cost_subject` options and three
enabled proceedings.

The target now exposes source-compatible read boundaries:

| Source surface | Target endpoint | Target state |
|---|---|---|
| Cost-subject dictionary | `/api/company/budget/dict/cost-subjects` | source-compatible read |
| Proceedings dictionary | `/api/company/budget/proceedings` | source-compatible read |
| Users in business-unit scope | `/api/company/source/budget/users-in-bu?buGuid=<guid>` | bounded source observation |
| Current user's approved loan balance | `/api/company/source/budget/my-loan-balance?userCode=<code>` | bounded source observation |
| Budget headroom preview | `/api/company/budget-check` | non-authorizing calculation-only read |
| Expense auto-offset | `/api/company/budget/expenses/:guid/auto-offset` | command-owned Draft writeback with FIFO loan plan |
| Workflow synchronization | `/api/company/budget/expenses/:guid/sync-from-workflow` | explicit 409 gate until workflow-engine source rows are imported |

Each response preserves source field names (`code`, `name`, and `guid` where
applicable) and marks rows `sourceKind=imported`. The budget-check response
preserves the source `matched`, `target`, `used`, `remain`, `willOver`, and
`overAmount` fields while explicitly returning `authorizing=false`,
`persisted=false`, and `budget_consumption=false`. No dictionary, reservation,
or imported-row mutation is enabled by this read slice. The local expense
command boundary separately supports a bounded auto-offset writeback.

The evidence-ready scope batch now also reads four enabled users under
`bu-tjgs-0001` and the imported `limingjin` balance of `3500.00` through the
source service/read-model adapter. Scope and balance responses carry coverage,
`scope_applied`, and `authorizing=false`; they do not grant a budget scope,
reserve funds, or mutate a loan. Rabbita renders this provenance on the expense
list and new-expense surfaces.

## Evidence

- PostgreSQL service smoke returns five cost-subject rows ordered by source
  `display_order` and three proceedings ordered by source code.
- `scripts/company_postgres_source_read_smoke.sh` verifies the four-user BU
  scope and 3,500.00 loan-balance read without mutations.
- The service and trusted-gateway smokes verify a matched `CB-101` budget
  preview and its non-authorizing/no-consumption markers without an
  idempotency receipt.
- The parity matrix marks the source budget `GET /dict/cost-subjects` and
  `GET /proceedings` handlers as `connected_budget_read`.
- Expense create/update/approval and auto-offset are covered by the native
  command boundary; the auto-offset smoke proves FIFO planning, replay,
  command-owned expense readback, and `loan_balance_effect=false`. The
  budget-check preview remains observation-only and does not grant authority.

## Remaining gate

1. Bind the dictionaries to the full expense create/detail browser scenario
   through production identity and company scope.
2. Accept the full expense create/detail and budget-check browser scenario
   through production identity and company scope.
3. Obtain finance-owner acceptance before allowing scope grants, reservations,
   dictionary writes, or expense writes.
