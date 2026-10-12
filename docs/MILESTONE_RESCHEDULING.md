# Reschedule a plan while keeping milestone spacing

Use this after importing a complete plan template or when a project start or
delivery target moves. Choose one milestone's new date; MoonProj shifts every
dated milestone by the same number of calendar days.

## Use

1. Open the company project in **Projects**, then open **整体调整里程碑日期**
   in the milestone section. This works on the current editable draft, including
   a template copy or a reopened saved plan.
2. Select the dated milestone you want to anchor. Enter its new date as
   `YYYY-MM-DD`, then choose **预览整体日期调整**.
3. Inspect the before/after dates for every milestone. Positive offsets move
   dates later; negative offsets move them earlier. Empty dates remain empty.
4. Choose **应用全部新日期** to edit the draft, or **取消日期调整** to discard
   the preview. Apply changes all dates together, saves through the usual
   browser-local draft storage and clears the old prepared result. Repeated
   Apply cannot shift dates twice.
5. Continue editing or download the complete plan template. Use the existing
   **原生准备并保存计划** action when ready to validate and save a new native
   version. Existing saved versions are unchanged. Calendar export still needs
   a valid explicit date for every milestone.

For example, changing the anchor from **2028-02-28** to **2028-03-02** moves it
three days, including leap day. A review on **2028-03-01** becomes
**2028-03-04**, and a release on **2028-03-10** becomes **2028-03-13**. Their
spacing stays intact. An unscheduled follow-up stays unscheduled.

Changing the anchor or new date discards the previous preview. Any draft edit,
template replacement, project/actor change, project refresh or successful
saved-version open also clears it. A preview is temporary and is not restored
after reload; applied dates use the ordinary actor/project-scoped draft reload.
If browser storage is unavailable, the usual warning explains that edits remain
only on this page. A zero-day adjustment makes no edit or new revision.

## Date rules and boundaries

- Supports 1–40 milestones with unique, nonempty IDs. Choose a dated anchor.
- Dates must be real Gregorian dates from `0001-01-01` through `9999-12-31`.
  An invalid nonblank date or an out-of-range result blocks the entire change
  and identifies the field to repair. No partial update occurs.
- Blank and whitespace-only date strings remain exactly as authored. Nonblank
  date strings must use the exact ten-character format.
- Shifts use calendar days, independent of time zones or daylight-saving time.
  Weekends and holidays count; there is no business-day or month-based mode.
- Task/owner/risk IDs, references, row order, cost strings, currency, criteria,
  evidence requirements and scope notes are unchanged. The edit refreshes only
  the draft request identity/time in addition to milestone dates.

This edits planning targets, not task durations or execution schedules. Preview
and Apply make no HTTP requests, native save, task dispatch, calendar-service
update or financial change. Normal native validation and review remain separate.
