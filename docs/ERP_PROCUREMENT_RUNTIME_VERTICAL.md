# ERP procurement/tender runtime vertical

Status: local PostgreSQL/Rabbita slice verified; source export and production
acceptance remain open. Supplier provider data and supplier dictionaries are
kept as separate observations. Native MoonBit owns the bounded supplier
command lifecycle and source provider aliases; they persist only command-owned
projections and remain non-authorizing for procurement.

The ERP `/tender` and `/srm/providers` pages are now connected to the company
boundary. They read the latest `tender` and `supplier` aggregate projections
from PostgreSQL and keep the source planning/budget/bid/status and supplier
qualification shapes. If no accepted procurement rows are present, Rabbita
visibly falls back to the reviewed snapshot instead of claiming that synthetic
rows are production data.

## Connected API

The supported runtime is the compiled `cmd/postgres_company_service` binary
started by `scripts/company_postgres_service.sh`; the Python service is a
frozen comparison adapter and is not executed by the supported path. The
native service exposes:

- `GET /api/company/source/tender/tenders` (with `tenderGuid`/`projGuid`/
  `state` filters) for the latest tender plan projection, including bids,
  award, commitment identity, source kind, snapshot, and mapping metadata;
- `GET /api/company/suppliers` and `GET /api/company/suppliers/<id>` for the
  latest supplier qualification, scope, and source metadata;
- `POST /api/company/tenders` to create a local planning draft;
- `POST /api/company/tenders/<id>/publish` to publish a planning draft;
- `POST /api/company/tenders/<id>/open_bidding` to enter bidding;
- `POST /api/company/tenders/<id>/cancel` to cancel an active local plan.
- `POST /api/company/tenders/<id>/award` and `/complete` to finish a local
  tender after bid/supplier qualification checks;
- `DELETE /api/company/tenders/<id>` for a command-owned tender tombstone;
- `POST /api/company/source/tender/tenders` and
  `POST /api/company/source/tender/splits` for source-field create aliases;
- `PUT /api/company/source/tender/tenders/<id>/state` for a forward-only
  source-state alias that reuses the native lifecycle checks;
- `POST /api/company/source/tender/awards` for a source-field award alias that
  requires matching bid and qualified-supplier evidence;
- `DELETE /api/company/source/tender/tenders/<id>` for a command-owned source
  tender tombstone;
- `POST /api/company/suppliers` to create a local supplier draft;
- `POST /api/company/suppliers/<id>/{update,submit_review,review,blacklist,void}`
  for the local supplier lifecycle;
- `GET /api/company/suppliers/<id>/risk` and
  `GET /api/company/supplier-risk-board` for derived risk reads;
- `GET /api/company/srm/providers` for the source-compatible ERP supplier
  master list. It reads only imported `srm_provider`, `srm_provider_bu`,
  `srm_category`, and related contract envelopes, and returns source coverage,
  explicit empty/missing tables, and `authorizing=false`;
- `GET /api/company/srm/providers/<guid>` for the source-compatible provider
  detail, including linked business units and historical contract evidence;
  a missing provider returns a source-covered 404 rather than a fabricated
  detail row;
- `GET /api/company/srm/providers/<guid>/risk` for the source-compatible
  provider risk detail. It reuses the ERP risk calculation over that provider's
  imported contracts and milestones, returns coverage metadata, and remains a
  derived non-authorizing read;
- `GET /api/company/srm/providers/<guid>/check-sign` for the source-compatible
  missing-provider boundary. With an imported provider it returns an explicit
  procurement-owner gate rather than authorizing a contract signature or
  invoking an external provider. With a command-owned supplier projection it
  returns a `derived_command_preview` using local risk semantics; that
  preview is non-authorizing, non-persistent, and still requires
  procurement-owner approval;
- `POST /api/company/source/srm/providers` and `PATCH`, `PUT`, or `DELETE`
  `/api/company/source/srm/providers/<guid>` for source-field provider CRUD.
  These aliases create, update, or void command-owned supplier projections,
  merge those projections into source-shaped list/detail reads with
  `source_kind=command`, and preserve idempotent replay evidence. Imported
  providers remain read-only; qualification, signature, and external provider
  effects are not inferred. Rescore is a local command that writes only
  command-owned risk projections;
