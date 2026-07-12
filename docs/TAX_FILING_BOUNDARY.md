# Tax Filing Boundary

Recorded: 2026-07-13

The company product now separates four tax concerns:

1. obligation calculation from a reviewed source reference;
2. filing preparation for a jurisdiction and filing period;
3. external submission and acceptance/rejection evidence;
4. tax payment and accounting-book posting.

`TaxObligation::prepare_filing` is allowed only from `Reviewed` state and
requires a filing ID, filing period, authority reference, and explicit
`tax:filing:prepare` authority. `TaxFiling` then transitions through
`Prepared → Submitted → Accepted/Rejected` and persists as its own immutable
projection.

The filing aggregate does not mark the obligation paid, release cash, post a
journal, or contact a tax authority. External filing adapters, statements,
period-close integration, and production tax reconciliation remain later
deployment/migration gates.
