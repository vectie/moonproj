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

The separate reviewed [contract milestone and settlement cohort](ERP_CONTRACT_MILESTONE_COHORT.md)
uses the same source-table boundary to prove a performed commitment, a
reached progress milestone, and a milestone-linked requested settlement. It
does not turn a payment application into an approval, release, cash movement,
or accounting posting.

Employee expense and advance-offset behavior is documented separately in
[ERP_EXPENSE_ADVANCE_COHORT.md](ERP_EXPENSE_ADVANCE_COHORT.md); it is not
implicitly created by a contract award or payment application.
