///|
/// A dated planning assessment. It never authorizes execution or records company facts.
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Inventory {
  schema : String
  product_id : String
  as_of : String
  origin : String
  source_scope : String
  current_gap : String
  vision_scope : String
  full_target_estimate : String
  next_milestone : Milestone
  prd_source : String
  prd_sha256 : String
  philosophy : Array[String]
  non_goals : Array[String]
  requirements : Array[Requirement]
  groups : Array[WorkGroup]
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Milestone {
  title : String
  estimate_low_days : Int32?
  estimate_high_days : Int32?
  unit : String
  confidence : String
  scope : String
  linked_group_id : String?
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Requirement {
  id : String
  title : String
  track : String
  priority : String
  statement : String
  acceptance : Array[String]
  dependencies : Array[String]
  historical_status : String
  historical_evidence : Array[String]
  status : String
  reason : String
  evidence : Array[String]
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct EffortItem {
  task : String
  estimate_low_days : Int32
  estimate_high_days : Int32
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct WorkGroup {
  id : String
  title : String
  requirement_ids : Array[String]
  status : String
  next_action : String
  acceptance : Array[String]
  dependencies : Array[String]
  estimate_low_days : Int32?
  estimate_high_days : Int32?
  estimate_scope : String
  effort_breakdown : Array[EffortItem]?
  confidence : String
  assumptions : Array[String]
  evidence : Array[String]
}

///|
#derive(Debug)
pub suberror InventoryError {
  Invalid(String)
}

///|
fn valid_status(value : String) -> Bool {
  ["verified", "partial", "planned", "unverified", "missing"].contains(value)
}

///|
fn nonempty(value : String) -> Bool {
  !value.trim().is_empty()
}

///|
/// Parse only the declared product's versioned work inventory. Counts are derived,
/// never accepted from a supplied percentage or a neighboring product's record.
pub fn parse(
  value : Json,
  product_id : String,
) -> Inventory raise InventoryError {
  guard value is { "next_milestone": Object(milestone_fields), .. } else {
    raise Invalid("missing next milestone")
  }
  for
    key in [
      "title", "estimate_low_days", "estimate_high_days", "unit", "confidence", "scope",
      "linked_group_id",
    ] {
    if !milestone_fields.contains(key) {
      raise Invalid("missing milestone field: " + key)
    }
  }
  let inventory : Inventory = @json.from_json(nullable_inventory_fields(value)) catch {
    error => raise Invalid("invalid inventory fields: \{Repr(error)}")
  }
  if inventory.schema != "moonsuite.product-work-inventory.v1" ||
    inventory.product_id != product_id ||
    inventory.origin != "packaged_prd_assessment" ||
    ![
      inventory.as_of,
      inventory.source_scope,
      inventory.current_gap,
      inventory.vision_scope,
      inventory.full_target_estimate,
      inventory.prd_source,
      inventory.prd_sha256,
    ].all(nonempty) ||
    inventory.requirements.is_empty() ||
    inventory.groups.is_empty() {
    raise Invalid("invalid inventory identity or provenance")
  }
  let milestone = inventory.next_milestone
  if !nonempty(milestone.title) ||
    !nonempty(milestone.scope) ||
    milestone.unit != "engineer-days" ||
    !["low", "medium", "high"].contains(milestone.confidence) {
    raise Invalid("invalid next milestone")
  }
  match (milestone.estimate_low_days, milestone.estimate_high_days) {
    (None, None) => ()
    (Some(low), Some(high)) if low > 0 && high >= low => ()
    _ => raise Invalid("milestone estimate must be a range or unknown")
  }
  let ids : Array[String] = []
  for row in inventory.requirements {
    if !row.id.has_prefix(product_id.to_upper() + "-") ||
      ids.contains(row.id) ||
      !nonempty(row.title) ||
      !nonempty(row.statement) ||
      !["baseline", "roadmap", "quality"].contains(row.track) ||
      !["P0", "P1", "P2", ""].contains(row.priority) ||
      !valid_status(row.status) ||
      !nonempty(row.reason) ||
      row.acceptance.is_empty() ||
      !row.acceptance.all(nonempty) ||
      (row.status == "verified" && row.evidence.is_empty()) {
      raise Invalid("invalid or duplicate requirement: " + row.id)
    }
    ids.push(row.id)
  }
  let group_ids : Array[String] = []
  let assigned : Array[String] = []
  for group in inventory.groups {
    if !nonempty(group.id) ||
      group_ids.contains(group.id) ||
      !nonempty(group.title) ||
      !nonempty(group.next_action) ||
      !nonempty(group.estimate_scope) ||
      !["low", "medium", "high"].contains(group.confidence) ||
      !valid_status(group.status) ||
      group.requirement_ids.is_empty() ||
      group.acceptance.is_empty() ||
      !group.acceptance.all(nonempty) ||
      group.assumptions.is_empty() {
      raise Invalid("invalid work group: " + group.id)
    }
    match (group.estimate_low_days, group.estimate_high_days) {
      (None, None) => ()
      (Some(low), Some(high)) if low > 0 && high >= low => ()
      _ => raise Invalid("estimate must be an ordered range or unknown")
    }
    for id in group.requirement_ids {
      if !ids.contains(id) || assigned.contains(id) {
        raise Invalid("unknown or multiply assigned requirement: " + id)
      }
      assigned.push(id)
    }
    group_ids.push(group.id)
  }
  if assigned.length() != ids.length() {
    raise Invalid("work groups must retain the complete requirement scope")
  }
  if milestone.linked_group_id is Some(id) {
    let group = inventory.groups.filter(group => group.id == id).get(0)
    guard group is Some(group) else {
      raise Invalid("unknown next milestone group")
    }
    if milestone.title != group.title ||
      milestone.estimate_low_days != group.estimate_low_days ||
      milestone.estimate_high_days != group.estimate_high_days {
      raise Invalid(
        "next milestone must preserve its one group's title and estimate",
      )
    }
  }
  inventory
}

///|
// MoonBit derived optional record fields use absence for None, whereas the
// packaged JSON deliberately uses null to express an unestimated range.
// Normalize only those two nullable fields, without mutating the source object.
fn nullable_inventory_fields(value : Json) -> Json {
  guard value is Object(fields) else { return value }
  guard fields.get("groups") is Some(Array(groups)) else { return value }
  let copy = Map([])
  for key, value in fields {
    copy[key] = value
  }
  copy["groups"] = Json::array(groups.map(nullable_effort_fields))
  if fields.get("next_milestone") is Some(milestone) {
    copy["next_milestone"] = nullable_effort_fields(milestone)
  }
  Json::object(copy)
}

///|
fn nullable_effort_fields(value : Json) -> Json {
  guard value is Object(fields) else { return value }
  let copy = Map([])
  for key, value in fields {
    if ["estimate_low_days", "estimate_high_days", "linked_group_id"].contains(
        key,
      ) &&
      value is Null {
      continue
    }
    copy[key] = value
  }
  Json::object(copy)
}

///|
/// Preserve explicit null effort bounds on the catalog wire projection.
pub fn Inventory::projection(self : Inventory) -> Json {
  let value = self.to_json()
  guard value is { "groups": Array(groups), .. } else { return value }
  for group in groups {
    guard group is Object(fields) else { continue }
    for key in ["estimate_low_days", "estimate_high_days"] {
      if !fields.contains(key) {
        fields[key] = Json::null()
      }
    }
  }
  if value is { "next_milestone": Object(fields), .. } {
    for key in ["estimate_low_days", "estimate_high_days", "linked_group_id"] {
      if !fields.contains(key) {
        fields[key] = Json::null()
      }
    }
  }
  value
}

///|
/// Number of assessed requirements in one evidence state, not a completion rate.
pub fn Inventory::count(self : Inventory, status : String) -> Int32 {
  self.requirements.filter(row => row.status == status).length()
}

///|
/// Read a complete portfolio against the catalog's actual ID set. Missing source
/// evidence is represented inside requirements; missing products are not invented.
pub fn parse_portfolio(
  value : Json,
  product_ids : Array[String],
) -> Array[Inventory] raise InventoryError {
  let values = match value {
    { "schema": "moonsuite.work-inventory.v1", "products": Array(values), .. } =>
      values
    _ => raise Invalid("invalid portfolio inventory schema")
  }
  let result : Array[Inventory] = []
  for value in values {
    let id = match value {
      { "product_id": String(id), .. } => id
      _ => raise Invalid("missing inventory product identity")
    }
    if !product_ids.contains(id) || result.any(item => item.product_id == id) {
      raise Invalid("unexpected or duplicate inventory product")
    }
    result.push(
      parse(value, id) catch {
        error => raise Invalid(id + ": \{Repr(error)}")
      },
    )
  }
  if result.length() != product_ids.length() {
    raise Invalid("incomplete inventory product coverage")
  }
  result
}
