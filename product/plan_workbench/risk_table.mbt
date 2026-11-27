///|
#derive(Debug, Eq, ToJson)
pub(all) struct RiskTableChange {
  before : Risk?
  after : Risk
  fields : Array[String]
}

///|
#derive(Debug, Eq)
pub(all) struct RiskTableUpdate {
  draft : Draft
  changes : Array[RiskTableChange]
  ignored : Array[String]
}

///|
fn risk_column(header : String) -> String {
  match header.trim().to_owned().to_lower() {
    "id" | "risk_id" | "risk id" => "id"
    "summary" | "title" | "risk" => "summary"
    "severity" => "severity"
    "owner" | "owner_id" | "assignee" => "owner"
    "mitigation" | "mitigation plan" => "mitigation"
    "tasks" | "related_task_ids" | "related tasks" => "tasks"
    _ => ""
  }
}

///|
fn risk_table_tasks(
  value : String,
  draft : Draft,
  label : String,
) -> Array[String] raise InputError {
  let value = value.trim().to_owned()
  let ids : Array[String] = if value.has_prefix("[") {
    @json.from_json(@json.parse(value)) catch {
      _ =>
        raise Invalid(label + ": tasks must be a JSON array of task ID strings")
    }
  } else {
    value
    .split(";")
    .map(v => v.trim().to_owned())
    .filter(v => !v.is_empty())
    .collect()
  }
  let seen : Array[String] = []
  for id in ids {
    if draft.tasks.filter(t => t.id == id).length() != 1 {
      raise Invalid(label + ": unknown or ambiguous task ID " + id)
    }
    if seen.contains(id) {
      raise Invalid(label + ": duplicate task ID " + id)
    }
    seen.push(id)
  }
  ids
}

///|
/// Preview a risk register without changing the original draft. Existing IDs
/// update only supplied columns; new IDs append after existing rows. Summary,
/// severity and owner are required for new rows. Empty mitigation/tasks clear
/// those fields; omitted fields and rows stay unchanged. No rows are deleted.
pub fn preview_risk_table(
  draft : Draft,
  source : String,
  tsv : Bool,
) -> RiskTableUpdate raise InputError {
  if source.length() > 1000000 {
    raise Invalid("Risk table exceeds 1,000,000 text units")
  }
  let rows = task_records(source, if tsv { '\t' } else { ',' })
  if rows.length() < 2 || rows.length() > 101 {
    raise Invalid("Provide a header and 1–100 risk rows")
  }
  let headers = rows[0].map(risk_column)
  for key in ["id", "summary", "severity", "owner", "mitigation", "tasks"] {
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
  let originals : Map[String, Risk] = Map([])
  for risk in draft.risks {
    if risk.id.trim().is_empty() ||
      risk.id != risk.id.trim().to_owned() ||
      originals.contains(risk.id) {
      raise Invalid("Current draft has blank, padded or duplicate risk IDs")
    }
    originals[risk.id] = risk
  }
  let replacements : Map[String, Risk] = Map([])
  let added : Array[Risk] = []
  let owners = draft.owners.map(o => (o.id, o.name))
  for index = 1; index < rows.length(); index = index + 1 {
    let row = rows[index]
    let label = "Record " + (index + 1).to_string()
    if row.length() != headers.length() {
      raise Invalid(label + ": column count differs from header")
    }
    let values : Map[String, String] = Map([])
    for i, header in headers {
      if !header.is_empty() {
        values[header] = row[i]
      }
    }
    let id = values["id"].trim().to_owned()
    if id.is_empty() || replacements.contains(id) {
      raise Invalid(label + ": blank or duplicate risk ID " + id)
    }
    let before = originals.get(id)
    if before is None {
      for key in ["summary", "severity", "owner"] {
        if !values.contains(key) {
          raise Invalid(label + ": new risk " + id + " requires column " + key)
        }
      }
    }
    let base : Risk = before.unwrap_or({
      id,
      summary: "",
      severity: "",
      owner: "",
      mitigation: "",
      tasks: [],
    })
    let summary = match values.get("summary") {
      None => base.summary
      Some(value) => {
        if value.trim().is_empty() {
          raise Invalid(label + ": summary cannot be blank")
        }
        value
      }
    }
    let severity = match values.get("severity") {
      None => base.severity
      Some(value) => {
        let value = value.trim().to_owned()
        if !["low", "medium", "high", "critical"].contains(value) {
          raise Invalid(
            label + ": severity must be low, medium, high or critical",
          )
        }
        value
      }
    }
    let owner = match values.get("owner") {
      None => base.owner
      Some(value) => {
        if value.trim().is_empty() {
          raise Invalid(label + ": owner cannot be blank")
        }
        let owner = task_assignment(
          value.trim().to_owned(),
          owners,
          label + " owner",
        )
        if owner.is_empty() || owners.filter(p => p.0 == owner).length() != 1 {
          raise Invalid(label + ": owner identity is blank or ambiguous")
        }
        owner
      }
    }
    let tasks = match values.get("tasks") {
      None => base.tasks
      Some(value) => risk_table_tasks(value, draft, label)
    }
    let after : Risk = {
      id,
      summary,
      severity,
      owner,
      mitigation: values.get("mitigation").unwrap_or(base.mitigation),
      tasks,
    }
    replacements[id] = after
    if before is None {
      added.push(after)
    }
  }
  let risks = [
    ..draft.risks.map(r => replacements.get(r.id).unwrap_or(r)),
    ..added,
  ]
  if risks.length() > 100 {
    raise Invalid("A plan supports at most 100 risks")
  }
  let changes : Array[RiskTableChange] = []
  for after in risks {
    let before = originals.get(after.id)
    let fields : Array[String] = []
    match before {
      None => fields.push("new risk")
      Some(before) => {
        if before.summary != after.summary {
          fields.push("summary")
        }
        if before.severity != after.severity {
          fields.push("severity")
        }
        if before.owner != after.owner {
          fields.push("owner")
        }
        if before.mitigation != after.mitigation {
          fields.push("mitigation")
        }
        if before.tasks != after.tasks {
          fields.push("tasks")
        }
      }
    }
    if !fields.is_empty() {
      changes.push({ before, after, fields, })
    }
  }
  { draft: { ..draft, risks, }, changes, ignored, }
}

///|
/// Exact editable risk register. Tasks are a JSON array inside the quoted CSV
/// cell so task IDs containing semicolons, quotes or newlines remain unambiguous.
/// This is local planning content, not execution or evidence of resolved risks.
pub fn export_risk_table(draft : Draft) -> String {
  let rows = ["id,summary,severity,owner,mitigation,tasks"]
  for risk in draft.risks {
    rows.push(
      [
        risk.id,
        risk.summary,
        risk.severity,
        risk.owner,
        risk.mitigation,
        ToJson::to_json(risk.tasks).stringify(),
      ]
      .map(task_csv_cell)
      .join(","),
    )
  }
  rows.join("\r\n") + "\r\n"
}
