///|
fn charter_json_int(value : Json, key : String, fallback : Int) -> Int {
  match products_field(value, key) {
    Number(n, ..) => n.to_int()
    _ => fallback
  }
}

///|
fn charter_json_string_array(value : Json, key : String) -> Array[String] {
  match products_field(value, key) {
    Array(items) => {
      let out : Array[String] = []
      for item in items {
        match item {
          String(text) => {
            let trimmed = text.trim().to_owned()
            if !trimmed.is_empty() {
              out.push(trimmed)
            }
          }
          _ => ()
        }
      }
      out
    }
    _ => []
  }
}

///|
fn charter_decode_mission(obj : Json) -> CharterMission? {
  let mission = products_field(obj, "mission")
  if !(mission is Object(_)) {
    return None
  }
  let title = products_text(mission, "title").trim().to_owned()
  if title.is_empty() {
    return None
  }
  let focus_ratio = products_text(mission, "focus_ratio").trim().to_owned()
  Some({
    title,
    north_star: products_text(mission, "north_star").trim().to_owned(),
    active_stage_id: products_text(mission, "active_stage_id").trim().to_owned(),
    focus_ratio: if focus_ratio.is_empty() { "80/20" } else { focus_ratio },
  })
}

///|
fn charter_decode_stages(obj : Json) -> Array[CharterStage] {
  let stages : Array[CharterStage] = []
  match products_field(obj, "stages") {
    Array(items) => {
      let mut idx = 1
      for item in items {
        if !(item is Object(_)) {
          continue
        }
        let id = products_text(item, "id").trim().to_owned()
        let title = products_text(item, "title").trim().to_owned()
        if id.is_empty() || title.is_empty() {
          continue
        }
        let status_raw = products_text(item, "status").trim().to_owned()
        let status = if ["achieved", "active", "upcoming"].contains(status_raw) {
          status_raw
        } else {
          "upcoming"
        }
        let weight = charter_json_int(item, "weight_pct", 0)
        let weight_pct = if weight < 0 {
          0
        } else if weight > 100 {
          100
        } else {
          weight
        }
        stages.push({
          id,
          order: charter_json_int(item, "order", idx),
          title,
          status,
          weight_pct,
          outcome: products_text(item, "outcome").trim().to_owned(),
          milestone_task_id: products_text(item, "milestone_task_id")
          .trim()
          .to_owned(),
        })
        idx += 1
      }
    }
    _ => ()
  }
  stages.sort_by((a, b) => {
    if a.order != b.order {
      a.order - b.order
    } else {
      a.id.compare(b.id)
    }
  })
  stages
}

///|
fn charter_decode_roles(obj : Json) -> Array[CharterRole] {
  let roles : Array[CharterRole] = []
  match products_field(obj, "roles") {
    Array(items) =>
      for item in items {
        if !(item is Object(_)) {
          continue
        }
        let id = products_text(item, "id").trim().to_owned()
        let name = products_text(item, "name").trim().to_owned()
        if id.is_empty() || name.is_empty() {
          continue
        }
        let raw_tier = charter_json_int(item, "tier", 2)
        let tier = if raw_tier < 0 {
          0
        } else if raw_tier > 2 {
          2
        } else {
          raw_tier
        }
        let raw_kind = products_text(item, "kind").trim().to_owned()
        let kind = if raw_kind == "human" { "human" } else { "agent" }
        let raw_version = products_text(item, "version").trim().to_owned()
        let raw_status = products_text(item, "status").trim().to_owned()
        let status = if ["active", "evolving", "paused"].contains(raw_status) {
          raw_status
        } else {
          "active"
        }
        roles.push({
          id,
          name,
          tier,
          reports_to: products_text(item, "reports_to").trim().to_owned(),
          kind,
          mission: products_text(item, "mission").trim().to_owned(),
          powers: charter_json_string_array(item, "powers"),
          limits: charter_json_string_array(item, "limits"),
          skill_ref: products_text(item, "skill_ref").trim().to_owned(),
          model: products_text(item, "model").trim().to_owned(),
          version: if raw_version.is_empty() { "v1" } else { raw_version },
          status,
        })
      }
    _ => ()
  }
  roles
}

