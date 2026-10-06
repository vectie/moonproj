# Accepted human-result export

An accepted task whose delivery source is an immutable human revision exposes
**下载已接受人工修订 JSON** in its accepted report view. Refresh the formal task
if its accepted report/revision has not yet been verified. The action downloads
one JSON file; it does not send anything to another product.

The existing authenticated company gateway serves:

`GET /api/company/tasks/<task-id>/accepted-human-result`

It reads the exact accepted task, report and named report/acceptance receipts
through the existing actor/service bridge. It requires the accepted report's
`delivery_source_snapshot` to equal exactly one saved task human-revision
manifest and the canonical retained manifest on disk. It checks the captured
task/run/session/command lineage and the immutable content's size, SHA-256 and
UTF-8 round trip. Any retained attributed native output must agree; an already
accepted revision does not need a fresh runtime lookup or newly attached
continuation. The mutable original output file is never an export source.

## Wire contract

`contract_version` is `moonproj.accepted-human-result.v1`. The export has exactly
these top-level fields:

- `source_product`: `moonproj`
- `provenance_scope`: `captured_accepted_human_revision`
- `authenticity`: `unsigned_source_observation`
- `authorizing`: `false`
- `task`, `report`: captured `record_id`, positive decimal-string
  `record_version` (1–2147483647) and `record_digest`
- `revision`: `revision_id`, `original_run_id`, `session_id`,
  `original_command_id`, `output_command_id`, `output_evidence_id` and
  `revision_snapshot_digest`
- `content`: `encoding: "base64"`,
  `media_type: "text/plain;charset=utf-8"`, `size_bytes`, `sha256` and `data`

Digests are `sha256:` followed by 64 lowercase hexadecimal digits. Task/report
references use the same captured projection basis as the lesson handoff.
`revision_snapshot_digest` hashes UTF-8 bytes of the accepted, parsed, pinned
manifest's `stringify()` result. It is **not** the lexical digest of the original
manifest file: changing only that file's JSON whitespace does not change it.

The body is strict UTF-8, contains no NUL, and is at most 262,144 bytes. Empty
text is valid and has an empty Base64 `data` string. Exported metadata contains
no workspace, absolute filesystem path or output-path field. Native record and
command identifiers retain their bounded owner grammar; opaque evidence IDs
retain relative slash/colon forms but may not disclose absolute machine paths,
the captured workspace root, backslashes or controls. Filenames use safe,
bounded task/revision-derived components.

Unchanged accepted source and bytes produce identical response/download bytes.
The UI retains those response bytes unchanged, rejects stale task/report/source
responses, and permits a read-only retry after a failed or timed-out request.

## File journey

Save the downloaded original JSON file. In MoonDesk, explicitly import that
file into the accepted human-result package flow. Desk validates the bounded
source/body integrity and stages the decoded body plus the unchanged original
source JSON for the existing Book package collector. Choose the intended Book
destination and inspect the package through that established flow.

This is a captured unsigned source observation. A digest identifies retained
bytes and does not establish live source authenticity. Export/import does not
create a new model run or command, change Proj acceptance, grant authority,
write a ledger, or make a Book review/acceptance decision. No Town viewer or
automatic downstream publication is added by this export.
