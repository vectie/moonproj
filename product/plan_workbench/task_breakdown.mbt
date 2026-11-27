///|
#derive(Debug, Eq, ToJson)
pub(all) struct TaskStep {
  id : String
  name : String
  cost : String
}

///|
/// Replace one draft task, in place, with a sequential breakdown. New steps
/// inherit its owner and milestone. The first inherits its prerequisites, later
/// steps depend on the previous step, followers wait for the final step, and
/// risks mentioning the original cover every step. Exact minor-unit cost is
/// conserved. This is local authoring, not work execution or plan validation.
pub fn break_down_task(
  draft : Draft,
  task_id : String,
  steps : Array[TaskStep],
) -> Draft raise InputError {
  if steps.length() < 2 || steps.length() > 10 {
    raise Invalid("A breakdown needs 2 to 10 sequential steps")
  }
  if draft.tasks.length() - 1 + steps.length() > 100 {
    raise Invalid("The resulting plan cannot exceed 100 tasks")
  }
  guard draft.tasks.filter(t => t.id == task_id) is [original] else {
    raise Invalid("Choose one existing task to break down")
  }
  let task_ids : Array[String] = []
  let reserved : Array[String] = []
  for task in draft.tasks {
    if task.id.trim().is_empty() || task_ids.contains(task.id) {
      raise Invalid("Existing task IDs must be nonempty and unique")
    }
    task_ids.push(task.id)
    reserved.push(task.id)
    for id in task.dependencies {
      reserved.push(id)
    }
  }
  for risk in draft.risks {
    for id in risk.tasks {
      reserved.push(id)
    }
  }
  if original.dependencies.contains(task_id) {
    raise Invalid("Remove the task's self-dependency before breaking it down")
  }
  let ids : Array[String] = []
  let mut total = 0L
  for step in steps {
    if step.id.trim().is_empty() ||
      reserved.contains(step.id) ||
      ids.contains(step.id) {
      raise Invalid("Step IDs must be fresh, distinct and nonempty: " + step.id)
    }
    if step.name.trim().is_empty() {
      raise Invalid("Enter a name for every step")
    }
    ids.push(step.id)
    // minor() bounds each amount to at most 17 digits; at most ten are added.
    total += minor(step.cost, "Step " + step.name + " cost")
  }
  if total != minor(original.cost, "Original task cost") {
    raise Invalid("Step costs must add up exactly to the original task cost")
  }
  let final_id = ids[ids.length() - 1]
  let tasks : Array[Task] = []
  for task in draft.tasks {
    if task.id == task_id {
      for i, step in steps {
        tasks.push({
          ..original,
          id: step.id,
          name: step.name,
          cost: step.cost,
          dependencies: if i == 0 {
            original.dependencies.copy()
          } else {
            [ids[i - 1]]
          },
        })
      }
    } else {
      tasks.push({
        ..task,
        dependencies: task.dependencies.map(id => {
          if id == task_id {
            final_id
          } else {
            id
          }
        }),
      })
    }
  }
  {
    ..draft,
    tasks,
    risks: draft.risks.map(risk => {
      let tasks : Array[String] = []
      for id in risk.tasks {
        if id == task_id {
          for step_id in ids {
            tasks.push(step_id)
          }
        } else {
          tasks.push(id)
        }
      }
      { ..risk, tasks, }
    }),
  }
}
