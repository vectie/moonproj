# Markdown checklist to project tasks

Projects can append a Markdown action checklist to the current editable plan.
This is useful for a working brief, meeting action list or repository issue whose
checklist would otherwise need manual conversion into a spreadsheet.

## Use

1. Open an actual company project in Projects using the existing company gateway.
   Add the owners and at least one milestone you want the new tasks to use.
2. Expand **Markdown checklist / Markdown 清单导入** in the task-import section.
3. Paste Markdown, choose the existing owner and milestone for all new rows, and
   choose **Unchecked items only** (the default) or **Include checked items as
   planned** when intentionally replanning work that is checked in the source.
4. Choose **Preview checklist tasks**. Inspect the source line, original checkbox,
   contextual task name, new ID, chosen assignments and initial cost for each row.
   The preview also reports skipped checked items and shows the original text.
5. Choose **Append checklist tasks** to save this local draft edit. Close cancels
   only the preview. Successful append clears the importer so a repeated click
   cannot append the same preview twice. Deliberately pasting again creates fresh
   tasks; there is no cross-import deduplication by label or text.
6. Review costs and add real dependencies in the existing task editor. Download
   the existing task CSV or hand a selected task to Dispatch. Native prepare/save
   is still a later, explicit operation and performs its existing validation.

## Supported Markdown subset

- One-line checkbox list items using `-`, `*`, `+`, or an integer followed by `.`
  or `)`, whitespace, `[ ]`, `[x]` or `[X]`, then whitespace and nonempty text.
- Leading spaces and tabs establish nested-list context. Tabs advance to the next
  four-column stop. All indented checkbox items are interpreted as checklist
  content; wrap code examples in fences instead of relying on four-space code.
- ATX headings (`#` through `######` followed by whitespace) and parent list items
  become the task-name prefix, separated by ` / `. A same-level or higher heading
  starts a new section. Unchecked children of checked parents keep parent context
  even if the parent is excluded. Plain bullets are context, not tasks.
- Inline Markdown, links, Unicode and punctuation remain literal task-name text.
  Leading/trailing item whitespace and the checkbox/list markers are omitted from
  the name. The full original source, including whitespace and original line
  endings, is appended verbatim to scope notes along with line-to-task IDs.
- Backtick or tilde fences of at least three matching characters exclude content
  until a matching fence of at least that length. HTML-comment lines and blocks,
  blockquote lines, ordinary prose and continuation lines produce no tasks. Their
  original text is still retained in scope notes. Unclosed fences/comments and
  empty recognized checkbox items return a repairable error without appending.
- This is a line-oriented import, not a CommonMark renderer. Setext headings,
  lazy blockquote continuation and multi-line item-body interpretation are not
  supported. Put task text on its checkbox line and inspect the preview.

## Planning semantics and continuity

The new tasks append in source order with fresh IDs. Existing tasks, owners,
milestones, risks, limits, contingency and dependencies keep their values. Each
new task starts with planned cost `0` and no dependencies; zero is an editable
initial value, not a sourced estimate. Neither indentation nor checkbox order
implies prerequisites. Source checkmarks never become completion, acceptance or
formal company status. All included items are ordinary planned rows.

The preview is read-only. Input changes, draft edits, project selection, project
refresh or actor changes invalidate it. A stale base cannot be appended. Applying
clears the old prepared preview and creates a new local plan version, using the
existing draft-save path. Storage failure keeps the current-page edit and shows
the existing warning; it is not reported as persisted. Saved native versions and
formal tasks stay unchanged. No gateway mutation, provider request or execution
is performed by importing.

The UI uses labeled native fields and buttons and textual status messages. Source
Markdown is displayed as escaped text, with no rendering or fetched links. Pasted
input remains ephemeral until append, after which it is part of the browser-local
plan notes and any later plan/template/brief exports that include those notes.
Do not paste secrets into planning notes or share an export without reviewing it.

## Verification boundary

Focused tests exercise the production parser and compiled Projects update/render
path, including append, local storage/reload, CSV output, request projection,
Dispatch projection, source fidelity, repeated actions, invalid input, context
changes and storage failure. Node supplies synthetic browser adapters; this does
not qualify graphical layout, keyboard/screen-reader execution, a live gateway,
PostgreSQL, native plan persistence, formal task creation or live execution.
