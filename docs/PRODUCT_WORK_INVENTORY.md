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

## Bounded round-two feature revision (r13)

R13 adds twelve requirement notes and eight group next-action notes for Across projects Today, human-revision comparison, optional exact original-Book-bound Desk import with Town read-only output inspection, and Find evidence-choice worksheets. It uses fresh published-main identities and separately frozen cloud candidates, with precise source/build/reducer and isolated CLI-fixture boundaries. No authored PRD or production parser/API/runtime change is part of this assessment patch.

All 344 requirements, 61 groups and 20 products retain their exact identities, authored criteria/history, scopes and conditional estimates. Status totals remain 179 partial, 97 unverified, 67 planned and 1 verified. Find R02 was already partial; the new worksheet adds bounded implementation evidence. Proj N04, Desk N05 and Town B05 remain unverified because source/render or read-only fixture evidence does not establish their complete live accessibility/authority criteria. Other affected partial requirements retain wider unresolved acceptance. Counts describe evidence scope rather than completion percentage.

The original as_of remains 2026-10-04; the dated r13 addendum and assessment carry the later evidence cutoff. Historical gaps are superseded only within the explicit slices: multi-project coverage is over listed projects, exact-bound import does not qualify ordinary unbound imports, comparison does not grant acceptance, and a user-authored worksheet is not a scored recommendation or company decision. Remaining effort has not been recalculated. Live signed service/PostgreSQL, mounted browser and accessibility, provider/Mac, customer/cash, full lifecycle and measured-learning gates remain separate.

## Bounded round-three feature revision (r14)

R14 adds thirteen requirement notes and nine group next-action notes for MoonFind decision JSON into MoonProj editable local work/packet, Flow owner actions in CLI and Desk, Cast named multi-cut delivery/exact SRTs, and Mold deterministic cylinder/mixed geometry. Evidence uses exact delivered round-two baselines, independently frozen cloud candidates and bounded actual producer/CLI/media/package fixtures. Find production is unchanged.

All 344 requirements, 61 groups and 20 products retain exact identities, authored criteria/history, scopes and conditional estimates. Every selected requirement was already partial; status totals remain 179 partial, 97 unverified, 67 planned and 1 verified. No group status changes. Find R01's opposite formal research contract, Cast N02's full master-rebuild gate, Flow observed reviewer understanding and mounted accessibility remain separate. Counts are evidence categories, not completion percentages.

The original as_of stays 2026-10-04; r14 records the later evidence cutoff. Only explicitly named local gaps are superseded: typed research preparation creates no company decision; owner summaries observe event history without assigning a person or authority; cuts retain prior master/package versions; cylinders remain mock/reference geometry with old box bytes retained. Free research text is not secret-scanned. Remaining effort has not been recalculated. The progress addendum preserves known broad Mold environment failures and other build/fixture limits. Live signed service/PostgreSQL, mounted browser/storage/accessibility, providers/Mac, customer/cash, full lifecycle/learning, Blender and physical/engineering gates remain open.

## Bounded round-four feature revision (r15)

R15 adds ten requirement notes and seven group next-action notes for MoonProj accepted-human-text client ZIP preparation, Desk grouped Book outputs, Cast timestamped PNG/JPG covers and gallery, and Mold typed model/primitive/absolute-move controls. Evidence uses exact delivered round-three baselines, independently frozen cloud candidates and bounded actual archive/Book/Town/media/mock-adapter fixtures. Book/Town are unchanged dependencies; Find and Flow product sources are unchanged.

All 344 requirements, 61 groups and 20 products retain exact identities, authored criteria/history, scopes and conditional estimates. Nine annotated rows remain partial; Proj R04 stays planned because the local ZIP supplies neither external acceptance nor authentic payment/reconciliation. Status totals remain 179 partial, 97 unverified, 67 planned and 1 verified. No group status changes. Book B06 records only the portable-carrier component; Book B03/UC03 projection/timestamp acceptance and Desk B06 HTML Work Package are unchanged. Counts are evidence categories, not completion percentages.

The original as_of stays 2026-10-04; r15 records the later evidence cutoff. Only explicitly named local gaps are superseded: a client ZIP is preparation without transmission; grouped files preserve relative assets without app activation; covers remain exact retained build outputs; typed controls prepare existing digital mock operations without additional modeling or physical authority. Remaining effort has not been recalculated. Prior broad Mold environment/fixture failures and other build limits remain retained. Live signed service/PostgreSQL, mounted browser/storage/accessibility, providers/Mac, actual client access/acceptance, cash, full lifecycle/learning, Blender and engineering/physical gates remain open.

## Bounded round-five feature revision (r16)

R16 adds eight existing requirement notes and five group next-action notes for Proj read-only commitment journeys, Book pre-task reviewed-lesson discovery, Find continued worksheets with exact historical evidence retained through paired Proj packets, and Mold structured digital briefs/revisions/package restoration. Evidence uses exact delivered round-four baselines, independently frozen cloud candidates and actual bounded local journal/producer-consumer/mock-adapter data. Book is changed this round; Desk, Flow and Cast source remain unchanged.

All 344 requirements, 61 groups and 20 products retain exact identities, authored criteria/history, scopes and conditional estimates. All eight annotated rows remain partial; no requirement or group status changes. Totals remain 179 partial, 97 unverified, 67 planned and 1 verified. Book trust defaults, B03/UC03 projection/timestamp policy, Find B03 configured runtime/B04 host delivery and Proj R04 external acceptance/cash are unchanged. Counts are evidence categories, not completion percentages.

The original as_of stays 2026-10-04; r16 records the later evidence cutoff. Only explicit local gaps are superseded. Journey stages are causal order rather than invented chronology; lesson search cannot attach/approve; continued choices are not revalidated; draft preparation cannot execute or inherit review. Remaining effort has not been recalculated. Historical broad environment failures remain retained. Optimized native Book host and full Mold Vite distribution are not qualified by the passed stripped host and JS compile checks. Live signed service/PostgreSQL, mounted browser/storage/accessibility, providers/Mac, actual client access/acceptance, cash, full lifecycle/learning, Blender and engineering/physical gates remain open.

