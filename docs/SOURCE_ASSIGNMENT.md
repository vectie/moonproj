# Give a delegated task its source files

A specialist can have a clear acceptance test and still lack the source files
needed to do the work. Saved evidence is assigned only to the tasks selected at
intake. Specialist delegation deliberately does not copy assignments implicitly.
Use **Assign source evidence to a task** to make that choice before import.

## Connected journey

1. Start with a saved native plan in **Delegate a deliverable**. Select local
   evidence files, inspect them, assign them to their original tasks, preview the
   complete mapping, and save the board. The existing intake limits still apply.
2. Optionally create **Delegate specialist contributions** for a broad task. The
   retained integration task still waits for all contributions' independent
   acceptance. New contributions initially have no local files assigned.
3. On that saved, unimported board, open **Assign source evidence to a task**.
   Choose the task by its displayed stable ID and owner. Check the saved files
   that task should use. Use **Inspect saved …** in the mapping above to read
   their verified contents. Explain why the assignment is changing.
4. Choose **Preview source assignment**. Inspect added/removed filenames, the
   complete task/source mapping, the proposed graph's `input_artifacts` and the
   new exact review digest. Preview writes nothing and starts no work.
5. Choose **Save review-pending source assignment**. A separate durable child
   appears. The original native plan bytes, source bytes, earlier boards, owners,
   task acceptance and prerequisite edges are unchanged. The child carries its
   parent ID/digest and the reason for every assignment revision.
6. Reload and select that child. Its owner brief now lists the newly assigned
   source references and assignment history; source text still requires the
   brief's separate explicit opt-in. Existing prepare/dispatch uses those exact
   files in the task's generated inputs and untrusted-evidence instructions.
   Obtain a new exact operator review first. Parent review/provider approval
   cannot authorize the changed inputs.

The portable [sample walkthrough](examples/source-assignment/README.md) combines
the existing delivery plan template with two synthetic source files. It uses
the current task IDs shown by the board and needs no fixed machine path.

## Editing and recovery

- You can add or remove existing saved files for a selected task. A file must
  remain assigned to at least one task. To move its last assignment, first save
  a child assigning it to the new task, then edit that child to remove the old
  assignment. The intermediate board is an explicit proposal too.
- This does not upload, replace, delete or fetch source files. Boards without
  local evidence must capture it during their original intake. Unknown source
  paths, duplicate references, unknown tasks, unchanged selections, blank reasons
  and histories over 32 revisions return a repairable error.
- Source assignment works before or after owner, prerequisite, specialist and
  capacity planning. Since no edge, owner or acceptance changes, those derived
  scopes remain intact. Existing restrictions on the order of those other
  planning operations still apply.
- Imported boards and boards with pending native preparation reject preview and
  save. Any existing native projection or preparation checkpoint requires
  reconciliation, including null, malformed or nonregular files; damaged native
  state never counts as a never-imported board. Rework scopes reject because they retain output-review/carry-in context.
  This cannot retarget a running attempt or transplant an old task acceptance.
- A changed checkbox, task, reason, board selection or refresh clears the preview.
  Cancel clears the draft and ignores late preview responses. A save already in
  flight cannot be cancelled as if no board had been saved. Repeated clicks are
  serialized; stale controls cannot act on a newly selected board.
- An exact retry after restart returns the same child and repairs missing
  materialization using verified parent bytes. Conflicting existing bytes are
  not overwritten. Missing, modified or symlinked plan/evidence files block
  preview/save, including files not selected for the changed task.

These are task scope declarations within one approved run workspace, not
filesystem confidentiality boundaries. All included source contents remain
untrusted material. Assignment does not send files to a person, authenticate an
owner, approve providers, accept an output/customer delivery, sign or pay.

## Product mapping and evidence limits

This is bounded support for MOONPROJ-UC07/B07's exact versioned review-pending
plan handoff. It connects existing source intake and top-down specialist planning
to actual generated execution inputs and owner-brief output. The PRD does not
specifically promise this editor, and its broader native planning and signed
execution requirements are not marked complete. Local retry/reload tests only
support N02; they do not establish signed company-service idempotency. Labeled
controls/textual state support N04 without graphical accessibility qualification.

Focused tests exercise production helpers, durable host files, mounted controller
events, real loopback HTTP/restart, and the existing synthetic Flow/Claw adapter
through specialist dispatch and independent integration review. They cover
canonical add/remove selections, preservation, stale review rejection, source
corruption, refused native-pending states, cancellation and detached controls.
The simulated native/provider responses are fixtures; no real native execution,
provider, signed company database or customer payment is demonstrated.

Run from the repository root:

```sh
node --test --test-concurrency=1 scripts/deliverable_sources.test.mjs scripts/deliverable_dependencies.test.mjs scripts/delegation_brief.test.mjs scripts/deliverable_acceptance.test.mjs scripts/deliverable_evidence_panel.test.mjs scripts/deliverable_owner_handoff.test.mjs scripts/deliverable_workflow.test.mjs scripts/deliverable_http.test.mjs scripts/portfolio_execution.test.mjs scripts/portfolio_dispatch.test.mjs
```

Full frontend packaging, graphical browser/keyboard/accessibility, installed native
execution, providers, signed company/PostgreSQL and nine-gate release qualification
remain unrun/blocking. There is no release or autonomous-operation claim.
