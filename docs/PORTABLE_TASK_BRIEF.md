# Portable task brief

In **Task dispatch**, open a local draft and expand **可重用工作简报 · JSON
导入与导出** (Reusable task brief). **Download reusable brief (.json)** saves
`moonproj-work-brief.json` from the currently open draft. It contains exactly:

- Task title and acceptance criterion
- Source reference and observed problem
- Planned start and planned end, as entered

This is a reusable task definition, not a full backup. Project and owner
assignments, login identity, local draft/task/request IDs, product binding,
execution workspace/model, task receipts, attached research and proposal records
are excluded. The existing **Export local work packet Markdown** remains available
for a readable copy with richer research/proposal context; Markdown is not an
input format for this JSON importer. Neither file is a recovery record for an
uncertain formal create request. Keep that original draft and its recovery ID.
Free text is preserved exactly and can itself contain personal information or
secrets: inspect it before sharing. Export does not send the file anywhere.

## Reuse a brief

1. Open or create the destination local draft. Set its company project if known.
   Its current content will be retained.
2. Choose a previously exported JSON file, or paste its JSON and choose **Preview
   task brief**. The preview shows all six fields and the destination project.
   Source text is displayed, not opened or fetched.
3. Choose **Create editable draft**. This adds one fresh ordinary local draft in
   the destination draft's project. The old draft and any currently selected
   formal task remain unchanged. The new draft has new local identities, no
   product binding, and blank owner/workspace/model fields.
4. Edit the imported text, check dates, and fill any missing assignment or
   execution settings. The normal local draft store retains it across reload
   when an authenticated actor and browser storage are available. Formal task
   creation remains the separate existing action.

Text retains Unicode, line breaks, spacing and empty values. Import does not
validate or infer schedule dates; a missing or malformed date stays editable.
The existing Create validation is still required for a formal task. Reusing a
brief may carry an old date, so review both dates explicitly.

No import replaces or merges with the old draft. Applying consumes the preview;
a repeated Apply has no effect. Deliberately choosing and importing the file again
creates another local draft. There is no cross-file deduplication or synchronization.

## Failures and cancellation

Malformed JSON, a different schema, missing/non-text fields, unsupported fields,
oversized files and unreadable files show an error without modifying any draft.
A failed preview cannot apply earlier bytes. Cancel, closing the draft, switching
drafts, changing the destination project, leaving Dispatch or changing login
identity clears the preview. Late file callbacks cannot reopen it. A reload also
clears the temporary preview; imported drafts use normal local recovery.

If storage is unavailable, the imported draft stays on the page and the existing
storage warning says it was not saved. Keep the page open or download the brief.
The original on-page draft remains intact. No failed file read or storage attempt
submits a company request.

## Format and verification

Schema: `moonproj.work-brief.v1`. All six fields above are required strings, named
`title`, `acceptance`, `source_reference`, `observed_problem`, `begin_date` and
`end_date`. Unknown keys are rejected. Each string is at most 8,192 UTF-16 code
units. The entire UTF-8 JSON input is at most 262,144 bytes. Export uses the same
limits and never truncates a field. This importer accepts the brief schema only,
not a whole draft-store record, MoonFind export or arbitrary Markdown.

Nine focused tests execute the pure codec, production UI reducers/rendering,
download bytes, actual file-selection callbacks, import/local-storage reload,
error and cancellation paths. Browser APIs are synthetic Node adapters. These
checks do not qualify a graphical browser, keyboard/screen-reader ergonomics,
a live gateway, PostgreSQL, task execution, customer acceptance or payments.
