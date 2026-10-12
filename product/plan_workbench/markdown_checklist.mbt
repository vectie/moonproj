///|
pub(all) struct ChecklistTask {
  line : Int
  checked : Bool
  text : String
  context : Array[String]
  task : Task
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ChecklistImport {
  draft : Draft
  entries : Array[ChecklistTask]
  skipped_checked : Int
} derive(Eq, Debug)

///|
fn checklist_space(c : Char) -> Bool {
  c == ' ' || c == '\t'
}

///|
// A deliberately small, line-oriented Markdown subset. Return the list body
// without interpreting inline Markdown, links, HTML or emphasis.
fn checklist_list(chars : Array[Char]) -> String? {
  let mut i = 0
  if chars.get(0) is Some('-' | '*' | '+') {
    i = 1
  } else {
    while chars.get(i) is Some('0'..='9') {
      i += 1
    }
    if i == 0 || !(chars.get(i) is Some('.' | ')')) {
      return None
    }
    i += 1
  }
  if !(chars.get(i) is Some(c) && checklist_space(c)) {
    return None
  }
  while chars.get(i) is Some(c) && checklist_space(c) {
    i += 1
  }
  Some(String::from_array(chars[i:].to_owned()))
}

///|
/// Preview a Markdown checklist as fresh planned rows. The original source is
/// retained verbatim in scope notes; source checkmarks never become task status.
pub fn preview_markdown_checklist(
  draft : Draft,
  source : String,
  owner_id : String,
  milestone_id : String,
  id_prefix : String,
  include_checked : Bool,
) -> ChecklistImport raise InputError {
  if draft.owners.filter(o => o.id == owner_id).length() != 1 {
    raise Invalid("Choose one existing owner ID for the checklist tasks")
  }
  if draft.milestones.filter(m => m.id == milestone_id).length() != 1 {
    raise Invalid("Choose one existing milestone ID for the checklist tasks")
  }
  if id_prefix.trim().is_empty() {
    raise Invalid("Checklist task identity prefix is required")
  }
  let reserved : Map[String, Bool] = Map::new()
  for task in draft.tasks {
    reserved[task.id] = true
    for dep in task.dependencies {
      reserved[dep] = true
    }
  }
  for risk in draft.risks {
    for id in risk.tasks {
      reserved[id] = true
    }
  }
  let entries : Array[ChecklistTask] = []
  let headings : Array[(Int, String)] = []
  let parents : Array[(Int, String)] = []
  let mut fence : Char? = None
  let mut fence_length = 0
  let mut comment = false
  let mut skipped_checked = 0
  let lines = source
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .split("\n")
    .collect()
  for index, raw in lines {
    let raw_chars = raw.to_owned().to_array()
    let raw = if index == 0 && raw_chars.get(0) == Some('\u{FEFF}') {
      String::from_array(raw_chars[1:].to_owned())
    } else {
      raw.to_owned()
    }
    let chars = raw.trim().to_owned().to_array()
    if chars.is_empty() {
      continue
    }
    let first = chars[0]
    if fence is Some(marker) {
      let mut count = 0
      while chars.get(count) == Some(marker) {
        count += 1
      }
      if count >= fence_length && chars[count:].iter().all(checklist_space) {
        fence = None
      }
      continue
    }
    let mut comment_line = comment
    let mut position = 0
    while position < chars.length() {
      if comment && chars[position:] is ['-', '-', '>', ..] {
        comment = false
        position += 3
      } else if !comment && chars[position:] is ['<', '!', '-', '-', ..] {
        comment = true
        comment_line = true
        position += 4
      } else {
        position += 1
      }
    }
    if comment_line {
      continue
    }
    if first == '`' || first == '~' {
      let mut count = 0
      while chars.get(count) == Some(first) {
        count += 1
      }
      if count >= 3 {
        fence = Some(first)
        fence_length = count
        continue
      }
    }
    if first == '#' {
      let mut count = 0
      while chars.get(count) == Some('#') {
        count += 1
      }
      if count <= 6 && chars.get(count) is Some(c) && checklist_space(c) {
        while headings.last() is Some((depth, _)) && depth >= count {
          ignore(headings.pop())
        }
        let title = String::from_array(chars[count:].to_owned())
          .trim()
          .to_owned()
        if !title.is_empty() {
          headings.push((count, title))
        }
        parents.clear()
        continue
      }
    }
    guard checklist_list(chars) is Some(body) else {
      // Unindented prose/quotes end the list. Their text stays in source notes.
      if raw.to_array().get(0) is Some(c) && !checklist_space(c) {
        parents.clear()
      }
      continue
    }
    let mut indent = 0
    for c in raw {
      if c == ' ' {
        indent += 1
      } else if c == '\t' {
        indent += 4 - indent % 4
      } else {
        break
      }
    }
    while parents.last() is Some((depth, _)) && depth >= indent {
      ignore(parents.pop())
    }
    let body_chars = body.to_array()
    let checkbox = body_chars.length() >= 3 &&
      body_chars[0] == '[' &&
      (body_chars[1] == ' ' || body_chars[1] == 'x' || body_chars[1] == 'X') &&
      body_chars[2] == ']' &&
      (body_chars.length() == 3 || checklist_space(body_chars[3]))
    if !checkbox {
      parents.push((indent, body))
      continue
    }
    let text = String::from_array(body_chars[3:].to_owned()).trim().to_owned()
    let line = index + 1
    if text.is_empty() {
      raise Invalid("Checklist line " + line.to_string() + " has no task text")
    }
    let context = [..headings.map(p => p.1), ..parents.map(p => p.1)]
    parents.push((indent, text))
    let checked = body_chars[1] != ' '
    if checked && !include_checked {
      skipped_checked += 1
      continue
    }
    let id = id_prefix + "-line-" + line.to_string()
    if reserved.contains(id) {
      raise Invalid("Checklist identity already used or referenced: " + id)
    }
    entries.push({
      line,
      checked,
      text,
      context,
      task: {
        id,
        name: [..context, text].join(" / "),
        owner: owner_id,
        milestone: milestone_id,
        cost: "0",
        dependencies: [],
      },
    })
  }
  if fence is Some(_) {
    raise Invalid(
      "Close the Markdown code fence before importing the checklist",
    )
  }
  if comment {
    raise Invalid(
      "Close the Markdown HTML comment before importing the checklist",
    )
  }
  if entries.is_empty() {
    raise Invalid(
      if skipped_checked > 0 {
        "No unchecked tasks. Choose include checked items to plan them again."
      } else {
        "No checkbox tasks found. Use - [ ] Task text outside fenced code and quotes."
      },
    )
  }
  let mapping = entries
    .map(e => {
      "Line " +
      e.line.to_string() +
      " → " +
      e.task.id +
      (if e.checked {
        " (source checked; imported as planned)"
      } else {
        " (source unchecked)"
      })
    })
    .join("\n")
  let notes = draft.notes +
    "\n\nMarkdown checklist import (local planning)\n" +
    mapping +
    "\nSkipped checked items: " +
    skipped_checked.to_string() +
    "\nOriginal Markdown (verbatim):\n" +
    source
  {
    draft: {
      ..draft,
      notes,
      tasks: [..draft.tasks, ..entries.map(e => e.task)],
    },
    entries,
    skipped_checked,
  }
}
