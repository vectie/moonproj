///|
#derive(Debug, Eq, ToJson)
pub(all) struct RiskImpact {
  direct_tasks : Array[String]
  downstream_tasks : Array[String]
  known_minor : Int64?
  invalid_tasks : Int32
  owners : Array[CostBucket]
  milestones : Array[CostBucket]
}

///|
/// Trace one risk's authored task links through a valid dependency graph.
/// A task appears once even when several linked tasks or paths reach it.
/// Costs describe the scope of work, never expected loss or risk probability.
pub fn risk_impact(d : Draft, risk_id : String) -> RiskImpact raise InputError {
  if d.tasks.length() > 100 ||
    d.risks.length() > 100 ||
    d.owners.length() > 40 ||
    d.milestones.length() > 40 {
    raise Invalid(
      "Risk impact supports at most 100 tasks/risks and 40 owners/milestones",
    )
  }
  let risks = d.risks.filter(r => r.id == risk_id)
  guard !risk_id.trim().is_empty() && risks is [risk] else {
    raise Invalid("Select a current risk with a unique nonblank ID")
  }
  if risk.tasks.length() > 100 {
    raise Invalid("A risk can link at most 100 task references")
  }
  for task in d.tasks {
    if task.id.trim().is_empty() {
      raise Invalid("Repair the blank task ID before tracing risk impact")
    }
  }
  let graph = dependency_plan(d, "")
  if !graph.issues.is_empty() {
    raise Invalid(
      "Repair the dependency graph before tracing risk impact:\n" +
      graph.issues.join("\n"),
    )
  }
  for id in risk.tasks {
    if !d.tasks.any(t => t.id == id) {
      raise Invalid(
        "Risk " +
        risk_id +
        " references missing task " +
        id +
        "; repair its task links",
      )
    }
  }
  let direct_tasks = d.tasks
    .filter(t => risk.tasks.contains(t.id))
    .map(t => t.id)
  let reached = direct_tasks.copy()
  // Seed all linked tasks together, then compute the union of their descendants.
  let mut changed = true
  while changed {
    changed = false
    for task in d.tasks {
      if !reached.contains(task.id) &&
        task.dependencies.any(id => reached.contains(id)) {
        reached.push(task.id)
        changed = true
      }
    }
  }
  let tasks = d.tasks.filter(t => reached.contains(t.id))
  let scoped = { ..d, tasks, }
  let (known, invalid_tasks) = cost_sum(tasks)
  {
    direct_tasks,
    downstream_tasks: tasks
    .filter(t => !direct_tasks.contains(t.id))
    .map(t => t.id),
    known_minor: if tasks.is_empty() {
      None
    } else {
      known
    },
    invalid_tasks,
    owners: cost_buckets(scoped, true),
    milestones: cost_buckets(scoped, false),
  }
}

///|
fn risk_impact_owner(d : Draft, id : String) -> String {
  let names = d.owners.filter(o => o.id == id).map(o => o.name)
  let label = if id.trim().is_empty() {
    "Unassigned"
  } else {
    match names {
      [name] if !name.trim().is_empty() => name
      [_] => "Unnamed owner"
      [] => "Missing owner reference"
      _ => "Ambiguous owner reference"
    }
  }
  label + " [" + id + "]"
}

///|
fn risk_impact_task(d : Draft, task : Task) -> String {
  let milestones = d.milestones.filter(m => m.id == task.milestone)
  let milestone = match milestones {
    [m] => m.name + " [" + m.id + "]; target date (authored): " + m.date
    [] => "Missing/unassigned milestone [" + task.milestone + "]"
    _ => "Ambiguous milestone [" + task.milestone + "]"
  }
  "- " +
  task.name +
  " [" +
  task.id +
  "]\n  Owner: " +
  risk_impact_owner(d, task.owner) +
  "\n  Milestone: " +
  milestone +
  "\n  Cost (authored): " +
  task.cost +
  " " +
  d.currency +
  "; minor units: " +
  cost_text((Ok(minor(task.cost, "Cost")) catch { e => Err(e) }).to_option()) +
  "\n  Prerequisites: " +
  (if task.dependencies.is_empty() {
    "None"
  } else {
    task.dependencies.join(", ")
  })
}

