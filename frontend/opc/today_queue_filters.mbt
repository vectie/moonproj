///|
// View-local observations only. Owner keys are tagged so even an ID named
// "unassigned" cannot collide with the empty-owner choice.
#derive(Debug, Eq)
struct TodayFilters {
  owner : String
  due : String
  blocker : String
  title : String
}

///|
fn today_filters_initial() -> TodayFilters {
  { owner: "", due: "", blocker: "", title: "", }
}

///|
fn today_observed_owners(state : TodayState) -> Array[(String, String)] {
  let owners : Map[String, String] = Map([])
  for task in today_portfolio_queue(state) {
    if !task.owner_id.is_empty() {
      owners["id:" + task.owner_id] = task.owner_name + " · " + task.owner_id
    }
  }
  let choices = owners.to_array()
  choices.sort_by((a, b) => a.0.lexical_compare(b.0))
  choices
}

///|
fn today_filters_change(
  state : TodayState,
  field : String,
  value : String,
) -> TodayFilters {
  let filters = state.filters
  match field {
    "clear" => today_filters_initial()
    "owner" if value == "" ||
      value == "unassigned" ||
      today_observed_owners(state).any(owner => owner.0 == value) =>
      { ..filters, owner: value, }
    "due" if ["", "attention", "overdue", "today", "future", "unknown"].contains(
        value,
      ) => { ..filters, due: value, }
    "blocker" if ["", "blocked", "unblocked"].contains(value) =>
      { ..filters, blocker: value, }
    "title" => { ..filters, title: value, }
    _ => filters
  }
}

///|
fn today_filtered_queue(state : TodayState) -> Array[TodayTask] {
  let f = state.filters
  let query = f.title.trim().to_owned().to_lower()
  today_portfolio_queue(state).filter(task => {
    let day = today_portfolio_day(state, task.project_id)
    let known = today_date_valid(task.due) && today_date_valid(day)
    let blocked = !today_blocker(task).is_empty() || task.status == "blocked"
    (
      f.owner == "" ||
      (f.owner == "unassigned" && task.owner_id.is_empty()) ||
      (!task.owner_id.is_empty() && f.owner == "id:" + task.owner_id)
    ) &&
    (match f.due {
      "attention" => !today_attention(task, day).is_empty()
      "overdue" => (known && task.due < day) || task.status == "overdue"
      "today" => known && task.due == day
      "future" => known && task.due > day
      "unknown" => !known
      _ => true
    }) &&
    (
      f.blocker == "" ||
      (f.blocker == "blocked" && blocked) ||
      (f.blocker == "unblocked" && !blocked)
    ) &&
    task.title.to_lower().contains(query)
  })
}