- `GET /api/company/srm/stats/overview` for source-backed enabled-provider,
  rating, category/source, and top-business aggregates;
- `GET /api/company/source/srm/categories` for the source `srm_category`
  observation;
- `GET /api/company/source/srm/dict/eval-results` and
  `GET /api/company/source/srm/dict/sources` for reviewed evaluation-result and
  supplier-source definitions. These are definition observations, not grants
  to qualify, approve, blacklist, or otherwise authorize a supplier;
- `GET /api/company/srm/risk-board` for the source-compatible ERP risk-board
  envelope. It computes the source risk formula only from imported
  `srm_provider`, `cb_contract`, and `cb_contract_milestone` rows and reports
  coverage/missing tables; it never falls back to local supplier projections;
- `POST /api/company/source/srm/providers/rescore-all` (and the canonical alias)
  for a signed supplier-risk rescore command. It computes the ERP formula and
  persists score/rating/tags only on command-owned supplier projections, records
  an idempotent command/audit receipt, protects imported rows, and never calls a
  provider or changes cash/accounting/tax;
- `GET /api/company/source/tender/splits` (with
  `parentContractGuid`/`state` filters) for explicit contract-split evidence;
  `POST /api/company/tender-splits` and the source-field POST alias create
  command-owned splits.

The direct `/api/company/tenders` and `/api/company/tender-splits` GET
list/detail shapes now read the latest PostgreSQL projections with the ERP
fixed-point amount/percent fields, display values, source provenance, and
not-found behavior. The Rabbita tender page continues to use the
source-compatible reads above, while native tender lifecycle writes remain
available on the direct command paths.

Each command requires an idempotency key, persists an immutable tender
revision, a command receipt, and an audit record. Imported tender projections
are read-only. The `award` command is deliberately stricter than a button: it
requires a matching bid and an active qualified/strategic supplier projection;
the award-to-commitment grant remains a separate native boundary and no cash,
accounting, tax, or settlement effect is inferred.

The read-only development adapter exposes the same GET surface. Rabbita
`/tender` first loads source-compatible tender-plan, award, and split
observations, then provides local create,
publish, bidding, award, completion, and cancellation actions through the
authenticated gateway;
`/srm/providers` first loads the source-compatible provider master list, then
keeps the local supplier projection/command state separate for command
feedback and fallback. An empty source list remains an explicit empty table;
it does not silently become fixture suppliers. The source-shaped supplier
detail/new screen remains alongside the local command states. The detail route
loads the source provider, BU, and contract envelope when available and keeps
the designer form as its transport-failure fallback. The provider page also
loads the source statistics overview after the list, retaining explicit zero
counts when source tables are empty. `/srm/risk-board`
loads the source-compatible risk envelope and shows an explicit empty/missing-
source state for the available snapshot; supplier risk is a derived read and
does not mutate qualification. Provider detail also loads the risk-detail read
and shows score, rating, tags, contract count, and overdue milestones while
keeping the designer detail layout and source provenance banner.

The source parity audit also records the remaining differences. The
`srm.js` signature-check endpoint now has a bounded missing-provider/gated
boundary plus a local command-owned derived preview; imported populated-
provider decisions still require procurement-owner approval. The native
rescore-all route is now a local command; it mutates only command-owned ratings. The
source-compatible risk board remains read-only and non-authorizing while the
snapshot has no supplier rows. All target mutations above are separate
idempotent company commands, not proxied legacy writes.

The native supplier/provider and tender/split smokes and gateway smoke cover create/replay,
collision, source-shaped detail, update, review, blacklist, void, and trusted
forwarding. The source supplier CRUD aliases follow the same rule: they translate the ERP
field family into a local supplier command, but do not pretend that a local
projection is an imported `srm_provider` row. List/detail readback is useful
for the designer flow and carries provenance; source statistics, imported
provider signature/risk decisions, and populated-source rescore remain source-
evidence and owner gates. The native rescore command is a local projection
write and never a signature decision or provider call.

