///|
fn consolidation_links(
  links : Array[String],
  selected : Array[String],
  retained : String,
) -> Array[String] {
  let result : Array[String] = []
  for id in links {
    let next = if selected.contains(id) { retained } else { id }
    if !result.contains(next) {
      result.push(next)
    }
  }
  result
}

///|
/// Combine selected tasks without losing their authored cost or graph links.
/// The retained task ID survives. All selected tasks must share an owner and
/// milestone. Internal dependencies collapse; external dependencies and risk
/// links are deduplicated. Stable topological ordering keeps prerequisites
/// before followers. A contraction that would introduce a cycle is rejected.
/// This changes a local draft only; no saved plan or execution is authorized.
pub fn consolidate_tasks(
  draft : Draft,
  selected : Array[String],
  retained : String,
  name : String,
) -> Draft raise InputError {
  if selected.length() < 2 ||
    selected.length() > 100 ||
    draft.tasks.length() > 100 {
    raise Invalid("Select 2 to 100 tasks in a plan of at most 100 tasks")
  }
  let seen : Array[String] = []
  for id in selected {
    if seen.contains(id) || !draft.tasks.any(t => t.id == id) {
      raise Invalid("Select distinct existing task IDs")
    }
    seen.push(id)
  }
  if !selected.contains(retained) || name.trim().is_empty() {
    raise Invalid(
      "Choose a selected task ID to retain and enter a combined task name",
    )
  }
  let issues = dependency_plan(draft, "").issues
  if !issues.is_empty() {
    raise Invalid(
      "Repair existing task dependencies before consolidating: " +
      issues.join("; "),
    )
  }
  let original = draft.tasks.filter(t => t.id == retained)[0]
  let group = draft.tasks.filter(t => selected.contains(t.id))
  if group.any(t => {
      t.owner != original.owner || t.milestone != original.milestone
    }) {
    raise Invalid(
      "Selected tasks must share the same owner and milestone; edit assignments first",
    )
  }
  let mut total = 0L
  let dependencies : Array[String] = []
  for task in group {
    let amount = minor(task.cost, "Task " + task.id + " cost")
    // Keep the combined amount within the same wire/input precision as one task.
    if amount > 99999999999999999L - total {
      raise Invalid("Combined cost exceeds the supported single-task amount")
    }
    total += amount
    for id in task.dependencies {
      if !selected.contains(id) && !dependencies.contains(id) {
        dependencies.push(id)
      }
    }
  }
  let fraction = (total % 100L).to_string()
  let merged = {
    ..original,
    name,
    cost: (total / 100L).to_string() +
    "." +
    (if fraction.length() == 1 { "0" } else { "" }) +
    fraction,
    dependencies,
  }
  let tasks : Array[Task] = []
  let mut inserted = false
  for task in draft.tasks {
    if selected.contains(task.id) {
      if !inserted {
        tasks.push(merged)
        inserted = true
      }
    } else {
      tasks.push({
        ..task,
        dependencies: if task.dependencies.any(id => selected.contains(id)) {
          consolidation_links(task.dependencies, selected, retained)
        } else {
          task.dependencies.copy()
        },
      })
    }
  }
  let result = {
    ..draft,
    tasks,
    risks: draft.risks.map(r => {
      ..r,
      tasks: if r.tasks.any(id => selected.contains(id)) {
        consolidation_links(r.tasks, selected, retained)
      } else {
        r.tasks.copy()
      },
    }),
  }
  let issues = dependency_plan(result, "").issues
  if !issues.is_empty() {
    raise Invalid(
      "Consolidation would create a dependency cycle through an unselected task. Include the intervening task or change the selection.",
    )
  }
  order_dependencies(result)
}
