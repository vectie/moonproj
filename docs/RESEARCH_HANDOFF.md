# MoonFind research to a local work draft

This is a bounded file-based planning handoff. MoonFind remains the owner of the
research comparison. MoonProj receives its versioned exported content and lets
the founder explicitly prepare ordinary local work. Importing or preparing does
not create a formal task, call a provider, validate demand, approve a company
decision, send a message or spend money.

## Use

1. In MoonFind's comparison worksheet, record a chosen option and next action,
   then export its decision JSON.
2. In MoonProj's task-dispatch page, choose **选择 MoonFind 决策 JSON**.
3. Inspect the question, chosen option, reasoning and next action. Expand the
   retained source register to inspect source versions, digests, dates, abstracts,
   analysis claims, locations, reported confidence, contradictions and unknowns.
4. Click **准备可编辑草稿** to prepare editable local work. The visible source
   notice and retained packet explain that current freshness has not been checked;
   local drafting needs no separate acknowledgment step.
5. The next action seeds the editable task title; the research question seeds the
   problem field. Complete the acceptance criterion, project and dates yourself.
   Existing drafts and the selected formal task remain intact.
6. Use **导出本地工作包 Markdown** to retain the editable draft alongside its
   original decision and source text, including any optional offer draft. Formal
   task creation remains the separate existing signed-command action.

Preparing the same worksheet again resumes its retained draft without replacing
later edits or retrying a request. If that draft has already been attempted, its
existing immutable/recovery state is preserved. A newer worksheet revision can
produce a new independent draft. The same run/revision with changed content is
rejected instead of silently replacing the retained version.

## Producer and consumer contract

The consumer accepts the existing `moonfind.decision-brief.v1` wrapper with
`moonfind.choice-worksheet.v1`. No MoonFind production changes are required.
The wrapper's `company_decision_recorded` must be false. The known current and
historical export-time source-status strings are retained verbatim, but neither
establishes present freshness in MoonProj. No URL is fetched by this flow.

All producer-defined worksheet fields, source records, optional source dates,
Int64 retrieval timestamp, summaries, claims, options, criteria and assessments
are decoded into typed content and preserved in local storage. Unknown JSON
fields, including actor, authority, credentials, runtime settings and signed
request metadata, are discarded. Raw arbitrary JSON is deliberately not stored.
This is not a secret scanner: never put credentials in the retained prose or
source URL fields. Imported URLs are rendered as escaped text, not executed.

Unreadable JSON, unsupported versions/statuses, authority claims, duplicate or
missing source identities, inconsistent option identities/criteria, conflicting
claim identities, and unresolved source/claim references are rejected. A missing
choice is inspectable but cannot prepare work. A named chosen option, decision
question and next action are required; missing reasoning/evidence stays unknown.

The picker bounds input at 8,000,000 bytes and decoding at 2,000,000 characters.
These bounds allow ordinary Unicode exports. Cancellation, file-read failure,
later selection, Close, navigation and actor changes do not overwrite existing
drafts. Late callbacks are fenced by generation and actor, and obsolete picker
elements are removed. Invalid selections preserve the prior valid preview and
show the error; malformed content never replaces the retained draft.

## Storage and export boundary

This extends the existing `DispatchDraft` collection with an optional typed
`research_brief`; older drafts still decode. Storage remains browser-origin and
actor scoped under the existing rules. Before login a draft is page-local; a
browser-storage failure is surfaced by the existing draft status. The portable
Markdown export is available without a signed service. Draft task IDs,
idempotency keys, actor identity and authority are excluded from that export.

The full research snapshot is retained locally and in the founder packet. The
existing create command still sends only its existing ordinary source reference
and problem fields. It does not silently promote the imported research JSON into
canonical company evidence or forward it to a runtime. The original source can
contain errors: digest identity, a chosen option and an experiment proposal are
not scientific validity, customer demand, acceptance or cash evidence.

## PRD mapping and limits

- MOONFIND-R02: preserve the evidence-to-choice comparison and what could falsify it
- MOONFIND-B04: retain source version/digest/context without claiming live artifact validation
- MOONPROJ-B02: source-backed reloadable local work and portable text without authority
- MOONPROJ-R01: retain a source/decision link while leaving formal receipts separate
- MOONPROJ-R05: expose a concrete next action without inventing accepted learning

This is partial progress toward those requirements. It does not complete the
commitment timeline, source refresh, signed-company qualification, demand proof,
customer communication, Book acceptance, or a commercial execution loop.

## Qualification

The tests embed current, historical and undecided JSON emitted by the unchanged
final round-two MoonFind `choice_export_json`. They exercise full known-field
round-trip, Unicode and Int64 dates, missing choices, malformed references,
whitelisted storage, interruptions, repeated selection, overwrite protection,
escaped rendering, portable text, and intercepted local-only effects.

Qualification is source-only: compiled reducers/rendering, local picker stubs,
unit/check/build. No mounted browser, real file dialog, screen reader, signed
PostgreSQL service, model provider, Mac app, publication or deployment was used.
