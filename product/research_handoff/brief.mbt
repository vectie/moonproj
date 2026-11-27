///|
/// Retained MoonFind content only. Unknown JSON fields are never persisted.
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Paper {
  paper_id : String
  versioned_id : String
  title : String
  abstract_text : String
  abs_url : String
  pdf_url : String
  source_digest : String
  published_at : String?
  updated_at : String?
  retrieved_at : Int64?
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Claim {
  claim_id : String
  statement : String
  paper_ids : Array[String]
  evidence_location : String
  confidence : String
  counterevidence : String
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Summary {
  paper_id : String
  one_sentence : String
  problem : String
  method : String
  evidence : String
  limitations : Array[String]
  claims : Array[Claim]
  open_questions : Array[String]
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Evidence {
  run_id : String
  question : String
  papers : Array[Paper]
  summaries : Array[Summary]
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct OptionEntry {
  id : String
  name : String
  assessments : Array[String]
  source_id : String
  claim_id : String
  contradiction : String
  unknowns : String
  cost_of_error : String
  experiment : String
  retained_source : Paper?
  retained_claim : Claim?
  evidence_review_note : String?
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Worksheet {
  contract_id : String
  revision : Int32
  next_option : Int32
  evidence : Evidence
  question : String
  audience : String
  commitment_ref : String
  criteria : Array[String]
  options : Array[OptionEntry]
  chosen_option_id : String
  reasoning : String
  next_action : String
  history : Array[Archive]?
}

///|
/// Earlier user worksheet only; its evidence is never current evidence.
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Archive {
  revision : Int32
  next_option : Int32
  evidence : Evidence
  question : String
  audience : String
  commitment_ref : String
  criteria : Array[String]
  options : Array[OptionEntry]
  chosen_option_id : String
  reasoning : String
  next_action : String
}

///|
#derive(Debug, Eq, ToJson, FromJson)
pub(all) struct Brief {
  contract_id : String
  boundary : String
  evidence_status : String
  company_decision_recorded : Bool
  worksheet : Worksheet
}

///|
/// Decode a versioned decision export, never an arbitrary worksheet or command.
/// Unknown metadata is discarded by typed decoding and cannot grant authority.
pub fn decode(text : String) -> Result[Brief, String] {
  if text.length() > 2000000 {
    return Err("Decision brief exceeds the 2-million-character limit.")
  }
  let value : Brief = @json.from_json(@json.parse(text)) catch {
    _ => return Err("Decision brief is not readable versioned JSON.")
  }
  let sheet = value.worksheet
  if value.contract_id != "moonfind.decision-brief.v1" ||
    sheet.contract_id != "moonfind.choice-worksheet.v1" ||
    value.company_decision_recorded ||
    sheet.revision < 1 ||
    sheet.evidence.run_id.is_blank() ||
    sheet.options.length() < 2 ||
    sheet.options.length() > 4 ||
    sheet.criteria.is_empty() ||
    sheet.criteria.length() > 6 ||
    sheet.next_option < 3 ||
    sheet.next_option > 1000000 {
    return Err(
      "Unsupported decision version, run, authority claim or worksheet shape.",
    )
  }
  if ![
      "Matches the currently loaded research projection", "Historical or unavailable current context: review retained citations before using this brief",
    ].contains(value.evidence_status) {
    return Err("Unknown export-time source status. Export again from MoonFind.")
  }
  let papers : Array[String] = []
  for paper in sheet.evidence.papers {
    if paper.paper_id.is_blank() || papers.contains(paper.paper_id) {
      return Err("Retained source identities are missing or duplicated.")
    }
    papers.push(paper.paper_id)
  }
  let claims : Map[String, Claim] = Map([])
  for summary in sheet.evidence.summaries {
    if !papers.contains(summary.paper_id) {
      return Err("A research summary points to a missing retained source.")
    }
    for claim in summary.claims {
      if claim.claim_id.is_blank() ||
        !claim.paper_ids.all(id => papers.contains(id)) {
        return Err(
          "A retained claim has an invalid identity or missing source.",
        )
      }
      if claims.get(claim.claim_id) is Some(old) && old != claim {
        return Err("Conflicting retained claims reuse the same identity.")
      }
      claims[claim.claim_id] = claim
    }
  }
  let ids : Array[String] = []
  for option in sheet.options {
    if option.id.is_blank() ||
      ids.contains(option.id) ||
      option.assessments.length() != sheet.criteria.length() {
      return Err("Option identities or criterion assessments are inconsistent.")
    }
    if (!option.source_id.is_empty() && !papers.contains(option.source_id)) ||
      (!option.claim_id.is_empty() && !claims.contains(option.claim_id)) {
      return Err("An option points to a missing retained source or claim.")
    }
    ids.push(option.id)
  }
  if !sheet.chosen_option_id.is_empty() && !ids.contains(sheet.chosen_option_id) {
    return Err("The chosen option is not retained in this brief.")
  }
  let history = sheet.history.unwrap_or([])
  if history.length() > 20 {
    return Err("Research history exceeds the 20-version retention limit.")
  }
  let mut previous = 0
  for archive in history {
    if archive.revision <= previous ||
      archive.revision >= sheet.revision ||
      archive.evidence.run_id != sheet.evidence.run_id {
      return Err(
        "Historical worksheets must be earlier unique ordered revisions of this run.",
      )
    }
    previous = archive.revision
    let problem = history_issue(archive)
    if problem != "" {
      return Err(problem)
    }
  }
  Ok(value)
}

///|
fn history_issue(archive : Archive) -> String {
  if archive.next_option < 3 ||
    archive.next_option > 1000000 ||
    archive.options.length() < 2 ||
    archive.options.length() > 4 ||
    archive.criteria.is_empty() ||
    archive.criteria.length() > 6 {
    return "A historical worksheet has an invalid bounded shape."
  }
  let ids : Array[String] = []
  for option in archive.options {
    if option.id.is_blank() ||
      ids.contains(option.id) ||
      option.assessments.length() != archive.criteria.length() {
      return "Historical option identities or assessments are inconsistent."
    }
    ids.push(option.id)
  }
  if archive.chosen_option_id != "" && !ids.contains(archive.chosen_option_id) {
    return "A historical choice points to a missing option."
  }
  // Historical unresolved source/claim IDs are deliberately preserved as text.
  // They are never added to the active evidence register or resolved by new IDs.
  ""
}

///|
pub fn Brief::chosen(self : Brief) -> OptionEntry? {
  self.worksheet.options
  .filter(option => option.id == self.worksheet.chosen_option_id)
  .get(0)
}

///|
/// Missing choice and next action remain inspectable but cannot seed work.
pub fn Brief::preparation_blocker(self : Brief) -> String {
  guard self.chosen() is Some(option) else {
    return "No chosen option. Record a direction in MoonFind and export again."
  }
  if self.worksheet.question.is_blank() ||
    option.name.is_blank() ||
    self.worksheet.next_action.is_blank() {
    "A decision question, named chosen option and next action are required to prepare work."
  } else {
    ""
  }
}
