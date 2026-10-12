# Milestone calendar export

The Projects workbench can download the current draft's milestone dates as a
portable `plan-milestones.ics` file. This is useful for putting an already-authored
review or delivery target alongside your ordinary calendar without rebuilding
the project's task context by hand.

## Use

1. Open **Projects**, read company projects through the existing gateway, and
   select the project. Continue its current browser draft, or explicitly open a
   saved version using the existing history controls.
2. In **Milestones and acceptance**, enter a milestone name, named owner, and
   real `YYYY-MM-DD` target date. Add acceptance criteria and required evidence.
   Assign relevant tasks to that milestone with their existing task owners.
3. Choose **Download milestone calendar (.ics)** (`下载里程碑日历 (.ics)`).
   This uses exactly the current draft, including unsaved edits. The plan does
   not need native preparation first. An incomplete or invalid date, duplicate
   milestone ID, missing named owner, or task assigned to a removed milestone
   produces a repair message instead of a partial file.
4. Inspect the downloaded file and import it using your calendar application's
   `.ics` import feature. The file contains project/task/owner names, identifiers,
   acceptance text and evidence requirements. Choose an appropriate calendar
   and audience before importing or sharing it. MoonProj does not contact a
   calendar provider or send invitations.

For example, a milestone named **Reviewable result** dated **2028-02-29**, with
**Design** and **Review** tasks, becomes one all-day calendar marker on February
29. Its description contains both tasks, their owners and dependency IDs, and
the milestone's acceptance/evidence text. Neither task receives a date.

The marker is prefixed `[Planning]` and is transparent to free/busy time. It
does not reserve work time, infer duration, set task status, accept the plan,
or establish a delivery commitment. Exporting leaves draft bytes, browser
storage, prepared result, revision and history unchanged. A downloaded file is
a snapshot; editing the project does not update an imported calendar.

## Re-export and format

Project and milestone IDs produce stable UIDs across name, date and plan-version
edits. A different project or milestone ID creates a different UID. How repeated
imports update or duplicate existing entries depends on the calendar application;
this is not a subscription or synchronization protocol. Use a separate planning
calendar or remove a previous imported snapshot when needed. Renaming a milestone
retains its identity; deleting and adding a row creates a new one.

The [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545) projection uses VCALENDAR
and VEVENT, `DTSTART;VALUE=DATE`, the current draft revision time as `DTSTAMP`, and
`TRANSP:TRANSPARENT`. No end, duration, timezone conversion, recurrence, alarm,
attendee, organizer, scheduling method or completion status is emitted. A DATE
event without an end is an all-day date marker. CRLF content lines are folded at
75 UTF-8 octets without splitting Unicode characters. Text punctuation and
newlines are escaped, retaining multilingual and multiline content.

This is a deliberately bounded export of 1–40 milestones and up to 100 tasks.
It checks the calendar projection's inputs, not the entire native project's
budget, dependency ordering or authority. The existing prepare/save operation
remains the validator for the full plan. Existing native and compiled UI tests
cover date validation, stable identities, Unicode/escaping, preserved source
state, correct download bytes/MIME type, errors and project/actor changes.
Third-party calendar application imports are not covered by those tests.

## MoonBit API

`product/plan_workbench.export_milestone_calendar(draft, project_name)` returns
UTF-8 calendar text or raises `InputError`. It is pure and works on native and JS
targets. The caller supplies the observed project name; no company lookup or
write takes place inside the exporter.
