# ERP cost-dashboard v3 runtime audit

## Source contract

`CostDashboardV3.vue` composes the source project list and CBS-version reads,
then calls:

`GET /investment/projects/:projGuid/profit-actual-v2?planVersion=...`

The source response groups CBS leaves as `R → l2 → l3` and calculates the
five-column cost model:

- `A`: CBS plan target;
- `D`: signed/paid contracts and approved expenses;
- `E`: approving contracts and expenses;
- `F`: remaining plan amount (`max(0, A - D - E)`);
- `G`: estimated/approving changes;
- `B = D + E + F + G`, with `H = A - B`.

R6 received revenue and unclassified R0 contracts are reported separately.
The route is read-only; it does not reserve budget, approve changes, post
accounting entries, release cash, or call an external provider.

## PostgreSQL adapter

The authenticated service and fixed read-model server now expose the same
path under `/api/company/investment/projects/:id/profit-actual-v2`. The adapter
reads project, CBS version/master/dictionary, contract, expense-split,
expense, change, and received-revenue source rows. It preserves the nested
hierarchy, counts, selected plan version, source coverage, and explicit
`authorizing=false`, `persisted=false`, and `provider_execution=false` flags.

The controlled export contains no `cb_subject_dict` or `cb_plan_version` rows.
The adapter therefore returns a successful empty hierarchy with zero counts
and missing/empty-table metadata rather than returning a transport error or
fabricating CBS rows.

## Rabbita mapping

`/cost-dashboard-v3` now requests the source read on navigation. A successful
response renders the source CBS hierarchy and summary metrics; an empty
successful response renders `源表为空` with the source note. Transport or
invalid-response failures retain the designer dashboard as a visible fallback.
The source action is a refresh/read action only; no cost mutation is attached.

## Verification and remaining gates

The service smoke test probes `proj-0001` with the controlled empty CBS export
and asserts the empty rows, zero counts, and `cb_subject_dict=0` /
`cb_plan_version=0` coverage. The parity matrix marks `/cost-dashboard-v3`
and `GET /investment/projects/:projGuid/profit-actual-v2` as
`connected_cost_dashboard_read`.

Project-scope and production-identity acceptance, a complete CBS/version
export, budget reservation, accounting, cash, tax, period close, and
finance-owner reconciliation remain separate gates.