///|
/// A readable, source-backed snapshot of the selected risk's planning scope.
pub fn risk_impact_report(
  d : Draft,
  risk_id : String,
  project_name : String,
) -> String raise InputError {
  let impact = risk_impact(d, risk_id)
  let risk = d.risks.filter(r => r.id == risk_id)[0]
  let out = [
    "Risk impact planning brief / 风险影响简报",
    "Project: " + project_name + " [" + d.project_id + "]",
    "Local plan version: " + d.key,
    "Revision timestamp (authored): " + d.prepared_at,
    "Planning context only. No task is dispatched, blocked, completed or authorized by this report.",
    "Dependency reachability shows potentially affected work, not probability, expected loss, delay duration or actual status.",
    "",
    "Risk: " + risk.summary + " [" + risk.id + "]",
    "Severity (authored): " + risk.severity,
    "Risk owner: " + risk_impact_owner(d, risk.owner),
    "Mitigation (authored):\n" +
    (if risk.mitigation.is_empty() { "Not supplied" } else { risk.mitigation }),
    "",
    "Source and scope notes (authored):\n" + d.notes,
    "",
    "Directly linked tasks (" + impact.direct_tasks.length().to_string() + ")",
  ]
  if impact.direct_tasks.is_empty() {
    out.push(
      "No task links supplied. Exposure is unassessed, not zero; link tasks in the risk editor.",
    )
  }
  for task in d.tasks.filter(t => impact.direct_tasks.contains(t.id)) {
    out.push(risk_impact_task(d, task))
  }
  out.push(
    "\nDownstream-only tasks (" +
    impact.downstream_tasks.length().to_string() +
    ")",
  )
  if impact.downstream_tasks.is_empty() {
    out.push("No additional downstream tasks in the current graph.")
  }
  for task in d.tasks.filter(t => impact.downstream_tasks.contains(t.id)) {
    out.push(risk_impact_task(d, task))
  }
  out.push("\nAuthored cost exposure across unique affected tasks")
  out.push("Currency (authored): " + d.currency)
  out.push(
    "Known cost subtotal (minor units, 100 per entered unit): " +
    cost_text(impact.known_minor),
  )
  out.push("Blank/invalid cost estimates: " + impact.invalid_tasks.to_string())
  out.push(
    if impact.direct_tasks.is_empty() {
      "Cost coverage: unassessed (no linked tasks)."
    } else if impact.known_minor is None {
      "Cost coverage: unavailable (sum overflow)."
    } else if impact.invalid_tasks > 0 {
      "Cost coverage: incomplete. Missing/invalid estimates are not zero."
    } else {
      "Cost coverage: all affected task estimates parsed."
    },
  )
  out.push(
    "Each task is counted once across direct and downstream work. Unrelated tasks, contingency and budget headroom are excluded. This subtotal is not expected loss.",
  )
  for
    (title, buckets) in [
      ("Affected task owners", impact.owners),
      ("Affected milestones", impact.milestones),
    ] {
    out.push("\n" + title)
    if buckets.is_empty() {
      out.push("None assessed.")
    }
    for bucket in buckets {
      out.push(
        "- " +
        (if bucket.label.trim().is_empty() {
          "Unnamed reference"
        } else {
          bucket.label
        }) +
        " [" +
        bucket.id +
        "]: tasks " +
        bucket.task_ids.join(", ") +
        "; known minor units " +
        cost_text(bucket.known_minor) +
        "; invalid estimates " +
        bucket.invalid_tasks.to_string(),
      )
    }
  }
  out.push(
    "Owner and milestone groups partition the SAME affected task costs; do not add the two views together. Other risks may overlap this scope; do not sum risk briefs as independent losses.",
  )
  out.join("\n") + "\n"
}
