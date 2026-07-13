# ERP Procurement Cohort

This opt-in reviewed cohort translates supplier qualification, tender bidding,
award, and commitment creation as separate company-owned boundaries. Supplier
review does not authorize an award; an award does not silently release cash or
post accounting; and a performed commitment is not a settlement.

The reviewed fixture contains two construction suppliers and one project tender
with two CNY bids. `East Ridge Supply` is awarded CNY 1,050,000 against a CNY
1,200,000 estimate. The native command moves both suppliers through review to
active, moves the tender through publishing/bidding to awarded, creates the
commitment through a separate award-to-commitment grant, and performs the
commitment without settling it.

The receipt emits four immutable candidates: two `supplier`, one `tender`, and
one `commitment` projection. SQLite and PostgreSQL adapters compare complete
candidates by target/source identity and replay the receipt idempotently. All
candidates keep `cash_released`, `accounting_posted`, and `period_closed` false.
The available ERP snapshot has no supplier or tender rows, so this remains
reviewed synthetic evidence until a redacted procurement export and owner
acceptance are supplied.

The local runtime now consumes these same `supplier`/`tender` projection
shapes when a reviewed cohort is present: `GET /api/company/tenders` serves
the latest tender plan and `/tender` in Rabbita drives local planning,
publishing, bidding, and cancellation commands. Imported plans remain
read-only; award still requires a qualified supplier projection and a matching
bid, with commitment creation kept as a separate authority decision.
