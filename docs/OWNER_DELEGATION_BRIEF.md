# Prepare an owner delegation brief

A saved task board describes the whole deliverable. An owner needs a readable
brief of their own task criteria, incoming dependencies, required outputs and
who needs those outputs next. In **Delegate a deliverable**, select a saved board
and open **Prepare an owner delegation brief**.

1. Choose a current accountable owner. This uses the board's current scope,
   including owner handoffs, specialist contributions and capacity lanes.
2. Leave **Include full text of this owner's assigned local sources** unchecked
   for a reference-only brief. To deliberately include source content, check it.
   This includes complete shared files, not selected excerpts. Files assigned
   only to other owners are excluded. Inspect the packet before sharing it.
3. Choose **Preview owner brief**. Read the complete Markdown, including task
   acceptance, required evidence, prerequisite owners, downstream consumers,
   task-specific source references and retained planning history.
4. Choose **Download owner brief Markdown**. The host re-verifies the saved plan,
   source bytes and exact preview digest before the local browser download.
   The file contains the board, plan and execution-scope identities and a clear
   authority boundary. No email, assignment, provider call or execution occurs.

A changed owner, source-text choice, board selection or refresh clears the old
preview. **Close owner brief** clears the selection and opt-in and dismisses its
preview. It also suppresses a late preview/download response. Repeated clicks
are serialized; detached controls cannot operate on a newer board. Preview and
export create no files or additional boards on the host. Reopening after a host
restart reproduces the same packet from the same saved scope and choices.

## What the packet means

This is a scope briefing, not a current execution-status report, import artifact,
operator review, company assignment or proof of completed work. It never claims
that a prerequisite is accepted. Named acceptance of each exact output still
controls downstream execution through the existing native workflow. Customer
acceptance, delivery and payment remain separate.

Owner handoff reasons for selected tasks and the specialist integration/capacity
boundaries remain visible. For rework, retained carry-in bytes are verified and
listed as references with their original review identity. Their contents are
not included by the source-text option. This does not re-accept those results.

The packet does not automatically include workspace paths, model settings,
operator configuration, execution credentials or the full original native plan.
Authored criteria, names and optional source text may themselves contain private
information; this is not an automatic redaction or authorization-to-share tool.
There is no automatic sending or cross-product ingest.

## Verification and limits

The existing source intake bounds apply: 12 text files, 128 KiB each and 256 KiB
total. Included UTF-8 source text retains BOM and line endings inside dynamically
sized literal fences; the surrounding Markdown is a presentation, not a file
transfer format. Original byte counts and digests remain alongside each source.
Authored metadata is Markdown-escaped and the UI displays packet text without
executing HTML. The total exported brief is bounded to 2 MB. Verification checks
all board source files, including when exporting references only. Changed,
missing or symlinked source files block export. Rework carry-ins retain the
existing 2 MB/file and 8 MB/verification bounds.

This is bounded usability support for MOONPROJ-UC07/B07's exact versioned
review-pending plan handoff. Those requirements do not specifically promise this
owner-brief export and are not marked complete. It also keeps a useful local
workflow when execution configuration is absent, without introducing company
facts. It does not alter the authored PRD or the original founder packet's B02
contract.

Focused verification exercises actual production helpers, mounted controller
handlers, the Markdown Blob download adapter and real loopback HTTP with
restart. Tests cover current-owner composition, opt-in exclusion, source and
carry-in corruption, stale digests, cross-origin requests, cancellation, repeated
clicks, new selections and disposal. The event DOM is not a graphical browser,
layout, keyboard or accessibility qualification. Existing native Flow/Claw
workflow fixtures are explicitly synthetic; installed execution, providers,
company services, customer acceptance and full release gates remain unqualified.

Run the feature's tests and retained regressions:

```sh
node --test --test-concurrency=1 scripts/delegation_brief.test.mjs scripts/deliverable_acceptance.test.mjs scripts/deliverable_evidence_panel.test.mjs scripts/deliverable_owner_handoff.test.mjs scripts/deliverable_workflow.test.mjs scripts/deliverable_http.test.mjs scripts/portfolio_execution.test.mjs scripts/portfolio_dispatch.test.mjs
```