## Bounded round-six feature revision (r17)

R17 adds eight existing requirement notes and seven group next-action notes for MoonGate saved-provider catalog selection, MoonClaw retained run-owned downloads with prerequisite session-only gateway authentication, and MoonFort signed retained command-output API/CLI inspection and one-pass raw export. These are three newly changed runtime products; MoonProj has only this inventory/data/docs overlay.

All 344 requirements, 61 groups and 20 products retain exact identities, authored criteria/history, scopes and conditional estimates. Seven annotated rows remain partial and Claw B06 remains unverified because authentication transport does not establish version negotiation and reconnect acceptance. No requirement or group status changes. Totals stay 179 partial, 97 unverified, 67 planned and 1 verified. Counts are evidence categories, not completion percentages.

The original as_of stays 2026-10-04; r17 records the later evidence cutoff. Only explicit local gaps are superseded. Claw reads current retained file contents, with exact record/run ownership but no content-digest historical immutability contract. Fort signed output reading does not add Claw/Desk UI mapping. Gate catalog discovery does not invoke inference or prove route readiness. Remaining effort has not been recalculated. Normal Gate checks/focused tests are separate from its unchanged strict-warning failure and disclosed broad-suite environment limits. Live provider, mounted browser/OS save, installed Mac, production deployment/containment, full privacy/retention/recovery and authentic customer/cash gates remain open.

## Bounded round-seven authoring revision (r18)

R18 appends bounded round-seven MoonTown one-off collaboration-plan authoring and MoonChat source-bound review-bundle authoring evidence to four existing requirements and two existing groups. All authored criteria, status categories, history, estimates and portfolio membership remain unchanged.

R18 evidence is bounded cloud source, compiled contract/reducer/render/transport fixtures, native filesystem authoring and portable pending-bundle qualification. It does not establish an executed collaboration, semantic synthesis or contradiction discovery, actual human decision, Book-owner acceptance, provider execution, receiver delivery, mounted-browser/keyboard/accessibility, installed Mac, publication or business outcome. Test counts overlap and are not product completion measurements.

The original as_of stays 2026-10-04; r18 records the later evidence cutoff. Town B03/B05 remain unverified, Town R02 remains planned and Chat R01 remains partial. Town preparation does not fulfill Chat's named Proj/Find hosted criterion. Totals remain 179 partial, 97 unverified, 67 planned and one verified. No group status or estimate changes; no completion percentages are implied.

## Bounded round-eight authoring progress (r19, 2026-10-06)

R19 appends accepted round-eight Robo digital design, MoonMoon mission alternative authoring and Flow graph authoring through Desk evidence to eight existing requirements and six existing groups. It preserves all authored criteria, statuses, history, conditional estimates and the 20-product portfolio.

R19 qualification is bounded source/unit/UI-fixture and actual isolated native CLI/store execution. It is not mounted-browser/keyboard/accessibility, installed-Mac, live-provider, calibrated physics, external dataset truth, physical readiness or dispatch, customer outcome, publication or deployment acceptance. Robo is one generic box-link excavation-haul concept and its validator checks artifact consistency rather than executing scenarios. MoonMoon and Desk require manual native command steps; declared mission power assumptions remain inherited, and newly imported robot calibration is cleared. Desk/Flow source inputs are existence/containment checked but their contents are not frozen, so immutable versioned inputs are required. Test counts overlap and do not measure product completion.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Bounded completed-outcome review and return (r20, 2026-10-06)

R20 appends independently accepted round-nine completed digital outcome intake and Book-owned review/portable disposition evidence to four existing requirements and two existing groups. MoonBook owns the useful receiver/review workflow; MoonMoon supplies the bounded producer/return integration, and MoonLib source is unchanged. All authored criteria, statuses, history, conditional estimates and portfolio membership remain unchanged.

R20 qualification is cloud source, compiled reducer/render/control fixtures, isolated native Book CLI/store and actual completed R8 digital simulation evidence. Named reviewers and grants installed by tests are explicitly synthetic fixture authority, never real human or business acceptance. A rejected negative-energy simulation remains rejected. Source integrity and Book decisions do not establish terrain/calibration truth, physical performance, customer/cash outcome, capability activation or a current-status guarantee. Receipt return is an explicit unsigned historical file workflow; refresh Book for current state. No live browser, installed app/Mac, provider, credential, hardware, customer transmission, push or deployment was exercised. The unchanged native simulator reuses its qualified R8 binary; the large native wiki harness was not run. Host/store default typecheck has zero errors and 816 retained warnings. Test counts overlap and do not measure completion.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Separate LunaNexa infrastructure evidence (r21, 2026-10-06)

R21 records the independently accepted LunaNexa offline benchmark-capacity planning slice as separate infrastructure outside the existing MoonSuite PRD portfolio. This is a provenance/docs revision with zero product, requirement or group annotations: it adds no LunaNexa criteria and does not alter the existing 20 products, 344 requirements, 61 groups, statuses, definitions, history or conditional estimates. The generated inventory changes only its assessment-source hash.

R21 is an out-of-portfolio infrastructure evidence note. Planner/native/JavaScript/actual-CLI-to-host fixtures pass for the accepted corrected tree, but full native telemetry execution is blocked by missing libpq headers and broad API/controller/node checks remain blocked by existing MoonLeaf warnings and missing xlsx.set_cell_number/recalculate APIs. No dependency/system change hides those failures. No full application, live browser/file-save/accessibility, Mac, provider/credential/GPU, physical-cluster, commercial, deployment or publication qualification is claimed. Local measurements remain operator-declared and unauthenticated; hashes prove reproducibility/integrity rather than truth. Planning performs no allocation and promises no price, savings, future capacity or SLA.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Run and compare an edited digital mission (r22, 2026-10-07)

