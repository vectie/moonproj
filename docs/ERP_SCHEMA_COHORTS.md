# ERP Schema-Only Cohort Plan

Recorded: 2026-07-13  
Source: `../erp/erp_new/server/src/db/index.js`  
Scope: 49 tables defined by the ERP but absent from the available snapshot

The fixture is not the complete ERP database. The schema-cohort planner turns
the 49 absent tables into seven ordered migration waves with capability IDs,
security actions, declared schema references, and explicit prerequisites. It
does not invent rows or treat schema presence as migration success.

## Waves

1. `foundation-security`: attachments, parameters, preferences, roles, and
   credential-history review.
2. `workflow-control`: approval rules, runtime assignees, warnings, scans,
   subscriptions, and warning tickets.
3. `cost-investment`: CBS versions/subjects, R/R0 rules, cost changes, and
   spreadsheet/model import structures.
4. `procurement-contract`: suppliers, categories, tender plans/awards,
   contract splits, and contract milestones.
5. `sales-receivables`: customers, subscriptions, sales contracts, mortgages,
   refunds, revenue, and inbound/outbound invoices.
6. `delivery-treasury`: project progress/outputs, fund plans/dispatch, and
   marketing campaigns, channels, materials, and placements.
7. `reporting-notification`: report templates, share links, messages, and
   email outbox controls.

The machine-readable artifact is emitted by
`scripts/erp_schema_cohort_plan.py` as `schema-cohort-plan.json` during the
rehearsal. Every wave requires credential-safe export, relationship review,
explicit identity/principal mappings, a native domain importer, exact parity,
replay evidence, and business acceptance. Tokens, password history, file paths,
email/network data, and AI-extracted content require separate security and
retention review.

The plan is a scope gate, not a cutover authorization. The current gate remains
open until the absent tables are actually exported, translated, reconciled, and
accepted.

The first wave has a separate [foundation-security mapping](ERP_FOUNDATION_SECURITY_COHORT.md).
It is intentionally `mapped_scope_only` while the available snapshot contains
zero rows for all six tables.

The second wave has a separate
[workflow-control mapping](ERP_WORKFLOW_CONTROL_SCHEMA_COHORT.md). It is also
`mapped_scope_only` while the available snapshot contains zero rows for all
seven tables.

The fifth wave has a separate
[sales-receivables mapping](ERP_SALES_RECEIVABLES_SCHEMA_COHORT.md). It is
`mapped_scope_only` while the available snapshot contains zero rows for all
eight tables.

The target now also has a reviewed synthetic [sales lifecycle cohort](ERP_SALES_COHORT.md)
for the native customer, subscription, contract, mortgage, refund, receivable,
and revenue-evidence boundaries. It proves domain behavior and exact durable
parity without claiming that the absent production rows have been imported.

The sixth wave has a separate
[delivery-treasury mapping](ERP_DELIVERY_TREASURY_SCHEMA_COHORT.md). It is
`mapped_scope_only` while the available snapshot contains zero rows for all
eight tables.

The target also has a reviewed synthetic [marketing cohort](ERP_MARKETING_COHORT.md)
for the native campaign/placement boundary and catalog-only channel/material
evidence; it does not claim absent production marketing rows were imported.

The seventh wave has a separate
[reporting-notification mapping](ERP_REPORTING_NOTIFICATION_SCHEMA_COHORT.md).
It is `mapped_scope_only` while the available snapshot contains zero rows for
all four tables.

The third wave has a separate
[cost-investment mapping](ERP_COST_INVESTMENT_SCHEMA_COHORT.md). It is
`mapped_scope_only` while the available snapshot contains zero rows for all
nine tables.

The fourth wave has a separate
[procurement-contract mapping](ERP_PROCUREMENT_CONTRACT_SCHEMA_COHORT.md). It
is `mapped_scope_only` while the available snapshot contains zero rows for all
seven tables.

The target also has a reviewed [contract milestone and settlement cohort](ERP_CONTRACT_MILESTONE_COHORT.md)
for the performed-commitment, reached-milestone, and requested-settlement
state boundary. It is an executable lifecycle rehearsal, not a claim that the
incomplete source snapshot contains accepted production settlement rows.

The target also has a reviewed [employee expense and advance-offset cohort](ERP_EXPENSE_ADVANCE_COHORT.md)
for the advance, approved expense, and bounded offset relationship. The
available snapshot has no accepted expense rows, so this rehearsal does not
authorize production expense migration.
