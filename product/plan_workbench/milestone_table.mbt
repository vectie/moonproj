///|
#derive(Debug, Eq, ToJson)
pub(all) struct MilestoneTableChange {
  before : Milestone
  after : Milestone
  fields : Array[String]
}

///|
#derive(Debug, Eq)
pub(all) struct MilestoneTableUpdate {
  draft : Draft
  changes : Array[MilestoneTableChange]
  ignored : Array[String]
}

///|
fn milestone_column(header : String) -> String {
  match header.trim().to_owned().to_lower() {
    "id" | "milestone_id" | "milestone id" => "id"
    "name" | "title" | "milestone" => "name"
    "owner" | "owner_id" | "assignee" => "owner"
    "date" | "target_date" | "target date" | "due date" => "date"
    "criteria" | "acceptance criteria" => "criteria"
    "evidence" | "required evidence" => "evidence"
    _ => ""
  }
}

///|
/// Preview a spreadsheet edit to existing milestones, preserving stable IDs,
/// task assignments and row order. Omitted rows/columns are retained. Authored
/// name/criteria/evidence text is exact; a blank date explicitly unschedules.
/// This is local draft editing, never evidence of acceptance or completion.
pub fn preview_milestone_table_updates(
  draft : Draft,
  source : String,
  tsv : Bool,
) -> MilestoneTableUpdate raise InputError {
  if source.length() > 1000000 {
    raise Invalid("Milestone table exceeds 1,000,000 text units")
  }
  let rows = task_records(source, if tsv { '\t' } else { ',' })
  if rows.length() < 2 {
    raise Invalid("Provide a header and at least one existing milestone row")
  }
  let headers = rows[0].map(milestone_column)
  for key in ["id", "name", "owner", "date", "criteria", "evidence"] {
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
  if draft.milestones.is_empty() || draft.milestones.length() > 40 {
    raise Invalid("Milestone table editing needs 1–40 existing milestones")
  }
  let originals : Map[String, Milestone] = Map([])
  for milestone in draft.milestones {
    if milestone.id.trim().is_empty() || originals.contains(milestone.id) {
      raise Invalid("Current draft has empty or duplicate milestone IDs")
    }
    originals[milestone.id] = milestone
  }
  let replacements : Map[String, Milestone] = Map([])
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
    guard originals.get(id) is Some(before) else {
      raise Invalid(label + ": unknown milestone ID " + id)
    }
    if replacements.contains(id) {
      raise Invalid(label + ": duplicate milestone ID " + id)
    }
    let name = match values.get("name") {
      None => before.name
      Some(value) => {
        if value.trim().is_empty() {
          raise Invalid(
            label + ": title cannot be blank; omit the column to keep it",
          )
        }
        value
      }
    }
    let owner = match values.get("owner") {
      None => before.owner
      Some(value) if value.trim().is_empty() =>
        raise Invalid(
          label + ": owner cannot be blank; omit the column to keep it",
        )
      Some(value) => {
        let owner = task_assignment(
          value.trim().to_owned(),
          owners,
          label + " owner",
        )
        if owners.filter(p => p.0 == owner).length() != 1 {
          raise Invalid(label + ": owner identity is ambiguous: " + owner)
        }
        owner
      }
    }
    let date = match values.get("date") {
      None => before.date
      Some(value) => {
        let date = value.trim().to_owned()
        if !date.is_empty() {
          let _ = rebase_date(date, label + " date")
        }
        date
      }
    }
    replacements[id] = {
      id: before.id,
      name,
      owner,
      date,
      criteria: values.get("criteria").unwrap_or(before.criteria),
      evidence: values.get("evidence").unwrap_or(before.evidence),
    }
  }
  let milestones = draft.milestones.map(m => replacements.get(m.id).unwrap_or(m))
  let changes : Array[MilestoneTableChange] = []
  for i, after in milestones {
    let before = draft.milestones[i]
    let fields : Array[String] = []
    if before.name != after.name {
      fields.push("title")
    }
    if before.owner != after.owner {
      fields.push("owner")
    }
    if before.date != after.date {
      fields.push("date")
    }
    if before.criteria != after.criteria {
      fields.push("criteria")
    }
    if before.evidence != after.evidence {
      fields.push("evidence")
    }
    if !fields.is_empty() {
      changes.push({ before, after, fields, })
    }
  }
  { draft: { ..draft, milestones, }, changes, ignored, }
}