R22 appends independently accepted round-eleven MoonMoon local-host and native-run UI evidence to four existing requirements and two existing groups. It preserves the completed round-ten source and exact r21 inventory. Authored criteria, statuses, history, estimates and the 20-product portfolio remain unchanged.

R22 qualification is cloud source, production JavaScript-controller/HTTP fixtures, compiled UI assets and actual native digital simulation/replay. The corrected review reused the exact qualified native binary and unchanged generated inputs; it did not repeat every native/scientific suite. No live browser, real human Book authority, provider, hardware, external-dataset truth, physical readiness, Mac, push or deployment is qualified. Storage remains local single-operator, limited to 32 retained runs, with exceptional stale-lock recovery and no fsync-backed power-loss guarantee. A completed calculation may still reject the mission.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Prepare, inspect and adopt a Flow plan inside Desk (r23, 2026-10-07)

R23 appends independently accepted round-twelve Desk/Flow preparation, input-capture and explicit import/revision evidence to six existing requirements and four existing groups. The default Desk production assets were corrected and actually served. All authored criteria, statuses, history, estimates and portfolio membership remain unchanged.

R23 qualification is cloud source, compiled controller/render fixtures, actual production Desk host to fixed-argv native Flow preparation/import/revision and corrected default-host HTTP asset checks. No execution attempt or generic executor is enabled. Known Mold spatial primary/reference bytes are captured; opaque input bindings are revalidated at apply, while unknown nested dependencies and runtime/product state are not frozen. No live browser, Mac, provider, credentials, hardware, customer action, push or deployment is qualified. Tests overlap and are not completion percentages.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Retained output and Claw-to-Book outcome return (r24, 2026-10-07)

R24 appends accepted round-thirteen Fort-to-Claw retained-byte download and Claw-to-Book completed-text outcome evidence to seven existing requirements and four existing groups. Book production source is reused unchanged; shared Claw one-off support is separately attributed to R14. All authored criteria, statuses, history, estimates and portfolio membership remain unchanged.

R24 qualification is cloud source, real local Fort retention/signing/read-only CLI, actual authenticated Claw loopback gateway plus shipped controller/transport, production local lifecycle output and the unchanged Book CLI/store receiver. Execution observations and Book reviewer authority are synthetic fixtures. Browser saving/DOM boundaries are simulated. The cloud OS sandbox is unavailable and verifies refusal, not successful containment. No real provider, real human, hardware, customer/cash outcome, Mac, push or deployment is qualified. Old unbound runs, expired/missing/changed records, output beyond capture ceilings and bytes already lost by legacy String producers are not recovered.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## One-off participant work, result review and Book return (r25, 2026-10-07)

R25 appends accepted round-fourteen Town one-off participant execution, retained result, embedded Chat review and Book return evidence to twelve existing requirements and five existing groups. Claw's shared one-off runtime support is attributed here; Chat and Book production sources remain unchanged. Authored criteria, statuses, history, estimates and all 20 portfolio products are preserved.

R25 qualification is cloud source, compiled host/UI/controller fixtures, actual production Claw proposal/workflow/artifact persistence with a deterministic local fixture worker, and the unchanged production Book CLI/store. Reviewer contexts and participant text are synthetic fixtures, not real model or human acceptance. Town's own path creates no schedule/daemon/recurring goal and does not materialize or rewrite participant Book sources; configured runtime tools retain their existing policies and authority. Collected attributed outputs are not model-written synthesis or consensus. No live browser, full identity-service authentication, real provider, customer, hardware, Mac, push or deployment is qualified.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Separate LunaNexa recorded-observation planning evidence (r26, 2026-10-07)

R26 records accepted round-fifteen LunaNexa recorded-observation selection, missing-metadata form and native evidence-file import as separate infrastructure outside the MoonSuite PRD portfolio. It adds no product, requirement or group annotations and invents no LunaNexa criteria. The existing 20 products, 344 requirements, 61 groups, authored statuses, definitions, history and estimates remain unchanged; the generated inventory changes only its assessment-source hash.

R26 is an out-of-portfolio infrastructure evidence note. Production FileTelemetry store record/persist/reopen, the exact GET telemetry payload expression, console decoding/selection/metadata, native evidence export and shared planning packet/reopen are exercised with synthetic measurements. This is not execution of the full API server/auth middleware, whose broad check remains blocked by unrecovered sibling Leaf xlsx APIs. No live browser saving/accessibility, real GPU/provider measurements, physical cluster, commercial/SLA, allocation, Mac, push or deployment is qualified. LocalObservation remains operator-declared and unauthenticated; hashes prove typed content identity rather than measurement truth.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Inspect exact built delivery media (r27, 2026-10-07)

R27 appends independently accepted bounded round 16 mooncast evidence to existing requirements/groups. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. The evidence overlay is applied separately to the already accepted R19 Proj feature baseline.

R27 qualifies cloud synthetic FFmpeg/native HTTP socket/compiled controller and actual served-asset checks. No mounted-browser playback, OS saving, provider generation, Mac, customer, push or deployment acceptance is claimed. Bare / retains its old404; /studio is the entry. Integrity reads each complete artifact before ranges; no new large-file streaming claim.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Browse verified retained scene objects (r28, 2026-10-07)

R28 appends independently accepted bounded round 17 moonmold evidence to existing requirements/groups. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. The evidence overlay is applied separately to the already accepted R19 Proj feature baseline.

