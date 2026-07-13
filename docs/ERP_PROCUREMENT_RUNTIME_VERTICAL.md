# ERP procurement/tender runtime vertical

Status: local PostgreSQL/Rabbita slice verified; source export and production
acceptance remain open.

The ERP `/tender` and `/srm/providers` pages are now connected to the company
boundary. They read the latest `tender` and `supplier` aggregate projections
from PostgreSQL and keep the source planning/budget/bid/status and supplier
qualification shapes. If no accepted procurement rows are present, Rabbita
visibly falls back to the reviewed snapshot instead of claiming that synthetic
rows are production data.

## Connected API

`scripts/company_postgres_service.py` exposes:

- `GET /api/company/tenders` and `GET /api/company/tenders/<id>` for the latest
  tender plan projection, including bids, award, commitment identity, source
  kind, snapshot, and mapping metadata;
- `GET /api/company/suppliers` and `GET /api/company/suppliers/<id>` for the
  latest supplier qualification, scope, and source metadata;
- `POST /api/company/tenders` to create a local planning draft;
- `POST /api/company/tenders/<id>/publish` to publish a planning draft;
- `POST /api/company/tenders/<id>/open_bidding` to enter bidding;
- `POST /api/company/tenders/<id>/cancel` to cancel an active local plan.

Each command requires an idempotency key, persists an immutable tender
revision, a command receipt, and an audit record. Imported tender projections
are read-only. The `award` command is deliberately stricter than a button: it
requires a matching bid and an active qualified/strategic supplier projection;
the award-to-commitment grant remains a separate native boundary and no cash,
accounting, tax, or settlement effect is inferred.

The read-only development adapter exposes the same GET surface. Rabbita
`/tender` loads PostgreSQL rows when available and provides local create,
publish, bidding, and cancellation actions through the authenticated gateway;
`/srm/providers` loads the same supplier projection boundary while retaining
the source-shaped supplier detail/new screen for the next command slice.

The source parity audit makes that next slice concrete. `srm.js` still has
supplier create, partial/full update, void, risk scoring, risk-board, and
signature-check actions; `tender.js` still has award and contract-split
actions. None of those source mutations is currently connected to the target
service or browser. They must be added as separate idempotent company commands,
not proxied legacy writes.

## Evidence

The reviewed synthetic procurement cohort contains two qualified suppliers, a
two-bid tender, and one performed commitment. Applying that receipt to
PostgreSQL produced four projections and `company_procurement_cohort_parity.py`
reported `shadow_verified` with no missing, extra, or candidate mismatches.
That temporary evidence was removed after the runtime read check; the target
database is back to its pre-test counts because the available ERP export has
no supplier/tender rows.

Remaining gates are the supplier/tender command slice above, a redacted source
procurement export, supplier identity and owner approval, award-to-commitment
acceptance, browser acceptance through the real gateway session, and production
identity/role/session deployment.
