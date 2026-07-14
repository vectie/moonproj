# ERP expense-detail runtime audit

## Source contract

The source router mounts `GET /budget/expenses/:guid` for
`ExpenseDetail.vue`. The response is a detail envelope with three independent
collections:

- `expense`: the `vcb_expense` master row plus applicant and department labels;
- `details`: `cb_expense_detail` rows (`summary`, `amount`, `occurDate`);
- `splits`: `cb_expense_split` rows with user, department, cost-subject,
  proceeding, and amount labels.

The source route is a read operation. It does not approve, settle, post to an
accounting book, or execute a provider.

## PostgreSQL adapter

Both the authenticated service and fixed read-model server expose:

`GET /api/company/budget/expenses/:guid?userCode=...`

The adapter reads the five expense tables plus `my_biz_param_option` and
`vys_proceeding` for labels. It returns `source_kind=imported_or_empty`, table
coverage, and `authorizing=false`, `persisted=false`, and
`provider_execution=false`. When the controlled export has no matching
`vcb_expense` row, the response remains a successful read with
`data.expense=null`, empty `details`/`splits`, and explicit missing/empty table
coverage. This prevents an absent source row from being replaced by a
designer fixture.

The route is intentionally separate from `/api/company/expenses/:id`, which
reads local command projections. Imported source rows and local command rows
therefore retain distinct provenance and ownership boundaries.

## Rabbita mapping

`/expenses/:guid` requests the source detail endpoint on navigation. The
designer form remains intact as a transport-failure fallback, while a
successful source response switches the form to read-only source values and
renders separate expense-detail and four-dimensional allocation tables. Empty
source tables are rendered as `源表为空`; no mutation command is attached to
the imported detail action.

## Verification and remaining gates

The service smoke test probes the detail endpoint with the controlled empty
export and asserts the null master row, empty detail/split arrays, and source
coverage. Parity now classifies `/expenses/:guid` and the source `GET
/expenses/:guid` handler as `connected_expense_detail_read`.

Browser acceptance of the new edit/void controls, production identity/scope,
budget checks, workflow synchronization, accounting recognition, tax, and
finance-owner reconciliation remain separate gates.