R28 qualifies native14/14, real retained-host/recovery25/25, actual native wire to compiledUI66/66 and ordinary3asset build equality. No browser, Blender/provider, manufacturing/engineering fitness, physical, Mac, push or deployment claim. Unfiltered Node remains unqualified: unavailable Blender/manifest support and external city-hall PNG are excluded; the permitted offline subset passed. Inventory bounds4MiB/2000entries/100objects; mm fields and reset semantics remain explicit.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Search maintained pages and export cited context (r29, 2026-10-07)

R29 appends independently accepted bounded round 18 moonbook evidence to existing requirements/groups. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. The evidence overlay is applied separately to the already accepted R19 Proj feature baseline.

R29 qualifies actual native TCP2/2, independent native-wire/UI3/3 and identical release/install asset checks. DOM/clipboard/download effects are controlled fixtures, not OS/browser acceptance. Owner505 native broad tests preceded final refinements; final frozen focus and127UI results are separate. Limits16KiB request/1024UTF16 question/10000pages/32levels/2MiBpage; external rewrites are not transactional. No provider/Mac/push/deployment.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Prepare and reopen company project plans (r30, 2026-10-07)

R30 appends independently accepted bounded round 19 moonproj evidence to existing requirements/groups. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. The evidence overlay is applied separately to the already accepted R19 Proj feature baseline.

R30 qualifies actual authenticated gateway/native persistence/UI crossing with a synthetic read-only company projection and browser mocks. Independent7native/5UI plus owner117/431 aggregates are distinct. The gateway is the normal debug stripped build, not release-profile certification. No productionDB/identity, mounted browser, Mac/provider/customer/financial action/push/deployment. Fixed two-decimal entry and newest100 version history bounds remain explicit.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Discover compare and fork saved digital designs (r31, 2026-10-07)

R31 appends independently accepted bounded round 20 moonrobo evidence to existing requirements/groups. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. The evidence overlay is applied separately to the already accepted R19 Proj feature baseline.

R31 qualifies native workbench11/11, host catalogue1/1, shipped controllers46/46, exact native-produced fixture and normal6asset build equivalence. These compare declared digital concepts, not scenario execution or physical performance. No live browser/provider/hardware/Mac/push/deployment. Catalogue40 summaries/40directories/40revisions follows directory enumeration; not a hostile-filesystem streaming scanner. Older optional root-check completion is unknown/unqualified, not passed or asserted running.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Plan and revise source-bound experiments (r32, 2026-10-07)

R32: Append independently accepted R21 MoonFind experiment-planning, original-source retention, reported observations and explicit local-choice revision evidence All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact R20 r31 source.

R32 qualifies browser-local source/compiled rendering/command/download fixtures, independent JS120/120, two supplemental tests and exact release-asset equality. The cloud browser was blocked; no live-browser, native host rerun, provider, actual experiment, customer, Book review, Proj approval, Mac, push or deployment acceptance is claimed. Reports remain user assertions; no threshold evaluation or automatic winner is computed. Limits of 12 cards, 20 versions, 10,000 characters per entry and 2-million-character backups reject rather than evict.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Run named digital sensitivity studies (r33, 2026-10-07)

R33: Append independently accepted R22 MoonMoon one-reference plus two-to-four named-variant sensitivity and recovery evidence All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact R20 r31 source.

R33 qualifies native adapter12/12, compiledUI3/3, native-host/UI36/36, freshly rebuilt CLI focused3/3, storage9/9, normal production assets and exact v1 compatibility. Fixtures run the actual deterministic native simulator with synthetic inputs; full product aggregate and live-browser acceptance were not independently rerun. No provider, measured terrain/calibration, physical/hardware dispatch, Mac, push or deployment qualification. No performance speedup, automatic ranking or overall score is claimed; existing input/run bounds remain.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Run and reconcile one imported digital step through Desk and Flow (r34, 2026-10-07)

R34: Append independently accepted R23 Desk and Flow evidence for one selected ready native digital Mold item, existing authority, original-attempt recovery and a Review stop All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact R20 r31 source.

R34 qualifies independent Flow root 74/74 wasm tests, an 18-case real native matrix including actual parent process kill after Mold mutation, Desk compiled UI 10/10, actual native HTTP and rendered result 1/1, asset checks 83/83, exact frozen source reconstruction and 16 tracked assets. Existing synthetic approved Gate fixtures are used, never production grants. Only the exact native mock-reference Mold route is accepted: fixture-reference-only, production_qualified=false and physical_authority=false. The journal-only interruption is a labeled retained-file simulation. Heavy owner native aggregates and Vite build were reviewed, not independently duplicated. No live-browser, Blender/provider, hardware, engineering fitness, Mac, push or deployment acceptance.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Reopen exported LunaNexa workbench drafts (r35, 2026-10-07)

R35: Append independently accepted R24 LunaNexa draft-reopening infrastructure evidence as a separate outside-portfolio note; no product, PRD requirement, group or status is invented All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact R20 r31 source.

R35 is separate infrastructure evidence only. Independent focused JS36/36, native20/20, exact ordinary workbench build and supplemental File/Blob interruption tests passed. The shipped moon.work still refers to unrecovered moonleaf; focused disposable harness scope is disclosed, not a full workspace/cluster/API pass. No actual browser file-picker/disk-save, provider, upload, auth, inference, Mac, push or deployment acceptance is claimed.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Inspect retained Gate requests and export the displayed evidence (r36, 2026-10-07)

R36: Append independently accepted R25 Gate fixed-interval request filters, pagination, selected details and allowlisted page/report exports All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact R20 r31 source.

R36 qualifies independent native focused 15/15 and nested real authenticated API to exact served UI and export 9/9, with 37 offline JS passes and one native-only skip. Owner aggregate is 912/914; two unchanged session tests fail because sqlite3 CLI is unavailable. Unmasked baseline/candidate diagnostics match at 275 normal and 104 strict, strict exit 255; no full aggregate or strict pass is claimed. Synthetic retained requests, no live provider, mounted-browser visual, actual billing, Mac, push or deployment acceptance. Twelve-row offsets are not a transactional snapshot; exports cover a displayed page or selected request only.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Compare two immutable saved project plans without replacing the draft (r37, 2026-10-07)

