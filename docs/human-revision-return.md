# Human-authored revision return

MoonDesk's bounded UTF-8 task editor saves a separate immutable human revision;
it does not overwrite the live workspace or native-agent output. The manifest
requires `capture_scope:"immutable_human_revision"` and is retained under
`.moonsuite/products/moonproj/human-revisions/{revision_id}/revision.json` with
`content.txt` beside it. The content is at most 256 KiB; the manifest is at most
128 KiB. Its base digest describes the current workspace bytes when the edit
started, not a reconstructed original native output.

The return URL carries only `human_revision_id` as a navigation hint. MoonProj
reads the exact manifest and content from the original execution's captured
workspace. It checks canonical paths, UTF-8, byte size, SHA-256, complete task
lineage, and the exact original or continuation output path/evidence/command.
An unattached native continuation is read through the existing native control
and immutable-input path; this does not attach or select that agent result.

The existing continuation gateway and authenticated internal observation route
carry a `human_revision` sibling. No human revision gets its own native command,
model, receipt, run state, or execution promotion. Original execution and native
continuation records remain unchanged. The browser never supplies canonical
revision bytes or trusted manifest fields.

Returning opens a read-only, escaped preview of the retained exact UTF-8 bytes.
The bounded `human_revision_content` readback field is transient; it never enters
the task mutation or report snapshot. A live workspace-file link is not used as
the immutable revision preview. Explicit source selection uses the existing
durable idempotent selection flow and selects
`{type:"human_revision", revision_id, original_run_id}`. Report submission and
Accept remain separate explicit actions. Each report pins the immutable manifest
snapshot and exact selected source; later source changes do not rewrite old
reports. Accepted/done work remains inspection-only at gateway, service and UI.

The shared workspace must already be available to the gateway. Missing,
changed, oversized, non-UTF-8 or symlinked snapshots fail closed. There is no
fallback transport, model execution, service startup or automatic publication.
