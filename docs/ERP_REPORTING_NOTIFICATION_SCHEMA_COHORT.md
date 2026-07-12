# ERP Reporting-Notification Schema Cohort

Recorded: 2026-07-13  
Source wave: `reporting-notification` from `../erp/erp_new/server/src/db/index.js`

The final schema-only wave maps user messages, email delivery evidence, report
templates, and report share links to local notification/reporting boundaries.

Sensitive and executable behavior stays constrained: email addresses and body
content require review, outbox rows never trigger implicit resend, report
templates require an allow-listed dataset and data scope, and share tokens are
excluded rather than imported as live credentials.

The machine-readable mapping is
`scripts/fixtures/schema_reporting_notification_mapping.json`; each rehearsal
emits `schema-reporting-notification.json` with four mapped tables, zero
available rows, and `promotion_authorized=false`.