The tender command runtime is not an exact proxy for every legacy tender
mutation. Local create and lifecycle commands enforce a forward-only state
machine, while the legacy API also exposes arbitrary state replacement and
hard-delete semantics. Source-compatible create, state, and award aliases now
translate the source field family at `/api/company/source/tender/tenders` and
`/api/company/source/tender/awards`; state transitions still reuse the native
graph, and awards still require matching bid/qualified-supplier evidence.
Command-owned awards merge into the source-shaped awards read with explicit
provenance. `DELETE /api/company/source/tender/tenders/:guid` and the native
`/api/company/tenders/:guid` use an idempotent tombstone for command-owned
tenders only; imported tender rows remain read-only and are never deleted.
Arbitrary source-state overwrite, hard-delete, award-to-commitment, and
procurement-owner acceptance remain gates.

The source tender boundary is:

- `GET /api/company/source/tender/tenders` over `tender_plan`;
- `GET /api/company/source/tender/awards` over `tender_award`;
- `GET /api/company/source/tender/splits` over `contract_split`.
- `POST /api/company/source/tender/tenders` as a source-field create alias;
- `PUT /api/company/source/tender/tenders/:guid/state` as a forward-only
  source-state alias;
- `POST /api/company/source/tender/awards` as a qualification-gated award
  alias, merged into command-owned award readback;
- `DELETE /api/company/source/tender/tenders/:guid` as a command-owned
  tombstone alias;
- `POST /api/company/source/tender/splits` as a source-field split alias.

The GET responses preserve source fields, add normalized identity and display
fields for Rabbita, report all three table counts, and mark the read as
non-authorizing and non-persisting. The POST/DELETE aliases instead return
persisted command receipts with explicit command provenance and no
cash/accounting/tax effect. The available export has zero rows in all three
tables, so the tender page renders an explicit empty source state rather than
promoting its reviewed snapshot rows.

The supplier dictionary boundary is:

- `GET /api/company/source/srm/categories` over the imported `srm_category`
  table;
- `GET /api/company/source/srm/dict/eval-results` for six reviewed evaluation
  outcomes;
- `GET /api/company/source/srm/dict/sources` for four reviewed source labels.

All three responses preserve explicit coverage and mark the observation
non-authorizing and non-persisting. The current export has no `srm_category`
rows, while the latter two are definition observations because their source
dictionary rows are not present. They must not be used to seed supplier
qualification state or to bypass the source identity/owner-approval gate.

## Evidence

The reviewed synthetic procurement cohort contains two qualified suppliers, a
two-bid tender, and one performed commitment. Applying that receipt to
PostgreSQL produced four projections and `company_procurement_cohort_parity.py`
reported `shadow_verified` with no missing, extra, or candidate mismatches.
That temporary evidence was removed after the runtime read check; the target
database is back to its pre-test counts because the available ERP export has
no supplier/tender rows.

The authenticated service smoke also runs a nonce-scoped local procurement
workflow: supplier create/update/submit/review, derived risk, tender
publish/open-bidding/award/complete, contract-split create/read, and the
source-field tender create/split aliases. It checks idempotent replay and
source-shaped command readback; imported source-table coverage remains
unchanged while local command projections are retained as target evidence. It
separately verifies the source risk-board response has
zero high-risk rows, two imported contracts, missing `srm_provider`,
`srm_category`, and `cb_contract_milestone` coverage, and
`authorizing=false`. It separately verifies the source supplier list returns no
rows for the current snapshot, two imported contract envelopes, missing
  `srm_provider`/`srm_category` coverage, and `authorizing=false`; the source
detail route returns a covered 404 for the missing provider. Imported
supplier and tender mutation attempts return 409 read-only rejections. The
source provider-risk detail also returns a covered 404 when the supplier table
is absent; a disposable non-empty source cohort was verified to produce the
expected contract/overdue counts and a derived rating, then removed.

Remaining gates are populated-provider qualification/signature/rescore and
supplier/tender owner acceptance, a redacted source
procurement export, supplier identity and owner approval, the populated-provider
signature decision, award-to-commitment acceptance, browser acceptance through
the real gateway session, and production identity/role/session deployment.
