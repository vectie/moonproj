///|
pub(all) struct DependencyPlan {
  waves : Array[Array[String]]
  prerequisites : Array[String]
  downstream : Array[String]
  issues : Array[String]
} derive(Eq, Debug)

///|
// Reachability is bounded by the finite task set, including malformed cycles.
fn dependency_reach(
  tasks : Array[Task],
  focus : String,
  forward : Bool,
) -> Array[String] {
  let seen = [focus]
  let mut changed = true
  while changed {
    changed = false
    for task in tasks {
      if forward {
        if !seen.contains(task.id) &&
          task.dependencies.any(id => seen.contains(id)) {
          seen.push(task.id)
          changed = true
        }
      } else if seen.contains(task.id) {
        for id in task.dependencies {
          if !seen.contains(id) && tasks.any(t => t.id == id) {
            seen.push(id)
            changed = true
          }
        }
      }
    }
  }
  tasks.filter(t => t.id != focus && seen.contains(t.id)).map(t => t.id)
}

///|
/// Explore draft dependencies without changing task order or authored statuses.
/// Waves describe precedence only, not duration or resource availability.
pub fn dependency_plan(draft : Draft, focus : String) -> DependencyPlan {
  let issues : Array[String] = []
  let ids : Array[String] = []
  for task in draft.tasks {
    if task.id.is_empty() || ids.contains(task.id) {
      issues.push("Empty or duplicate task ID: " + task.id)
    }
    ids.push(task.id)
    for dep in task.dependencies {
      if !draft.tasks.any(t => t.id == dep) {
        issues.push(task.id + " references missing prerequisite " + dep)
      }
    }
  }
  let done : Array[String] = []
  let waves : Array[Array[String]] = []
  if issues.is_empty() {
    while done.length() < draft.tasks.length() {
      let ready = draft.tasks
        .filter(t => {
          !done.contains(t.id) && t.dependencies.all(id => done.contains(id))
        })
        .map(t => t.id)
      if ready.is_empty() {
        issues.push(
          "Dependency cycle blocks: " +
          draft.tasks
          .filter(t => !done.contains(t.id))
          .map(t => t.id)
          .join(", "),
        )
        break
      }
      waves.push(ready)
      for id in ready {
        done.push(id)
      }
    }
  }
  {
    waves,
    prerequisites: if ids.contains(focus) {
      dependency_reach(draft.tasks, focus, false)
    } else {
      []
    },
    downstream: if ids.contains(focus) {
      dependency_reach(draft.tasks, focus, true)
    } else {
      []
    },
    issues,
  }
}

///|
/// Stable topological ordering: among currently ready tasks prefer draft order.
pub fn order_dependencies(draft : Draft) -> Draft raise InputError {
  let plan = dependency_plan(draft, "")
  guard plan.issues.is_empty() else { raise Invalid(plan.issues.join("\n")) }
  let tasks : Array[Task] = []
  while tasks.length() < draft.tasks.length() {
    for task in draft.tasks {
      if !tasks.any(t => t.id == task.id) &&
        task.dependencies.all(id => tasks.any(t => t.id == id)) {
        tasks.push(task)
        break
      }
    }
  }
  { ..draft, tasks, }
}

///|
pub fn dependency_report(draft : Draft, focus : String) -> String {
  let plan = dependency_plan(draft, focus)
  let lines = [
    "Dependency planning explorer",
    "Project: " + draft.project_id,
    "Planning only. Waves show precedence, not dates, duration or owner capacity.",
  ]
  for i, wave in plan.waves {
    lines.push("\nWave " + (i + 1).to_string())
    for id in wave {
      for task in draft.tasks {
        if task.id == id {
          lines.push(
            "- " +
            task.id +
            ": " +
            task.name +
            " | owner=" +
            task.owner +
            " | milestone=" +
            task.milestone,
          )
        }
      }
    }
  }
  if !focus.is_empty() {
    lines.push("\nFocus: " + focus)
    lines.push("Prerequisites: " + plan.prerequisites.join(", "))
    lines.push("Downstream impact: " + plan.downstream.join(", "))
  }
  for issue in plan.issues {
    lines.push("Problem: " + issue)
  }
  lines.join("\n") + "\n"
}
