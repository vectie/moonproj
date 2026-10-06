# PRD remaining-work inventory

Products can read a dated, packaged work assessment for each of the existing
twenty Moon products. It does not enroll new engineering targets, create company
projects, dispatch tasks, accept work, or write PostgreSQL records.

## Target and evidence

`config/moonsuite-work-inventory.json` preserves all 242 functional and 102
quality requirements from the twenty packaged PRDs, including exact IDs,
statements, acceptance criteria, historical evidence and statuses. Current
assessment is a separate field, with a reason and evidence boundary. The original
PRD philosophy and non-goals remain visible. Later founder direction that exceeds
these authored PRDs is explicitly unresolved target scope, not removed ambition.

The status vocabulary is `verified`, `partial`, `planned`, `unverified`, and
`missing`. Verified means only the exact stated requirement/evidence scope.
Unknown current source does not imply absent implementation. Planned means an
intended roadmap requirement whose present fulfillment has not been established.
Counts are scope and evidence counts, never completion percentages. A partial
requirement is not counted as wholly unimplemented.

The 2026-10-04 build-progress revision records completed local acceptance slices
separately from their remaining full criteria in the existing visible assessment
and next-action fields. `PRODUCT_BUILD_PROGRESS_2026-10-04.md` maps those slices
to the exact requirements and independent review/promotion evidence, and
distinguishes checkpoint 122 from later source-only milestones. Its r4 section
records connected-work progress after checkpoint 127, distinguishes delivered
checkpoint 134 from later independently postchecked source milestones, and
provides its dated remaining-blocker overview. The r5 section updates selected
saved-lesson observations returned to Proj, contiguous-cut caption derivation,
and historical Fish package/UI provenance. R5 changes annotations only; every
requirement and group status and all conditional estimates remain unchanged.
It distinguishes verified historical source from unknown current repository
fulfillment and supersedes only the corresponding older gap wording. The r3/r4/r5 sections remain dated history. The r6 section records current
transferred Edit/Leaf/Poly source-only promotions, 13 narrowly evidenced partial
requirements, unchanged Vis input availability and historical Fish native
qualification. It preserves all original acceptance and estimates and makes no
full-product, live-browser, publication or later Mac-parity claim. No parser,
wire-schema, company database, or product-catalog change is needed.
The r7 section adds selected-outcome preparation, explicit model choice, bounded
code-source save recovery, Proj/Book outcome authoring/intake and related native
Fort configuration-reference forwarding. It annotates 15 existing requirements
and nine groups; only Desk B02/N01 and moondesk-editing advance to partial.
Native Book optional-field migration and all live/browser/host limits are
explicit. No runtime, authored PRD, estimate or group-membership change is made.
The r7 data checks do not rerun the compiler or original MoonBit importer.
The r8 section adds eight Proj/Desk human-revision row notes and four group
notes without changing any status, acceptance or estimate. The first slice is
a separate immutable UTF-8 revision up to 256 KiB; live agent bytes remain
untouched, and selection, Report and Accept are explicit. Native identity
readback remains a recovery prerequisite. Proj N01's original task-URL criterion
remains unresolved, and the human-source Book evidence is projection-only.
The broader prototype-build/preview/change ambition remains undecomposed.

Original conditional engineer-day ranges and their arithmetic remain unchanged.
Completed subwork is not subtracted mechanically from those ranges. The displayed
scope notes explicitly state that remaining effort has not been recalculated;
the original planning ranges are not precise current remaining-work estimates.

Work groups partition all requirements exactly once. Each has a next action,
acceptance gate, dependencies, conditional engineer-day range, assumptions and
confidence. Unknown effort has two null bounds. A verification-only estimate is
not an estimate of all implementation work. Shared dependencies and overlapping
verification mean group estimates must not be summed as a release promise.
External licenses, hardware, providers, customer decisions and observation windows
are not interchangeable with engineering days.

## File-backed read integration

