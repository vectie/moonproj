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
`warning_rule_config` candidate, and custom-rule create/delete writes a
`warning_custom_rule` candidate with the same replay/audit guarantees. Warning
to-ticket writes a command-owned `warning_ticket` candidate and `/tickets/mine`
merges imported and local ticket rows with assignee filtering. Custom
SQL is validated as a single read-only SELECT/WITH statement and retained only
as a digest. These commands do not create `sys_warning` rows, run provider
scans, send notifications, or invoke external ticket/notification providers.
Ticket status, reassignment, and due-date extension now append local ticket
revisions with actor/owner checks and replay receipts; completing a local
ticket also appends the warning-state resolution overlay.
The signed `/scan` path
is a deterministic dry-run preview that returns rule/finding totals and source
coverage without persisting findings or dispatching notifications.
The signed `/custom-rules/preview` path now validates the source SQL shape and
returns a deterministic empty result with its digest; it never executes SQL,
persists a rule, or creates a warning/provider effect.

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
- `POST/DELETE /api/company/warning/custom-rules[/:code]` (and `/source` aliases)
- `POST /api/company/warning/custom-rules/preview` (dry-run; and `/source` alias)
- `POST /api/company/warning/scan` (dry-run; and `/source` alias)
- `POST /api/company/warning/:guid/to-ticket` (and `/api/company/source` alias)
- `GET /api/company/warning/tickets/mine` (and `/api/company/source` alias)
- `PATCH /api/company/warning/tickets/:id/{status,reassign,extend}` (and
  `/api/company/source` aliases)
