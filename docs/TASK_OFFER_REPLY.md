# Record a customer's reply to a proposal

## Founder flow

Open a saved proposal on an ordinary, creator-owned, pending task that has not
started or received execution/report/delivery records. Choose **Record customer
reply**, then select the exact saved proposal version the customer responded to.
This records a reply you already received; it does not send a message.

Enter its summary and choose interested, changes requested, declined, or other.
The respondent and received UTC time may stay unknown. Choose either an existing
source reference or an explicit human observation. A reference is retained as
text; MoonProj does not fetch it, upload private evidence, or authenticate its
contents. The signed company actor is the recorder, separately from the claimed
respondent.

**Save reply** waits for the exact company command and audit readback. Afterwards,
use the existing proposal editor to revise or close the proposal. Earlier
proposal content and the original reply stay visible. Replies to an older version
do not become replies to a newer one. To correct a transcription, append a
correction with a reason. The original remains in history.

An interested reply or a recorded "yes" does not establish a signed order,
customer delivery acceptance, validated demand, revenue, or cash. This feature
does not modify Product In-Gate or add an admission requirement. Existing
problem/commitment receipt references may be reused when relevant.

## Ownership and boundaries

- Local reply drafts are explicit working state in the current browser tab
- The company service owns saved reply commands and their audit history
- A reply advances the pending task's record revision without changing its
  proposal, internal acceptance criterion, status, execution, demand state, or
  financial fields
- Reply bodies are stored in immutable commands, not the task list projection
- Ordinary proposal exports do not contain reply contents
- Executing, accepted, deleted, imported, or otherwise ineligible tasks cannot
  receive new reply writes; exact saved-operation replay still works later
- Saved task/report identities used by Book are not changed by an after-delivery
  feature, because after-delivery reply recording is outside this slice

The authored external acceptance and reconciled-cash requirement remains broader:
outbound delivery, inbound acceptance, partial acceptance/dispute, invoice,
partial collection, refund, and authentic provider/bank evidence need their own
records. None is inferred here.

## Reply contract

`moonproj.offer-reply.v1` accepts only:

| Field | Meaning |
| --- | --- |
| schema | Exact contract identifier |
| offer_revision | Positive integer identifying an actual saved proposal revision |
| respondent | Claimed respondent or null; never defaulted to recorder |
| received_at | Real UTC timestamp `YYYY-MM-DDTHH:mm:ssZ` or null |
| summary | Required nonblank multiline reply summary |
| kind | interested, changes_requested, declined, other |
| evidence_kind | reference or human_observation |
| source_reference | Existing source locator or null; required for reference |
| supersedes_reply_id | Prior reply receipt being corrected or null |
| correction_reason | Required when supersedes_reply_id is present |

CR and CRLF normalize to LF; outer whitespace is trimmed at validation/save.
Raw in-progress editor input is not normalized per keystroke. Bounds count
Unicode characters: summary 8192, respondent/supersession reference 512,
source/correction text 2048. Canonical JSON is limited to 32 KiB. Unsupported
control characters, invalid calendar/time values, unknown fields, and missing
required selections are rejected rather than silently rewritten.

The company receipt supplies `reply_id` (the event ID), `record_revision`,
`recorded_by`, `recorded_at`, audit identity/state, operation identity and normalized
reply content. Its explicit labels are `authorizing=false`,
`customer_acceptance=not_asserted`, and `cash=not_asserted`.

## Existing API and storage

The UI uses the existing signed `PUT /api/company/plan/tasks/{id}` with an
exclusive reply body: idempotency key, existing task-update authority,
`reply_base_revision`, and `offer_reply`. The base task revision is independent of
the proposal revision being answered.

The service normalizes the reply, verifies creator/project authority, checks the
existing pending/unexecuted eligibility, and resolves the exact saved proposal
and optional prior correction from task-scoped persisted history. A correction
must retain the same proposal target and cannot overwrite an already superseded
reply. The original and correction are separate commands.

An update reuses the existing `plan_task` command family,
`company_record` command/audit rows, and revisioned `company_aggregate_projection`.
The existing task CAS/lock and proposal eligibility guard enclose all inserts.
No table, CRM, payment ledger, upload store, provider call or outbound message is
introduced. The task projection only changes event/update metadata; reply text
lives in immutable commands.

`GET /api/company/tasks/{id}` retains its existing envelope. The commitment
history gains `offer_reply_history`, derived from task-scoped command/audit rows.
Missing or conflicting lineage is visible and cannot verify a saved reply.

Same-actor exact-operation replay is checked before later state/revision changes.
Changed target, actor, authority, base revision or normalized content cannot reuse
an operation identity. After an uncertain write, the UI reads the same operation
before offering an identical retry. It does not silently allocate another key.

## Recovery and privacy

The UI explicitly saves reply working state in tab-scoped session storage.
Switching tasks and refreshing the same tab can restore it. Recovery after closing
the tab is not guaranteed. Switching accounts clears local working state and
attempts to remove that account's tab copy; a removal failure is reported.
Storage failure is visible and
prevents an initial send whose exact operation has not been retained. A confirmed
canonical save clears the private reply payload from that tab's draft record.

Account/session-generation checks and exact task/project/operation readback keep
late callbacks from claiming another draft was saved. The reply body is absent
from ordinary task lists, URLs, proposal Markdown, and automatic Book material.

## Qualification scope

The candidate is tested through shared normalization/history, real compiled UI
reducer/transport/SSR functions, exact production gateway normalization, and
exact native company-service command/SQL/detail functions in a thin harness.
Database reads are controlled fixtures and JSON emitted by production SQL is
inspected. This is not PostgreSQL execution, socket/signature exchange, mounted
browser/storage/accessibility testing, provider execution, deployed acceptance,
or authentic customer evidence. Those limits are retained in the feature report.