R37: Append independently accepted R26 MoonProj read-only saved-plan comparison and exact report evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the independently accepted R26 feature source based on exact R25 r36.

R37 qualifies exact source/mode reconstruction, nine independent compiled-JS checks, three native gateway/money tests, three UI transport tests, six fresh native-readback comparison checks and normal release byte equality. Company projection is synthetic read-only; no production database/identity, interactive browser, provider, Mac, push or deployment acceptance. Plans remain pending_review, accepted=false, review_required=true, digital-artifact only, all five authority effects false. No authored status or estimate changes.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Observe bounded live command output through the existing trusted Fort reader (r38, 2026-10-07)

R38: Append independently accepted R27 MoonClaw read-only live command observation, cursor recovery and separate terminal download evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the independently accepted R26 feature source based on exact R25 r36.

R38 qualifies 23 independent focused checks: UI10, native11, actual live native HTTP/UI1 and terminal native HTTP/UI1, with frozen tracked assets and unchanged Fort reader hashes. Signed spool/retained-output fixtures are synthetic; no real provider or host/AEN command, interactive browser/disk-save, hardware, Mac, push or deployment acceptance. Native reader binaries were reused, not independently rebuilt; unrelated aggregates unrun. Only the existing build-info banner rewrote for reviewer HEAD and was restored after tests; feature source stayed frozen. Stream termination never marks job success or grants execution authority.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Inspect all retained collaboration outcomes and export an exact selected historical dossier (r39, 2026-10-07)

R39: Append independently accepted corrected R28 MoonTown outcome library, explicit historical review selection and exact-buffer dossier binding. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the independently accepted R26 feature source based on exact R25 r36.

R39 qualifies the corrected final source, independent native authoring/contract31 and UI8 checks, independently rebuilt normal native server/HTTP and production JS download with exact archive and unchanged 42-file store proof. Four same-size export-buffer substitutions refuse after the reviewer-found correction; prior failure/freeze evidence is preserved as superseded. Normal UI assets were independently byte-checked/served rather than redundantly rebuilt. Earlier pre-correction call-entry instrumentation has ten zero boundary counters and is historical, not final production-byte proof; ptrace unavailable and instrumentation not independently rerun. Synthetic local contributions/fixture executables only, no real provider/human identity, Book acceptance, interactive browser/disk-save, Mac, hardware, push or deployment; unrelated aggregates unrun.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Assign exact semantic material identities from retained objects (r40, 2026-10-07)

R40: Append independently accepted R29 MoonMold typed material assignment, current-inventory refusal and exact retained/delivery evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the independently accepted R26 feature source based on exact R25 r36.

R40 qualifies independent root wasm/wasm-gc/JS 12 each and native14, compiled UI72, native-to-UI material/retained bridges, deterministic native reference execution, exact production asset parity, extra preflight probes and source/mode/dependency reconstruction. Filtered Node72 passed, two opt-in skips, four external tests excluded; unfiltered suite not run. Semantic IDs only; current-inventory check is an operator material-route safeguard, not general native geometry validation or physical properties. No interactive browser, Blender/provider, hardware, manufacturing authority, Mac, push or deployment acceptance.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Manage browser-local infrastructure workbench drafts (r41, 2026-10-07)

R41: Append independently accepted R30 LunaNexa create, duplicate and rename evidence outside the MoonSuite PRD portfolio. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the independently accepted R26 feature source based on exact R25 r36.

R41 is outside-portfolio infrastructure evidence only: 46 affected independent JS tests, eight focused native tests, production File/Blob bridges under a synthetic DOM/download host, exact no-effect local actions, debug byte equality and normal workbench release build. Missing MoonLeaf override omitted only in disposable harness; shipped manifests unchanged; no full API/cluster/bundle, physical browser/disk-save, provider, Mac or deployment acceptance. A stale workload response after identity switch without input edits reproduces on R25 and R30 and remains a separate known issue; new-file input fencing passes.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Read exact retained source behind a maintained Book page (r42, 2026-10-07)

R42: Append independently accepted R31 MoonBook retained-source inspection and already-inspected-buffer download evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over exact independently accepted R30 r41 source.

R42 qualifies exact frozen source, six independent focused Linux native checks, 130 compiled UI tests, real socket text/binary crossings, exact normal served assets and unchanged Book content/metadata. Retained-byte SHA is current inspection identity, not original-ingest equivalence or factual truth. No broad wiki aggregate, graphical browser/OS download dialog, Mac, provider, push or deployment acceptance. Authored statuses and estimates stay unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Inspect frozen digital-study terrain and route evidence (r43, 2026-10-07)

R43: Append independently accepted R32 MoonMoon bounded frozen-source map and native-result inspection evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over exact independently accepted R30 r41 source.

R43 is presentation-only frozen-dossier evidence: exact archive/patch/source/modes and 90 normal UI assets, 37 focused passes with the native-CLI authoring round-trip skipped because that stage did not supply a CLI, nine storage passes, and a separate passing real HTTP/native CLI journey with production handlers under a deterministic DOM. Unchanged native source/binary verified without duplicate physics build. No graphical-browser/pixel, broad scientific aggregate, geographic truth, physical clearance, hardware, Mac, provider or deployment qualification; statuses and estimates unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Mark named delivery ranges against the exact promoted Cast master (r44, 2026-10-07)

R44: Append independently accepted corrected R33 MoonCast prebuild range marking and actual native-wire-to-compiled-UI evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over exact independently accepted R30 r41 source.

