# Prepare a reviewed lesson from an accepted task

This is a bounded continuation of MOONPROJ-R05/R01 and MOONBOOK-R02/R03/B05.
Internal task acceptance does not establish a customer outcome, a Three-Gap
judgment, a saved lesson, cash, or capability activation.

## Ordinary product flow

1. Open an accepted task in Proj and choose **Prepare lesson**. The existing
   authenticated company gateway reads that task without refreshing, observing,
   starting or resuming execution. It requires the actual accepted report and
   unambiguous matching named command/audit receipts.
2. In **Record the actual outcome**, write what you observed and when (UTC).
   Explicitly answer the information, recognition and decisiveness gap questions,
   explain each judgment, and choose the captured task/report evidence supporting
   it. Every choice starts unset. A gap that was not assessed is not an absent
   gap. Present gaps need severity 1–5 and a real capability-change descriptor;
   no-gap outcomes omit unused capability metadata rather than inventing it.
3. Choose **Preview the complete outcome file**. The gateway rereads the accepted
   source and refuses a changed task/report binding while retaining the draft.
   Inspect the preview, then download the outcome, source handoff and evidence
   files together. The ordinary form produces the complete Book submission;
   JSON editing, manual IDs and manual digests are unnecessary.
4. Enter the HTTP(S) origin of the Book you intend to use and choose **Open**.
   This address has an empty default, stays in this tab, and grants no credentials
   or persistent access. Only an application hosted at `/` is supported.
5. In the opened Book, choose **Receive task from Proj**. The page shows the
   sender origin and explains its readback. Browser messages check the exact
   window, origin and one-time nonce in both directions. Task/report content is
   sent only after this explicit receive action and never placed in the URL.
   Book validates the exact task and report snapshot digests and displays their
   ID, version, original source, summary, reviewer and acceptance event. Proj
   shows success only after the receiver returns the same typed binding.
6. In Book, choose **Import outcome file**, inspect the exported submission and
   explicitly save it for review. Use the existing deliverable review, **Continue
   outcome review**, and assessment review. Already-saved submissions can resume
   at their current step. Book then resolves the exact submission, outcome and
   named-human accepted assessment. Choose **Start lesson from this assessment**
   to hydrate the current lesson authoring UI. The action explicitly replaces an
   unsaved authoring draft; a repeated selection retains its identity and text.
   Write guidance and applicability, save the candidate, and use the existing
   governed review controls. There is no automatic save or acceptance.
7. **Use task for lesson retrieval** hydrates task ID/version/digest and its actual
   project condition without replacing the authoring draft. Supply other truthful
   conditions. Existing exact-scope lesson retrieval is unchanged.

If the origin is absent, invalid, popup-blocked, or the browser severs opener
access, **Download lesson handoff file** and Book's **Import Proj task handoff
file** provide the same typed handler and readback without retyping identifiers.
The existing Desk/manual learning paths remain available. No service is started.

## Authored outcome export

`POST /api/company/tasks/{id}/outcome-export` is an authenticated, read-only
projection operation in the existing gateway. It performs one canonical company
GET, compares the exact prepared handoff, and returns files. It does not create
a company command, observe or run execution, write a ledger, contact Book, or
accept a review. HTTP 409 means the captured source changed; refresh it explicitly.
Notes attached to older captured versions stay separately readable in this tab
and are never silently rebound. All unsaved forms and prepared exports are
tab-local and disappear on reload, tab close, sign-out or account change. A same
actor session refresh retains them.

The submission uses `moonbook.bookkeeper.product_outcome_submission.v1`.
Task and report reference triples are preserved exactly; their provenance points
to the corresponding snapshot strings in the downloaded handoff file. The
decision reference names the task snapshot containing its original named
internal acceptance, not a customer response or Book review. Title and
deliverable summary come from those captured records. The founder supplies the
outcome, observation time and evidence-bound gap judgments. Broader business
claims are not inferred or independently verified by this exporter.

The UI supplies the task's display route from its actual origin and current
mount path, retaining only `page=dispatch&task={id}`. Credentials, other query
parameters and fragments are excluded. The exported `owner_route` therefore
reopens the task screen rather than raw API JSON. This route is included in the
digest basis but is never fetched, used as company identity or treated as
authority. API calls keep the application's existing root `/api` topology;
arbitrary API-prefix rewrites are not introduced or qualified here.

