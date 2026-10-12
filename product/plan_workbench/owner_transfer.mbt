///|
/// Reassign one owner's complete draft allocation, without changing identities,
/// owner membership, preparer, costs, dependencies or any saved company state.
pub fn transfer_owner(
  draft : Draft,
  source : String,
  destination : String,
) -> Draft raise InputError {
  if source.is_empty() || destination.is_empty() || source == destination {
    raise Invalid("Select two different declared owners")
  }
  for id in [source, destination] {
    if draft.owners.filter(o => o.id == id).length() != 1 {
      raise Invalid("Owner must exist exactly once: " + id)
    }
  }
  {
    ..draft,
    tasks: draft.tasks.map(t => {
      if t.owner == source {
        { ..t, owner: destination, }
      } else {
        t
      }
    }),
    milestones: draft.milestones.map(m => {
      if m.owner == source {
        { ..m, owner: destination, }
      } else {
        m
      }
    }),
    risks: draft.risks.map(r => {
      if r.owner == source {
        { ..r, owner: destination, }
      } else {
        r
      }
    }),
  }
}
