///|
// A small delimited-record reader shared by native and browser workflows.
fn task_records(
  source : String,
  separator : Char,
) -> Array[Array[String]] raise InputError {
  let chars = source.to_array()
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let mut cell = ""
  let mut quoted = false
  let mut closed = false
  let mut i = if chars.get(0) == Some('\u{FEFF}') { 1 } else { 0 }
  while i < chars.length() {
    let c = chars[i]
    if quoted {
      if c == '"' {
        if chars.get(i + 1) == Some('"') {
          cell += "\""
          i += 1
        } else {
          quoted = false
          closed = true
        }
      } else {
        cell += c.to_string()
      }
    } else if c == separator || c == '\n' || c == '\r' {
      row.push(cell)
      cell = ""
      closed = false
      if c != separator {
        if !row.iter().all(v => v.is_empty()) {
          rows.push(row)
        }
        row = []
        if c == '\r' && chars.get(i + 1) == Some('\n') {
          i += 1
        }
      }
    } else if c == '"' && cell.is_empty() && !closed {
      quoted = true
    } else if closed || c == '"' {
      raise Invalid(
        "Invalid quoting near record " + (rows.length() + 1).to_string(),
      )
    } else {
      cell += c.to_string()
    }
    i += 1
  }
  if quoted {
    raise Invalid("Unclosed quoted field")
  }
  row.push(cell)
  if !row.iter().all(v => v.is_empty()) {
    rows.push(row)
  }
  rows
}

///|
fn task_column(header : String) -> String {
  match header.trim().to_owned().to_lower() {
    "id" | "task_id" | "issue key" | "identifier" | "key" => "id"
    "name" | "title" | "summary" => "name"
    "owner" | "owner_id" | "assignee" => "owner"
    "milestone" | "milestone_id" => "milestone"
    "cost" | "planned cost" => "cost"
    "dependencies" | "depends on" => "dependencies"
    _ => ""
  }
}

///|
fn task_assignment(
  value : String,
  options : Array[(String, String)],
  label : String,
) -> String raise InputError {
  let ids = options.filter(p => p.0 == value)
  if ids.length() == 1 {
    return ids[0].0
  }
  let names = options.filter(p => p.1 == value)
  if names.length() == 1 {
    return names[0].0
  }
  raise Invalid(label + ": choose an existing unique ID or name: " + value)
}

///|
/// Append table rows atomically to an editable plan. Unknown source columns
/// are returned to the caller for explicit visibility, never projected as facts.
pub fn import_task_table(
  draft : Draft,
  source : String,
  tsv : Bool,
  default_owner : String,
  default_milestone : String,
) -> (Draft, Array[String]) raise InputError {
  let rows = task_records(source, if tsv { '\t' } else { ',' })
  if rows.length() < 2 {
    raise Invalid("Provide a header and at least one task row")
  }
  let headers = rows[0].map(task_column)
  for key in ["id", "name", "owner", "milestone", "cost", "dependencies"] {
    let count = headers.filter(h => h == key).length()
    if count > 1 {
      raise Invalid("Duplicate mapped column: " + key)
    }
    if (key == "id" || key == "name") && count == 0 {
      raise Invalid("Missing column: " + key)
    }
  }
  let ignored : Array[String] = []
  for i, h in headers {
    if h.is_empty() {
      ignored.push(rows[0][i])
    }
  }
  let tasks = draft.tasks.copy()
  let owners = draft.owners.map(o => (o.id, o.name))
  let milestones = draft.milestones.map(m => (m.id, m.name))
  for index = 1; index < rows.length(); index = index + 1 {
    let row = rows[index]
    let label = "Record " + (index + 1).to_string()
    if row.length() != headers.length() {
      raise Invalid(label + ": column count differs from header")
    }
    let values : Map[String, String] = Map([])
    for i, h in headers {
      if !h.is_empty() {
        values[h] = row[i].trim().to_owned()
      }
    }
    let id = values.get("id").unwrap_or("")
    let name = values.get("name").unwrap_or("")
    if id.is_empty() || name.is_empty() {
      raise Invalid(label + ": ID and title are required")
    }
    if tasks.any(t => t.id == id) {
      raise Invalid(label + ": duplicate task ID " + id)
    }
    let owner = values.get("owner").unwrap_or("")
    let milestone = values.get("milestone").unwrap_or("")
    let cost = values.get("cost").unwrap_or("")
    let cost = if cost.is_empty() { "0" } else { cost }
    let _ = minor(cost, label + " cost")
    let dependencies = values
      .get("dependencies")
      .unwrap_or("")
      .split(";")
      .map(v => v.trim().to_owned())
      .filter(v => !v.is_empty())
      .collect()
    tasks.push({
      id,
      name,
      owner: task_assignment(
        if owner.is_empty() {
          default_owner
        } else {
          owner
        },
        owners,
        label + " owner",
      ),
      milestone: task_assignment(
        if milestone.is_empty() {
          default_milestone
        } else {
          milestone
        },
        milestones,
        label + " milestone",
      ),
      cost,
      dependencies,
    })
  }
  if tasks.length() > 100 {
    raise Invalid("A plan supports at most 100 tasks")
  }
  let seen : Array[String] = []
  for task in tasks {
    for dependency in task.dependencies {
      if !seen.contains(dependency) {
        raise Invalid(
          "Task " + task.id + ": dependency must appear earlier: " + dependency,
        )
      }
    }
    seen.push(task.id)
  }
  ({ ..draft, tasks, }, ignored)
}

///|
fn task_csv_cell(value : String) -> String {
  "\"" + value.replace_all(old="\"", new="\"\"") + "\""
}

///|
/// Exact editable task table; owner/milestone IDs retain assignments on reimport.
pub fn export_task_table(draft : Draft) -> String {
  let rows = ["id,title,owner,milestone,cost,dependencies"]
  for task in draft.tasks {
    rows.push(
      [
        task.id,
        task.name,
        task.owner,
        task.milestone,
        task.cost,
        task.dependencies.join(";"),
      ]
      .map(task_csv_cell)
      .join(","),
    )
  }
  rows.join("\r\n") + "\r\n"
}
