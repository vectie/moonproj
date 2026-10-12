///|
pub(all) struct Owner {
  id : String
  name : String
  role : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Task {
  id : String
  name : String
  owner : String
  milestone : String
  cost : String
  dependencies : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Milestone {
  id : String
  name : String
  owner : String
  date : String
  criteria : String
  evidence : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Risk {
  id : String
  summary : String
  severity : String
  owner : String
  mitigation : String
  tasks : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct Draft {
  key : String
  project_id : String
  prepared_at : String
  notes : String
  currency : String
  limit : String
  contingency : String
  owners : Array[Owner]
  tasks : Array[Task]
  milestones : Array[Milestone]
  risks : Array[Risk]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror InputError {
  Invalid(String)
} derive(Debug, Eq)

///|
pub fn minor(value : String, field : String) -> Int64 raise InputError {
  let parts = value.trim().split(".").map(p => p.to_owned()).collect()
  if parts.is_empty() ||
    parts.length() > 2 ||
    parts[0].is_empty() ||
    parts[0].length() > 15 ||
    !parts[0].iter().all(c => c.is_ascii_digit()) {
    raise Invalid(
      field + ": enter a non-negative amount with at most two decimal places",
    )
  }
  let fraction = if parts.length() == 2 { parts[1] } else { "" }
  if fraction.length() > 2 || !fraction.iter().all(c => c.is_ascii_digit()) {
    raise Invalid(field + ": use at most two decimal places")
  }
  @string.parse_int64(parts[0] + fraction + "0".repeat(2 - fraction.length())) catch {
    _ => raise Invalid(field + ": amount is too large")
  }
}

///|
fn lines(value : String) -> Array[String] {
  value
  .split("\n")
  .map(v => v.trim().to_owned())
  .filter(v => !v.is_empty())
  .collect()
}

///|
pub fn field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
pub fn text(value : Json, key : String) -> String {
  match field(value, key) {
    String(v) => v
    _ => ""
  }
}

///|
pub fn items(value : Json, key : String) -> Array[Json] {
  match field(value, key) {
    Array(v) => v
    _ => []
  }
}

///|
/// Wire projection only. All project rules remain in native project_plan.prepare.
pub fn request(
  draft : Draft,
  actor : String,
  project : Json,
  source_ref : String,
  digest : String,
) -> Json raise InputError {
  if draft.owners.length() > 40 ||
    draft.tasks.length() > 100 ||
    draft.milestones.length() > 40 ||
    draft.risks.length() > 100 ||
    draft.notes.trim().is_empty() {
    raise Invalid(
      "Scope notes are required; limits are 40 owners, 100 tasks, 40 milestones and 100 risks",
    )
  }
  let milestones = draft.milestones.map(m => {
    (
      {
        "milestone_id": m.id,
        "name": m.name,
        "owner_id": m.owner,
        "target_date": m.date,
        "task_ids": draft.tasks
        .filter(t => t.milestone == m.id)
        .map(t => t.id)
        .to_json(),
        "acceptance_gate_ids": [m.id + "-gate"],
      } : Json)
  })
  let tasks : Array[Json] = []
  for i, t in draft.tasks {
    tasks.push({
      "task_id": t.id,
      "name": t.name,
      "owner_id": t.owner,
      "milestone_id": t.milestone,
      "planned_cost_minor": minor(
        t.cost,
        "Task " + (i + 1).to_string() + " cost",
      ).to_json(),
      "dependencies": t.dependencies.to_json(),
      "acceptance_gate_ids": [t.milestone + "-gate"],
      "source_evidence_refs": [source_ref],
    })
  }
  {
    "contract_id": "moonproj.project-plan-request.v1",
    "operation_ref": "moonproj/project.plan.prepare@0.1.0",
    "plan_request_id": draft.key,
    "project": project,
    "prepared_by": actor,
    "prepared_at": draft.prepared_at,
    "owners": draft.owners
    .map(o => {
      ({ "owner_id": o.id, "display_name": o.name, "role": o.role } : Json)
    })
    .to_json(),
    "budget_envelope": {
      "currency": draft.currency,
      "limit_minor": minor(draft.limit, "Budget limit").to_json(),
      "contingency_minor": minor(draft.contingency, "Contingency").to_json(),
    },
    "tasks": tasks.to_json(),
    "milestones": milestones.to_json(),
    "risks": draft.risks
    .map(r => {
      (
        {
          "risk_id": r.id,
          "summary": r.summary,
          "severity": r.severity,
          "owner_id": r.owner,
          "mitigation": r.mitigation,
          "related_task_ids": r.tasks.to_json(),
          "source_evidence_refs": [source_ref],
        } : Json)
    })
    .to_json(),
    "acceptance_gates": draft.milestones
    .map(m => {
      (
        {
          "gate_id": m.id + "-gate",
          "name": m.name + " review",
          "owner_id": m.owner,
          "scope_type": "milestone",
          "scope_id": m.id,
          "criteria": lines(m.criteria).to_json(),
          "required_evidence": lines(m.evidence).to_json(),
        } : Json)
    })
    .to_json(),
    "source_evidence": [
      {
        "artifact_ref": source_ref,
        "digest": digest,
        "observed_at": draft.prepared_at,
        "kind": "user-authored-planning-input-and-company-project-identity",
      },
    ],
  }
}

///|
pub fn readable(artifact : Json) -> String {
  let out = StringBuilder()
  let project = field(artifact, "project")
  out.write_string(
    "Project plan: " +
    text(project, "name") +
    "\nProject: " +
    text(project, "project_id") +
    "\nPending named-human review. No spending, payment, accounting, contract or work authorization.\n\n",
  )
  let budget = field(artifact, "budget")
  out.write_string(
    "Budget in " +
    text(budget, "currency") +
    " (minor units)\nLimit: " +
    field(budget, "limit_minor").stringify() +
    "\nPlanned: " +
    field(budget, "planned_total_minor").stringify() +
    "\nContingency: " +
    field(budget, "contingency_minor").stringify() +
    "\nUnallocated: " +
    field(budget, "unallocated_minor").stringify() +
    "\n\nOwners\n",
  )
  for owner in items(artifact, "owners") {
    out.write_string(
      "- " + text(owner, "display_name") + ": " + text(owner, "role") + "\n",
    )
  }
  out.write_string("\nDependency sequence\n")
  for i, task in items(artifact, "tasks") {
    let deps = items(task, "dependencies").filter_map(value => {
      match value {
        String(id) =>
          Some(readable_name(artifact, "tasks", "task_id", "name", id))
        _ => None
      }
    })
    out.write_string(
      (i + 1).to_string() +
      ". " +
      text(task, "name") +
      "\n   Owner: " +
      readable_name(
        artifact,
        "owners",
        "owner_id",
        "display_name",
        text(task, "owner_id"),
      ) +
      " | milestone: " +
      readable_name(
        artifact,
        "milestones",
        "milestone_id",
        "name",
        text(task, "milestone_id"),
      ) +
      " | cost minor: " +
      field(task, "planned_cost_minor").stringify() +
      "\n   Dependencies: " +
      (if deps.is_empty() { "None" } else { deps.join(", ") }) +
      "\n",
    )
  }
  out.write_string("\nMilestones and acceptance\n")
  for milestone in items(artifact, "milestones") {
    out.write_string(
      "- " +
      text(milestone, "name") +
      " | target: " +
      text(milestone, "target_date") +
      " | owner: " +
      readable_name(
        artifact,
        "owners",
        "owner_id",
        "display_name",
        text(milestone, "owner_id"),
      ) +
      "\n",
    )
    for
      gate in items(artifact, "acceptance_gates").filter(g => {
        text(g, "scope_id") == text(milestone, "milestone_id")
      }) {
      for criterion in items(gate, "criteria") {
        if criterion is String(value) {
          out.write_string("   Criterion: " + value + "\n")
        }
      }
      for evidence in items(gate, "required_evidence") {
        if evidence is String(value) {
          out.write_string("   Required evidence: " + value + "\n")
        }
      }
    }
  }
  out.write_string("\nRisks\n")
  if items(artifact, "risks").is_empty() {
    out.write_string("No risk rows supplied; this is not proof of no risk.\n")
  }
  for risk in items(artifact, "risks") {
    out.write_string(
      "- " +
      text(risk, "severity") +
      ": " +
      text(risk, "summary") +
      "\n   Owner: " +
      readable_name(
        artifact,
        "owners",
        "owner_id",
        "display_name",
        text(risk, "owner_id"),
      ) +
      "\n   Mitigation: " +
      text(risk, "mitigation") +
      "\n",
    )
  }
  out.write_string(
    "\nPlan version: " +
    text(artifact, "plan_request_id") +
    "\nRecorded at: " +
    text(artifact, "recorded_at") +
    "\nRequest digest: " +
    text(artifact, "request_digest") +
    "\n",
  )
  out.to_string()
}

///|
fn readable_name(
  artifact : Json,
  array : String,
  id_field : String,
  name_field : String,
  id : String,
) -> String {
  items(artifact, array)
  .filter(v => text(v, id_field) == id)
  .get(0)
  .map(v => text(v, name_field))
  .unwrap_or(id)
}
