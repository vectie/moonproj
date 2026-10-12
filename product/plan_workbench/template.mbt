///|
/// Portable authoring content only. Row IDs are template-local references.
pub(all) struct Template {
  format : String
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
fn template_ids(ids : Array[String], label : String) -> Unit raise InputError {
  let seen : Map[String, Bool] = {}
  for id in ids {
    if id.trim().is_empty() || seen.contains(id) {
      raise Invalid(label + ": IDs must be nonempty and unique: " + id)
    }
    seen[id] = true
  }
}

///|
fn template_ref(
  id : String,
  ids : Array[String],
  label : String,
) -> Unit raise InputError {
  // Blank assignments remain editable blanks, not invented assignments.
  if !id.is_empty() && !ids.contains(id) {
    raise Invalid(label + ": missing reference " + id)
  }
}

///|
fn template_validate(t : Template) -> Unit raise InputError {
  if t.format != "moonproj-plan-template/v1" {
    raise Invalid("Expected moonproj-plan-template/v1")
  }
  if t.owners.is_empty() ||
    t.owners.length() > 40 ||
    t.tasks.length() > 100 ||
    t.milestones.length() > 40 ||
    t.risks.length() > 100 {
    raise Invalid(
      "Template limits: 1–40 owners, 100 tasks, 40 milestones, 100 risks",
    )
  }
  let owners = t.owners.map(o => o.id)
  let tasks = t.tasks.map(v => v.id)
  let milestones = t.milestones.map(v => v.id)
  template_ids(owners, "Owners")
  template_ids(tasks, "Tasks")
  template_ids(milestones, "Milestones")
  template_ids(t.risks.map(v => v.id), "Risks")
  for task in t.tasks {
    template_ref(task.owner, owners, "Task " + task.id + " owner")
    template_ref(task.milestone, milestones, "Task " + task.id + " milestone")
    template_ids(task.dependencies, "Task " + task.id + " dependencies")
    for id in task.dependencies {
      template_ref(id, tasks, "Task " + task.id + " dependency")
    }
  }
  for milestone in t.milestones {
    template_ref(
      milestone.owner,
      owners,
      "Milestone " + milestone.id + " owner",
    )
  }
  for risk in t.risks {
    template_ref(risk.owner, owners, "Risk " + risk.id + " owner")
    template_ids(risk.tasks, "Risk " + risk.id + " tasks")
    for id in risk.tasks {
      template_ref(id, tasks, "Risk " + risk.id + " task")
    }
  }
}

///|
fn template_keys(
  value : Json,
  keys : Array[String],
  label : String,
) -> Unit raise InputError {
  guard value is Object(fields) else {
    raise Invalid(label + ": expected an object")
  }
  for key, _ in fields {
    if !keys.contains(key) {
      raise Invalid(label + ": unsupported field " + key)
    }
  }
  for key in keys {
    if !fields.contains(key) {
      raise Invalid(label + ": missing field " + key)
    }
  }
}

///|
/// Parse the bounded editable format without interpreting dates, money or status.
pub fn read_template(source : String) -> Template raise InputError {
  if source.length() > 1000000 {
    raise Invalid("Template exceeds 1,000,000 text code units")
  }
  let json = @json.parse(source) catch {
    _ => raise Invalid("Template is not valid JSON")
  }
  template_keys(
    json,
    [
      "format", "notes", "currency", "limit", "contingency", "owners", "tasks", "milestones",
      "risks",
    ],
    "Template",
  )
  let t : Template = @json.from_json(json) catch {
    _ =>
      raise Invalid(
        "Template fields have the wrong types; text values must be strings",
      )
  }
  for
    (kind, keys) in [
      ("owners", ["id", "name", "role"]),
      ("tasks", ["id", "name", "owner", "milestone", "cost", "dependencies"]),
      ("milestones", ["id", "name", "owner", "date", "criteria", "evidence"]),
      ("risks", ["id", "summary", "severity", "owner", "mitigation", "tasks"]),
    ] {
    for i, row in items(json, kind) {
      template_keys(row, keys, kind + " " + (i + 1).to_string())
    }
  }
  template_validate(t)
  t
}

///|
fn template_map(ids : Array[String], prefix : String) -> Map[String, String] {
  let result : Map[String, String] = { "": "" }
  for i, id in ids {
    result[id] = prefix + (i + 1).to_string()
  }
  result
}

///|
fn template_remap(
  t : Template,
  owners : Map[String, String],
  tasks : Map[String, String],
  milestones : Map[String, String],
  risks : Map[String, String],
) -> Template {
  {
    ..t,
    owners: t.owners.map(o => { ..o, id: owners[o.id], }),
    tasks: t.tasks.map(v => {
      ..v,
      id: tasks[v.id],
      owner: owners[v.owner],
      milestone: milestones[v.milestone],
      dependencies: v.dependencies.map(id => tasks[id]),
    }),
    milestones: t.milestones.map(v => {
      ..v,
      id: milestones[v.id],
      owner: owners[v.owner],
    }),
    risks: t.risks.map(v => {
      ..v,
      id: risks[v.id],
      owner: owners[v.owner],
      tasks: v.tasks.map(id => tasks[id]),
    }),
  }
}

///|
/// Remove source project/request/time and replace every identity with a local slot.
/// All authored text, dates, amount strings and row order remain exact.
pub fn export_template(d : Draft) -> String raise InputError {
  let t : Template = {
    format: "moonproj-plan-template/v1",
    notes: d.notes,
    currency: d.currency,
    limit: d.limit,
    contingency: d.contingency,
    owners: d.owners,
    tasks: d.tasks,
    milestones: d.milestones,
    risks: d.risks,
  }
  template_validate(t)
  let portable = template_remap(
      t,
      template_map(t.owners.map(v => v.id), "owner-"),
      template_map(t.tasks.map(v => v.id), "task-"),
      template_map(t.milestones.map(v => v.id), "milestone-"),
      template_map(t.risks.map(v => v.id), "risk-"),
    )
    .to_json()
    .stringify(indent=2)
  if portable.length() > 1000000 {
    raise Invalid("Template exceeds 1,000,000 text code units")
  }
  portable
}

///|
/// Replace target authoring content with a fresh copy; map one chosen owner slot
/// to the current preparer, with the explicitly entered display name.
pub fn apply_template(
  t : Template,
  target : Draft,
  actor : String,
  owner_slot : String,
  preparer_name : String,
  fresh_prefix : String,
) -> Draft raise InputError {
  template_validate(t)
  if actor.is_empty() ||
    !target.owners.any(o => o.id == actor) ||
    target.project_id.is_empty() {
    raise Invalid("Choose a current project and preparer first")
  }
  if !t.owners.any(o => o.id == owner_slot) ||
    preparer_name.trim().is_empty() ||
    fresh_prefix.is_empty() {
    raise Invalid("Choose your template owner and enter your display name")
  }
  let owners = template_map(t.owners.map(v => v.id), fresh_prefix + "-owner-")
  owners[owner_slot] = actor
  if owners.values().filter(v => v == actor).count() != 1 {
    raise Invalid("Fresh owner identity collides with preparer")
  }
  let imported = template_remap(
    t,
    owners,
    template_map(t.tasks.map(v => v.id), fresh_prefix + "-task-"),
    template_map(t.milestones.map(v => v.id), fresh_prefix + "-milestone-"),
    template_map(t.risks.map(v => v.id), fresh_prefix + "-risk-"),
  )
  {
    ..target,
    notes: imported.notes,
    currency: imported.currency,
    limit: imported.limit,
    contingency: imported.contingency,
    owners: imported.owners.map(o => {
      if o.id == actor {
        { ..o, name: preparer_name, }
      } else {
        o
      }
    }),
    tasks: imported.tasks,
    milestones: imported.milestones,
    risks: imported.risks,
  }
}