The existing authenticated `GET /api/moonsuite/products` projection adds
`work_inventory_state` and per-product `work_inventory` only when the separate
assessment file is valid and covers the exact catalog set. It checks product
identity, requirement identity, complete group partition, evidence state,
estimate bounds and declared PRD hash. The product catalog schema and enrollment
file are unchanged.

The assessment is the sibling `moonsuite-work-inventory.json` in the configured
catalog directory. The existing `--product-catalog`/`MOONPROJ_PRODUCT_CATALOG`
therefore selects both locations without a new listener or authority. The
Lepusa bundle includes the sibling file in `config/`. Missing, invalid or stale
assessment returns `missing`/`invalid` while valid product definitions and
document reads remain available. No substitute backlog or zero-work claim is
invented. Current source availability remains separate from the assessment date.

LunaNexa, LunaFlux, LunaFlex, LunaChip and LunaRein are infrastructure dependencies,
not extra Moon product/application rows. MoonStat remains retired. MoonProp and
Mooncake remain outside this task scope. Current transferred Edit, Leaf and Poly snapshots plus reviewed local patches
are disclosed separately from bounded tests; Vis is an unchanged input only.
Fish remains historical source with no current Mac/repository parity. The
original recovery-named milestone labels and budgets are retained as dated
planning history; updated current gaps and group next actions state remaining
work. None of these source records establishes full product completion.

## Preparing an actionable task

The default view shows purpose, scope/evidence counts and bounded next work.
Each product has an explicit chosen next-deliverable title, scoped range and
confidence. A milestone linked to one work group must retain exactly its title
and estimate; it cannot silently total other groups. Source-recovery milestones
have no implementation-group link and are labeled as audit-only work.
Requirement text, historical evidence and non-goals are expandable. Search and
status filters change only the visible requirement list. Selecting another
product clears those filters and retains ordinary product history behavior.

“Prepare this work” requires a successfully read, explicitly selected actual
company project. It fills an ordinary local draft with the work-group and PRD
requirement IDs, next action, acceptance and dependencies. It never starts or
creates a formal task. Workspace, actor, dates and owner remain explicit inputs.
An edited or attempted draft is resumed intact rather than overwritten; repeated
clicks do not create duplicate drafts. A selected outcome is retained while its
prerequisite project read/selection is pending or retrying; stale replies cannot
replace the newer selection. Once an eligible project is selected, preparation
retains the group's exact IDs, acceptance, dependencies and snapshot. This pending
selection is page-local; no formal task is created by preparation. Large inventory data is not copied into
persisted product snapshots. Canonical task state and company/task APIs are
unchanged. Creating a task still uses the existing reviewed form and gateway.

## Rebuilding and checking the import

Run from the MoonProj repository with the approved MoonBit toolchain:

```
moon run --target native scripts/prepare_product_work_inventory.mbtx SOURCE_WORKSPACE ASSESSMENT_JSON
moon run --target native scripts/prepare_product_work_inventory.mbtx SOURCE_WORKSPACE ASSESSMENT_JSON --check
```

The importer checks exact authored JSON hashes against the existing document
manifest and verifies every requirement ID, statement and acceptance against the
packaged DOCX main-body extraction. It keeps the catalog and PRD bytes unchanged.
`--check` is read-only. It does not retrieve repositories or contact providers.

Validate the shared parser, frontend and existing gateway package on their
supported JS/native targets, format and regenerate interfaces, and run the
existing product asset verifier. UI/reducer and source checks do not establish
installed desktop behavior, live signed-company operation or customer acceptance.

## Reviewed guidance and first-customer proposal revision (r9)

R9 records five existing Proj/Book requirement annotations and four existing group updates for explicit reviewed Book guidance into a first native request and canonical task-linked proposal drafting/revision/history/export. Only MOONPROJ-R02 advances from planned to partial. Totals are 344 requirements, 61 groups, 20 products: 179 partial, 97 unverified, 67 planned and 1 verified. No group status, authored criterion, source PRD, scope, estimate, dependency or membership changes. The original as_of date remains the baseline date; the r9 assessment and progress addendum carry the later 2026-10-05 evidence cutoff.

