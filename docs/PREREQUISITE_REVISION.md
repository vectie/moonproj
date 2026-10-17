# Revise prerequisites on a saved delegation board

An existing local proposal may wait for the wrong input. Before importing the
board, select it in **Delegate a deliverable**, then open **Revise task
prerequisites**. This edits the executable proposal through an inspectable child
board; it never overwrites the original native plan or an existing run.

1. Choose the task by its stable ID. The selection shows its current prerequisites
   and offers every other task with its name and accountable owner.
2. Check the tasks whose independently accepted results it must wait for. Uncheck
   every box to propose an independent task. Explain the change.
3. Choose **Preview prerequisite revision**. Inspect added and removed edges,
   the changed task and downstream tasks, the complete task/source mapping and
   proposed MoonFlow graph, and the exact new execution digest.
4. Choose **Save review-pending prerequisite revision**. Select the saved child
   after reload. Its history retains the parent board/digest, old/new prerequisites
   and reason. The parent remains available for comparison.
5. Obtain the existing exact operator review for this new digest before using
   **Import / prepare ready tasks**. An earlier board's review cannot authorize
   the changed graph. The existing independently named task-review rule still
   controls downstream readiness.

Changing the selected task, checkboxes, reason or saved board invalidates the
preview. **Cancel prerequisite draft** clears it, including an in-flight preview;
late responses cannot restore discarded scope. Once save starts, cancellation
cannot pretend that nothing was written. Repeat the exact request against the
same parent to recover its same child after a lost response or restart.

## What changes, and what stays historical

The child has a new content-addressed ID, execution digest, work-graph declarations
and Claw requests. Its actual `depends_on` edges use the selected prerequisites.
Requests identify the original source plan as historical and point to the current
reviewed task scope. Current prerequisite context and revision reasons also appear
in the existing selected-owner Markdown brief.

Only the chosen task's prerequisites change. Owners, task acceptance, required
evidence, assigned source files, original native plan bytes, authored costs and
estimates remain unchanged. A revision's affected-task list shows the changed
task and its transitive consumers; the entire new execution digest needs its
own operator review. Saving a child does not transplant prior task acceptance.

Prerequisites are canonicalized to saved task order. Reordering an identical set
is a no-op; duplicate, missing and self prerequisites, cycles, empty reasons and
stale parent/preview digests are rejected before a child is saved. History is
bounded to 32 revisions. Existing task-count and request-size limits still apply.
Preview verifies source-plan and assigned evidence bytes without writing files.
Save re-verifies them before copying. Missing, changed or symlinked input files
fail closed. An identical retry repairs missing child materialization; conflicting
existing child bytes are never overwritten.

## Planning order and authority

Revise prerequisites on an unimported original or owner-handoff board. Repeated
prerequisite revisions and owner handoffs can compose. Then optionally apply
specialist delegation and owner capacity planning. Those child proposals preserve
the revised edges and history. Further prerequisite edits on specialist, capacity
or rework scopes are refused, so their derived acceptance/lane edges cannot be
silently removed. Return to the earlier unimported parent for another proposal.

An imported board or one with a pending native preparation intent is rejected,
even if no provider call is known. This feature does not cancel or migrate runs.
Owner names remain accountability labels, not authenticated assignments. A local
proposal is not a company signature, external acceptance, budget authorization,
provider approval, payment or evidence that work executed. No network provider,
formal company service or native execution is invoked by preview or save.

## Scope and qualification

This is bounded development support for MOONPROJ-UC07 / MOONPROJ-B07's exact
versioned review-pending handoff and explicit changed-dependency review boundary.
It does not replace native planning's cost invariants, complete the broader
requirement or qualify the signed-execution roadmap. Local retry/restart and
labeled task controls provide supporting evidence for MOONPROJ-N02/N04 only.

Focused tests cover production compiler/host functions, mounted production panel
handlers and real loopback HTTP preview/save/restart, including source corruption,
cycles, stale scope, imported/preparing parents, cancellation, detached controls,
repeated saves, history and owner/specialist/capacity composition. The event DOM
is not a graphical browser, accessibility or keyboard qualification. Existing
Flow/Claw regression adapters are explicitly synthetic. Live native execution,
providers, signed company/PostgreSQL, customer/payment and full release gates
remain unqualified. Warren packaging remains blocked by the missing verified
pinned Warren artifact; prohibited Chromium is not retried.

Focused regression command from the repository root:

```sh
node --test --test-concurrency=1 scripts/deliverable_dependencies.test.mjs scripts/delegation_brief.test.mjs scripts/deliverable_acceptance.test.mjs scripts/deliverable_evidence_panel.test.mjs scripts/deliverable_owner_handoff.test.mjs scripts/deliverable_workflow.test.mjs scripts/deliverable_http.test.mjs scripts/portfolio_execution.test.mjs scripts/portfolio_dispatch.test.mjs
```
