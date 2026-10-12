///|
/// A read-only, typed difference. Identity is never inferred from a row label.
pub(all) struct PlanChange {
  kind : String
  id : String
  field : String
  status : String
  before : String
  after : String
  delta : String
} derive(Debug, Eq, ToJson)

///|
pub(all) struct PlanComparison {
  before_header : String
  after_header : String
  changes : Array[PlanChange]
} derive(Debug, Eq, ToJson)

///|
fn comparison_value(value : Json) -> String {
  match value {
    Null => "Unavailable (missing value)"
    String(s) => s
    _ => value.stringify()
  }
}

///|
fn comparison_minor(value : Json) -> Int64? {
  // Native Int64 JSON is a decimal string. Never convert through a Double,
  // a JavaScript number, a draft decimal amount, or a missing-value default.
  guard value is String(s) &&
    !s.is_empty() &&
    s.iter().all(c => c.is_ascii_digit()) else {
    return None
  }
  let amount = @string.parse_int64(s) catch { _ => return None }
  if amount < 0L {
    None
  } else {
    Some(amount)
  }
}

///|
pub fn comparison_delta(
  before : Json,
  after : Json,
  before_currency : String,
  after_currency : String,
) -> String {
  let valid_currency = fn(c : String) {
    c.length() == 3 && c.iter().all(ch => ch >= 'A' && ch <= 'Z')
  }
  if !valid_currency(before_currency) || !valid_currency(after_currency) {
    return "Unavailable: missing or invalid currency"
  }
  if before_currency != after_currency {
    return "Unavailable: currencies differ; no FX conversion"
  }
  match (comparison_minor(before), comparison_minor(after)) {
    (Some(a), Some(b)) => {
      // Both operands are in [0, Int64::MAX], so b-a cannot overflow Int64.
      let delta = b - a
      (if delta > 0L { "+" } else { "" }) +
      delta.to_string() +
      " " +
      before_currency +
      " minor units"
    }
    _ => "Unavailable: missing or invalid non-negative native Int64 amount"
  }
}

///|
fn comparison_add(
  changes : Array[PlanChange],
  kind : String,
  id : String,
  field : String,
  before : String,
  after : String,
  delta? : String = "",
) -> Unit {
  if before != after || delta.has_prefix("Unavailable") {
    changes.push({
      kind,
      id,
      field,
      status: if before == after {
        "unavailable"
      } else {
        "changed"
      },
      before,
      after,
      delta,
    })
  }
}

///|
fn comparison_set(
  changes : Array[PlanChange],
  kind : String,
  id : String,
  field : String,
  before : Array[String],
  after : Array[String],
) -> Unit {
  if !before.all(v => after.contains(v)) || !after.all(v => before.contains(v)) {
    changes.push({
      kind,
      id,
      field,
      status: "changed",
      before: before.join("\n"),
      after: after.join("\n"),
      delta: "",
    })
  }
}

///|
fn comparison_row(
  changes : Array[PlanChange],
  kind : String,
  id : String,
  before : Json?,
  after : Json?,
) -> Unit {
  changes.push({
    kind,
    id,
    field: "Row",
    status: if before is None {
      "added"
    } else {
      "removed"
    },
    before: before.map(v => v.stringify(indent=2)).unwrap_or("Absent"),
    after: after.map(v => v.stringify(indent=2)).unwrap_or("Absent"),
    delta: "",
  })
}

///|
fn comparison_header(saved : Json) -> String {
  let artifact = field(saved, "artifact")
  "Version: " +
  text(saved, "key") +
  "\nProject: " +
  text(saved, "project_id") +
  "\nActor: " +
  text(saved, "actor") +
  "\nRecorded at: " +
  text(artifact, "recorded_at") +
  "\nRequest digest: " +
  text(artifact, "request_digest") +
  "\nArtifact digest: " +
  text(saved, "artifact_sha256") +
  "\nSource provenance: " +
  field(artifact, "source_evidence").stringify(indent=2)
}

///|
fn comparison_cost(saved : Json, id : String) -> Json {
  items(field(saved, "artifact"), "tasks")
  .iter()
  .find_first(t => text(t, "task_id") == id)
  .map(t => field(t, "planned_cost_minor"))
  .unwrap_or(Json::null())
}

