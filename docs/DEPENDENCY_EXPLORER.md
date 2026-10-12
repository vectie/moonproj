# Dependency planning explorer

Open **Projects**, read company projects, and select your project. In the task
editor, the explorer updates immediately from your current draft, including
CSV/TSV imports and unsaved dependency edits.

1. Add/import tasks and select prerequisites using the existing task buttons.
2. Read the waves: tasks in Wave 1 have no prerequisites; each later wave can
   become ready after earlier waves finish. Select a wave task or any task in
   **Task impact** to trace all transitive prerequisites and downstream tasks.
   The panel also lists milestones touched by the selected task or its dependents.
3. Try an alternative dependency in the editor and inspect the changed waves.
   **Order tasks by dependencies** repairs the execution list, keeping the earliest
   currently ready task in original draft order. Task IDs, text, owners, costs,
   milestones, dependencies and risks are retained. The edit uses normal local
   recovery and invalidates an older prepared preview. Already ordered plans
   remain unchanged.
4. **Download dependency plan** exports the waves, task labels, owners, milestone
   IDs, selected impact and visible problems as a readable local text file.
5. Continue editing or use the existing **Native prepare and save plan** workflow.

Try the synthetic [release backlog](samples/dependency-release.csv), using your
existing owner and milestone as the import defaults. First select DESIGN to see
all three downstream tasks. Move SHIP above DESIGN, then use the ordering action
to restore a valid sequence. Change DOCS to depend on TEST to see a four-wave
scenario; remove that dependency to restore parallel-ready DOCS and TEST.

Waves are precedence groups, not a calendar, critical path, duration estimate,
resource leveling, or proof that one person can do concurrent work. Cycles and
missing references are shown with task IDs and prevent reordering; edit the
named prerequisites to resolve them. A cycle's blocked list includes downstream
tasks, not just members of the cycle. Reachability remains available for diagnosis.
Focus is temporary UI state; draft recovery persists the actual ordering edits.
No status, percentage, execution task, saved historical version or business
authorization is changed by exploration or export.
