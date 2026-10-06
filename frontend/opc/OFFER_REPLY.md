# Pre-execution customer reply recording

The task detail offers **记录客户回复** for creator-owned ordinary pending tasks that have a verifiable saved proposal and no execution or acceptance lineage. This is a receipt for a reply already received; it does not send a message or authorize any execution, acceptance, commitment, or financial action.

- Select the exact saved proposal revision from audited `offer_history`; this is distinct from the current task revision used for compare-and-swap
- Explicitly select the reply kind and either a real source reference or human observation. Respondent and received UTC time may remain unknown. The recorder comes from the authenticated actor and is not substituted for the respondent
- Raw multiline edits are retained until explicit save. Shared validation normalizes the canonical payload
- Corrections append a receipt with the original reply ID and a mandatory reason. The original remains visible; the target proposal revision cannot change
- Proposal revision/close controls remain available beside reply history. A reply-only task revision never becomes a new proposal revision, and replies do not transfer to a later proposal

## Local privacy and recovery

Working reply content uses actor-scoped `sessionStorage`, never `localStorage`, URL state, list projections, or Markdown exports. Refresh and task navigation retain the current tab's drafts. Closing a tab is not a qualified recovery path. Account changes clear in-memory drafts and attempt removal of the previous account's tab storage; storage failures are shown. Actor and authentication-generation guards reject old callbacks and storage effects.

Before PUT, the normalized reply, task/project identity, base revision, and idempotency key are frozen in tab storage. A storage failure prevents sending. PUT completion alone cannot claim success: GET detail must contain the exact task/project, recorder, operation key, normalized reply, record revision, event/reply ID, and available audit. Uncertainty preserves the frozen operation; explicit retries resend byte-identical content. Conflict requires explicit review/rebase. Exact successful readback removes private content from the tab-local draft and retains saved-state metadata; browser write failures remain visible.

## Verification

`dispatch_reply_baseline_wbtest.mbt` is the semantic red-to-green affordance test. Reducer/SSR tests cover draft loss, navigation, identity changes, stale CAS, late callbacks, corrections, version targeting, and escaped multiline content. Serialized tests invoke the actual compiled PUT/GET transports in an isolated, non-networking browser harness. `MOONPROJ_REPLY_REQUEST_OUTPUT` and `MOONPROJ_REPLY_TRANSPORT_OUTPUT` write request captures; `MOONPROJ_REPLY_DETAIL_INPUT` supplies the actual native service detail bytes for decoder/recovery verification, and `MOONPROJ_REPLY_RENDER_OUTPUT` saves its rendered UI.
