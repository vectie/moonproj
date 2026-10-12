# Resolve returned plan feedback

The existing [offline plan-review worksheet](PLAN_REVIEW_WORKSHEET.md) now has a
**Preparer feedback inbox** beneath the individual reviewer form. A planning
preparer can collect several returned reviews of the same snapshot, inspect
conflicting comments beside the exact source row, record their responses, and
save a combined session to resume or share manually. No new server or CLI is
needed. The individual reviewer form and its JSON format remain compatible.

## Complete workflow

1. From Projects → **复用完整计划模板**, download a fresh **下载离线计划审阅表
   (.html)** for the current draft. Keep this exact HTML. Reviewers can annotate
   copies and download their `plan-review-notes.json` using the existing controls.
   Reviewers and preparers exchange files through their own approved method.
2. Open this HTML locally with JavaScript enabled. In **Preparer feedback inbox**,
   enter your self-declared preparer label, then use **Add returned review-notes
   JSON files** to select one or several returned files. No upload occurs.
3. Inspect the per-review coverage counts and feedback grouped by source row.
   Each group displays the complete source scope/budget, owner, task, milestone
   or risk. Each feedback item identifies its imported review number, reviewer
   label, original state and note. The overview maps review numbers to filenames.
   Conflicting statements stay separate. Blank reviewer names stay visibly blank.
4. Set a **Preparer disposition** and record a **Preparer response / planned change**:
   - `open`: more work or a decision is needed; a note is optional.
   - `change-planned`: describe the proposed edit; it still needs action.
   - `answered`: record your answer. This is not evidence that the reviewer agrees.
   - `not-adopted`: explain why you are not adopting the suggestion.
   Any non-open disposition requires a nonblank explanation before saving.
   Until an explanation is present, the item still counts as needing action.
5. Select **Needs action** to focus open, change-planned or unexplained items.
   Counts update immediately as you type. An item stays in place while editing
   so focus is not lost; choose **Refresh feedback view** or change the filter
   to recompute the visible list. **All feedback** restores every feedback item.
6. Choose **Download feedback inbox JSON**, verify `plan-review-inbox.json` saved,
   and keep the original HTML. Reopen that HTML later and select **Reopen saved
   feedback inbox**. Reviewer observations and all preparer responses return.
   Replacing an edited inbox asks for confirmation; Cancel keeps current work.
7. If an edit is warranted, make it separately in MoonProj, export a new snapshot
   and obtain any required new review. A planned change never edits this source
   snapshot, applies a plan change or becomes a formal approval. An old inbox
   cannot load into a changed snapshot, even a whitespace-only template change.

The inbox includes every nonblank reviewer note, plus every question or change
request even without a note. Empty `not-reviewed` and `no-change-requested` rows
remain intact in the imported review and its coverage counts, but do not create
response items. Zero items needing action is not a claim that every row was
reviewed, that the reviewers agree or that the plan is approved.

## Return replies to one reviewer

Use [per-reviewer response packets](PLAN_REVIEW_RESPONSE.md) to hand back one
submission and its replies without the other imported reviews. The reviewer
loads it into the same worksheet, reads replies beside source rows and returns
revised notes through the existing inbox import. The complete plan is included.

## Repeated files, revisions and retained context

Identical parsed review content is imported once, even when the JSON formatting
or filename changes. Existing responses survive repeated imports. Deduplication
compares all permitted content after canonical field ordering, including the
exact source-template string, reviewer label and all states/notes. It does not
authenticate the sender. A changed review with the same label is a separate
numbered review; it never replaces earlier comments or inherits their answers.
There is no inferred reviewer identity, consensus or latest-revision policy.

The saved `moonproj.plan-review-inbox.v1` JSON holds the exact source-template
string, preparer label, imported filename labels, each complete original review
object, and responses explicitly associated with its review and annotation
indexes. Values are retained; original JSON file formatting is not. Keep the
original returned files if their original bytes matter. No timestamp, signature
or verified identity is fabricated. The input/source files remain unchanged.

To start over, **Clear inbox in this tab** asks before clearing a nonempty inbox.
It does not remove downloaded files or affect the separate reviewer form.
Individual reviewer JSON and combined inbox JSON use different load/save
controls. Loading an individual reviewer draft never clears the inbox.

## Limits, recovery and authority

The inbox supports 12 distinct reviews. A selected batch, one loaded file, and
the serialized combined inbox are each limited to 40,000,000 bytes. If a full
collection exceeds that limit, retain smaller separate inboxes. Preparer and
filename labels allow 1,000 UTF-16 units; each response allows 16,384. Imported
reviews retain the existing worksheet’s label/note/template limits. A malformed
file, incomplete response set or different snapshot rejects the whole selected
batch/load without applying part of it. Editing, clearing or loading newer data
while a read is pending prevents the older read from replacing newer work;
reselect the intended file after finishing edits if its read was superseded.

There is no automatic storage. The close warning remains after requesting a
download, because a request cannot prove the file was saved; browsers can suppress
that warning. Always verify the saved file. Download/open policies may prevent
use in some browsers. No remote fallback, network, provider or dependency is used.

All input text is rendered as text. The worksheet’s restrictive content-security
policy remains. Both HTML and JSON contain the complete plan and private free
text; the combined JSON additionally contains every imported review and preparer
response. Inspect before sharing. Nothing is sent automatically.

Reviewer labels and preparer dispositions are unauthenticated drafting context.
This creates no native plan validation, signed command, canonical task, accepted
work, customer acceptance, spend, accounting entry or payment. It adds no actor
credentials, authority or receipts, and does not alter company or ERP state.

## Focused verification

From the repository root:

```sh
node --test scripts/test_plan_review_inbox.mjs scripts/test_plan_review.mjs scripts/test_trello_plan.mjs scripts/test_import_csv.mjs
```

The 11 new tests execute the actual production JavaScript renderer and embedded
worksheet handlers in Node with a synthetic DOM. They cover several reviewers,
source-row grouping, conflicting comments, dispositions, filtering, actual Blob
contents, saved HTML/JSON disk reopen, repeated/revised reviews, coverage without
approval, exact-snapshot rejection, retained edits and interrupted/replaced reads.
The 53 existing worksheet/Trello/CSV tests remain regression checks. The reusable
test harness now supports multiple event listeners, as browsers do.

No Moon command was invoked: no MoonBit interface changed, and only the existing
JavaScript extern body and exported HTML were extended. Native MoonBit compilation,
mounted browser behavior, visual/accessibility QA, OS file dialogs, PostgreSQL,
provider execution and full-product acceptance remain unqualified. No dependencies
were installed. PRD statuses are unchanged. R50 remains the last fully verified
cumulative baseline; R51–55 remain separate.

PRD rationale: MOONPROJ-UC07/B07 calls for review-pending plan artifacts and
invalidating review when plan inputs change. This closes the bounded manual gap
between receiving several returned worksheet reviews and deciding the preparer’s
next edits, while preserving each comment and its snapshot. N01 requires draft,
signed-company and financial authority separation. This workflow does not fulfill
signed orchestration or commercial closure, nor claim measured coordination savings.
