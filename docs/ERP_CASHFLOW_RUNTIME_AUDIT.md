# ERP cashflow runtime audit

The Rabbita `/cashflow` page now has a source-compatible PostgreSQL read
boundary at `/api/company/cashflow/forecast`. The authenticated service and
read-model adapter also expose the rest of the ERP cashflow read family:
`forecast-v3`, `forecast/detail`, `inflow`, `net`, and `gap-alert`. These are
read-only source projections; the page uses the forecast and inflow reads for
its live table and summary metrics, while detail/v3/net/gap-alert remain
available for the next drill-down screens.

The forecast reproduces the ERP shape for the selected month horizon and
project: payment-plan outflow, pending and approved payment applications,
approved unpaid expenses, and approved loan balances are rolled into monthly
totals, cumulative outflow, and top business-unit/project breakdowns. The
detail endpoint returns the source plan/application rows for a selected month;
inflow classifies received, expected, and overdue `sale_revenue`; net combines
source planned/pending outflow with revenue; gap-alert buckets time milestones
and pending revenue by week; and forecast-v3 preserves the ERP A/D/E/F/G
calculation when CBS and revenue rows are present.

The read operates on raw imported envelopes only:

- `cb_htfkplan` supplies planned payment rows;
- `cb_htfk_apply` supplies pending and approved payment rows;
- `cb_contract` supplies the project join for payment plans;
- `vcb_expense` and `vcb_loan_simple` supply expense/advance outflow when
  those source tables are present;
- `ep_project` and `mu_business_unit` supply display identities;
- `sale_revenue`, `cb_contract_milestone`, `cb_plan_version`, and
  `cb_subject_dict` remain explicit coverage dependencies for inflow, event,
  and v3 forecast semantics.

Every response includes `source_coverage`,
`missing_or_empty_source_tables`, `source_kind`, and `authorizing=false`.
Missing source tables contribute zero rather than fixture values or inferred
cash. The current export proves four payment-plan rows, three applications,
two contracts, one loan, seven organization rows, and no expense, sales,
milestone, or v3 CBS rows. A six-month `proj-0001` read therefore preserves
the August planned outflow and visibly reports the missing inflow/expense
dependencies.

The page keeps the designer snapshot as a transport-failure fallback while
showing the live monthly table, inflow metric, and source provenance banner
when the reads succeed. `POST /api/company/cashflow/ai-explain` (and its
`/source` alias) is now a signed, deterministic analytics candidate: it
summarizes supplied series/gap evidence, returns the source envelope, and
explicitly performs no provider call, prompt persistence, cash release,
accounting posting, or tax effect. Browser/finance-owner acceptance and any
real provider integration remain separate migration gates. The
current controlled export has no `sale_revenue`, milestone, or v3 CBS rows, so
those endpoints truthfully return empty series/coverage instead of fabricated
cash.
