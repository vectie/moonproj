# ERP Parameter and Expense-Proceeding Cohort

Recorded: 2026-07-13  
Source: `../erp/erp_new/backup/erp-v0.1.0-snapshot.db`  
Target: `foundation.ParameterDictionary`

## Boundary

The fixture contains two configuration catalogs:

- `my_biz_param_option.cost_subject`: 5 opaque cost-subject options;
- `vys_proceeding`: 3 expense-proceeding options.

The second catalog is configuration, not an expense claim, approval, payable,
budget reservation, CBS subject, account, tax code, or authority rule. Its
manager, department, and cost-code columns remain source evidence until a
separate reviewed domain mapping exists.

## Mapping contract

The reviewed mapping file supplies:

```json
{
  "parameter_by_name": {
    "cost_subject": {
      "principal_id": "co-001",
      "scope": "organization:bu-group-0001"
    },
    "expense_proceeding": {
      "principal_id": "co-001",
      "scope": "organization:bu-group-0001"
    }
  },
  "parameter_source_by_name": {
    "cost_subject": "my_biz_param_option",
    "expense_proceeding": "vys_proceeding"
  }
}
```

The planner fails closed for unsupported source tables, duplicate or missing
option identities/codes, missing values, empty groups, missing ownership, and
multiple `vys_proceeding` targets. The native `cmd/promote` boundary then
requires separate `parameter:create` and `parameter:edit` grants for each
dictionary.

## Rehearsal evidence

The typed parameter cohort produces two target dictionaries and eight options,
persists them as immutable `parameter_dictionary` projections, verifies exact
source/target parity, and replays idempotently. The source rows are also kept
as redacted typed evidence, so the target configuration does not erase source
provenance. No accounting posting, budget consumption, expense transition, or
authority grant is inferred.

This cohort is technically ready for business acceptance, but it does not
authorize cutover or imply that the 49 schema-only ERP tables are covered.
