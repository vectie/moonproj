///|
pub(all) struct TaskTableChange {
  before : Task
  after : Task
  fields : Array[String]
} derive(Debug, Eq, ToJson)

///|
pub(all) struct TaskTableUpdate {
  draft : Draft
  changes : Array[TaskTableChange]
  ignored : Array[String]
} derive(Debug, Eq)

///|
/// Preview edits to existing tasks by stable ID. Omitted rows and columns are
/// unchanged; an explicit blank dependencies cell clears its prerequisites.
/// The input draft is never mutated. Native prepare remains a separate action.
///
/// ```mbt nocheck
/// let preview = @plan_workbench.preview_task_table_updates(
///   draft, "id,cost\nTASK-1,125.50", false,
/// )
/// // Inspect preview.changes before replacing the browser draft with preview.draft.
/// ```
pub fn preview_task_table_updates(
  draft : Draft,
  source : String,
  tsv : Bool,
) -> TaskTableUpdate raise InputError {
  let rows = task_records(source, if tsv { '\t' } else { ',' })
  if rows.length() < 2 {
    raise Invalid("Provide a header and at least one existing task row")
  }
  let headers = rows[0].map(task_column)
  for key in ["id", "name", "owner", "milestone", "cost", "dependencies"] {
    if headers.filter(h => h == key).length() > 1 {
      raise Invalid("Duplicate mapped column: " + key)
    }
  }
  if !headers.contains("id") {
    raise Invalid("Missing column: id")
  }
  if !headers.any(h => !h.is_empty() && h != "id") {
    raise Invalid("Include at least one editable column besides id")
  }
  let ignored : Array[String] = []
  for i, header in headers {
    if header.is_empty() {
      ignored.push(rows[0][i])
    }
  }
  let originals : Map[String, Task] = {}
  for task in draft.tasks {
    if task.id.trim().is_empty() || originals.contains(task.id) {
      raise Invalid("Current draft has empty or duplicate task IDs")
    }
    originals[task.id] = task
  }
  let replacements : Map[String, Task] = {}
  let owners = draft.owners.map(o => (o.id, o.name))
  let milestones = draft.milestones.map(m => (m.id, m.name))
  for index = 1; index < rows.length(); index = index + 1 {
    let row = rows[index]
    let label = "Record " + (index + 1).to_string()
    if row.length() != headers.length() {
      raise Invalid(label + ": column count differs from header")
    }
    let values : Map[String, String] = {}
    for i, header in headers {
      if !header.is_empty() {
        values[header] = row[i]
      }
    }
    let id = values["id"].trim().to_owned()
    guard originals.get(id) is Some(before) else {
      raise Invalid(
        label + ": unknown task ID " + id + "; use append for new tasks",
      )
    }
    if replacements.contains(id) {
      raise Invalid(label + ": duplicate task ID " + id)
    }
    let name = values.get("name").unwrap_or(before.name)
    if name.trim().is_empty() {
      raise Invalid(label + ": title cannot be blank")
    }
    let owner = match values.get("owner") {
      None => before.owner
      Some(value) if value.trim().is_empty() =>
        raise Invalid(
          label + ": owner cannot be blank; omit the column to keep it",
        )
      Some(value) =>
        task_assignment(value.trim().to_owned(), owners, label + " owner")
    }
    let milestone = match values.get("milestone") {
      None => before.milestone
      Some(value) if value.trim().is_empty() =>
        raise Invalid(
          label + ": milestone cannot be blank; omit the column to keep it",
        )
      Some(value) =>
        task_assignment(
          value.trim().to_owned(),
          milestones,
          label + " milestone",
        )
    }
    let cost = match values.get("cost") {
      None => before.cost
      Some(value) => {
        let value = value.trim().to_owned()
        let value = if value.is_empty() { "0" } else { value }
        let _ = minor(value, label + " cost")
        value
      }
    }
    let dependencies = match values.get("dependencies") {
      None => before.dependencies
      Some(value) =>
        value
        .split(";")
        .map(v => v.trim().to_owned())
        .filter(v => !v.is_empty())
        .collect()
    }
    replacements[id] = { id, name, owner, milestone, cost, dependencies, }
  }
  let tasks = draft.tasks.map(t => replacements.get(t.id).unwrap_or(t))
  let seen : Array[String] = []
  let changes : Array[TaskTableChange] = []
  for i, task in tasks {
    let dependencies : Array[String] = []
    for dependency in task.dependencies {
      if dependencies.contains(dependency) {
        raise Invalid(
          "Task " + task.id + ": duplicate dependency " + dependency,
        )
      }
      if !seen.contains(dependency) {
        raise Invalid(
          "Task " +
          task.id +
          ": dependency must appear earlier in the draft: " +
          dependency,
        )
      }
      dependencies.push(dependency)
    }
    seen.push(task.id)
    let before = draft.tasks[i]
    let fields : Array[String] = []
    if before.name != task.name {
      fields.push("title")
    }
    if before.owner != task.owner {
      fields.push("owner")
    }
    if before.milestone != task.milestone {
      fields.push("milestone")
    }
    if before.cost != task.cost {
      fields.push("cost")
    }
    if before.dependencies != task.dependencies {
      fields.push("dependencies")
    }
    if !fields.is_empty() {
      changes.push({ before, after: task, fields, })
    }
  }
  { draft: { ..draft, tasks, }, changes, ignored, }
}
