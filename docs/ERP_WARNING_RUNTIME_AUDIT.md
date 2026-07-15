# ERP warning runtime audit

The Rabbita `/warning` and `/warning-rules` routes now consume an observed,
source-compatible PostgreSQL warning boundary:

- `/api/company/warning/badge`;
- `/api/company/warning`;
- `/api/company/warning/rules`;
- `/api/company/warning/scans`, `/custom-rules`, `/rule-templates`, and
  `/tickets/mine` as explicit empty-source reads.

The adapter evaluates the ERP's twelve built-in quality rules against imported
project, contract, payment-application, cost, task, loan, user, supplier, and
expense envelopes. Findings are deterministic observations with source IDs;
the response carries source coverage, `persisted=false`, and
`authorizing=false`. Imported findings remain read-only, while resolve/ignore
actions write only a command-owned `warning_state` overlay, idempotency receipt,
and audit event; built-in rule enable/disable writes a separate
`warning_rule_config` candidate with the same replay/audit guarantees. These
commands do not create `sys_warning` rows, run scans, send notifications, or
create/modify tickets.

In the controlled export, one W005 observation is present: a project lacks an
imported dynamic-cost end subject. Workflow, supplier, expense, and warning
storage tables are absent, so those dimensions remain explicit empty coverage.
The designer warning table remains only a transport-failure fallback. Scans,
custom rules, tickets, notification delivery, production identity, and owner
acceptance remain separate gates.

Bounded command paths:

- `POST /api/company/warning/:guid/resolve`
- `POST /api/company/warning/:guid/ignore`
- `PATCH /api/company/warning/rules/:code` (and `/api/company/source` alias)
