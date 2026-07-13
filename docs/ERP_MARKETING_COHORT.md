# ERP Marketing Cohort

Recorded: 2026-07-13
Status: reviewed local rehearsal; no provider or budget authority

The marketing cohort exercises the target's native campaign and placement
state machines against a reviewed synthetic map. It preserves one completed
campaign with a CNY 100,000 budget and CNY 30,000 planned spend, one placed
online placement with 42 leads, and two catalog-evidence rows for the channel
and material surfaces: four durable projections.

`scripts/erp_marketing_cohort_plan.py` requires explicit campaign, placement,
channel, and material identities. It rejects secret-shaped fields, budget or
placement amount drift, non-catalog evidence rows, and invalid lifecycle
expectations.

`cmd/marketing_cohort` reconstructs campaign activation, placement creation and
placement, bounded spend, and campaign completion through native authority
checks. Channel and material remain catalog evidence; they do not execute a
provider campaign. The receipt keeps `budget_consumed`, `provider_called`,
`cash_released`, `accounting_posted`, and `period_closed` false.

`scripts/company_marketing_cohort_rehearsal.sh` applies the native receipt to
SQLite and PostgreSQL, checks exact source/target identity and type counts, and
replays it. The local rehearsal reports four `shadow_verified` items on both
backends; each replay inserts zero projections.

The available ERP snapshot contains no accepted marketing rows. Production
campaign/channel/material exports, provider credentials, budget-owner review,
and any real spend or attribution policy remain open.
