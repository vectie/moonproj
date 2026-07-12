# ERP CBS Cost-Link Cohort

Recorded: 2026-07-13

The legacy fixture's `cb_cost` rows now have an optional, independently
reviewed migration path into governed CBS subjects. This is deliberately a
separate cohort from dynamic-cost arithmetic and budget consumption.

## Mapping contract

`scripts/erp_cbs_cost_link_plan.py` consumes the credential-safe export and a
mapping shaped like `scripts/fixtures/cbs_cost_link_mapping.json`. Every
project mapping names:

- the target CBS version and legal principal;
- the exact project scope and currency;
- the source amount column to link;
- every source `cost_code` to a target subject ID, code, name, parent, and
  target amount.

Missing projects or subject mappings quarantine the affected source row. The
planner never treats a legacy cost code as a CBS subject by convention.

## Native and durable boundary

The generated plan is validated by `cmd/cbs_link`. For each ready row, the
native command creates the mapped CBS version, adds its subjects, activates the
version, and calls `CbsVersion::link_cost` with separate `cbs:create`,
`cbs:edit`, `cbs:activate`, and `cbs:cost:link` grants. The resulting receipt
uses the normal domain-promotion envelope, so the existing SQLite projection
adapter can persist and parity-check it.

The link is an allocation/traceability record. It does not consume budget,
approve an overrun, post a journal, or release cash.

## Rehearsal

The eighth argument to `scripts/erp_migration_rehearsal.sh` supplies the CBS
mapping:

```text
scripts/erp_migration_rehearsal.sh \
  /controlled/erp.db \
  /controlled/work \
  /controlled/base-mapping.json \
  /controlled/accounting-mapping.json \
  /controlled/offset-mapping.json \
  /controlled/typed-mapping.json \
  /controlled/payment-accounting-mapping.json \
  scripts/fixtures/cbs_cost_link_mapping.json
```

The cohort emits its own plan, native receipt, projection apply, exact parity,
and idempotent replay artifacts. The reviewed fixture contains seven ready
links for the seven non-empty `cb_cost` rows.

## Remaining gates

This cohort does not yet import the full CBS schema family, consume budgets, or
reconcile actual cost against all source financial totals. Those remain later
source-cohort and accounting/subledger gates.
