# Extract a reusable phase from the current draft

Open **Projects**, choose the current company project, then expand
**提取可复用阶段 / Extract reusable phase**. Select individual tasks, one
milestone, or both. Milestone selection includes all tasks assigned to that
milestone; combined selection is a union, not a replacement. Preview before
downloading **plan-phase-template.json**.

## What the preview includes

- Explicitly selected tasks and a separate list of automatically included
  transitive prerequisites. Downstream dependents are not added. Source row
  order is retained, even when it is not dependency order.
- Owners referenced by included tasks, milestones, or retained risks. If every
  included assignment is blank, the first source owner supplies the required
  reusable owner slot. This fallback is disclosed and assignments stay blank.
- Each milestone referenced by an included task. Original date, criteria, and
  evidence text remain unchanged. A partial milestone is called out with its
  omitted sibling tasks: original requirements are not claimed to be achievable
  with the extracted tasks alone.
- Risks whose nonempty task scope is fully included. Cross-scope risks are
  omitted rather than having their task list silently narrowed. Their summary,
  severity, mitigation, and original task names remain visible as context.
  Unscoped risks are also omitted and disclosed as source-wide context. Unrelated
  risks are excluded and counted in the total omitted risks.

The original project-wide scope notes, limit, and contingency are not copied or
apportioned. Template limit and contingency are empty strings, not zero or an
implied approval. Currency remains the unit of copied task costs. Generated
template notes retain extraction caveats, selected/prerequisite task names,
partial milestones and relevant omitted risk context. They are not a new scope
specification. Review the text for private information before sharing.

## Reuse through the existing template flows

The downloaded file is the standard `moonproj-plan-template/v1` JSON, accepted
unchanged by **复用完整计划模板**. Paste it, preview, and choose your owner slot.
The template scope/context notes are visible above the reuse controls.

- **Replace current draft** imports the selected rows with fresh identities and
  maps the chosen owner slot to the current preparer. Scope/context notes are
  imported and budget fields remain blank. Author the new project's actual scope
  and budget before native preparation.
- **Append reusable phase** previews the combined draft, retains existing rows,
  scope, and budget, and remaps every added reference. It requires matching
  currency. As before, append does not copy template notes; review and manually
  retain any context that the target plan needs. It does not create cross-phase
  dependencies, apportion budget, shift dates or convert currency.

Task costs, owner names/roles, dates, milestone requirements/evidence and retained
risk fields are preserved verbatim, except the existing explicit preparer mapping
when reusing. Blank or invalid editable dates/costs stay editable; extraction is
not native validation. Cyclic draft dependencies terminate safely and remain in
the template for correction. Source-wide structural errors (duplicate IDs or
missing references) block extraction instead of silently dropping broken rows.

## State and authority

Selection, preview, cancel and download are read-only. They do not write browser
storage, alter draft keys/revisions, invalidate prepared output, or send a network
request. Any edit invalidates the preview. Re-preview reads fresh current rows;
a stale download is blocked. Project/account switches, refresh, and opening a
saved plan clear the extraction state. Selection is in-page only.

Replacement and append are separate explicit existing edits and retain their
normal persistence and prepared-output invalidation behavior. A phase export is
an authoring aid, not saved company state, acceptance, dispatch, a budget approval,
or a financial/contractual operation.

## Verification

`product/plan_workbench/phase_extract_test.mbt` covers transitive closure, ordering,
milestone union, partial scope, risk policy, owner fallback, source immutability,
all remapped reference categories, retained authored fields, normal template
read/replace/append, invalid input, cycles, and changed-input freshness.
`frontend/opc/project_plan_extract_wbtest.mbt` runs the compiled production
reducers, HTML rendering and Blob/download commands with the established browser
adapter. It exercises source/storage/prepared preservation, selection changes,
actual downloaded bytes, both reuse flows, stale previews, project/account
isolation, invalid input, and repeat downloads. This is not graphical-browser or
live company-service qualification.
