# Selected-project Today queue

## Filter the observed cross-project queue

Open Today → **跨项目查看**, then use **筛选已观察队列**. Choose an
observed owner by the displayed exact ID, or Unassigned; combine a due/attention
choice, blocker choice and title substring. Duplicate owner names remain separate
identities. The title search trims surrounding whitespace and ignores ASCII case;
other characters match literally. **清除筛选** restores the observed outstanding
queue without another request.

Match count is separate from successful-project coverage and the unfiltered
observed KPIs. Zero matches never means zero company work. Failed/queued projects
remain visible in the coverage explanation. Due filters use each project's
successful observed UTC day and the existing Gregorian date validation. Overdue
also includes the reported canonical `overdue` state; unknown dates may therefore
also be overdue. Needs attention and blockers use the existing canonical reasons.

Filters are presentation-only and are cleared on actor change, leaving Today or
choosing a single project. They are not persisted, shared or sent to a second
backend query. Refresh keeps the selected filter; an owner no longer observed
stays explicitly selected with a missing-observation label instead of silently
widening the scope. Read/actor identities fence stale filter callbacks. Selecting
a match opens the unchanged exact task route and preserves local drafts.

The controls use native labelled inputs/selects and a live match-count status.
Compiled reducer/render tests are not mounted keyboard or screen-reader acceptance.

## Across projects

Choose **跨项目查看** (Across projects) to combine the current returned company
project list. This is an explicit scope choice; the page still does not select
the first project or read an unscoped task catalog. It reuses one existing
project-scoped task read per listed project, with at most three active reads
in the current batch. Invalidated older transport requests may still finish
within the existing timeout; their replies cannot update the new scope.

Successful project reads remain visible while other projects are loading or
failed. Counts always describe only those successful reads, and the coverage
line states how many listed projects contributed. The project list can omit
problematic identities and its legacy source read is bounded, so even a
completed batch is not claimed to be a complete company ledger. Existing
project diagnostics remain visible. A successful empty project read differs
from unavailable, unauthorized, offline and malformed reads.

Each project has its own successful browser observation and UTC due-date
interpretation. **重试此项目** retries a failed project in place, with a new
request identity, through the same bounded queue. **重试失败项目** retries all
failed reads after the batch settles while retaining successful scopes.
Refreshing the entire task batch clears its old rows first. Refreshing the
project list rebuilds membership and removes projects no longer returned.

The combined queue keeps the existing blocker, overdue, due-today ordering.
Every row names its company project and opens only the existing exact task
detail. Duplicate canonical task IDs across projects invalidate all affected
scopes until reread; they are neither double-counted nor opened ambiguously.
Project scope, actor epochs and per-project request identities fence late or
duplicate replies. Switching back to a single project preserves ordinary
draft and task navigation. No task, proposal, execution, report or acceptance
mutation is added.

Overview now shows an observed daily work queue for one explicitly selected actual company project. Products remains the boot default. The previous fixed cockpit cash, agent, decision and health figures are removed from Overview.

## Use

1. Open Overview and choose a company project returned by the authenticated project list
2. Read the project's outstanding work and observed attention reasons
3. Open a task's existing canonical detail for inspection

Refresh the project list or selected task list to observe changes. The displayed scope always names the selected project. The project list never selects its first result implicitly and no unfiltered company-wide task request is made. Browser drafts appear separately and can resume through the existing draft flow; they do not contribute to formal task counts.

## Evidence and dates

The queue uses GET `/api/company/projects` and GET `/api/company/tasks?project_id=...`, with the existing status-preserving bounded read transport. Counts describe only the successfully decoded task response for the selected project. Last successful read is the browser's UTC observation time, not a server freshness guarantee. During refresh or failure counts are unknown, and previous task rows are hidden. A retained previous read time is labeled as the last successful observation.

Native task status `done` is terminal. Explicit imported `cancelled`, `canceled`, and `closed` statuses are also excluded from outstanding rows. Other unfamiliar statuses remain visible for inspection, with their unmodified canonical value. Run state `completed` does not finish or accept a task.

`planEndDate` is a date-only deadline, using UTC calendar dates to match the existing `dispatch_today()` task form. Due today and overdue are evaluated against the UTC date of the successful observation. A valid Gregorian `YYYY-MM-DD` value has no inferred hour. Missing, invalid or timestamp-shaped deadlines remain unknown and their raw text is visible. No timezone offset is guessed. Refresh after a UTC date rollover for a new observation.

Ordering is observed execution/task blockers first, then overdue, then due today, then other outstanding work; ties use valid due date followed by exact task ID. Unknown dates sort last. Observed blockers include explicit failed, blocked, runtime-unavailable, interrupted, waiting-approval and cancelled execution states, plus canonical task `blocked` status. A waiting-approval run does not establish approval readiness. Error text is displayed only alongside an explicit observed execution blocker. Canonical `overdue` remains a reported fact even when its date is unknown.

## Failure and navigation behavior

- Empty successful project/task reads, offline, unauthorized, unavailable and malformed responses have distinct states
- Invalid/mixed-scope/duplicate task rows invalidate the whole response rather than silently lowering counts
- Actor changes clear scoped evidence and advance an epoch; old actor or project responses, superseded requests and duplicate terminal replies are ignored
- Project navigation and read results do not overwrite local drafts
- Opening a listed task uses the existing exact-detail flow and preserves local draft input. It sends a canonical GET and records local navigation; it never creates, starts, reports or accepts work
- Existing Back/Forward task routing remains authoritative. Today project selection is page-local; it is not a persisted link or an authorization claim

## Qualification

Source-backed reducer, HTML-render and transport-fixture tests cover the above behaviors. These are not mounted-browser or signed live PostgreSQL qualification. No service, runtime/provider, purchase, publication or Mac operation is part of this feature.
