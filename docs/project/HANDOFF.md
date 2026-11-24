# MoonProj project handoff

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