R44 binds corrected tree 79b311535651dab4844e0c8d633353411edc77f9: 27 independent focused compiled tests, genuine native playback projection consumed verbatim, fresh native MP4/range/HEAD/stale-SHA tests, exact normal served assets, unchanged fixture and empty build list. Prefix mismatch and retry-error defects were corrected before acceptance; pre-fix failure remains history. No actual Chromium decode/render/event-loop, broad native aggregate, customer/provider, Mac, hardware, push or deployment acceptance; authored statuses/estimates unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Inspect exact retained single-step Flow results in Desk (r45, 2026-10-07)

R45: Append independently accepted R34 MoonDesk retained-result inspection, identity-separated preview and pinned binary download evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over exact independently accepted R30 r41 source.

R45 qualifies exact R34 source/replay, three independent Linux native tests, 34 compiled UI tests, genuine retained HTTP/download crossings and exact ordinary served assets. Canonical Flow/Mold records unchanged; pre-existing host startup auto-pump updates its own status workspace_root/last_checked_at_ms, so no whole-suite zero-writes claim. Existing adapter remains fixture-reference-only, not production/Blender/physical qualification. No broad aggregate, interactive desktop-browser, Mac, provider, push or deployment acceptance; statuses and estimates unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Compare exact retained-request cohorts without routing or repricing (r46, 2026-10-07)

R46: Append independently accepted R35 MoonGate bounded snapshot, cohort statistics and displayed-report export evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over exact independently accepted R30 r41 source.

R46 qualifies exact 398-file source reconstruction, 1348 unchanged private dependency files, normal 275 / strict 104 diagnostic equality, native 6/6 plus independent 4/4, actual native HTTP/served-JS/export 7/7 and standalone UI 43 pass / 2 native-only skips. Node DOM/Blob harness is not rendered-browser/OS-download acceptance. Current full aggregate is incomplete at unchanged external-target mock guard, not a current two-sqlite3-failure result. No live provider, real credentials, routing, repricing, persistence, causal ranking, proxy-overhead measurement, Mac, push or deployment claim; authored statuses and estimates unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Prepare offline Find briefs with exact retained local-source dossiers (r47, 2026-10-07)

R47: Append independently accepted R36 offline preparation, immutable source capture/revision and complete dossier export evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over exact independently accepted R35 r46 source.

R47 qualifies exact R36 prepared-brief source, independent native/research/focused UI checks, actual native-host/compiled-UI save/retry/reopen/ZIP crossing and byte/mode/patch reconstruction. Native dependencies are fresh official-registry reconstruction, not historical-byte equivalence; UI dependencies match sealed R21. No research execution, model/source analysis, approved criteria, requested research-output production, interactive browser/file-chooser, native aggregate, customer/provider, Mac, hardware, push or deployment claim; authored statuses and estimates unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Inspect and compare retained Robo digital-trial evidence (r48, 2026-10-07)

R48: Append independently accepted R37 retained-trial catalogue, state-separated inspection and same-verified-baseline comparison evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over exact independently accepted R35 r46 source.

R48 qualifies exact R37 source, 52 independent production-controller/native-HTTP tests with zero skips, unchanged fixture/dependency bytes and exact rebuilt normal assets. Frozen result, current binding and import acknowledgement/history remain separate; numeric deltas require identical verified baselines. The inherited whole-cockpit MoonBit JS CommonJS/import.meta runner failure is reproduced from exact R35 and remains open. No simulation/replay, physical command/retry, browser pixels, native aggregate rerun, hardware, provider, Mac, Book acceptance, push or deployment; authored status/estimates unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Save human-revised Claw artifact copies with separate lineage (r49, 2026-10-07)

R49: Append independently accepted R38 authenticated human revision, exact-save retry and retained-copy reopening evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over exact independently accepted R35 r46 source.

R49 qualifies exact R38 bounded UTF-8 human_revision copies, separate canonical lineage, authenticated real gateway/compiled-editor crossing, lost-acknowledgement same-ID recovery and fresh-process exact download. Original artifact/run/event records remain unchanged; human attribution does not mark executor or accepted output. Unsaved drafts are tab-memory only and survive Close/navigation, not reload. No complete Claw aggregate, real token/provider, power-loss/fsync, browser save-dialog, Mac, hardware, push or deployment qualification; authored statuses/estimates unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Decide an existing exact-result Desk collaboration review (r50, 2026-10-07)

R50: Append independently accepted R39 existing-review decisions through verified human identity and unchanged Flow collaboration persistence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over exact independently accepted R35 r46 source.

R50 qualifies exact R39 Desk, fourteen independent native tests, ten compiled UI tests, real HTTP/Flow begin/decision/replay/stale-head crossings and 38 preserved run/Gate/Mold files. The exact existing assigned independent human Reviewer is selected only through host-verified identity and an explicit host principal map; fixtures are synthetic and no production mapping is supplied. Decisions are collaboration records, not FlowItemAccepted, customer acceptance, grants or execution. Flow source/executable remain unchanged. No aggregate/browser/Mac/provider/Blender/physical/push/deployment claim; statuses and estimates unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Navigate output-local captions beside completed Cast videos (r51, 2026-10-07)

R51: Append independently accepted R40 completed-output transcript search/seek and actual native-output timing-to-compiled-handler evidence. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over exact independently accepted R35 r46 source.

R51 qualifies exact R40 source, all 127 independent compiled UI tests, freshly fetched genuine native response to seek-zero/after-render/media-handler crossing and exact rebuilt normal assets. Synthetic native source cut 2–4s yields output-local 0–2s captions; historical build identities remain separate. Read-only seeking creates no editing/build/QC/acceptance/publication action. Normal native host is exact-source-bound reuse, not a new native aggregate. No actual browser playback/pixels/keyboard/focus, provider/customer, Mac, hardware, push or deployment claim; authored status/estimates unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Filter the observed cross-project Today queue (r52, 2026-10-08)

R52: Append independent evidence for presentation-only exact-owner, due-state, blocker and title filtering over the existing observed Today queue. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact independently accepted R41 feature source, which retains the prior r51 inventory.

