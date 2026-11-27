///|
/// Read-only extraction preview. Context IDs refer to the source draft; the JSON
/// uses only portable template IDs and can be read by the existing template flow.
#derive(Debug, Eq, ToJson)
pub(all) struct PhaseExtraction {
  selected : Array[String]
  prerequisites : Array[String]
  partial_milestones : Array[String]
  cross_scope_risks : Array[String]
  unscoped_risks : Array[String]
  omitted_risk_count : Int32
  fallback_owner : Bool
  json : String
}

///|
/// Extract the union of explicit task selections and a selected milestone's
/// tasks, including every transitive prerequisite. Keep authored rows intact.
/// Whole-project notes and budget are deliberately not copied or apportioned.
pub fn extract_phase(
  d : Draft,
  task_ids : Array[String],
  milestone_id : String,
) -> PhaseExtraction raise InputError {
  // Validate the whole source, so dangling/ambiguous references are never
  // silently repaired by filtering. Editable dates/cost text remain supported.
  ignore(export_template(d))
  template_ids(task_ids, "Selected tasks")
  for id in task_ids {
    template_ref(id, d.tasks.map(t => t.id), "Selected task")
  }
  template_ref(milestone_id, d.milestones.map(m => m.id), "Selected milestone")
  let selected = d.tasks
    .filter(t => {
      task_ids.contains(t.id) ||
      (!milestone_id.is_empty() && t.milestone == milestone_id)
    })
    .map(t => t.id)
  if selected.is_empty() {
    raise Invalid("Select at least one task or a milestone containing tasks")
  }
  let included : Map[String, Bool] = Map([])
  let pending = selected.copy()
  for id in selected {
    included[id] = true
  }
  // Each source task is visited at most once, even in an editable cyclic graph.
  for i = 0; i < pending.length(); i = i + 1 {
    for t in d.tasks.filter(t => t.id == pending[i]) {
      for id in t.dependencies {
        if !included.contains(id) {
          included[id] = true
          pending.push(id)
        }
      }
    }
  }
  let tasks = d.tasks.filter(t => included.contains(t.id))
  let milestones = d.milestones.filter(m => tasks.any(t => t.milestone == m.id))
  let partial = milestones.filter(m => {
    d.tasks.any(t => t.milestone == m.id && !included.contains(t.id))
  })
  // A risk is retained only when its complete explicit task scope is included.
  // Never trim risk references and imply the authored mitigation is phase-local.
  let risks = d.risks.filter(r => {
    !r.tasks.is_empty() && r.tasks.all(id => included.contains(id))
  })
  let cross = d.risks.filter(r => {
    r.tasks.any(id => included.contains(id)) &&
    r.tasks.any(id => !included.contains(id))
  })
  let unscoped = d.risks.filter(r => r.tasks.is_empty())
  let referenced = d.owners.filter(o => {
    tasks.any(t => t.owner == o.id) ||
    milestones.any(m => m.owner == o.id) ||
    risks.any(r => r.owner == o.id)
  })
  let fallback_owner = referenced.is_empty()
  let owners = if fallback_owner { [d.owners[0]] } else { referenced }
  let notes = [
    "Extracted reusable phase. Author phase scope and budget before preparing a plan.",
    "Source-wide scope notes, budget limit and contingency are omitted, not apportioned. Currency is retained only as the unit of authored task costs. Dates, cost text and milestone requirements are unchanged and need review for the new project.",
    "Selected tasks: " +
    tasks.filter(t => selected.contains(t.id)).map(t => t.name).join("; "),
    "Automatically included prerequisites: " +
    tasks.filter(t => !selected.contains(t.id)).map(t => t.name).join("; "),
  ]
  for m in partial {
    let omitted = d.tasks
      .filter(t => t.milestone == m.id && !included.contains(t.id))
      .map(t => t.name)
    notes.push(
      "Partial milestone: " +
      m.name +
      ". Original criteria/evidence retained; omitted sibling tasks: " +
      omitted.join("; "),
    )
  }
  for r in cross {
    notes.push(
      "Omitted cross-scope risk: " +
      r.summary +
      " [" +
      r.severity +
      "]. Mitigation: " +
      r.mitigation +
      ". Original task scope: " +
      d.tasks.filter(t => r.tasks.contains(t.id)).map(t => t.name).join("; "),
    )
  }
  for r in unscoped {
    notes.push(
      "Omitted unscoped/source-wide risk: " +
      r.summary +
      " [" +
      r.severity +
      "]. Mitigation: " +
      r.mitigation,
    )
  }
  if fallback_owner {
    notes.push(
      "No included row has an owner assignment. The first source owner is retained only as the required reusable owner slot; blank assignments remain blank.",
    )
  }
  let json = export_template({
    ..d,
    notes: notes.join("\n\n"),
    limit: "",
    contingency: "",
    owners,
    tasks,
    milestones,
    risks,
  })
  {
    selected,
    prerequisites: tasks.filter(t => !selected.contains(t.id)).map(t => t.id),
    partial_milestones: partial.map(m => m.id),
    cross_scope_risks: cross.map(r => r.id),
    unscoped_risks: unscoped.map(r => r.id),
    omitted_risk_count: d.risks.length() - risks.length(),
    fallback_owner,
    json,
  }
}
