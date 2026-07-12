# ERP Workflow-Control Schema Cohort

Recorded: 2026-07-13  
Source wave: `workflow-control` from `../erp/erp_new/server/src/db/index.js`

The second schema-only wave now has an explicit target and security mapping for
approval rules, runtime assignees, warnings, scans, subscriptions, custom
warning rules, and remediation tickets. The current snapshot contains no rows
for these tables, so the mapping is readiness evidence only.

Important boundaries:

- runtime assignees do not grant permissions or approve workflow instances;
- warning scans and subscriptions are evidence/notification state, not
  accounting or authority state;
- custom SQL templates are never executed implicitly during import;
- warning resolution and ticket transitions require local authority;
- every future row import requires identity, principal, scope, parity, replay,
  and named business acceptance.

The machine-readable mapping is
`scripts/fixtures/schema_workflow_control_mapping.json`; each rehearsal emits
`schema-workflow-control.json` with seven mapped tables, zero available rows,
and `promotion_authorized=false`.
