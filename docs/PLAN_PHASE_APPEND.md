# Compose a reusable phase into the current plan

Append a template's complete task phase without replacing the project you have
already planned. Unlike a task CSV, the phase includes its owners, milestones,
acceptance criteria, evidence requirements, risks and internal dependencies.
Use the existing [complete template format](PLAN_TEMPLATES.md).

Try the synthetic [phase template](examples/phase-append/phase-template.json)
against the [illustrative destination draft](examples/phase-append/destination-draft.json).
The latter documents the starting editor values; it is not a new draft-import
format or a signed company record.

## Preview, append and continue editing

1. Open the destination project in **Projects**. Its current draft may already
   contain tasks, milestones and risks. Download its template first if you want
   a separate portable copy.
2. Under **Reuse complete plan template**, paste the source template JSON and
   choose **Preview template**. Inspect its complete content. Choose the source
   owner whose assignments should belong to the current signed-in preparer.
3. Under **Append reusable phase**, choose **Preview phase append**. Inspect
   the addition counts and expand **Complete combined draft** to see every
   existing and imported row, including the actual new IDs and references.
   This does not write storage or change the prepared result.
4. Choose **Apply phase append**. This appends the previewed rows together to
   the browser-local draft. Existing rows keep their order and IDs. The previous
   prepared preview is cleared; local reload uses the ordinary draft recovery.
5. Edit the added rows normally. Add any dependency between the old and new
   phases explicitly using the existing task controls; no join is inferred.
   Download an editable CSV or the complete combined template, or separately
   choose **Native prepare and save plan** when the entire plan is ready.

Closing template input discards staging. Changing the source or owner mapping,
editing the draft, or switching account/project invalidates the append preview.
The apply action consumes its preview, so a repeated click does not append
twice. To intentionally reuse the phase again, paste/preview it again; it gets
a separate fresh set of row IDs.

## What stays and what is added

- Destination scope notes, currency, budget limit and contingency stay exact.
  The template's scope notes and budget are visible in the source preview but
  are not merged. Check whether the phase fits your destination scope/budget.
- Template currency must exactly match destination currency. There is no FX
  conversion. Task amount strings and milestone dates are copied exactly.
- The chosen owner slot maps to the existing preparer's ID. That person's
  destination name and role stay unchanged. The name input used by template
  replacement does not apply to phase append. Other template owners are added
  as new editable rows, even if their display names match existing people.
- All imported tasks, milestones and risks get fresh IDs; internal references
  are remapped together. Existing references and rows are untouched. No existing
  milestone/person is automatically merged by matching name.
- Acceptance/evidence text, risk details and mitigation, order and dependency
  lists retain their source values. Blank assignments, unfinished dates/costs
  and dependency order remain editable; append is not native plan validation.

The combined plan must remain within the existing editor limits: 40 owners,
100 tasks, 40 milestones and 100 risks. The phase must contain at least one
task. Invalid source structure, missing references, identity collisions or
currency mismatch leave the draft and source input available for correction.

## Boundaries and verification

This is a local authoring operation. It does not save an immutable native plan,
create/start work, contact another person, approve a budget, execute a provider
or establish delivery/payment evidence. The separate native prepare operation
still validates the whole proposal, including aggregate budget and acceptance.

Focused native domain and compiled JavaScript tests cover complete phase
composition, exact owner/identity preservation, preview/apply, normal editing,
local reload, portable output and explicit prepare-request generation. These
checks use synthetic examples and a browser API fixture, not a graphical
browser, live gateway, database or company identity.