///|
/// Compare two exact saved envelopes already verified by the native GET route.
/// Draft decoding provides typed, stable identities and complete authored text;
/// monetary values come exclusively from their saved native artifacts.
pub fn compare_saved(before : Json, after : Json) -> PlanComparison raise {
  let a : Draft = @json.from_json(field(before, "draft"))
  let b : Draft = @json.from_json(field(after, "draft"))
  guard a.project_id == b.project_id &&
    text(before, "actor") == text(after, "actor") else {
    fail("Comparison requires the same actor and project")
  }
  let changes : Array[PlanChange] = []
  comparison_add(changes, "Plan", "", "Scope / source notes", a.notes, b.notes)
  let ab = field(field(before, "artifact"), "budget")
  let bb = field(field(after, "artifact"), "budget")
  let ac = text(ab, "currency")
  let bc = text(bb, "currency")
  comparison_add(changes, "Budget", "", "Currency", ac, bc)
  for
    key in [
      "limit_minor", "planned_total_minor", "contingency_minor", "unallocated_minor",
    ] {
    let av = field(ab, key)
    let bv = field(bb, key)
    // Keep currency-labelled values visible even when a cross-currency amount
    // has identical digits. An invalid amount is never presented as zero.
    comparison_add(
      changes,
      "Budget",
      "",
      key,
      comparison_value(av) + " " + ac,
      comparison_value(bv) + " " + bc,
      delta=comparison_delta(av, bv, ac, bc),
    )
  }
  for o in a.owners {
    match b.owners.iter().find_first(p => p.id == o.id) {
      None => comparison_row(changes, "Owner", o.id, Some(o.to_json()), None)
      Some(p) => {
        comparison_add(changes, "Owner", o.id, "Name", o.name, p.name)
        comparison_add(changes, "Owner", o.id, "Role", o.role, p.role)
      }
    }
  }
  for o in b.owners.filter(p => !a.owners.any(o => o.id == p.id)) {
    comparison_row(changes, "Owner", o.id, None, Some(o.to_json()))
  }
  comparison_add(
    changes,
    "Plan",
    "",
    "Execution order (task IDs)",
    a.tasks.map(t => t.id).join("\n"),
    b.tasks.map(t => t.id).join("\n"),
  )
  for t in a.tasks {
    match b.tasks.iter().find_first(u => u.id == t.id) {
      None => comparison_row(changes, "Task", t.id, Some(t.to_json()), None)
      Some(u) => {
        comparison_add(changes, "Task", t.id, "Name", t.name, u.name)
        comparison_add(changes, "Task", t.id, "Owner ID", t.owner, u.owner)
        comparison_add(
          changes,
          "Task",
          t.id,
          "Milestone ID",
          t.milestone,
          u.milestone,
        )
        comparison_set(
          changes,
          "Task",
          t.id,
          "Dependencies (ID set)",
          t.dependencies,
          u.dependencies,
        )
        let av = comparison_cost(before, t.id)
        let bv = comparison_cost(after, u.id)
        comparison_add(
          changes,
          "Task",
          t.id,
          "Cost (minor units)",
          comparison_value(av) + " " + ac,
          comparison_value(bv) + " " + bc,
          delta=comparison_delta(av, bv, ac, bc),
        )
      }
    }
  }
  for t in b.tasks.filter(u => !a.tasks.any(t => t.id == u.id)) {
    comparison_row(changes, "Task", t.id, None, Some(t.to_json()))
  }
  for m in a.milestones {
    match b.milestones.iter().find_first(n => n.id == m.id) {
      None =>
        comparison_row(changes, "Milestone", m.id, Some(m.to_json()), None)
      Some(n) => {
        comparison_add(changes, "Milestone", m.id, "Name", m.name, n.name)
        comparison_add(changes, "Milestone", m.id, "Owner ID", m.owner, n.owner)
        comparison_add(
          changes,
          "Milestone",
          m.id,
          "Target date",
          m.date,
          n.date,
        )
        comparison_add(
          changes,
          "Milestone",
          m.id,
          "Acceptance criteria",
          m.criteria,
          n.criteria,
        )
        comparison_add(
          changes,
          "Milestone",
          m.id,
          "Required evidence",
          m.evidence,
          n.evidence,
        )
      }
    }
  }
  for m in b.milestones.filter(n => !a.milestones.any(m => m.id == n.id)) {
    comparison_row(changes, "Milestone", m.id, None, Some(m.to_json()))
  }
  for r in a.risks {
    match b.risks.iter().find_first(q => q.id == r.id) {
      None => comparison_row(changes, "Risk", r.id, Some(r.to_json()), None)
      Some(q) => {
        comparison_add(changes, "Risk", r.id, "Summary", r.summary, q.summary)
        comparison_add(
          changes,
          "Risk",
          r.id,
          "Severity",
          r.severity,
          q.severity,
        )
        comparison_add(changes, "Risk", r.id, "Owner ID", r.owner, q.owner)
        comparison_add(
          changes,
          "Risk",
          r.id,
          "Mitigation",
          r.mitigation,
          q.mitigation,
        )
        comparison_set(
          changes,
          "Risk",
          r.id,
          "Related tasks (ID set)",
          r.tasks,
          q.tasks,
        )
      }
    }
  }
  for r in b.risks.filter(q => !a.risks.any(r => r.id == q.id)) {
    comparison_row(changes, "Risk", r.id, None, Some(r.to_json()))
  }
  {
    before_header: comparison_header(before),
    after_header: comparison_header(after),
    changes,
  }
}

///|
pub fn PlanComparison::readable(self : PlanComparison) -> String {
  let out = StringBuilder()
  out.write_string(
    "Saved project plan comparison\nRead only. Both plans remain pending named-human review. No acceptance, spending, accounting, payment, contract or work authorization.\n\nBEFORE\n" +
    self.before_header +
    "\n\nAFTER\n" +
    self.after_header +
    "\n\n",
  )
  if self.changes.is_empty() {
    out.write_string("No substantive changes.\n")
  }
  for change in self.changes {
    out.write_string(
      change.kind +
      " " +
      change.id +
      " · " +
      change.field +
      " · " +
      change.status +
      "\nBefore:\n" +
      change.before +
      "\nAfter:\n" +
      change.after +
      "\n",
    )
    if !change.delta.is_empty() {
      out.write_string("Delta: " + change.delta + "\n")
    }
    out.write_string("\n")
  }
  out.to_string()
}
