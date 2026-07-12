# ERP Cost-Investment Schema Cohort

Recorded: 2026-07-13  
Source wave: `cost-investment` from `../erp/erp_new/server/src/db/index.js`

The third schema-only wave now has explicit ownership for nine tables covering
CBS rules, subject dictionaries, plan versions, change applications, and
Moonfish-related model/import structures.

The mapping preserves an important boundary: CBS and investment model records
may be imported as governed configuration or evidence, but they do not consume
budget, post accounting, execute formulas, or execute investments merely by
being present. Spreadsheet/import data requires hashes and provenance; formula
semantics, accounting meaning, and approval remain native target decisions.

The machine-readable mapping is
`scripts/fixtures/schema_cost_investment_mapping.json`; each rehearsal emits
`schema-cost-investment.json` with nine mapped tables, zero available rows, and
`promotion_authorized=false`.
