///|
pub(all) struct PlanTextChange {
  kind : String
  id : String
  field : String
  before : String
  after : String
  occurrences : Int
} derive(Debug, Eq, ToJson)

///|
pub(all) struct PlanTextReplacement {
  draft : Draft
  changes : Array[PlanTextChange]
  occurrences : Int
} derive(Debug, Eq)

///|
fn replace_plan_field(
  value : String,
  kind : String,
  id : String,
  field : String,
  scope : String,
  query : String,
  replacement : String,
  remaining : Array[Int],
  changes : Array[PlanTextChange],
) -> String raise InputError {
  if (scope != "all" && scope != kind) ||
    !value.contains(query) ||
    query == replacement {
    return value
  }
  let parts = value.split(query).map(p => p.to_owned()).collect()
  let count = parts.length() - 1
  let size = value.length() + count * (replacement.length() - query.length())
  if size > remaining[0] {
    raise Invalid(
      "Replacement result is too large; narrow the scope or replacement text.",
    )
  }
  remaining[0] -= size
  let after = parts.join(replacement)
  if after.trim().is_empty() && !value.trim().is_empty() {
    raise Invalid(
      kind + " " + id + " / " + field + ": replacement would empty this field.",
    )
  }
  changes.push({ kind, id, field, before: value, after, occurrences: count, })
  after
}

///|
/// Preview case-sensitive, non-overlapping literal replacement in authored plan
/// prose. Scope is all/notes/tasks/milestones/risks. Stable references, owners,
/// dates, amounts, plan identity and the input draft are never changed here.
pub fn preview_plan_text_replacement(
  draft : Draft,
  query : String,
  replacement : String,
  scope : String,
) -> PlanTextReplacement raise InputError {
  if query.is_empty() || query.length() > 2000 || replacement.length() > 2000 {
    raise Invalid(
      "Find text must contain 1–2000 text units; replacement allows up to 2000.",
    )
  }
  if !["all", "notes", "tasks", "milestones", "risks"].contains(scope) {
    raise Invalid("Choose a supported text replacement scope.")
  }
  if draft.tasks.length() > 100 ||
    draft.milestones.length() > 40 ||
    draft.risks.length() > 100 ||
    draft.owners.length() > 40 ||
    ToJson::to_json(draft).stringify().length() > 1000000 {
    raise Invalid(
      "Plan is too large for text replacement (100 tasks, 40 milestones, 100 risks, 40 owners, 1000000 text units).",
    )
  }
  let changes : Array[PlanTextChange] = []
  let remaining = [1000000]
  let replace = fn(value, kind, id, field) raise InputError {
    replace_plan_field(
      value, kind, id, field, scope, query, replacement, remaining, changes,
    )
  }
  let after : Draft = {
    ..draft,
    notes: replace(draft.notes, "notes", draft.project_id, "notes"),
    tasks: draft.tasks.map(t => {
      ..t,
      name: replace(t.name, "tasks", t.id, "name"),
    }),
    milestones: draft.milestones.map(m => {
      ..m,
      name: replace(m.name, "milestones", m.id, "name"),
      criteria: replace(m.criteria, "milestones", m.id, "criteria"),
      evidence: replace(m.evidence, "milestones", m.id, "evidence"),
    }),
    risks: draft.risks.map(r => {
      ..r,
      summary: replace(r.summary, "risks", r.id, "summary"),
      mitigation: replace(r.mitigation, "risks", r.id, "mitigation"),
    }),
  }
  if ToJson::to_json(after).stringify().length() > 1000000 {
    raise Invalid(
      "Replacement result is too large; narrow the scope or replacement text.",
    )
  }
  {
    draft: after,
    changes,
    occurrences: changes.fold(init=0, (sum, c) => sum + c.occurrences),
  }
}
