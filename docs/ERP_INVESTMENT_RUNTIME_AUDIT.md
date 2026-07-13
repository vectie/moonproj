# ERP Investment Runtime Audit

Recorded: 2026-07-13  
Source: `../erp/erp_new`  
Target: this repository

## Finding

The source investment route exposes feasibility versions, grouped plan indices,
profit summary values, and dimension metadata. The available credential-safe
export contains one current version for `proj-0001` and 26 indices across five
dimensions: key points, tax, financing, investment, and carry-over.

The target now exposes source-compatible read boundaries:

| Source surface | Target endpoint | Target state |
|---|---|---|
| Project versions | `/api/company/investment/projects/:id/versions` | source-compatible read |
| Version indices | `/api/company/investment/versions/:id/indices` | source-compatible read |
| Profit summary | `/api/company/investment/projects/:id/profit-summary` | source-compatible read |
| Dimension metadata | `/api/company/investment/meta/dimensions` | source-compatible read |

Rows preserve source field names and are marked `sourceKind=imported`. No Excel
import, version creation/activation, index update, valuation, cash movement,
or accounting posting is enabled by this slice.

## Evidence

- PostgreSQL service smoke returns one current version, 26 grouped indices,
  five dimension groups, and the source profit summary (`revenue=18500`,
  `netProfit=2890`, `irr=14.8`).
- The parity matrix marks the four source investment GET handlers as
  `connected_investment_read`.
- Existing native investment valuation, performance, and benchmark boundaries
  remain separate reviewed analytics gates; they do not authorize source-row
  ownership or cash/accounting effects.

## Remaining gate

1. Bind the reads to the full investment browser scenario and production
   identity, including project scope and version ownership.
2. Obtain the missing investment/source export rows and owner-approved model
   semantics before accepting imported values as target-owned.
3. Keep Excel import, activation, index mutation, valuation, cash release,
   accounting, tax, and period-close actions separately authorized.
