# ERP cashflow runtime audit

The Rabbita `/cashflow` page now has a source-compatible PostgreSQL read
boundary at `/api/company/cashflow/forecast`. It reproduces the ERP forecast
shape for the selected month horizon and project: payment-plan outflow,
pending and approved payment applications, approved unpaid expenses, and
approved loan balances are rolled into monthly totals, cumulative outflow, and
top business-unit/project breakdowns.

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
showing the live monthly table and source provenance banner when the read
succeeds. Forecast-v3, inflow, net, gap-alert, AI explanation, cash release,
accounting posting, tax, bank settlement, and production identity remain
separate migration gates.
