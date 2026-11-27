///|
#derive(Debug, Eq, ToJson)
pub(all) struct CostBucket {
  id : String
  label : String
  task_ids : Array[String]
  known_minor : Int64?
  invalid_tasks : Int32
}

///|
#derive(Debug, Eq, ToJson)
pub(all) struct BudgetBreakdown {
  currency : String
  known_minor : Int64?
  invalid_tasks : Int32
  limit_minor : Int64?
  contingency_minor : Int64?
  remaining_minor : Int64?
  owners : Array[CostBucket]
  milestones : Array[CostBucket]
}

///|
fn cost_sum(tasks : Array[Task]) -> (Int64?, Int32) {
  let mut sum = 0L
  let mut overflow = false
  let mut invalid = 0
  for t in tasks {
    match (Ok(minor(t.cost, "Task cost")) catch { e => Err(e) }) {
      Err(_) => invalid += 1
      Ok(amount) =>
        if amount > 9223372036854775807L - sum {
          overflow = true
        } else {
          sum += amount
        }
    }
  }
  (if overflow { None } else { Some(sum) }, invalid)
}

///|
fn cost_buckets(d : Draft, owner : Bool) -> Array[CostBucket] {
  let ids : Array[String] = []
  for t in d.tasks {
    let id = if owner { t.owner } else { t.milestone }
    if !ids.contains(id) {
      ids.push(id)
    }
  }
  ids.map(id => {
    let names = if owner {
      d.owners.filter(o => o.id == id).map(o => o.name)
    } else {
      d.milestones.filter(m => m.id == id).map(m => m.name)
    }
    let label = if id.is_empty() {
      "Unassigned"
    } else {
      match names {
        [name] => name
        [] => "Missing reference"
        _ => "Ambiguous reference"
      }
    }
    let tasks = d.tasks.filter(t => {
      (if owner { t.owner } else { t.milestone }) == id
    })
    let (known_minor, invalid_tasks) = cost_sum(tasks)
    { id, label, task_ids: tasks.map(t => t.id), known_minor, invalid_tasks, }
  })
}

///|
/// Read-only allocation of authored task costs. Incomplete totals never yield headroom.
pub fn budget_breakdown(d : Draft) -> BudgetBreakdown {
  let (known_minor, invalid_tasks) = cost_sum(d.tasks)
  let limit_minor = (Ok(minor(d.limit, "Budget limit")) catch { e => Err(e) }).to_option()
  let contingency_minor = (Ok(minor(d.contingency, "Contingency")) catch {
    e => Err(e)
  }).to_option()
  let remaining_minor = match (known_minor, limit_minor, contingency_minor) {
    (Some(cost), Some(limit), Some(contingency)) =>
      if invalid_tasks == 0 && contingency <= 9223372036854775807L - cost {
        Some(limit - (cost + contingency))
      } else {
        None
      }
    _ => None
  }
  {
    currency: d.currency,
    known_minor,
    invalid_tasks,
    limit_minor,
    contingency_minor,
    remaining_minor,
    owners: cost_buckets(d, true),
    milestones: cost_buckets(d, false),
  }
}

///|
fn cost_text(value : Int64?) -> String {
  match value {
    Some(n) => n.to_string()
    None => "Unavailable"
  }
}

///|
pub fn budget_report(d : Draft, project_name : String) -> String {
  let b = budget_breakdown(d)
  let out = [
    "Draft budget breakdown / 草稿成本分配",
    "Project: " + project_name,
    "Planning only; not approval, spending, accounting or payment evidence.",
    "Currency (authored): " + d.currency,
    "Amounts below use minor units (100 per entered unit); no FX conversion.",
    "Known task subtotal: " + cost_text(b.known_minor),
    "Invalid or blank task costs: " + b.invalid_tasks.to_string(),
    "Budget limit: " + cost_text(b.limit_minor) + " (authored: " + d.limit + ")",
    "Contingency: " +
    cost_text(b.contingency_minor) +
    " (authored: " +
    d.contingency +
    ")",
    "Remaining after tasks and contingency: " + cost_text(b.remaining_minor),
    "Negative remaining means over budget. Unavailable means incomplete or overflow, never zero.",
    "Owner and milestone views partition the SAME task costs; do not add them together.",
    "Contingency is shown once, not allocated to either view. Zero-task groups are omitted.",
  ]
  for
    (title, buckets) in [
      ("By task owner", b.owners),
      ("By task milestone", b.milestones),
    ] {
    out.push("")
    out.push(title)
    for bucket in buckets {
      out.push(
        bucket.label +
        " [" +
        bucket.id +
        "]: known " +
        cost_text(bucket.known_minor) +
        "; invalid " +
        bucket.invalid_tasks.to_string() +
        "; tasks " +
        bucket.task_ids.join(", "),
      )
    }
    if buckets.is_empty() {
      out.push("No tasks.")
    }
  }
  out.push("")
  out.push("Task source amounts (authored; invalid entries are not zero)")
  for t in d.tasks {
    let amount = (Ok(minor(t.cost, "Cost")) catch { e => Err(e) }).to_option()
    out.push(
      t.name +
      " [" +
      t.id +
      "] | owner [" +
      t.owner +
      "] | milestone [" +
      t.milestone +
      "] | " +
      t.cost +
      " => " +
      cost_text(amount),
    )
  }
  out.join("\n") + "\n"
}
