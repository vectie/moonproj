# ERP Notification Boundary

Recorded: 2026-07-13
Owner: `intelligence/notification` and `cmd/notification`

The company product owns a notification outbox, not a provider connection. The
boundary translates a reviewed source message or workflow event into a
company-owned, source-bound `notification_outbox` projection. It supports
`in_app`, `email`, and `webhook` intent while keeping external delivery,
workflow approval, cash release, and accounting posting separate.

## Lifecycle

`Notification::new` requires a scoped `notification:create` grant and creates
a `draft`. A separate `notification:queue` grant changes it to `queued`.
Provider attempts, delivery confirmation, failure, and suppression are
explicit authority-bearing transitions. A delivered notification must carry a
provider message identifier; the aggregate never sends a network request.
The idempotency key and source event identity are preserved on every
projection, so a retry can be replayed without creating another outbox item.

## Migration contract

`cmd/notification` consumes
`moonproj.company.notification-plan.v1` and emits the normal
`moonproj.erp.domain-promotion.v1` receipt. The optional twenty-third argument
of `scripts/erp_migration_rehearsal.sh` and optional twenty-first argument of
`scripts/company_postgres_cohort_rehearsal.sh` run this importer through the
same SQLite/PostgreSQL projection, parity, and replay adapters as other
cohorts. `scripts/fixtures/notification_plan.example.json` is synthetic
review evidence; it does not claim that the incomplete ERP snapshot contains
a real message row.

The receipt records `delivery_requested` independently from
`external_delivery_confirmed`, and always records
`workflow_mutated=false`, `cash_released=false`, and `accounting_posted=false`.
Those flags are deliberate safety boundaries, not inferred business effects.

## Open gates

The source schema still has `sys_message` and `sys_email_outbox` rows outside
the available 26-table snapshot. Source export, recipient consent, provider
credentials, retry/retention policy, observability, and owner acceptance are
required before a production adapter or real delivery is enabled.
