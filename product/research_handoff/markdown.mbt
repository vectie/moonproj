///|
fn unknown(text : String) -> String {
  if text.is_blank() {
    "Unknown / not recorded"
  } else {
    text
  }
}

///|
/// Portable retained source text, not verified demand or a live freshness check.
pub fn Brief::markdown(self : Brief) -> String {
  let sheet = self.worksheet
  let out = StringBuilder()
  out.write_string("## Retained MoonFind research decision\n\n")
  out.write_string(
    "Imported research is user-authored planning context. No formal task, company decision, customer demand, acceptance or payment is established. Source digests and dates are retained claims, not independently checked here.\n\n",
  )
  out.write_string(
    "Contract: " +
    self.contract_id +
    "\nRun: " +
    sheet.evidence.run_id +
    "\nWorksheet revision: \{sheet.revision}\n\n",
  )
  out.write_string(
    "Export-time source status (not a current check): " +
    self.evidence_status +
    "\n\nOriginal export boundary: " +
    self.boundary +
    "\n\n",
  )
  out.write_string(
    "Question: " +
    unknown(sheet.question) +
    "\n\nOriginal research question: " +
    unknown(sheet.evidence.question) +
    "\n\nAudience: " +
    unknown(sheet.audience) +
    "\n\nUser-supplied commitment reference: " +
    unknown(sheet.commitment_ref) +
    "\n\n",
  )
  out.write_string(
    "Chosen option: " +
    self
    .chosen()
    .map(option => unknown(option.name) + " (" + option.id + ")")
    .unwrap_or("Undecided") +
    "\n\nReasoning: " +
    unknown(sheet.reasoning) +
    "\n\nNext action: " +
    unknown(sheet.next_action) +
    "\n\n",
  )
  for option in sheet.options {
    out.write_string(
      "### Option " + option.id + ": " + unknown(option.name) + "\n\n",
    )
    for index, criterion in sheet.criteria {
      out.write_string(
        "Criterion: " +
        unknown(criterion) +
        "\nAssessment: " +
        unknown(option.assessments.get(index).unwrap_or("")) +
        "\n\n",
      )
    }
    out.write_string(
      "Strongest source ID: " +
      unknown(option.source_id) +
      "\nClaim ID: " +
      unknown(option.claim_id) +
      "\n\nContradictions: " +
      unknown(option.contradiction) +
      "\n\nUnknowns: " +
      unknown(option.unknowns) +
      "\n\nCost of being wrong: " +
      unknown(option.cost_of_error) +
      "\n\nSmallest falsifying experiment: " +
      unknown(option.experiment) +
      "\n\n",
    )
    if option.evidence_review_note is Some(note) {
      out.write_string("Carried evidence review note: " + note + "\n\n")
    }
    if option.retained_source is Some(paper) {
      out.write_string(
        "Historical source receipt (unresolved for this revision, not current evidence):\n\n" +
        ToJson::to_json(paper).stringify(indent=2) +
        "\n\n",
      )
    }
    if option.retained_claim is Some(claim) {
      out.write_string(
        "Historical claim receipt (unresolved for this revision, not current evidence):\n\n" +
        ToJson::to_json(claim).stringify(indent=2) +
        "\n\n",
      )
    }
  }
  out.write_string("### Retained source register\n\n")
  if sheet.evidence.papers.is_empty() {
    out.write_string("No retained sources. Evidence remains unknown.\n\n")
  }
  for paper in sheet.evidence.papers {
    out.write_string(
      "Source: " +
      paper.title +
      "\nID: " +
      paper.paper_id +
      "\nVersion: " +
      paper.versioned_id +
      "\nDigest: " +
      paper.source_digest +
      "\nURL: " +
      paper.abs_url +
      "\nPDF URL: " +
      paper.pdf_url +
      "\nPublished: " +
      paper.published_at.unwrap_or("Unknown") +
      "\nUpdated: " +
      paper.updated_at.unwrap_or("Unknown") +
      "\nRetrieved (epoch milliseconds): " +
      paper.retrieved_at.map(value => value.to_string()).unwrap_or("Unknown") +
      "\n\nRetained abstract/input text: " +
      paper.abstract_text +
      "\n\n",
    )
  }
  out.write_string("### Retained research summaries\n\n")
  for summary in sheet.evidence.summaries {
    out.write_string(
      "Source " +
      summary.paper_id +
      ": " +
      summary.one_sentence +
      "\n\nProblem: " +
      summary.problem +
      "\nMethod: " +
      summary.method +
      "\nEvidence: " +
      summary.evidence +
      "\nLimitations: " +
      summary.limitations.join("; ") +
      "\nOpen questions: " +
      summary.open_questions.join("; ") +
      "\n\n",
    )
    for claim in summary.claims {
      out.write_string(
        "Claim " +
        claim.claim_id +
        ": " +
        claim.statement +
        "\nSource IDs: " +
        claim.paper_ids.join(", ") +
        "\nLocation: " +
        claim.evidence_location +
        "\nReported confidence: " +
        claim.confidence +
        "\nCounterevidence: " +
        unknown(claim.counterevidence) +
        "\n\n",
      )
    }
  }
  if !sheet.history.unwrap_or([]).is_empty() {
    out.write_string(
      "### Historical worksheet versions\n\nThese are earlier user assessments and source receipts. They do not revalidate the current choice or enter the current evidence set.\n\n",
    )
    for archive in sheet.history.unwrap_or([]) {
      out.write_string(
        "#### Historical revision \{archive.revision}\n\nQuestion: " +
        unknown(archive.question) +
        "\nChosen option (historical): " +
        unknown(archive.chosen_option_id) +
        "\nReasoning: " +
        unknown(archive.reasoning) +
        "\nNext action (historical): " +
        unknown(archive.next_action) +
        "\n\nExact retained worksheet content:\n\n" +
        ToJson::to_json(archive).stringify(indent=2) +
        "\n\n",
      )
    }
  }
  out.to_string()
}