Bounded independently accepted R41 source and the exact checks in its receipt. No real Today HTTP read/UI crossing; no retained verified harness/normal host, no native slot used. No mounted graphical, keyboard, focus-order or screen-reader accessibility qualification. No live signed PostgreSQL, production deployment, provider calls or full-product acceptance. Owner reports 442 frontend tests; two independent executions and generated metadata show 443. Historical lower printed aggregate remains unexplained; source and dependency identities are unchanged. Independent compiler commands suppress warnings; owner interface evidence contains 80 warnings and zero errors. Authored product statuses, criteria, history and conditional estimates remain unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Inspect later maintained Book search results (r53, 2026-10-08)

R53: Append independent evidence for bounded paged maintained-page search, later-page citation inspection and exact displayed context export. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact independently accepted R41 feature source, which retains the prior r51 inventory.

Bounded independently accepted R42 source and the exact checks in its receipt. No full native CLI release rebuild or installed serve asset deployment No mounted graphical browser or real OS clipboard/download/accessibility qualification; prior localhost denial respected Controlled compiled UI browser effects consume actual fresh native socket wires No full wiki aggregate or new 10000-file/depth stress run; unchanged safeguards source-reviewed Fresh scans are not transactional snapshots; no performance acceptance No provider, GitHub, user computer, curation or execution authority Source archive/clone-safe replay remains a separate delivery gate Authored product statuses, criteria, history and conditional estimates remain unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Choose registered Book sources before explicit capture (r54, 2026-10-08)

R54: Append independent evidence for a bounded registered-Book source picker feeding explicit save-time immutable source capture. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact independently accepted R41 feature source, which retains the prior r51 inventory.

Bounded independently accepted R43 source and the exact checks in its receipt. Cloud-Linux native and compiled HTML/client only; graphical localhost browser was denied and no alternative graphical route was used. Mounted keyboard/screen-reader qualification remains open. Bounded observation is not a filesystem transaction; no protection against a concurrent adversarial writer or atomic snapshot is claimed. Owner intermediate cleanup occurred before explicit independent-review disposal instruction; evidence/INTERMEDIATE_CLEANUP.md is retrospective, not prior review authorization. No providers, user computer, publication, Book acceptance or execution-authority expansion qualified. Authored product statuses, criteria, history and conditional estimates remain unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Read exact saved digital delivery changes and checks (r55, 2026-10-08)

R55: Append independent evidence for typed bounded, digest-bound retained change/loss/validation report interpretation beside separate named digital review. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact independently accepted R41 feature source, which retains the prior r51 inventory.

Bounded independently accepted R44 source and the exact checks in its receipt. Graphical browser, keyboard and accessibility unexercised: parent cloud Chromium denied ERR_BLOCKED_BY_CLIENT; no bypass or alternate route attempted. Actual HTTP-to-compiled-UI/SSR evidence does not establish graphical browser acceptance. Historical synthetic native fixtures reused with exact source binding; no new native binary build or execution. Root all-target/native aggregate and broad npm suite not rerun; existing broad environment/test failures remain unresolved. Unrelated retained-scene/material/brief host bridge probes lacked their fixtures and were not exercised; the requested reader HTTP bridge passed. Owner normal Vite release assets hash-verified, not independently rebuilt. No live Blender, provider calls, publication, user-computer access, physical/manufacturing qualification, authenticated reviewer mapping or actual human/client acceptance. Authored product statuses, criteria, history and conditional estimates remain unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Edit a route draft against its frozen terrain (r56, 2026-10-08)

R56: Append independent evidence for route-draft editing, exact candidate export/discard/reopen, and explicit retained native-run crossing. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact independently accepted R41 feature source, which retains the prior r51 inventory.

Bounded independently accepted R45 source and the exact checks in its receipt. No graphical browser acceptance: prior cloud localhost denial remains; no alternate browser route attempted. DOM/SVG fixtures do not establish pointer layout, keyboard focus ergonomics or assistive technology acceptance. Normal native and asset builds were source-bound reused, not independently rebuilt; no duplicate native graph. One optional preexisting Book receipt test skipped; E1 archive unavailable bridge retained. Digital-only local qualification; no physical readiness, hardware, external provider, publishing, user computer or deployment acceptance. Capacity readings are samples, not continuous high-water measurements. Authored product statuses, criteria, history and conditional estimates remain unchanged.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Resume an exact-result hosted review draft (r57, 2026-10-08)

R57: R46 adds browser-local pre-submit review draft save, recovery, backup and restore in Find, bound to trusted Book, research run and exact source digest. Independent compiled-controller and native HTTP checks qualify this bounded hosted consumer; review authority remains native. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact independently accepted Proj feature source, which retains the prior r56 inventory.

Exact independently accepted R46 sources and checks. 137 is the owner full-suite reported total, not137 independently active end-to-end scenarios. Opt-in review-native and legacy brief-native tests return early without their URL environment variables; review-native was separately actively executed by owner and reviewer. Legacy brief-native external path and optional fixture exports were not qualified here. No full native test suite rerun. Native host compiled by owner and independently executed from its source-bound binary; native production source is unchanged from the accepted R36 baseline. Browser storage and transport adapters run under Node. Compiled HTML output is not a graphical screenshot or keyboard/accessibility qualification. No graphical browser, OS save dialog or assistive-technology acceptance claim; prior ERR_BLOCKED_BY_CLIENT remains and was not bypassed. Fixture result setup was a deterministic owner POST, not actual MoonTown/provider synthesis. The accepted restoration crossing itself was GET-only, with complete native store preservation. Browser-local storage is origin/profile scoped, bounded to131072 UTF-16 code units and nonauthoritative. Oversized backups are salvage text until shortened; no cross-device sync or encrypted vault claim. No customer, production deployment, publication, authentication, payment, provider execution or user Mac qualification. No new repository or product dependency changes. Initial cross-tool native replay failed connection refused and is retained honestly; independent same-task replay succeeded. Direct Node exit0 alone is not proof, so emitted per-case results were explicitly checked. Authored portfolio criteria, statuses, history and conditional estimates are preserved.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Compare choices from a retained offline brief (r58, 2026-10-08)

