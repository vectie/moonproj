# Replan a local Trello board

Projects' existing complete-plan template panel now accepts a local Trello board
JSON export through **预览 Trello 看板 JSON**. This is an offline planning intake,
not a Trello connection, synchronization, or company-task import.

## Use

1. Open a company project in the existing Projects workbench. Keep a downloaded
   plan template if you may want to restore the current draft.
2. Paste your existing board JSON into **计划模板 JSON**, then choose
   **预览 Trello 看板 JSON**, not the ordinary template-preview button.
3. Expand the full template preview. Open cards in open lists become tasks,
   ordered by list position then card position. Missing positions retain export
   order within their group. Archived cards and cards in archived lists are
   excluded; the source notes show the excluded count. Archived boards reject.
4. Select the **Planning preparer** owner slot and provide your name for
   replacement. This maps only the preparer. Imported tasks stay unassigned;
   Trello members are source context, not authenticated MoonProj owners.
5. Choose the existing explicit replacement operation, or preview and apply
   an appended phase. Replacement replaces the entire editable draft. Append
   preserves the existing rows/budget/scope and adds the Trello source notes to
   the existing scope notes. Inspect the full merged result before applying.
6. Assign task owners and milestones; supply milestone dates, acceptance and
   evidence criteria, dependencies, costs, currency and budget. These are not
   inferred from the board. Then use the ordinary native prepare/save operation
   to validate a review-pending plan, or download an editable plan template.

No draft is changed by conversion/preview. Editing the pasted source invalidates
its preview. Applying clears the staging state. Append checks that the destination
has not changed since preview. Applying the same board again is a new copy with
fresh plan identities, not an update, merge, or deduplicated synchronization.

## Preserved context and limits

Task titles and source card IDs appear in the template preview. The existing
apply/append operation generates fresh plan IDs; original card IDs remain in
scope notes for provenance. Scope notes preserve the board ID/name/URL/description
and each imported card's title, list name, URL, description, due-date text,
due-complete flag, member IDs/display names, labels, and referenced checklist
names/item text/states. Missing member details are labeled rather than guessed.
Due text, including invalid or unusual dates, is retained verbatim in notes;
it never becomes a milestone or commitment. Completed checklist items and
Trello's due-complete flag never become task completion or customer acceptance.
Checklists are context, not additional tasks or inferred dependencies.

The initial currency, limit, contingency, cost, owner and milestone fields are
blank. A blank cost is unknown, not a zero-cost assertion. Lists are source
workflow stages, not dated milestones. The existing native validator remains
the authority for whether the edited plan is ready for preparation.

Supported input is one JSON board object with nonempty `id`/`name`, boolean
`closed`, and `lists` and `cards` arrays. Lists/cards require stable unique IDs,
names, boolean closed flags and card-to-list references. Optional `members` and
`checklists` arrays carry detail. Referenced checklists must be present; missing
list/checklist references reject the entire preview with a repair message.
At most 100 open cards, 1,000,000 UTF-16 input units and 1,000,000 converted-template
units are accepted. Partial task batches are never returned on error.

Comments, attachments, activity/actions, custom fields, cover images, votes,
start dates and other fields are not imported. The preview notes warn about
these omissions; retain the original export if they matter. This is a bounded
subset of board JSON, not a complete Trello backup reader. Text is displayed as
text by the existing preview; URLs are not fetched. Free text may contain private
information: review notes before downloading or sharing any resulting plan.

## Authority and verification

The workflow only creates editable planning content. It never contacts Trello,
uses API credentials, authenticates, sends communications, creates formal tasks,
accepts work, spends, posts accounting or pays. Existing signed native operations,
immutable history, financial authority and review gates are unchanged.

From the repository root:

```sh
node --test scripts/test_trello_plan.mjs scripts/test_import_csv.mjs
```

The focused Trello tests execute the production JavaScript extern with Node,
validate the produced template's field/reference contract, and assert source
wiring through the existing MoonBit template reader, explicit preview/apply and
append paths. They cover realistic source detail, list/card order, omitted-field
warnings, incomplete references, blank planning fields, bounds, deterministic
conversion, and no partial result. The CSV suite is a regression check.
MoonBit wrappers/reducers are source-wiring-only in this qualification; they were
not compiled or executed. No browser, PostgreSQL, native service, provider or
live Trello execution is qualified. No PRD acceptance status is upgraded.

This supports MOONPROJ-UC07/B07's source-to-review-pending project planning,
UC04/B04's planning/domain authority boundary and N01's separation of drafts
from canonical authority. It does not fulfill the signed execution or commercial
closure roadmap.
