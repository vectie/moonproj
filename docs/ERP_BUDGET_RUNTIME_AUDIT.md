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

Each response preserves source field names (`code`, `name`, and `guid` where
applicable) and marks rows `sourceKind=imported`. No dictionary or expense
mutation is enabled by this slice.

The evidence-ready scope batch now also reads four enabled users under
`bu-tjgs-0001` and the imported `limingjin` balance of `3500.00` through the
source service/read-model adapter. Scope and balance responses carry coverage,
`scope_applied`, and `authorizing=false`; they do not grant a budget scope,
reserve funds, or mutate a loan. Rabbita renders this provenance on the expense
list and new-expense surfaces.

## Evidence

- PostgreSQL service smoke returns five cost-subject rows ordered by source
  `display_order` and three proceedings ordered by source code.
- `scripts/company_postgres_source_read_smoke.py` verifies the four-user BU
  scope and 3,500.00 loan-balance read without mutations.
- The parity matrix marks the source budget `GET /dict/cost-subjects` and
  `GET /proceedings` handlers as `connected_budget_read`.
- Expense create/update/approval, budget checks, and browser form binding
  remain separate boundaries; the new user-scope read is observation-only and
  does not grant authority.

## Remaining gate

1. Bind the dictionaries to the full expense create/detail browser scenario
   through production identity and company scope.
2. Connect the full expense create/detail and budget-check browser scenario
   through production identity and company scope.
3. Obtain finance-owner acceptance before allowing scope grants, reservations,
   dictionary writes, or expense writes.
