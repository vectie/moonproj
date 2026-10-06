# Selected-project Today queue

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