R58: R47 connects saved offline brief revisions to typed local choice worksheets, complete readable and JSON exports, source-bound continuation history and stale-action protection. It preserves R46 ancestry and existing research-run contracts. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact independently accepted Proj feature source, which retains the prior r56 inventory.

Exact independently accepted R47 sources and checks. Full owner suite count includes opt-in native cases that return early without URL/revision environment. Independent 34 cases and 2 active native crossings are distinct counts, not full-suite end-to-end qualification. No new native build or full native-suite replay. Exact accepted R46 host reused; final tracked changes confined to UI/docs and private dependencies match R46. Node storage/transport and compiled HTML tests are not graphical browser, keyboard, assistive technology or OS file/save-dialog qualification. Prior graphical ERR_BLOCKED_BY_CLIENT was not bypassed. Browser-local key is origin/profile plus brief ID, not trusted workspace scoped. Same-ID contexts deliberately recover prior historical comparison and require explicit continuation; no cross-device synchronization or encrypted-vault claim. Imported source receipts and history are user-supplied. Client checks syntax/structure/provenance binding and exact basis equality, not SHA256 recomputation or independent current host retention. Native match means equality with currently loaded prepared snapshot only. No fabricated research runs/papers/claims, provider execution, customer validation, company decision/import authority, deployment or publication acceptance. Research v1 contracts and Proj consumers are unchanged. Bounded 20 earlier worksheet versions and 2-million UTF16-code-unit backup; Markdown is readable export and JSON preserves exact source hex. Storage quota remains browser dependent. Authored portfolio criteria, statuses, history and conditional estimates are preserved.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Duplicate or remove declared work steps (r59, 2026-10-08)

R59: R48 extends the existing declared-plan authoring workflow with explicit duplicate/remove controls, source-template-bound new declaration identities, dependency validation and added/removed previews. Independent two-repository native, real HTTP, compiled UI and CLI boundary checks qualify this bounded slice; preparation/import remain explicit and do not dispatch work. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact independently accepted Proj feature source, which retains the prior r56 inventory.

Exact independently accepted R48 sources and checks. Compiled UI reducer/rendering plus real local HTTP/native CLI tests; no graphical browser or accessibility qualification. Previously denied browser access was not retried. Synthetic isolated Books, Mold requests, capability catalog and two synthetic accepted parent checkpoints. No real customer acceptance, provider, hardware, deployment, push or execution dispatch. Final owner executables were replayed independently after source/hash verification; a duplicate product build graph was intentionally not created. Opaque nested dependencies and mutable product runtime state remain outside snapshot reproducibility guarantees. Authored portfolio criteria, statuses, history and conditional estimates are preserved.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Record episode actual-cost attribution and corrections (r60, 2026-10-08)

R60: R49 adds evidenced episode actual-cost and founder-hours attribution with immutable corrections, explicit reconciliation and durable reload. Independent native and HTTP checks qualify the ledger; a narrow ordinary project-actuals UI request fix preserves absent versus zero values and rejects invalid numeric input. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact independently accepted Proj feature source, which retains the prior r56 inventory.

Exact independently accepted R49 sources and checks. User-authored actual attribution and named author only; no authenticated identity, accounting approval, inferred revenue/margin, payment or provider action. Single Studio host per data root; in-process semaphore and existing atomic rename, no cross-process CAS, malicious-filesystem tamper resistance or power-loss qualification. Native, actual loopback HTTP, SSR and compiled UI scope only; no graphical-browser, accessibility, pixels, OS dialogs, customer or production-deployment qualification; prior browser denial not bypassed. Historical media/build preservation uses a verified retained subtree and synthetic same-project shell, without reconstructing master-approval lineage or re-encoding media. Existing generic dispatcher reports malformed committed-store errors as HTTP400 request_invalid. They fail closed and do not overwrite history; diagnostic specificity remains limited. Earlier owner fixture-parent race, wire-format failures and reviewer compile/startup/status-expectation recoveries are retained and are not counted as final passes. Authored portfolio criteria, statuses, history and conditional estimates are preserved.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.

## Export and verify a retained digital trial comparison dossier (r61, 2026-10-08)

R61: R50 adds portable Markdown and JSON dossiers from the exact inspected retained A/B trial responses, with content-bound identities, digest manifest and local verification. Independent native HTTP/controller replay qualifies the retained digital evidence handoff without creating review, Book or physical authority. All 20 products, 344 requirements, 61 groups, authored criteria, statuses, history and conditional estimates remain unchanged. Only the existing three inventory/data/docs files change over the exact independently accepted Proj feature source, which retains the prior r56 inventory.

Exact independently accepted R50 sources and checks. HTTP/DOM source-controller replay fetches and hashes normal production assets; it does not execute browser pixels or prove accessibility, native save dialogs or multi-download delivery. Inherited MoonBit UI test-driver exits 255: exports is not defined in ES module scope. UI MoonBit tests were build-only; they are not claimed executed. Normal release builds and original native compile receipts are producer evidence independently pin-checked, not rebuilt by this reviewer. Portable verifier establishes historical self-consistency, not authenticated native-store truth, current-file state, named review, Book acceptance, provider or physical authority. Separate Markdown and JSON downloads are non-atomic. No deployment, customer, provider, hardware or broad PRD acceptance is claimed. Authored portfolio criteria, statuses, history and conditional estimates are preserved.

The original as_of stays 2026-10-04; the later evidence cutoff is separate. All status categories, definitions, history and conditional estimates are unchanged.
