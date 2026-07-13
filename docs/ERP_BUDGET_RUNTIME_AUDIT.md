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

Each response preserves source field names (`code`, `name`, and `guid` where
applicable) and marks rows `sourceKind=imported`. No dictionary or expense
mutation is enabled by this slice.

## Evidence

- PostgreSQL service smoke returns five cost-subject rows ordered by source
  `display_order` and three proceedings ordered by source code.
- The parity matrix marks the source budget `GET /dict/cost-subjects` and
  `GET /proceedings` handlers as `connected_budget_read`.
- Expense create/update/approval, budget checks, user-scope reads, and browser
  form binding remain separate boundaries.

## Remaining gate

1. Bind the dictionaries to the full expense create/detail browser scenario
   through production identity and company scope.
2. Connect expense list/detail and budget-check reads only after the source
   export and authority mapping are complete.
3. Obtain finance-owner acceptance before allowing dictionary or expense writes.