///|
fn charter_decode_resources(obj : Json) -> Array[CharterResource] {
  let resources : Array[CharterResource] = []
  match products_field(obj, "resources") {
    Array(items) =>
      for item in items {
        if !(item is Object(_)) {
          continue
        }
        let id = products_text(item, "id").trim().to_owned()
        let name = products_text(item, "name").trim().to_owned()
        if id.is_empty() || name.is_empty() {
          continue
        }
        let raw_kind = products_text(item, "kind").trim().to_owned()
        let kind = if ["moonbook", "corpus", "tool", "runtime"].contains(
            raw_kind,
          ) {
          raw_kind
        } else {
          "tool"
        }
        let raw_access = products_text(item, "access").trim().to_owned()
        let access = if ["read_only", "read_write", "execute"].contains(
            raw_access,
          ) {
          raw_access
        } else {
          "read_only"
        }
        resources.push({
          id,
          name,
          kind,
          uri: products_text(item, "uri").trim().to_owned(),
          desk_url: products_text(item, "desk_url").trim().to_owned(),
          access,
          owner_role: products_text(item, "owner_role").trim().to_owned(),
          notes: products_text(item, "notes").trim().to_owned(),
        })
      }
    _ => ()
  }
  resources
}

///|
fn charter_decode_evolution_log(obj : Json) -> Array[CharterEvolution] {
  let entries : Array[CharterEvolution] = []
  match products_field(obj, "evolution_log") {
    Array(items) =>
      for item in items {
        if !(item is Object(_)) {
          continue
        }
        let id = products_text(item, "id").trim().to_owned()
        let change = products_text(item, "change").trim().to_owned()
        if id.is_empty() || change.is_empty() {
          continue
        }
        let raw_target = products_text(item, "target").trim().to_owned()
        let target = if raw_target == "company" { "company" } else { "agent" }
        entries.push({
          id,
          date: products_text(item, "date").trim().to_owned(),
          target,
          target_id: products_text(item, "target_id").trim().to_owned(),
          change,
          evidence: products_text(item, "evidence").trim().to_owned(),
        })
      }
    _ => ()
  }
  entries
}

///|
fn charter_decode_json(obj : Json) -> CompanyCharter? {
  if !(obj is Object(_)) {
    return None
  }
  let mission = match charter_decode_mission(obj) {
    Some(m) => m
    None => return None
  }
  let raw_schema = products_text(obj, "schema").trim().to_owned()
  Some({
    schema: if raw_schema.is_empty() {
      "moonproj.company-charter.v1"
    } else {
      raw_schema
    },
    revision: charter_json_int(obj, "revision", 0),
    updated_by: products_text(obj, "updated_by").trim().to_owned(),
    mission,
    stages: charter_decode_stages(obj),
    roles: charter_decode_roles(obj),
    resources: charter_decode_resources(obj),
    evolution_log: charter_decode_evolution_log(obj),
    critical_task_ids: charter_json_string_array(obj, "critical_task_ids"),
  })
}

///|
fn charter_encode_strings(items : Array[String]) -> Json {
  let out : Array[Json] = []
  for item in items {
    let trimmed = item.trim().to_owned()
    if !trimmed.is_empty() {
      out.push(Json::string(trimmed))
    }
  }
  Json::array(out)
}

