# Find and replace authored plan text

Use this when a project term changes across a planning draft. For example,
replace `Pilot` with `Launch` in task titles and milestone descriptions without
recreating rows or breaking their dependencies.

1. Open **Projects** and an existing company project's local plan.
2. Expand **Find and replace plan text**, above the scope and budget editor.
3. Enter **Find text**, **Replace with**, and a **Text scope**.
4. Choose **Preview text replacements**. Each affected field shows its stable
   row ID, occurrence count, and complete before/after text.
5. Inspect the result, especially any source quotations. Choose **Apply text
   replacements** to save the edited browser draft, or **Close replacement
   preview** to leave it unchanged.
6. Continue editing, download the normal task CSV or whole-plan template, or
   explicitly prepare the plan through the existing native workflow.

## Matching and scope

Matching is literal, case-sensitive and non-overlapping. Spaces and line breaks
are significant; input is not trimmed. `.` and `*` have no regular-expression
meaning, and `$&` in replacement text is literal. `Review` also matches the start
of `Reviewable`; there is no word-boundary or case-insensitive mode.

Scopes are:

- Scope notes
- Task titles
- Milestone names, criteria and required evidence
- Risk summaries and mitigations
- All of the above

Owner names/roles, IDs, owner and milestone assignments, dependency/risk links,
severity, amounts, currency and dates are excluded. A rename keeps every row's
identity. The pure preview also preserves request identity; an applied edit uses
the existing fresh request key and revision timestamp.

An empty replacement removes matching text. A replacement that would make an
entire previously nonblank field blank is rejected atomically. Use the individual
field editor to intentionally clear it. Identical find/replacement and no matches
produce a zero-change preview; Apply does not write or invalidate anything.

The query permits 1–2,000 UTF-16 text units; replacement permits 0–2,000. The
existing 100-task, 40-milestone, 100-risk and 40-owner draft limits apply. Input
and resulting serialized draft each allow at most 1,000,000 text units. Output
expansion is checked before allocating replacement strings.

## State and authority

Preview, changing controls and Close never write the draft, browser storage or
prepared plan. Edits to the draft or controls invalidate the preview. Apply also
checks the exact previewed draft before saving, so an outdated preview cannot
replace newer work. Changing actor/project or reopening a saved version resets
the panel. Find/replacement controls and previews are ephemeral; only the applied
draft survives reload.

Apply uses the normal local draft save and clears its prepared preview. Saved
immutable versions are unchanged. No company task, work execution, payment,
accounting or acceptance effect is created. Native validation remains authoritative
when the user explicitly prepares a new version.

## Focused verification

Six new tests exercise literal/scoped matching, Unicode and multiline text,
reference preservation, bounded/atomic failures, escaped UI preview, apply,
reload, CSV output, explicit prepare payload, repeated/no-op actions and stale
or scope-changed previews. Ten adjacent task-finder tests also pass. These are
JavaScript tests with synthetic Node browser adapters; graphical-browser,
accessibility, live company service and native product qualification are outside
this focused change.
