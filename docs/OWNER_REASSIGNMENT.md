# Reassign a draft owner's complete allocation

When staffing changes, open **Projects → your project → 批量交接负责人 /
Reassign owner**. Add the replacement owner in the ordinary Owners editor first.
Select the outgoing owner under 转出负责人 and the replacement under 接任负责人.
Choose **预览负责人交接**. The preview lists each affected task, milestone and
risk with its stable row ID and a count per category. Confirm the two owner IDs,
then choose **应用全部负责人交接** to edit all those assignments together.

This is an all-allocation operation. For a partial handoff, use the individual
row owner controls instead. Cancel leaves the editor and prepared result alone.
Changing either selection clears the preview. Any intervening draft edit, project
switch, actor switch, refresh or historical reopen clears it; a stale source
cannot be applied. Missing, empty, identical or duplicate owner identities reject
rather than guessing. A source with no assigned rows produces a no-change preview.

Apply uses ordinary draft persistence: a fresh request key and preparation time,
one revision increment, and invalidation of the prepared result. The local draft
can be reopened after reload. If browser storage fails, the ordinary warning says
that the edit remains in this page only. Saved versions are unchanged. Prepare and
save again when ready for native validation. The existing complete template export
carries the new allocation (using portable template owner IDs).

The outgoing owner is retained in the owner list, including when that person is
the preparer. Task/milestone/risk IDs and all other fields are preserved: task
order, costs, dependencies, dates, criteria, evidence, mitigation, scope and budget.
Unassigned rows and rows belonging to other owners are unchanged. This operation
is not complete-plan validation; existing unrelated draft issues stay editable.

No formal tasks are reassigned, no access or approval authority is granted, and
no person is notified. This is local planning only, not a company-service receipt,
financial action, accepted plan, signed execution handoff or customer acceptance.
