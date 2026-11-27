///|
#derive(Debug, Eq, ToJson)
pub(all) struct OwnerTableChange {
  before : Owner?
  after : Owner
  fields : Array[String]
}

///|
#derive(Debug, Eq)
pub(all) struct OwnerTableUpdate {
  draft : Draft
  changes : Array[OwnerTableChange]
  ignored : Array[String]
}

///|
fn owner_column(header : String) -> String {
  match header.trim().to_owned().to_lower() {
    "id" | "owner_id" | "owner id" => "id"
    "name" | "display_name" | "display name" => "name"
    "role" | "responsibility" => "role"
    _ => ""
  }
}

///|
/// Preview a local planning roster. Existing stable IDs update supplied fields;
/// new IDs append in input order. Omitted rows and fields remain unchanged.
/// Names are exact text, never identity keys. No task assignment or authority
/// changes, and no rows are deleted. A blank role explicitly clears that text.
pub fn preview_owner_table(
  draft : Draft,
  source : String,
  tsv : Bool,
) -> OwnerTableUpdate raise InputError {
  if source.length() > 1000000 {
    raise Invalid("Owner table exceeds 1,000,000 text units")
  }
  let rows = task_records(source, if tsv { '\t' } else { ',' })
  if rows.length() < 2 || rows.length() > 41 {
    raise Invalid("Provide a header and 1–40 owner rows")
  }
  let headers = rows[0].map(owner_column)
  for key in ["id", "name", "role"] {
    if headers.filter(h => h == key).length() > 1 {
      raise Invalid("Duplicate mapped column: " + key)
    }
  }
  if !headers.contains("id") {
    raise Invalid("Missing column: id")
  }
  if !headers.contains("name") && !headers.contains("role") {
    raise Invalid("Include name or role besides id")
  }
  let ignored : Array[String] = []
  for i, header in headers {
    if header.is_empty() {
      ignored.push(rows[0][i])
    }
  }
  let originals : Map[String, Owner] = Map([])
  for owner in draft.owners {
    if owner.id.trim().is_empty() ||
      owner.id != owner.id.trim().to_owned() ||
      originals.contains(owner.id) {
      raise Invalid("Current draft has blank, padded or duplicate owner IDs")
    }
    originals[owner.id] = owner
  }
  let replacements : Map[String, Owner] = Map([])
  let added : Array[Owner] = []
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
      raise Invalid(label + ": blank or duplicate owner ID " + id)
    }
    let before = originals.get(id)
    if before is None && (!values.contains("name") || !values.contains("role")) {
      raise Invalid(
        label + ": new owner " + id + " requires name and role columns",
      )
    }
    let base : Owner = before.unwrap_or({ id, name: "", role: "", })
    let name = match values.get("name") {
      None => base.name
      Some(value) => {
        if value.trim().is_empty() {
          raise Invalid(
            label + ": name cannot be blank; omit the column to keep it",
          )
        }
        value
      }
    }
    let after : Owner = {
      id,
      name,
      role: values.get("role").unwrap_or(base.role),
    }
    replacements[id] = after
    if before is None {
      added.push(after)
    }
  }
  let owners = [
    ..draft.owners.map(o => replacements.get(o.id).unwrap_or(o)),
    ..added,
  ]
  if owners.length() > 40 {
    raise Invalid("A plan supports at most 40 owners")
  }
  let changes : Array[OwnerTableChange] = []
  for after in owners {
    let before = originals.get(after.id)
    let fields : Array[String] = []
    match before {
      None => fields.push("new owner")
      Some(before) => {
        if before.name != after.name {
          fields.push("name")
        }
        if before.role != after.role {
          fields.push("role")
        }
      }
    }
    if !fields.is_empty() {
      changes.push({ before, after, fields, })
    }
  }
  { draft: { ..draft, owners, }, changes, ignored, }
}

///|
/// Editable owner metadata only. Quoted CSV preserves multiline names/roles.
/// Owner IDs identify plan rows; this does not export account credentials.
pub fn export_owner_table(draft : Draft) -> String {
  let rows = ["id,name,role"]
  for owner in draft.owners {
    rows.push([owner.id, owner.name, owner.role].map(task_csv_cell).join(","))
  }
  rows.join("\r\n") + "\r\n"
}