///|
/// Portable editing table, not a plan backup or a record of completed work.
/// Multiline criteria/evidence and quote characters round-trip as quoted CSV.
pub fn export_milestone_table(draft : Draft) -> String {
  let rows = ["id,title,owner,date,criteria,evidence"]
  for milestone in draft.milestones {
    rows.push(
      [
        milestone.id,
        milestone.name,
        milestone.owner,
        milestone.date,
        milestone.criteria,
        milestone.evidence,
      ]
      .map(task_csv_cell)
      .join(","),
    )
  }
  rows.join("\r\n") + "\r\n"
}

///|
#derive(Debug, Eq)
pub(all) struct MilestoneTableImport {
  draft : Draft
  additions : Array[Milestone]
  unchanged : Array[String]
  ignored : Array[String]
}

///|
/// Preview new roadmap rows, preserving supplied IDs for later task imports.
/// Existing identical rows are harmless replays; changed existing IDs are
/// rejected and must use the separate update-only editor. Missing optional
/// columns describe blank draft fields, never defaults taken from an old row.
pub fn preview_milestone_table_import(
  draft : Draft,
  source : String,
  tsv : Bool,
) -> MilestoneTableImport raise InputError {
  if source.length() > 1000000 {
    raise Invalid("Milestone table exceeds 1,000,000 text units")
  }
  let rows = task_records(source, if tsv { '\t' } else { ',' })
  if rows.length() < 2 || rows.length() > 41 {
    raise Invalid("Provide a header and 1–40 milestone rows")
  }
  let headers = rows[0].map(milestone_column)
  for key in ["id", "name", "owner"] {
    if !headers.contains(key) {
      raise Invalid("New milestone import requires column: " + key)
    }
  }
  let originals : Map[String, Milestone] = Map([])
  for milestone in draft.milestones {
    if milestone.id.trim().is_empty() ||
      milestone.id != milestone.id.trim().to_owned() ||
      originals.contains(milestone.id) {
      raise Invalid(
        "Current draft has blank, padded or duplicate milestone IDs",
      )
    }
    originals[milestone.id] = milestone
  }
  if draft.milestones.length() > 40 {
    raise Invalid("A plan supports at most 40 milestones")
  }
  // Validate every supplied cell with the existing table parser. Detached blank
  // rows mean omissions stay blank and cannot inherit values from existing IDs.
  let candidates : Array[Milestone] = []
  let mut id_column = 0
  for i, header in headers {
    if header == "id" {
      id_column = i
    }
  }
  for index = 1; index < rows.length(); index = index + 1 {
    let row = rows[index]
    let label = "Record " + (index + 1).to_string()
    if row.length() != headers.length() {
      raise Invalid(label + ": column count differs from header")
    }
    let id = row[id_column].trim().to_owned()
    if id.is_empty() || candidates.any(m => m.id == id) {
      raise Invalid(label + ": blank or duplicate milestone ID " + id)
    }
    candidates.push({
      id,
      name: "",
      owner: "",
      date: "",
      criteria: "",
      evidence: "",
    })
  }
  let parsed = preview_milestone_table_updates(
    { ..draft, milestones: candidates, },
    source,
    tsv,
  )
  let additions : Array[Milestone] = []
  let unchanged : Array[String] = []
  for milestone in parsed.draft.milestones {
    match originals.get(milestone.id) {
      None => additions.push(milestone)
      Some(before) if before == milestone => unchanged.push(milestone.id)
      Some(_) =>
        raise Invalid(
          "Milestone ID " +
          milestone.id +
          " already exists with different fields. Use Edit existing milestones to update it.",
        )
    }
  }
  if draft.milestones.length() + additions.length() > 40 {
    raise Invalid("A plan supports at most 40 milestones")
  }
  {
    draft: { ..draft, milestones: [..draft.milestones, ..additions], },
    additions,
    unchanged,
    ignored: parsed.ignored,
  }
}
