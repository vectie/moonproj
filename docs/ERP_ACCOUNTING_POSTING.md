# ERP Accounting-Posting Boundary

Recorded: 2026-07-13

This slice makes the company accounting book a real target-owned boundary for
reviewed journal postings. It is intentionally downstream of the
source-to-journal link boundary:

```text
ERP/source evidence
  -> reviewed accounting-link plan
  -> native AccountingEvent validation
  -> reviewed book/chart/period posting plan
  -> native AccountingBook.post
  -> immutable accounting_posting projection
```

`scripts/erp_accounting_post_plan.py` accepts only an explicit
`moonproj.erp.accounting-link-plan.v1`, a reviewed
`moonproj.erp.accounting-posting-map.v1`, an explicit chart of accounts, a
period, and an exact allow-list of already-linked event IDs. It does not infer
accounts, amounts, currencies, scopes, or period state from ERP rows.

`cmd/accounting_post` constructs the native `finance/accounting` book, adds the
declared accounts, opens the declared period, and calls `AccountingBook.post`
for every approved journal. Balanced positive postings, one currency, active
accounts, open period state, exact principal/scope, and the `accounting:post`
authority grant are therefore checked before a receipt is emitted. A posting
must carry `link_event_id == event_id`, so an unlinked journal cannot cross the
boundary.

The receipt uses the normal domain-promotion envelope with cohort
`accounting-posting-v1` and target type `accounting_posting`. Its candidate
retains book, period, event, journal, and posting-side identity. The SQLite and
PostgreSQL projection adapters persist that immutable receipt and replay it
idempotently. This is a target accounting projection; it does not call a bank,
release cash, submit a tax filing, close a period, or transfer business
ownership.

## Local smoke

The synthetic link plan and reviewed posting map are checked in so the native
boundary can be exercised without credentials or source mutation:

```text
python3 scripts/erp_accounting_post_plan.py \
  scripts/fixtures/accounting_link_plan_for_posting.example.json \
  scripts/fixtures/accounting_link_receipt_for_posting.example.json \
  scripts/fixtures/accounting_posting_mapping.example.json \
  /tmp/accounting-posting-plan.json
moon run --target native cmd/accounting_post \
  /tmp/accounting-posting-plan.json /tmp/accounting-posting-receipt.json
```

For a source-bound rehearsal, pass the twenty-fifth argument of
`scripts/erp_migration_rehearsal.sh` after the base accounting-link map. The
wrapper compiles the approved commitment links, posts the two project journals,
persists SQLite projections, compares exact source identities, and replays with
zero inserts. The PostgreSQL cohort runner accepts the analogous twenty-third
argument after its base accounting map and runs the same native, parity, and
replay sequence.

The available fixture proves two reviewed commitment postings with exact
SQLite/PostgreSQL parity and idempotent replay. The real ERP export has no
complete chart/opening-book/period approval, so production accounting
ownership, broader source cohorts, opening balances, tax policy, and period
close remain explicit later gates.
