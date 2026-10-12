# MoonProj PRD workspace: first local version

MoonProj's **项目与 PRD** page now holds a local working register for its own PRD and the Moon/Luna portfolio. It replaces the previous sample-only project table. The register is for planning and traceability; it does not write formal company tasks, accept customer work, or certify a release.

## Start with MoonProj, then the portfolio

1. Open the built MoonProj web frontend and select **项目与 PRD**.
2. Download `OPC_OS_Requirements.csv` from the supplied Library file `libfile_daaefa906fb08191817c793c27a3090d`. Enter a distinct version label, such as `2026-10-01-portfolio-v1`, choose the CSV, inspect the preview, and confirm. The page defaults to **MoonProj**, so its 17 requirements are the first working set. You can also import a MoonProj-only CSV with the same 11 columns first, then import the full collection as an additive second version.
3. Choose `MOONPROJ-B01` or another requirement. Read its statement, acceptance criteria, cited sources, dependencies and **imported** evidence assessment. Filter by product, scope, or ID/title text.
4. Assign an owner, optional priority override, planned work, and proposed verification evidence. If a formal MoonProj task already exists, enter only its `OPC-TASK-…` ID. Save the plan. This creates a local planning link; it does not create or approve a signed task. The task link opens the existing formal task-readback route, which still requires the configured signed gateway.
5. Switch product filter to work through the other 25 entries. MoonStat's 12 rows are **retirement** scope. MoonProp and Mooncake have no rows in this source and remain excluded. MoonMini is an alias, not a separate PRD.
6. For a revised PRD CSV, use a new version label. Reimporting the same bytes is a no-op. A changed file shows added and changed counts before confirmation. Existing IDs and plans remain, and plans based on changed source rows are flagged for review. An import that would silently remove an existing requirement ID or reuse a label for different bytes is rejected.
7. Export the complete JSON backup periodically. It contains PRD text, version history, provenance metadata and local plans, with a checksum for accidental corruption detection. Store it with normal care. To restore, choose the JSON file, inspect the version and plan-conflict preview, then confirm. A matching backup is a no-op. Compatible histories merge; current local plans win conflicts only after explicit confirmation. Divergent histories are refused, never silently overwritten.
8. If local storage is unreadable, first download its raw bytes using **先导出原始损坏记录**. Only then can a valid backup explicitly replace that unreadable local record. Older plain JSON exports from the first version remain readable after strict schema validation, but have no checksum.

## What the statuses mean

| Field | Meaning |
| --- | --- |
| `baseline`, `roadmap`, `quality`, `retirement` | Source PRD scope; preserved exactly on import. |
| Source priority and evidence/current assessment | Author's assessment in the imported PRD, including any `Verified local` label. Importing it is **not** a new verification. |
| Owner, priority override, planned work, task ID | Browser-local management notes keyed by stable requirement ID. A task ID is only a reference to a separately created formal task. |
| Proposed verification evidence | A request or plan for an independent check. It does not mark the requirement verified. |
| Release readiness | Always **not independently verified** in this workspace. The P0-without-plan count shows a planning gap, never permission to ship. Formal Gate and evidence review remain separate. |

The 447-row source currently covers 26 entries: 229 baseline, 79 roadmap, 127 quality and 12 retirement requirements. These are source counts, not completed-work counts. MoonProj has 17 source requirements. Stable requirement IDs are the join key between PRD snapshots and plans.

## Persistence and integration boundary

The record is saved under `moonproj.prd-workspace.v1` in this browser origin's `localStorage`. Reloading the same origin restores saved versions and plans. Unsaved form text and the current filter/selection survive in-app page navigation in tab memory, but unsaved text does not survive a full reload. Changing browser/origin or clearing site data loses the live record unless a JSON backup is restored. Save failures leave the previous record intact and show an error. A checksum detects accidental backup changes; it is **not** an independent source signature or a release receipt. The static build script includes the workspace's JS and CSS. The signed PostgreSQL gateway, MoonClaw/Flow execution, release Gate and external customer/cash systems are **not** connected to this local register. Source text and plans stay out of URL query strings. Only a syntactically valid, non-secret `OPC-TASK-…` identifier may be used in the existing task readback link. Do not enter credentials or sensitive customer data.

## Verified in this implementation pass

- The exact Library CSV parsed as 447 unique IDs across 26 products and four scopes. A MoonProj-only 17-row import followed by the full collection produced two snapshots, preserved a synthetic plan, and counted the full portfolio correctly. Repeating the full import produced no duplicate version.
- Ten focused Node regressions passed: quoted CSV/newlines, malformed and duplicate rows, version/label conflicts, plan/source separation, backup roundtrip and checksum, malformed/injected/removed-ID histories, explicit plan conflict handling, storage failure, escaped imported markup, and navigation while the saved local record is unreadable.
- MoonProj's complete JS frontend test target passed **31/31**. `moon check frontend/opc --target js` and the documented `scripts/build_opc_frontend.sh` static build passed. The built bundle contains the PRD JS/CSS referenced by its HTML.
- An isolated cached Playwright Chromium run exercised real DOM interactions with a synthetic plan: 447-row file selection and confirmation, a second PRD version whose changed requirement flagged its plan for review, product/scope filtering, repeated save, navigation away and back with an unsaved tab draft, reload, JSON download, restore of both versions into a fresh browser context, repeat restore no-op, a conflicting local plan retained after explicit confirmation, malformed JSON rejection, and a synthetic quota failure leaving prior storage intact. A second isolated context exported the raw bytes of a corrupt local record, explicitly restored the backup, and reloaded the recovered 447-row register. There were **zero page errors** after the unreadable-state navigation fix. These were headless local browser tests, not tests of the user's existing browser profile or signed gateway.

## Next integration work

1. Add a server-side, permissioned PRD/plan store so the register can be shared across founder devices. Migrate browser-local records explicitly without overwriting them. JSON backup/restore now covers local recovery, but it is not shared multiuser persistence.
2. Link a requirement to a formal signed task by receipt, not by typed ID alone; show task progress as an external projection and retain the original PRD acceptance criteria.
3. Add independent verification submissions and review decisions with evidence provenance, then derive per-product release readiness from that governed record. A task marked complete must never automatically verify its requirement.
4. Connect approved PRD versions to MoonBook/Desk/Find source context and to MoonClaw/Flow bounded work packets through explicit, permissioned handoff contracts. Keep import assessments separate from fresh test results.
