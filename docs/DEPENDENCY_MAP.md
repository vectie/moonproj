# Visual project dependency map

Projects can turn the current local plan draft into a standalone SVG for offline
review, a planning document or a slide. It complements the existing textual
wave explorer and dependency report. No graph rendering service or new dependency
is required.

## Use it

1. Select a company project and open or edit its local plan.
2. In **Dependency planning explorer**, choose a task to highlight its complete
   prerequisite chain and downstream impact, or choose **Clear task focus**.
3. Open **Visual dependency map / 可视化依赖图**. Scroll the map when it is larger
   than the preview. The ordinary text wave list and impact summary remain above
   and below the image for keyboard and nonvisual use.
4. Choose **Download dependency map (.svg)**. Open `plan-dependencies.svg` in an
   SVG-capable viewer, or insert it into your planning document. The file is
   self-contained and needs no account, network request, scripts or external fonts.

The map always includes every task. Focus changes highlighting only. Each card
shows the stable task ID, authored title, owner, milestone and milestone's authored
target date. Relationship words accompany colors. Arrows point from prerequisite
to dependent. Long links route underneath the cards rather than across unrelated
tasks. Hover titles retain full task names and exact edge endpoint IDs.

Wave columns express precedence only. They are not a schedule, duration estimate,
resource allocation or completion state. Shared owners can still need to sequence
parallel-ready work. The map has the current project, local plan version and
revision time; its accessible description retains the full text dependency report
and authored scope/source notes. Review those notes before sharing the file.

## Draft behavior and repair

- Preview and download are read-only: no storage writes, draft edits, plan
  preparation, formal task creation, service request or company-state change.
- The current draft is used even when a prepared result is also present. Existing
  prepared results remain untouched. Repeated downloads are deterministic for the
  same draft, project label and focus.
- Draft order is retained. The visual layout groups by computed precedence wave;
  it does not invoke **Order tasks by dependencies**.
- Empty/duplicate task IDs, missing prerequisites, dependency cycles, duplicate
  prerequisite links and ambiguous/missing task owner or milestone references
  produce a repair message. The draft remains available to edit.
- If a focused task was removed, use **Clear task focus**. Switching project,
  account or page cannot export the old project's draft through this action.
- The map supports 1–100 tasks and at most 500 prerequisite links. For denser
  plans, the existing text dependency report remains available.
- Text is XML-escaped and conservatively wrapped without truncation; Unicode
  scalars stay intact. Unsupported XML 1.0 control characters are rejected. Long
  labels produce taller cards. Layout is intended for project review, not a
  resource-constrained schedule optimizer. Glyph coverage depends on the viewer's
  installed fonts; the SVG text and accessible descriptions retain Unicode even
  when a viewer cannot draw a particular glyph.

## Verification scope

Focused MoonBit JS tests cover the pure map export and actual Projects update,
render and Blob-download paths. Retained synthetic examples are parsed as SVG and
rasterized for visual inspection using installed Inkscape. Browser adapters in UI
tests are synthetic. These checks do not qualify a live graphical browser,
assistive-technology session, gateway, PostgreSQL, native product runtime, customer
acceptance or full repository regression suite.
