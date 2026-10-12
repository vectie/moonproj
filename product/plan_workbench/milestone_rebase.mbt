///|
pub(all) struct MilestoneRebase {
  offset_days : Int64
  draft : Draft
} derive(Debug, Eq)

///|
fn rebase_date(
  value : String,
  label : String,
) -> @time.PlainDate raise InputError {
  if value.length() != 10 || value[4] != '-' || value[7] != '-' {
    raise Invalid(
      label + ": use a date from 0001-01-01 to 9999-12-31 (YYYY-MM-DD)",
    )
  }
  let date = @time.PlainDate::from_str(value) catch {
    _ => raise Invalid(label + ": invalid date " + value)
  }
  if date.year() < 1 || date.year() > 9999 || date.to_string() != value {
    raise Invalid(
      label + ": use a date from 0001-01-01 to 9999-12-31 (YYYY-MM-DD)",
    )
  }
  date
}

///|
/// Move every dated milestone by the calendar-day distance from one anchor to
/// its new date. Blank date strings and every non-date field are preserved.
/// The input is never mutated, and all dates must fit before any result returns.
pub fn rebase_milestones(
  draft : Draft,
  anchor : String,
  new_date : String,
) -> MilestoneRebase raise InputError {
  if draft.milestones.is_empty() || draft.milestones.length() > 40 {
    raise Invalid("Rescheduling needs 1–40 milestones")
  }
  let seen : Array[String] = []
  for milestone in draft.milestones {
    if milestone.id.trim().is_empty() || seen.contains(milestone.id) {
      raise Invalid("Rescheduling needs unique milestone IDs: " + milestone.id)
    }
    seen.push(milestone.id)
  }
  guard draft.milestones.filter(m => m.id == anchor) is [chosen] else {
    raise Invalid("Choose an existing dated milestone as the anchor")
  }
  let before = rebase_date(chosen.date, "Anchor " + anchor)
  let after = rebase_date(new_date, "New anchor date")
  let offset_days = after.to_unix_day() - before.to_unix_day()
  let milestones : Array[Milestone] = []
  for milestone in draft.milestones {
    if milestone.date.trim().is_empty() {
      milestones.push(milestone)
      continue
    }
    let original = rebase_date(milestone.date, "Milestone " + milestone.id)
    let shifted = original.add_days(offset_days) catch {
      _ =>
        raise Invalid(
          "Milestone " + milestone.id + ": shifted date is out of range",
        )
    }
    if shifted.year() < 1 || shifted.year() > 9999 {
      raise Invalid(
        "Milestone " + milestone.id + ": shifted date is outside 0001–9999",
      )
    }
    milestones.push({ ..milestone, date: shifted.to_string(), })
  }
  { offset_days, draft: { ..draft, milestones, }, }
}
