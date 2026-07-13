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

The target also has a reviewed synthetic [marketing cohort](ERP_MARKETING_COHORT.md)
for campaign/placement lifecycle and channel/material catalog evidence. It
proves native behavior and durable parity without treating schema presence as
provider execution or budget consumption.