The exact authoring basis (handoff plus authored draft) is retained in the
evidence file. Its UTF-8 SHA-256 supplies the content-addressed submission ID and
digest; version is `1`. An unchanged frozen draft returns identical bytes.
Editing creates a different immutable submission identity after preview. A real
capability descriptor's digest hashes its exact retained change text. No
capability identity is derived from a task ID or guessed from product labels.
The producer checks the descriptor's completeness and bytes; it does not certify
that a supplied capability ID exists or that a proposed change is effective.
Those supplied claims remain visible for the existing Book review.

All three explicit absent-gap statements use severity zero. They still retain
their explanations and selected evidence. These records omit all four unused
capability-change properties, using Book's no-change-compatible v1 representation.
If any gap is present, the complete real capability ID, version, proposed change
summary and change text are required. An unresolved gap must not be marked absent
just to export without a descriptor. Existing complete Book submissions remain
valid. MoonClaw's separately stricter producer contract is unchanged.

Technical bounds are explicit validation, not additional human-review steps:
outcome text is at most 8 KiB UTF-8, each gap explanation 4 KiB, capability ID
256 bytes, version 128 bytes, summary 4 KiB and change text 64 KiB. Both timestamps
use Book's nonnegative 32-bit epoch-second integers and recording cannot precede
observation. The dedicated request limit is 2 MiB; other gateway request limits
are unchanged. Missing, oversized or invalid inputs preserve the UI draft.

## Contract and source linkage

`moonproj.book-lesson-handoff.v1` carries typed `task` and `report` references,
their exact serialized snapshot strings, `source_product: moonproj`, and explicit
non-authorizing/customer/cash labels. Task version is the actual company task
revision; report version is its actual report-command revision. Each digest is
SHA-256 of its captured projection bytes, not a newly invented company receipt
or a claim that presentation fields are the original command's canonical bytes.
The task snapshot retains the acceptance command/audit and selected delivery
source. The report retains its original delivery source and evidence IDs,
including existing Flow binding/result references when present. No Flow binding
or command is replaced or inferred.

The receiver uses its configured Book root. To resolve an existing outcome, both
exact reference triples must already occur in the originating moonproj
`ProductOutcomeSubmission.evidence_refs` and outcome evidence. Producers using
this bridge should retain these exported references and their snapshot evidence
when authoring that existing submission. Existing submissions without both exact
references remain readable and use the manual assessment-selection path.

An absent, rejected, unreviewed, or ambiguous assessment does not create facts.
The UI states the prerequisite or lists exact reviewed choices. The operator
must use the existing outcome-submission and named-human review process before
a source becomes available. Handoff itself is read-only: no journal record,
transport envelope, lesson, authority, customer acceptance or financial action
is written. Imported snapshots are context; their self-consistent hashes do not
independently authenticate the company service. Existing journal review decisions
remain the source of Book authority.

The initial direct acknowledgment contains only the original handoff and a matching-state label;
Book's private outcome text and review details stay in Book. The default browser
timeout is two minutes on Proj and 15 seconds while Book receives; retry or file
import is explicit. Reloading either tab loses the unsaved in-memory transfer.

## Return a saved lesson status

After explicitly saving and reviewing a lesson in Book, use **Refresh saved
lesson status**, select its exact version, and choose **Return selected lesson
status to Proj**. Book rereads its journal and sends only the selected lesson's
title/version, exact task/report/source references, review status and reviewer,
current-version relation, and observation metadata. Full guidance and scope stay
in Book. Proj acknowledges only the exact currently prepared task/report and
selected version. No company record, customer acceptance, payment, or activation
state changes.

`pending` means saved but not finally accepted; `retained` requires the existing
unique named-human Accept; `rejected` reports the existing Reject. Current and
historical accepted versions remain distinct. `legacy_unselected` means accepted
legacy versions exist without an explicit reviewed current choice; none is
silently selected or newly authorized.

After initial acknowledgment, the direct connection accepts one explicit saved
receipt for ten minutes. **Open** starts a fresh bounded connection; **Reopen in
this Book** carries the exact selected lesson reference through postMessage,
never the URL. If the opener closes, a popup fails, or a connection expires,
Book's download and Proj's **Import Book lesson receipt** provide the fallback.
Imported files are labeled historical observations. Reopening and explicitly
returning from a fresh Book readback updates the observed status; hashes and
origin/window correlation are not signatures. Proj keeps receipts in this tab,
while Book's original lesson and review remain in its persistent journal after
restart.

## Acceptance boundary

Local native producer/handler serialization, real journal replay, reducer/SSR and
controlled browser-message tests qualify the source implementation. They do not
qualify a live signed PostgreSQL company process, deployed browser topology,
provider run, customer, cash, or full portfolio requirement. No automatic Book
selection from an execution workspace or credential sharing is claimed.
