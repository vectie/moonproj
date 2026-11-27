///|
#derive(Debug, Eq, ToJson)
pub(all) struct TaskHandoff {
  title : String
  acceptance : String
  source_reference : String
  context : String
  end_date : String
}

///|
fn handoff_task_name(d : Draft, id : String) -> String {
  match d.tasks.filter(t => t.id == id) {
    [task] => task.name + " [" + id + "]"
    [] => "Missing prerequisite [" + id + "]"
    _ => "Ambiguous prerequisite [" + id + "]"
  }
}

///|
/// Snapshot authored planning context for an ordinary editable task draft.
/// Milestone criteria are context to adapt, never evidence of task acceptance.
pub fn task_handoff(d : Draft, id : String) -> TaskHandoff raise InputError {
  guard !id.is_empty() && d.tasks.filter(t => t.id == id) is [task] else {
    raise Invalid("Choose one uniquely identified plan task.")
  }
  if d.key.is_empty() || d.project_id.is_empty() {
    raise Invalid(
      "The plan needs a project and version key before task handoff.",
    )
  }
  let milestones = d.milestones.filter(m => m.id == task.milestone)
  let milestone = if task.milestone.is_empty() {
    None
  } else {
    match milestones {
      [m] => Some(m)
      _ => None
    }
  }
  let reference : Json = {
    "project_id": d.project_id,
    "plan_key": d.key,
    "task_id": task.id,
    "prepared_at": d.prepared_at,
  }
  let context = [
    "Planning snapshot only. Prerequisite completion, authority and execution are not established.",
    "Scope and source notes:",
    d.notes,
    "",
    "Plan task: " + task.name + " [" + task.id + "]",
    "Planned owner (not assigned to the new task): " +
    brief_owner(d, task.owner),
    "Estimated cost (authored text, not approved): " +
    task.cost +
    " " +
    d.currency,
    "Milestone: " +
    (match milestone {
      Some(m) => m.name + " [" + m.id + "]"
      None =>
        if task.milestone.is_empty() {
          "Unassigned"
        } else {
          "Missing or ambiguous [" + task.milestone + "]"
        }
    }),
    "Target date (authored text): " + milestone.map(m => m.date).unwrap_or(""),
    "",
    "Direct prerequisites (completion must be checked separately):",
  ]
  if task.dependencies.is_empty() {
    context.push("None declared.")
  }
  for prerequisite in task.dependencies {
    context.push("- " + handoff_task_name(d, prerequisite))
  }
  context.push("")
  context.push("Linked and plan-wide risks:")
  let risks = d.risks.filter(r => {
    r.tasks.is_empty() || r.tasks.contains(task.id)
  })
  if risks.is_empty() {
    context.push("None declared.")
  }
  for risk in risks {
    context.push(
      "- " +
      risk.summary +
      " [" +
      risk.id +
      "]" +
      (if risk.tasks.is_empty() { " (plan-wide)" } else { "" }),
    )
    context.push(
      "Severity: " + risk.severity + " · Owner: " + brief_owner(d, risk.owner),
    )
    context.push("Mitigation: " + risk.mitigation)
  }
  {
    title: task.name,
    acceptance: match milestone {
      Some(m) if !m.criteria.is_empty() || !m.evidence.is_empty() =>
        "Milestone context; adapt these criteria to this task before formal creation.\n" +
        "Criteria:\n" +
        m.criteria +
        "\nRequired evidence:\n" +
        m.evidence
      _ => ""
    },
    source_reference: "MoonProj plan task (local snapshot): " +
    reference.stringify(),
    context: context.join("\n") + "\n",
    end_date: milestone.map(m => m.date).unwrap_or(""),
  }
}
