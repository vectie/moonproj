# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Working style

- Work from first principles: establish the real user goal, constraints, and
  success criteria before choosing an implementation. Use the existing task
  context to resolve routine choices and continue authorized work.
- Fix bugs at the root cause; do not cover symptoms with unrelated patches.
- Read `docs/project/HANDOFF.md` before each new task when it exists, and record
  newly discovered pitfalls there. Create it when there is a pitfall to record.
- Include performance cost in production design and acceptance, including
  startup, rendering, interaction latency, and build/link time where relevant.
- Use focused checks while iterating. Complete the required checks for the
  finished change; broaden or repeat testing when a failure, new change, or
  unresolved risk warrants it.

## UI/UX

- Avoid unnecessary secondary labels and descriptions; let the layout explain
  relationships and the next action.
- Every element must serve a clear user purpose. Remove slogans, decoration,
  duplicate information, and repeated status or counts.
- Show explanations for abnormal states or required actions. Put secondary
  details behind progressive disclosure, close to the work they explain.
  Keep errors, recovery actions, and consequential choices visible.
- Stay consistent with existing screens. Prefer removing or simplifying over
  adding; a local change should not trigger a whole-page redesign.
- A first-time user should understand what to click next and what will happen.
  Keep task, sources, and output connected; open related tools locally and
  provide a clear return path when navigation is necessary.
- Follow `../moonvis/docs/ICON_LANGUAGE.md`. Use the shared styles in
  `frontend/opc_public/styles.css`; refer to
  MoonDesk's `../moondesk/ui/rabbita-desk/styles/type-hierarchy.css` for the
  shared control hierarchy. Align typography, control heights, spacing,
  corners, and row/column baselines across pages, drawers, and dialogs.
- Use the established icon set for familiar, repeated actions, with localized
  accessible names and tooltips. Keep meaningful names and necessary form
  labels; do not make users guess an unfamiliar action from an icon.
- Localize system labels consistently in the selected language. Preserve
  actual filenames, paths, identifiers, and user-authored content.
- Give empty, loading, and error states distinct behavior with concise copy.
  Avoid duplicate empty messages, filters with nothing to filter, and actions
  that only open an empty surface.
- Verify changed layouts and interactions in the relevant UI states. When the
  task includes a packaged-app update, install the new resources and verify
  the actual app as well as the browser preview.

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.
