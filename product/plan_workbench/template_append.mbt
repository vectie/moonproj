///|
/// Compose a reusable phase into an existing editable plan. Destination scope,
/// currency, budget and existing identities remain unchanged. The selected
/// template owner maps to the existing preparer; all other imported rows get
/// fresh identities. This is authoring, not native validation or task creation.
pub fn append_template(
  t : Template,
  target : Draft,
  actor : String,
  owner_slot : String,
  fresh_prefix : String,
) -> Draft raise InputError {
  template_validate(t)
  if t.tasks.is_empty() {
    raise Invalid("Choose a phase template containing at least one task")
  }
  if actor.is_empty() ||
    target.owners.filter(o => o.id == actor).length() != 1 ||
    target.project_id.is_empty() {
    raise Invalid("Choose a current project and preparer first")
  }
  if !t.owners.any(o => o.id == owner_slot) || fresh_prefix.trim().is_empty() {
    raise Invalid("Choose your template owner before previewing the phase")
  }
  if t.currency != target.currency {
    raise Invalid(
      "Phase currency must match the current draft; no currency conversion is performed",
    )
  }
  let owners = template_map(t.owners.map(o => o.id), fresh_prefix + "-owner-")
  owners[owner_slot] = actor
  if owners.values().filter(id => id == actor).count() != 1 {
    raise Invalid("Fresh owner identity collides with preparer")
  }
  let imported = template_remap(
    t,
    owners,
    template_map(t.tasks.map(v => v.id), fresh_prefix + "-task-"),
    template_map(t.milestones.map(v => v.id), fresh_prefix + "-milestone-"),
    template_map(t.risks.map(v => v.id), fresh_prefix + "-risk-"),
  )
  let combined : Template = {
    ..imported,
    notes: target.notes,
    currency: target.currency,
    limit: target.limit,
    contingency: target.contingency,
    owners: [..target.owners, ..imported.owners.filter(o => o.id != actor)],
    tasks: [..target.tasks, ..imported.tasks],
    milestones: [..target.milestones, ..imported.milestones],
    risks: [..target.risks, ..imported.risks],
  }
  // Combined validation also detects fresh-ID collisions with existing rows,
  // missing references and the editor's total row limits before any UI write.
  template_validate(combined)
  {
    ..target,
    owners: combined.owners.copy(),
    tasks: combined.tasks.map(t => { ..t, dependencies: t.dependencies.copy(), }),
    milestones: combined.milestones.copy(),
    risks: combined.risks.map(r => { ..r, tasks: r.tasks.copy(), }),
  }
}
