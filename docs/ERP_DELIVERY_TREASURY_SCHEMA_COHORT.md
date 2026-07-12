# ERP Delivery-Treasury Schema Cohort

Recorded: 2026-07-13  
Source wave: `delivery-treasury` from `../erp/erp_new/server/src/db/index.js`

The sixth schema-only wave maps project progress/outputs, treasury plans and
dispatches, and marketing campaigns, channels, materials, and placements.

The target keeps operational and economic effects separate: progress and output
records require evidence and acceptance; treasury plans do not move cash;
dispatches require source/target scope and release authority; marketing plans
and placements do not spend budget merely through import.

The machine-readable mapping is
`scripts/fixtures/schema_delivery_treasury_mapping.json`; each rehearsal emits
`schema-delivery-treasury.json` with eight mapped tables, zero available rows,
and `promotion_authorized=false`.
