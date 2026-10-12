///|
// RFC 5545 TEXT escaping happens before content-line folding. Authored newlines
// stay inside the property; they can never introduce another event or alarm.
fn calendar_text(value : String) -> String raise InputError {
  let normalized = value
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let out = StringBuilder()
  for c in normalized {
    match c {
      '\\' => out.write_string("\\\\")
      ';' => out.write_string("\\;")
      ',' => out.write_string("\\,")
      '\n' => out.write_string("\\n")
      _ => {
        let code = c.to_int()
        if (code < 32 && c != '\t') ||
          code == 127 ||
          (code >= 0xD800 && code <= 0xDFFF) {
          raise Invalid(
            "Calendar text contains an unsupported control or Unicode character",
          )
        }
        out.write_char(c)
      }
    }
  }
  out.to_string()
}

///|
// Fold at 75 UTF-8 octets, counting the continuation space and never splitting
// a Unicode scalar. String.length() would count UTF-16 units instead.
fn calendar_line(out : StringBuilder, value : String) -> Unit {
  let mut count = 0
  for c in value {
    let code = c.to_int()
    let size = if code < 0x80 {
      1
    } else if code < 0x800 {
      2
    } else if code < 0x10000 {
      3
    } else {
      4
    }
    if count + size > 75 {
      out.write_string("\r\n ")
      count = 1
    }
    out.write_char(c)
    count += size
  }
  out.write_string("\r\n")
}

///|
fn calendar_date(value : String, label : String) -> String raise InputError {
  if value.length() != 10 || value[4] != '-' || value[7] != '-' {
    raise Invalid(label + ": enter a target date as YYYY-MM-DD")
  }
  let _ = @time.PlainDate::from_str(value) catch {
    _ => raise Invalid(label + ": invalid target date " + value)
  }
  value.replace_all(old="-", new="")
}

///|
fn calendar_stamp(value : String) -> String raise InputError {
  if value.length() != 20 ||
    value[4] != '-' ||
    value[7] != '-' ||
    value[10] != 'T' ||
    value[13] != ':' ||
    value[16] != ':' ||
    value[19] != 'Z' {
    raise Invalid(
      "Calendar export needs the plan's UTC revision timestamp (YYYY-MM-DDTHH:MM:SSZ)",
    )
  }
  let _ = @time.PlainDateTime::from_str(value[0:19]) catch {
    _ => raise Invalid("Calendar export needs a valid plan revision timestamp")
  }
  value.replace_all(old="-", new="").replace_all(old=":", new="")
}

///|
fn calendar_owner(draft : Draft, id : String) -> String raise InputError {
  let owners = draft.owners.filter(owner => owner.id == id)
  guard owners is [owner] && !owner.name.trim().is_empty() else {
    raise Invalid("Calendar owner must have one named row: " + id)
  }
  owner.name + " [" + owner.id + "]"
}

///|
/// Export the current draft's explicit milestone target dates as non-blocking
/// all-day markers. Tasks have no dates and appear only as milestone context.
/// This pure projection neither validates/accepts the native plan nor changes it.
pub fn export_milestone_calendar(
  draft : Draft,
  project_name : String,
) -> String raise InputError {
  if draft.project_id.trim().is_empty() ||
    draft.key.trim().is_empty() ||
    project_name.trim().is_empty() {
    raise Invalid(
      "Calendar export needs a project identity, name and plan version",
    )
  }
  if draft.milestones.is_empty() ||
    draft.milestones.length() > 40 ||
    draft.tasks.length() > 100 {
    raise Invalid(
      "Calendar export needs 1–40 milestones and at most 100 tasks",
    )
  }
  let stamp = calendar_stamp(draft.prepared_at)
  let seen : Array[String] = []
  for milestone in draft.milestones {
    if milestone.id.trim().is_empty() ||
      milestone.name.trim().is_empty() ||
      seen.contains(milestone.id) {
      raise Invalid(
        "Calendar milestones need unique IDs and names: " + milestone.id,
      )
    }
    seen.push(milestone.id)
  }
  for task in draft.tasks {
    if !seen.contains(task.milestone) {
      raise Invalid(
        "Task " + task.id + ": choose an existing milestone before exporting",
      )
    }
  }
  let out = StringBuilder()
  for
    line in [
      "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//MoonProj//Planning milestones//EN",
      "CALSCALE:GREGORIAN",
    ] {
    calendar_line(out, line)
  }
  // Length-unambiguous hex components retain stable project/milestone identity
  // across edits without relying on randomized hashes or the changing draft key.
  let _ = calendar_text(draft.project_id)
  let project_uid = @hex.encode(@utf8.encode(draft.project_id))
  for milestone in draft.milestones {
    let date = calendar_date(milestone.date, "Milestone " + milestone.id)
    let owner = calendar_owner(draft, milestone.owner)
    let description = StringBuilder()
    description.write_string(
      "Planning target only; not an accepted plan or work authorization.\n" +
      "Tasks have no scheduled dates or durations.\nProject: " +
      project_name +
      " [" +
      draft.project_id +
      "]\nPlan version: " +
      draft.key +
      "\nMilestone: " +
      milestone.name +
      " [" +
      milestone.id +
      "]\nOwner: " +
      owner +
      "\nAcceptance criteria:\n" +
      milestone.criteria +
      "\nRequired evidence:\n" +
      milestone.evidence +
      "\nTasks (context only):\n",
    )
    let tasks = draft.tasks.filter(task => task.milestone == milestone.id)
    if tasks.is_empty() {
      description.write_string("No tasks assigned.\n")
    }
    for task in tasks {
      description.write_string(
        "- " +
        task.name +
        " [" +
        task.id +
        "] | owner: " +
        calendar_owner(draft, task.owner) +
        " | prerequisites: " +
        (if task.dependencies.is_empty() {
          "None"
        } else {
          task.dependencies.join(", ")
        }) +
        "\n",
      )
    }
    let _ = calendar_text(milestone.id)
    let milestone_uid = @hex.encode(@utf8.encode(milestone.id))
    for
      line in [
        "BEGIN:VEVENT",
        "UID:" + project_uid + "-" + milestone_uid + "@moonproj.local",
        "DTSTAMP:" + stamp,
        "DTSTART;VALUE=DATE:" + date,
        "SUMMARY:" +
        calendar_text("[Planning] " + project_name + " - " + milestone.name),
        "DESCRIPTION:" + calendar_text(description.to_string()),
        "TRANSP:TRANSPARENT",
        "END:VEVENT",
      ] {
      calendar_line(out, line)
    }
  }
  calendar_line(out, "END:VCALENDAR")
  out.to_string()
}
