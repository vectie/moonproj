# MoonProj project handoff

## Objective-first cleanup — 2026-11-24

Today is the default route; Today, Objectives and Company are the primary
navigation. Objectives reuse company `key_node` records and tasks' native
`parent_task_id`, not a new goal store. Imported key nodes remain visible.
The parent link is accountability only, never an execution dependency.
Owner acceptance is explicit and does not finish child tasks or create financial
effects. Live autonomous multi-agent delivery is not established by this UI.

Fleet no longer mounts sample agents or the sample execution-cockpit package;
Dispatch's reference task board is removed. Plan bulk/reuse tools remain in a
disclosure. Missing workspace no longer blocks saving a brief; execution still
requires actual runtime configuration. Do not weaken signing, reserved business
effects or ambiguous-create reconciliation while simplifying the journey.

Tests that render Products must explicitly select Products; relying on the
old initial page hides navigation regressions and can leak browser fixtures
when assertions fail before cleanup.

`moon fmt` with the current toolchain rewrites legacy syntax in unrelated
packages. Keep its changes scoped; do not ship repository-wide formatter
churn alongside a product change. No public interface change is expected here.

Validation: 543/543 frontend JS tests pass in the combined working tree with a
writable plan fixture directory. The isolated commit-only snapshot passes
542/542; it excludes the unrelated uncommitted GitHub import and its test.
Release frontend build passes, with no generated public-interface changes.
An isolated PostgreSQL 18 instance plus the real native signed gateway/service
was used for browser creation of an objective and parent-linked work, explicit
objective acceptance, and reload. Child state remained pending after the owner
accepted the objective, as declared. A 390px viewport had no horizontal overflow.
The test services/database were stopped. No provider-backed agent production,
new packaged-app installation or cluster deployment was performed in this slice.

## Cluster Mac installation and focused UI pass — 2026-11-24

Installed MoonProj 0.1.0-preview.3, clean main `b422502` plus the focused UI
changes, in `/Applications/MoonProj.app` on 192.168.2.195. Uncommitted plan,
GitHub-import and risk work in the primary checkout was excluded. Both native
services and the Lepusa runtime target macOS 15; strict deep signatures pass.
The gateway's `/ready` returns 200 and the product catalog loads without a DB.
The remote Mac has PostgreSQL 17 tooling, whereas the release documents 18.
No database, role, schema or credentials were created/changed. Database-backed
workflows still require operator configuration; a ready gateway is not proof
of those workflows.

Working style/UI/UX sections now follow MoonTown's guidance with local style
paths. The UI uses `frontend/opc_public/moonproj.svg`, matching the app identity,
instead of a generic overview glyph. Repeated navigation descriptions remain
in accessible names/tooltips. Catalog explanations, long assessment history,
scope assumptions and work groups use disclosures; actual warnings and next
actions remain available. Search/sort controls are omitted for an empty catalog.
Authored product intent, estimates, criteria and evidence were not rewritten.
The recommended-delivery card needs its own single-column grid: the generic
boundary-note flex layout squeezes its estimate and disclosure into narrow
columns. Keep this rule local to `.inventory-next`.

Frontend validation: 536 JS tests pass. The plan evidence helper returns an
empty string unless `MOONPROJ_PLAN_FIXTURE_DIR` is set; full-suite acceptance
requires a dedicated writable fixture directory. Do not replace its file
round-trip assertions or paste large HTML snapshots to conceal that setup.
Run Warren from the module root; an absolute package path from another module
can produce an empty artifact search. After Warren, copy the files listed by
the existing `scripts/build_opc_frontend.sh` into the dist directory before
packaging (the deployment used MoonBit automation for this).

Use the padded macOS SVG with a transparent rasterizer, not Quick Look's white
thumbnail background. The sibling Mooncast `scripts/generate_macos_icon.mbtx`
checks all four corner alpha values at every ICNS size. Installed ICNS hashes
match the verified output. Native app backups, receipts and MoonBit deployment
sources are retained in the remote user's `moonsuite-install-20261124` folder.
The served UI was visually checked through an SSH tunnel; direct remote native
window interaction and real company transactions were not qualified.

Launchpad follow-up: the installed icon hash still matches the transparent
output. Staged/rollback registrations were unregistered from LaunchServices,
canonical `/Applications` copies were re-registered, and the user's Dock was
restarted without a Launchpad reset. Launchpad bookmarks MoonProj's canonical
app; direct visual acceptance still needs a screenshot from that Mac. Other
products retained duplicate Launchpad rows after this non-destructive refresh;
do not imply this procedure guarantees cache cleanup. All backups remain.