The bounded later-task consumer narrows earlier hydration gaps but proves no semantic applicability, model adherence or measured learning. Proposal recovery and canonical save remain source/fixture qualified; a draft/closed proposal is always demand-unproven and does not alter customer/cash facts or ordinary task acceptance. Real PostgreSQL transactions/restarts, signed sockets, mounted browser/storage/download/popup/accessibility, providers and installed Mac behavior remain separate gates. The dated source/test evidence, exact requirement mapping and current next actions are in the r9 section of PRODUCT_BUILD_PROGRESS_2026-10-04.md.

## Reviewed Today queue and proposal-reply revision (r10)

R10 adds precise source/test notes to six existing MoonProj rows and four existing groups. The selected-actual-project Today queue replaces Overview sample metrics with successful-read scoped counts, UTC date knowledge, owner/blocker/task inspection and separate local drafts. Pre-execution proposal replies retain exact proposal-version, human recorder/respondent distinctions, append-only corrections and existing revise/close controls. R04 remains planned: human-recorded proposal feedback is not authenticated delivery acceptance or reconciled cash.

All 344 requirements, 61 groups, 20 products, authored criteria/history, scopes and conditional estimates are unchanged. Status totals remain 179 partial, 97 unverified, 67 planned and 1 verified; no group status changes. The original baseline as_of date remains, with the later r10 evidence cutoff recorded in the dated progress addendum. Live PostgreSQL/transaction/restart, mounted browser/storage/accessibility, signed sockets, provider/Mac, authentic customer/cash and measured-learning gates remain separate. No parser/API/runtime change is required.

## Accepted human-result portability revision (r11)

R11 adds seven existing Proj/Desk/Book row notes and six group notes. The separate read-only Proj accepted-human export, explicit Desk source selection/Prepare, unchanged Book pack/import and existing Town exact-byte transfer retain original source JSON and full text, including Unicode/empty/exact-limit cases and all 57 package members. Imported material remains an unsigned captured source observation. Package inclusion is not live authenticity, customer acceptance, Bookkeeper/lesson review, runtime activation or a Town viewer; the separate authored HTML Work Package and full privacy gates remain unchanged.

All 344 requirements, 61 groups, 20 products, criteria/history/scopes and conditional estimates remain unchanged. Counts stay 179 partial, 97 unverified, 67 planned and 1 verified. The unchanged importer and narrow parser/asset checks are separate from feature qualification. The r11 addendum discloses the recorded Town 100 ms test's 15/16 broad runs and isolated 1/1 pass without claiming a verified repair or broad Town green suite. Live company/host/browser, providers/Mac, cross-machine lifecycle and measured learning remain open.

## Town Imported outputs and timeout-test revision (r12)

R12 adds four Town row notes and two group notes for the separately reviewed/promoted read-only Imported outputs drawer and deterministic timeout-test correction. Exact local import/member pins, escaped text, held-byte verification and direct/Desk-proxy save gating do not establish import/execution/lesson promotion or full supervisor intervention. Ordinary Desk imports without the exact receipt remain unsupported. B05 and N04 stay unverified; N02 stays planned.

All 344 requirements, 61 groups, 20 products, authored criteria/history/scopes and estimates remain unchanged; counts stay 179 partial, 97 unverified, 67 planned and 1 verified. Historical 15/16 timeout failures remain intact; the later corrected 16-case suite has 15 active bodies and one existing opt-in return, without changing production timeouts. R12 separately records the final 23 native/5 shared JS/41 UI/63 combined and 60 explicitly awaited viewer evidence without summing overlapping scopes or claiming mounted browser, live service/server build, atomic concurrent-rename protection, provider or Mac acceptance.
