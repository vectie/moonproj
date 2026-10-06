# Optional reviewed Book guidance before first Start

This source-level feature connects an existing formal MoonProj task to one
explicitly selected MoonBook outcome lesson. It does not add a runner, review
authority, permission, company command family, or learning ledger.

## Founder flow

1. Read the canonical task, before its first native Start
2. Prepare the optional read-only Book query and choose the Book origin
3. In Book, add truthful customer/decision conditions and find reviewed lessons
4. Inspect the guidance, all conditions, named review and source references;
   explicitly choose one lesson
5. Inspect the returned observation in Proj, then Start or remove the selection

Ordinary Start remains available without Book or without a matching lesson.
An explicitly selected malformed or stale task binding requires refresh or
removal, rather than silently dispatching without the requested guidance.

## Separate contracts

`moonproj.book-guidance-query.v1` binds a canonical task ID, revision and digest
to a minimal snapshot containing task ID, project ID, suite product ID and
revision. Automatic query conditions are `project_id` and optional
`suite_product_id`. A suite catalog tag is not a business `product_id` or a
lesson's `source_product`; those meanings must not be inferred interchangeably.

`moonbook.task-guidance-selection.v1` returns the exact handoff and query,
selected lesson reference/title/guidance/conditions, named review, source
references and a dated currentness observation. It excludes raw outcome,
assessment and unrelated Book memory bodies. It is an unsigned, explicitly
chosen advisory snapshot, not independent proof of review authenticity,
current factual truth or semantic applicability.

The older accepted-task/report lesson handoff and minimal saved-lesson receipt
retain their original shapes and restrictions.

## Capture and retry

The first Start validates optional guidance against the latest canonical task
before accessing native control. The existing durable native execution stores
the exact request-body string plus the selected advisory metadata. Its prompt
contains the exact selected guidance as quoted external context, with no
additional authority. A canonical selection hash supports comparison despite
JSON object-key reordering in storage.

Every dispatch sends the request returned by the existing durable reservation.
A retry can omit tab-local advice and resume that original input. Supplying
different advice cannot replace it. If concurrent first Starts choose different
advice, the losing caller must inspect and explicitly resume the winner; it
does not silently dispatch a different selection.

Full guidance is private execution metadata. Public task readback exposes only
`moonproj.book-guidance-capture.v1` reference/digest/observation facts, marked
`captured_input`. That does not establish that a model followed the guidance.
Guidance is not stored in general browser drafts, URL content or localStorage.

Book re-queries its current journal on explicit selection. Later withdrawal or
supersession does not rewrite already captured execution input. The observation
can age; refresh and explicit removal/reselection remain user choices before
capture. No freshness TTL or automatic learning-performance claim is added.

The selection is bounded to 32 KiB UTF-8 and the complete existing native
reservation remains bounded to 128 KiB. Neither is silently truncated.

## Qualification boundary

Controlled tests use real source serialization, reducers, handlers, query
matching, private/public projection and native request construction with
explicit company/native transport fixtures. They do not establish mounted
browser interaction, real sockets/signatures, PostgreSQL transactions or crash
recovery, provider execution/adherence, installed Mac behavior, customer/cash
evidence, Book capability activation, or measured learning improvement.
