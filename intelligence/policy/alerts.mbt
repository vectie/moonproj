///|
pub(all) enum PolicyAlertSeverity {
  Information
  Attention
  Critical
} derive(Debug, Eq, ToJson)

///|
pub(all) enum PolicyAlertReviewState {
  Unreviewed
  SourceConfirmed
  InterpretationConfirmed
  Dismissed
} derive(Debug, Eq, ToJson)

///|
pub(all) struct PolicyAlert {
  alert_id : String
  severity : PolicyAlertSeverity
  title : String
  summary : String
  change_kind : PolicyChangeKind
  evidence : String
  source_document_id : String
  source_version : String
  source_url : String
  review_state : PolicyAlertReviewState
  reviewed_by : String
  review_evidence : String
} derive(Debug, Eq, ToJson)

///|
fn alert_severity(importance : Int) -> PolicyAlertSeverity {
  if importance >= 85 {
    Critical
  } else if importance >= 65 {
    Attention
  } else {
    Information
  }
}

///|
fn change_summary(change : PolicyChange) -> String {
  match change.kind {
    ClauseAdded => "新增条款：\{change.evidence}"
    ClauseRemoved => "删除条款：\{change.evidence}"
    TermIntroduced => "出现新政策词：\{change.evidence}"
    TermRetired => "政策词退出当前版本：\{change.evidence}"
    SignalStrengthened => "政策表述强化：\{change.evidence}"
    SignalWeakened => "政策表述弱化：\{change.evidence}"
  }
}

///|
pub fn build_policy_alerts(
  analysis : PolicyAnalysis,
  minimum_importance? : Int = 65,
) -> Array[PolicyAlert] {
  let alerts : Array[PolicyAlert] = []
  for index, change in analysis.changes {
    if change.importance >= minimum_importance {
      alerts.push({
        alert_id: "policy:\{analysis.current_document_id}:\{analysis.current_version}:\{index}",
        severity: alert_severity(change.importance),
        title: change.subject,
        summary: change_summary(change),
        change_kind: change.kind,
        evidence: change.evidence,
        source_document_id: analysis.current_document_id,
        source_version: analysis.current_version,
        source_url: analysis.current_source_url,
        review_state: Unreviewed,
        reviewed_by: "",
        review_evidence: "",
      })
    }
  }
  alerts
}

///|
pub fn PolicyAlert::confirm_source(
  self : PolicyAlert,
  reviewer_id~ : String,
  evidence~ : String,
) -> PolicyAlert raise PolicyIntelligenceError {
  if self.review_state != Unreviewed {
    raise InvalidState
  }
  if reviewer_id.trim().is_empty() || evidence.trim().is_empty() {
    raise EmptyIdentifier
  }
  {
    ..self,
    review_state: SourceConfirmed,
    reviewed_by: reviewer_id,
    review_evidence: evidence,
  }
}

///|
pub fn PolicyAlert::confirm_interpretation(
  self : PolicyAlert,
  reviewer_id~ : String,
  evidence~ : String,
) -> PolicyAlert raise PolicyIntelligenceError {
  if self.review_state != SourceConfirmed {
    raise InvalidState
  }
  if reviewer_id.trim().is_empty() || evidence.trim().is_empty() {
    raise EmptyIdentifier
  }
  {
    ..self,
    review_state: InterpretationConfirmed,
    reviewed_by: reviewer_id,
    review_evidence: "\{self.review_evidence}; \{evidence}",
  }
}

///|
pub fn PolicyAlert::dismiss(
  self : PolicyAlert,
  reviewer_id~ : String,
  evidence~ : String,
) -> PolicyAlert raise PolicyIntelligenceError {
  if reviewer_id.trim().is_empty() || evidence.trim().is_empty() {
    raise EmptyIdentifier
  }
  {
    ..self,
    review_state: Dismissed,
    reviewed_by: reviewer_id,
    review_evidence: evidence,
  }
}