///|
fn charter_encode_payload(
  charter : CompanyCharter,
  expected_revision : Int?,
) -> Json {
  let stages : Array[Json] = charter.stages.map(stage => {
    Json::object({
      "id": Json::string(stage.id),
      "order": Json::number(stage.order.to_double()),
      "title": Json::string(stage.title),
      "status": Json::string(stage.status),
      "weight_pct": Json::number(stage.weight_pct.to_double()),
      "outcome": Json::string(stage.outcome),
      "milestone_task_id": Json::string(stage.milestone_task_id),
    })
  })
  let roles : Array[Json] = charter.roles.map(role => {
    Json::object({
      "id": Json::string(role.id),
      "name": Json::string(role.name),
      "tier": Json::number(role.tier.to_double()),
      "kind": Json::string(role.kind),
      "reports_to": Json::string(role.reports_to),
      "mission": Json::string(role.mission),
      "powers": charter_encode_strings(role.powers),
      "limits": charter_encode_strings(role.limits),
      "skill_ref": Json::string(role.skill_ref),
      "model": Json::string(role.model),
      "version": Json::string(
        if role.version.is_empty() { "v1" } else { role.version },
      ),
      "status": Json::string(
        if role.status.is_empty() { "active" } else { role.status },
      ),
    })
  })
  let resources : Array[Json] = charter.resources.map(res => {
    Json::object({
      "id": Json::string(res.id),
      "name": Json::string(res.name),
      "kind": Json::string(res.kind),
      "uri": Json::string(res.uri),
      "desk_url": Json::string(res.desk_url),
      "access": Json::string(res.access),
      "owner_role": Json::string(res.owner_role),
      "notes": Json::string(res.notes),
    })
  })
  let evolution_log : Array[Json] = charter.evolution_log.map(entry => {
    Json::object({
      "id": Json::string(entry.id),
      "date": Json::string(entry.date),
      "target": Json::string(entry.target),
      "target_id": Json::string(entry.target_id),
      "change": Json::string(entry.change),
      "evidence": Json::string(entry.evidence),
    })
  })
  let payload : Map[String, Json] = {
    "mission": Json::object({
      "title": Json::string(charter.mission.title),
      "north_star": Json::string(charter.mission.north_star),
      "active_stage_id": Json::string(charter.mission.active_stage_id),
      "focus_ratio": Json::string(
        if charter.mission.focus_ratio.is_empty() {
          "80/20"
        } else {
          charter.mission.focus_ratio
        },
      ),
    }),
    "stages": Json::array(stages),
    "roles": Json::array(roles),
    "resources": Json::array(resources),
    "evolution_log": Json::array(evolution_log),
    "critical_task_ids": charter_encode_strings(charter.critical_task_ids),
  }
  match expected_revision {
    Some(rev) => payload["expected_revision"] = Json::number(rev.to_double())
    None => ()
  }
  Json::object(payload)
}

///|
fn charter_slug(
  raw : String,
  fallback_prefix : String,
  existing : Array[String],
) -> String {
  let buf = StringBuilder()
  let mut prev_dash = false
  for c in raw.trim().to_lower() {
    let valid = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
    if valid {
      buf.write_char(c)
      prev_dash = false
    } else if (c == '-' || c == '_' || c == ' ') && !prev_dash && buf.to_string().length() > 0 {
      buf.write_char('-')
      prev_dash = true
    }
    if buf.to_string().length() >= 48 {
      break
    }
  }
  let mut base = buf.to_string().trim(chars="-").to_owned()
  if base.is_empty() {
    base = fallback_prefix + "-" + (existing.length() + 1).to_string()
  }
  if !existing.contains(base) {
    return base
  }
  let mut suffix = 2
  while existing.contains(base + "-" + suffix.to_string()) {
    suffix += 1
  }
  base + "-" + suffix.to_string()
}

///|
fn charter_split_items(raw : String) -> Array[String] {
  let items : Array[String] = []
  let current = StringBuilder()
  for c in raw {
    if c == '\n' || c == ',' || c == '，' || c == ';' || c == '；' || c == '、' {
      let text = current.to_string().trim().to_owned()
      if !text.is_empty() {
        items.push(text)
      }
      current.reset()
    } else {
      current.write_char(c)
    }
  }
  let last = current.to_string().trim().to_owned()
  if !last.is_empty() {
    items.push(last)
  }
  items
}

