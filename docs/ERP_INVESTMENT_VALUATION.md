# ERP Investment Valuation Accounting Boundary

Recorded: 2026-07-13

This slice separates mark-to-market accounting evidence from the analytics-only
investment-performance cohort. A reviewed valuation map reuses the bounded
portfolio, positions, and quotes from the performance plan, then names the
valuation event, authority scope, and gain/loss accounts explicitly.

```text
reviewed performance plan + valuation map
  -> erp_investment_valuation_plan.py
  -> cmd/investment_valuation
  -> native investment_valuation accounting event
  -> erp_accounting_link_plan.py
  -> cmd/accounting_link
  -> SQLite/PostgreSQL traceability link
```

The synthetic fixture has CNY 3,000,000 of cost basis and CNY 3,100,000 of
quoted market value. The native portfolio boundary therefore creates a
CNY 100,000 gain event with journal identity
`investment/valuation-001/gain`. The separate accounting map binds that event
to `investment-asset` and `unrealized-gain`; the native command and planner
reject event, journal, account, scope, principal, amount, or currency drift.

The dedicated rehearsal is:

```text
scripts/company_investment_valuation_accounting_rehearsal.sh \
  scripts/fixtures/investment_performance_mapping.example.json \
  scripts/fixtures/investment_valuation_mapping.example.json \
  scripts/fixtures/investment_valuation_accounting_mapping.example.json \
  /tmp/investment-valuation.sqlite3 moonproj_migration_full2 \
  /tmp/investment-valuation-accounting
```

The reviewed run creates one accounting-link receipt. SQLite and PostgreSQL
both report exact `shadow_verified` identity parity; the second apply inserts
zero links. This is traceability evidence only: it does not mutate positions,
post the accounting book, release cash, close a period, or call a broker.

The available ERP snapshot has no accepted investment valuation rows. A real
valuation feed, valuation policy, investment-owner review, accounting policy,
and production period-close decision remain open.
