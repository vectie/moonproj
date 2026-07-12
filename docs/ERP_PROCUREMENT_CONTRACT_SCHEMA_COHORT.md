# ERP Procurement-Contract Schema Cohort

Recorded: 2026-07-13  
Source wave: `procurement-contract` from `../erp/erp_new/server/src/db/index.js`

The fourth schema-only wave maps supplier master/scope, categories, tender
plans and awards, contract splits, and contract milestones to the existing
procurement, contract, and commitment boundaries.

The mapping deliberately keeps these effects separate:

- supplier qualification is not inferred from contact or registration fields;
- tender awards do not create commitments, payables, or payments implicitly;
- contract splits require parent identity and amount/percentage reconciliation;
- milestones remain planned/actual evidence until a local reached transition;
- payment eligibility requires a reached milestone and separate authority.

The machine-readable mapping is
`scripts/fixtures/schema_procurement_contract_mapping.json`; each rehearsal
emits `schema-procurement-contract.json` with seven mapped tables, zero
available rows, and `promotion_authorized=false`.
