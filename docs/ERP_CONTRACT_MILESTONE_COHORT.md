# ERP Contract Milestone and Settlement Cohort

Recorded: 2026-07-13
Source boundary: `cb_contract`, `cb_htfkplan`, and `cb_htfk_apply` from
`../erp/erp_new`
Target boundary: `operations/commitment`, `operations/contract`, and
`operations/settlement`

This cohort closes the lifecycle gap between the existing typed payment
promotion and the target contract state machines. The older promotion keeps
payment-plan rows as planned milestones and applications as requested-payment
evidence. This reviewed cohort proves the next explicitly authorized step:

```text
performed commitment
  -> planned milestone
  -> eligible
  -> reached with actual amount
  -> requested settlement retaining milestone identity
```

The cohort is intentionally separate from cash and accounting. It does not
approve or release a settlement, reconcile a payment, call a bank/provider,
post a journal, recognize tax, or close a period. A reached milestone cannot
approve its own cash effect; the native boundary requires separate milestone
and settlement authority grants.

## Executable boundary

- `scripts/erp_contract_milestone_plan.py` validates the reviewed map, source
  table identities, commitment/milestone/settlement relationships, currency,
  sequence, percentage, and amount ceilings. It rejects secret-shaped keys,
  duplicate identities, mismatched amounts, and invalid expected states.
- `cmd/contract_milestone` constructs the performed commitment, drives the
  milestone through `eligible` and `reached`, and creates only a requested
  milestone-linked settlement. It emits three target candidates:
  `commitment`, `contract_milestone`, and `settlement`.
- `scripts/company_contract_milestone_rehearsal.sh` applies the native receipt
  to an isolated SQLite projection store and, when a PostgreSQL database is
  supplied, the PostgreSQL target adapter. Both paths run exact identity
  parity and a second apply for idempotent replay.
- `scripts/fixtures/contract_milestone_mapping.example.json` is a reviewed
  synthetic map because the checked-in source artifact is not a complete
  production export. It uses CNY 1,050,000 commitment value, a CNY 1,000,000
  progress milestone, CNY 960,000 actual achievement, and a CNY 960,000
  requested settlement.

The native receipt and durable candidates carry `cash_released=false`,
`accounting_posted=false`, and `period_closed=false`. Those markers are
controls, not claims that a source payment was settled.

## Verification

The reviewed fixture produces exactly one projection of each type. The
SQLite and PostgreSQL rehearsals report `shadow_verified`; the first apply
inserts three projections and the second inserts zero. The target state is
`performed`, `reached`, and `requested` respectively. A production source
export, owner acceptance, settlement approval/release policy, and accounting
link remain separate gates.

The optional thirty-third argument of
`scripts/company_postgres_cohort_rehearsal.sh` accepts this map and applies the
same native receipt to the selected PostgreSQL target. The standalone wrapper
is preferred when the cohort is being reviewed in isolation.
