///|
/// Find tasks in draft order. Empty identity filters mean all; nonempty owner
/// and milestone values match exact IDs, including unresolved references.
/// Text matches task name or ID literally, ignoring ASCII case and surrounding
/// query whitespace. This never changes the draft or includes prerequisites.
pub fn find_tasks(
  draft : Draft,
  query : String,
  owner : String,
  milestone : String,
) -> Array[Task] {
  let query = query.trim().to_owned().to_lower()
  draft.tasks.filter(task => {
    (owner.is_empty() || task.owner == owner) &&
    (milestone.is_empty() || task.milestone == milestone) &&
    (task.name.to_lower().contains(query) || task.id.to_lower().contains(query))
  })
}
