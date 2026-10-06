# Task-linked proposal drafts

This bounded feature prepares a reviewable first-customer proposal on an ordinary
planning task. It records what the founder proposes, not a customer order,
accepted delivery, contract, invoice, revenue or payment.

## Founder workflow

1. Open an ordinary work draft and optionally write a proposal. Merely opening,
   editing or exporting the proposal never creates or starts a task.
2. Fill the normal task fields and explicitly create the pending planning task.
   Alternatively, open an existing command-owned pending task that has never
   executed or received a report.
3. Write the buyer/problem, proposed scope, deliverables, customer criteria and
   price hypothesis. Unknown values remain blank/unresolved. Proposed customer
   criteria are separate from the task's internal acceptance criterion.
4. Save explicitly. Browser recovery state is retained first; the signed task
   command then saves a canonical revision. The UI rereads the exact task and
   matches its command/audit history before claiming that save is confirmed.
5. Inspect the current proposal and its earlier revisions, including closure
   reasons. Export a deterministic Markdown draft for manual review.
6. A proposal may be closed or revised without completing the task. To prepare
   a proposal from accepted/executing work, prepare a separate local planning
   draft with empty proposal content in the same project. It retains the original
   task/product as source context without inventing an execution workspace or
   changing the old task.

No customer communication, model/provider request, signing or payment is part
of this workflow. A complete proposal still has unproven demand.

## Wire contract

The optional `offer_draft` object has schema `moonproj.offer-draft.v1`.
`schema`, `state` and `demand_state` must be explicitly supplied. Unknown keys
are rejected. The normalized key order is stable:

- `schema`, `title`
- `buyer`, `buyer_reference`, `problem`, `problem_observed_on`
- `scope`, `exclusions`, `deliverables`, `acceptance_criteria`
- `price_amount`, `price_currency`, `price_basis`
- `timing`, `dependencies`, `proof_sought`
- `state`, `closure_reason`, `demand_state`

The title is text; missing/blank title normalizes to an empty string. Other
optional text normalizes to null when absent/blank. Deliverables and criteria
are ordered text arrays; normalization removes blank entries, preserves
duplicates and never invents entries. The editor preserves raw text and blank
lines while typing, including input that still needs correction before saving.

`state` is `draft` or `closed`; a closed proposal requires a nonblank closure
reason. `demand_state` is always `unproven`. No adjacent task state changes this.

Price is decimal text, not floating-point money. It permits nonnegative decimal
notation with at most two fractional digits. Explicit `0` remains an explicit
user value; absent price never becomes zero. Supplied currency is three
uppercase ASCII letters, a format check rather than verification of a price
or currency. Missing amount, currency or basis is visibly unresolved. A
supplied problem date must be a real Gregorian `YYYY-MM-DD` date.

Content limits: title/buyer 256 Unicode characters; other text 8,192 characters;
each array at most 32 entries of 2,048 characters; canonical UTF-8 JSON at most
64 KiB. CRLF/CR normalize to LF and unsafe controls are rejected. Markdown
renders user text as escaped blockquoted lines so content cannot forge the
generated status/source headings or embed executable HTML.

## Existing service and authority

No new endpoint, table or ledger is introduced:

- Explicit creation: `POST /api/company/plan/tasks`, optional `offer_draft`
- Proposal-only update: `PUT /api/company/plan/tasks/:id`
- Exact readback: `GET /api/company/tasks/:id`
- Existing project/product task lists expose only `offer_summary`

Creation retains the existing `project:task:create` authority. Proposal updates
retain `project:task:update`, exact project scope and the original signed
creator. The update body allows only `offer_draft`, `offer_base_revision`,
`authority` and the transport's optional `idempotency_key`. It cannot bundle
task status, progress, acceptance, execution settings or source-context changes.
The gateway moves the request key into the existing idempotency header.

New updates require an ordinary command-owned pending task, no native execution,
continuations, human revisions, selected/accepted delivery source or accepted
report. The client-observed positive `offer_base_revision` must equal the
canonical revision. Revision, creator/project, eligibility and absence of task
reports are checked under the existing record/projection lock before insertion.

The same JSONB tables retain the command, audit and immutable task projection.
An identical same-actor lost-response retry resolves its existing receipt before
checking a later task revision or state. Changed content, actor, task, authority
or original base revision cannot reuse that request identity.

Full proposal content and existing creator identity are returned only on exact
command-owned task detail. Lists retain a minimal summary. The existing
task-scoped receipt read projects `offer_history` only when proposal revisions
exist, preserving legacy history shape for other tasks. Missing or conflicting
audit/lineage stays visible and cannot confirm a proposal save.

## Recovery and export

Local draft and frozen operation data are scoped to the authenticated actor in
the current browser. They do not contain stored authority, credentials or signed
requests. A storage failure blocks submission and keeps the on-screen content.
Uncertain saves keep the exact task, operation key, normalized offer and base
revision; recovery/retry never silently creates a replacement operation.

Canonical changes do not overwrite unsaved local text. Revision conflicts need
an explicit read/rebase decision. A matching saved historical operation is
distinguished from the current canonical revision. Actor changes/signout clear
in-memory proposal state, and stale callbacks cannot adopt another task or save.

Exports identify either a local unsaved draft or an exact canonical task/project
revision. They include unresolved fields, proposed criteria, price assumptions
and unproven demand. They exclude actor/authority data, tokens, operation keys
and native execution identities. Export does not transmit the file to a client.

## Qualification boundary

Regression evidence includes shared native/JS contract tests, compiled UI
state/transport tests, exact-source gateway normalization, native service command
and GET projection fixtures, and native-to-UI Markdown byte comparison. Native
fixtures capture the actual command/audit JSON emitted by SQL construction;
their database state is controlled. They do not execute PostgreSQL SQL or prove
transaction enforcement, process-restart recovery, real signatures or sockets.

Mounted-browser interaction, real localStorage/download behavior, live signed
PostgreSQL operation, installed Mac behavior, customer outcomes and cash remain
separate qualification gates. The feature does not reuse gated attachment
storage, native human-revision identities, Bookkeeper or Flow authority.
