# Reuse a complete plan

Projects can download the current editable plan as `plan-template.json`, then
reuse it in another selected company project. This carries more than the task
CSV: scope notes, currency and budget strings, owners and roles, milestones and
their dates/criteria/evidence, tasks and dependencies, and risks and mitigations.
It works before native preparation and after reopening a saved version.

## Operator workflow

1. Open a company project in **Projects**. In **复用完整计划模板**, choose
   **下载可复用计划模板 (.json)**. Keep this file if you want to preserve the
   current draft before replacing it.
2. Select the destination project. Paste the downloaded JSON into
   **计划模板 JSON**, then select **预览模板**. Expand **查看完整模板内容**
   to inspect every field. Pasting, previewing and choosing a mapping do not
   change the current draft or its prepared result.
3. Choose the template owner whose work you will take over. Enter your display
   name. That owner's role and every task/milestone/risk assignment are retained;
   its ID becomes the current signed-in preparer and its display name is the
   name you entered. All other names and roles remain editable text.
4. Select **用模板替换当前草稿**. This explicitly replaces the entire current
   browser draft; it does not append or merge. Each copied row gets a fresh local
   identity and references are remapped together. The destination project stays
   selected, the request/time are refreshed, and the old prepared preview clears.
5. Edit dates, scope, names and cost assumptions for the new project. Dates are
   copied exactly, never shifted to today. Amount strings and currency are copied
   exactly, never recalculated or converted. Dependencies and row order are
   copied exactly; use the existing dependency explorer to repair order if needed.
   To move the copied dates together, use the separate
   [milestone rescheduling preview](MILESTONE_RESCHEDULING.md) and apply a new
   anchor date while retaining the original spacing.
6. Use the ordinary **原生准备并保存计划** workflow when ready. It performs the
   existing native validation and returns the same review-pending plan semantics.

**清空模板输入** discards only the pasted source and preview. Changing the
source invalidates its preview. Choosing another project or changing the actor
clears template staging. Successful import clears staging so a repeated click
does not import twice. A failed preview/import leaves the current draft, saved
preview, revision and browser storage intact. Imported drafts use the existing
actor/project-scoped local reload behavior; immutable saved versions are unchanged.

## Portable format

The exact format is `moonproj-plan-template/v1`. See the runnable synthetic
[two-stage delivery template](examples/delivery-plan-template.json): two owners,
four tasks, two milestones and one risk. It proposes USD 600.90 of work against
a USD 1,000.00 limit with USD 100.00 contingency. Those are planning examples,
not purchases, commitments or evidence that any work occurred.

Top-level fields are `format`, `notes`, `currency`, `limit`, `contingency`,
`owners`, `tasks`, `milestones`, and `risks`. Row fields match the preview. Amounts,
dates and all other authored text are strings. IDs are template-local references:
`owner-1`, `task-1`, `milestone-1`, and `risk-1` on download. Every ID must be unique
within its row category. Import also accepts other nonempty local IDs.

Limits match the workbench: 1–40 owners, up to 100 tasks, 40 milestones and 100
risks, with a 1,000,000 UTF-16 code-unit file limit. Unknown/missing fields, wrong
types, duplicate row/reference IDs and missing nonblank references are rejected
with a repair message. Incomplete authored text, blank assignments, invalid date
or amount text and dependency order/cycles are preserved for editing. Template
acceptance means the copy is structurally importable, not that native plan
validation has passed. Do not add status/approval/actual-cost fields: this format
has no such semantics and rejects unknown fields instead of silently dropping them.

## Sharing and boundaries

The exported envelope excludes the source project, request ID, prepared time,
actor IDs, saved artifact and receipts. Owner, task, milestone and risk identity
fields become local slots. Free-form notes, names, roles, URLs and other authored
text are not scrubbed; review them for private information before sharing.

Import/export is browser-local. It does not fetch a remote template, call an
agent or provider, save a native plan, create a task, confer authority or affect
financial records. Native preparation remains a separate explicit operation;
the result remains pending review with no spend, accounting, payment, contract
or work-execution effects. Templates do not preserve provenance of an accepted
artifact, transfer saved history, or establish another person's identity.

To retain an existing destination plan, use the separate
[preview-and-append reusable phase](PLAN_PHASE_APPEND.md) operation. It adds
complete template rows with fresh IDs while preserving destination scope,
budget and existing rows. It does not merge matching names or infer joins.

JSON paste is the supported import route. There is no file-picker, automatic merge mode,
automatic rebasing on import or universal project-management importer.

## Local Trello intake

The same panel has a separate [Trello board JSON preview](TRELLO_BOARD_IMPORT.md)
button. It converts open cards to unassigned planning tasks and preserves source
context in notes before the ordinary explicit replacement/append review. This
is a local conversion, not a remote board connection or native plan validation.

## Collect offline review feedback

The same panel can download an [offline plan-review worksheet](PLAN_REVIEW_WORKSHEET.md).
Keep its HTML snapshot and save review notes as JSON to reopen a review later.
Feedback remains separate from the editable plan and any company approval.

Returned worksheet reviews can be collected in the same HTML’s
[preparer feedback inbox](PLAN_REVIEW_INBOX.md). Keep original reviewer comments
separate from your answers and planned changes, filter items needing action,
and save/reopen the combined review session without changing the plan.
