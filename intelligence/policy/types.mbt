///|
/// The commercial lane that can act on a policy signal.
#derive(Debug, Eq, ToJson)
pub(all) enum BusinessLane {
  B2B
  B2G
  Dual
}

///|
#derive(Debug, Eq, ToJson)
pub(all) enum PolicyChangeKind {
  ClauseAdded
  ClauseRemoved
  TermIntroduced
  TermRetired
  SignalStrengthened
  SignalWeakened
}

///|
#derive(Debug, Eq, ToJson)
pub(all) enum SignalMomentum {
  New
  Strengthened
  Stable
  Weakened
}

///|
#derive(Debug, Eq, ToJson)
pub(all) enum PolicyGraphNodeKind {
  Document
  Authority
  Jurisdiction
  Signal
  Opportunity
  Audience
}

///|
/// An immutable version of a policy or official guidance document. The source
/// URL is evidence metadata; the analysis engine never treats the document as
/// law merely because it was ingested.
#derive(Debug, Eq, ToJson)
pub(all) struct PolicyDocument {
  document_id : String
  title : String
  issuer : String
  jurisdiction : String
  published_on : String
  version : String
  source_url : String
  authority_rank : Int32
  body : String
}

///|
/// Phrases are ordered from weaker/general wording to stronger/more specific
/// wording. This lets the engine distinguish a genuinely new signal from a
/// change in policy intensity.
#derive(Debug, Eq, ToJson)
pub(all) struct PolicySignalRule {
  rule_id : String
  phrases : Array[String]
  topic : String
  lane : BusinessLane
  base_score : Int32
  audience : String
  proposed_offer : String
  next_action : String
}

///|
#derive(Debug, Eq, ToJson)
pub(all) struct PolicyChange {
  kind : PolicyChangeKind
  subject : String
  before : String?
  after : String?
  importance : Int32
  evidence : String
}

///|
#derive(Debug, Eq, ToJson)
pub(all) struct PolicyGraphNode {
  node_id : String
  kind : PolicyGraphNodeKind
  label : String
}

///|
#derive(Debug, Eq, ToJson)
pub(all) struct PolicyGraphEdge {
  from_id : String
  to_id : String
  relation : String
  evidence : String
  source_document_id : String
}

///|
/// A scored and explainable business hypothesis. It is a lead for validation,
/// not an authorization to bid, sell, spend, or represent government intent.
#derive(Debug, Eq, ToJson)
pub(all) struct PolicyOpportunity {
  opportunity_id : String
  lane : BusinessLane
  topic : String
  score : Int32
  title : String
  why_now : String
  audience : String
  proposed_offer : String
  recommended_actions : Array[String]
  evidence_phrase : String
  source_document_id : String
  source_url : String
}

///|
#derive(Debug, Eq, ToJson)
pub(all) struct PolicyAnalysis {
  current_document_id : String
  previous_document_id : String?
  current_version : String
  current_source_url : String
  changes : Array[PolicyChange]
  nodes : Array[PolicyGraphNode]
  edges : Array[PolicyGraphEdge]
  opportunities : Array[PolicyOpportunity]
}

///|
#derive(Debug, Eq)
pub(all) suberror PolicyIntelligenceError {
  EmptyIdentifier
  InvalidAuthorityRank(Int32)
  InvalidScore(Int32)
  EmptyPhrases
  InvalidState
}

///|
pub fn PolicyDocument::new(
  document_id~ : String,
  title~ : String,
  issuer~ : String,
  jurisdiction~ : String,
  published_on~ : String,
  version~ : String,
  source_url~ : String,
  authority_rank~ : Int32,
  body~ : String,
) -> PolicyDocument raise PolicyIntelligenceError {
  if document_id.trim().is_empty() ||
    title.trim().is_empty() ||
    issuer.trim().is_empty() ||
    jurisdiction.trim().is_empty() ||
    published_on.trim().is_empty() ||
    version.trim().is_empty() ||
    source_url.trim().is_empty() ||
    body.trim().is_empty() {
    raise EmptyIdentifier
  }
  if authority_rank < 1 || authority_rank > 5 {
    raise InvalidAuthorityRank(authority_rank)
  }
  {
    document_id,
    title,
    issuer,
    jurisdiction,
    published_on,
    version,
    source_url,
    authority_rank,
    body,
  }
}

///|
pub fn PolicySignalRule::new(
  rule_id~ : String,
  phrases~ : Array[String],
  topic~ : String,
  lane~ : BusinessLane,
  base_score~ : Int32,
  audience~ : String,
  proposed_offer~ : String,
  next_action~ : String,
) -> PolicySignalRule raise PolicyIntelligenceError {
  if rule_id.trim().is_empty() ||
    topic.trim().is_empty() ||
    audience.trim().is_empty() ||
    proposed_offer.trim().is_empty() ||
    next_action.trim().is_empty() {
    raise EmptyIdentifier
  }
  if phrases.is_empty() {
    raise EmptyPhrases
  }
  for phrase in phrases {
    if phrase.trim().is_empty() {
      raise EmptyIdentifier
    }
  }
  if base_score < 0 || base_score > 100 {
    raise InvalidScore(base_score)
  }
  {
    rule_id,
    phrases,
    topic,
    lane,
    base_score,
    audience,
    proposed_offer,
    next_action,
  }
}

///|
pub fn BusinessLane::label(self : BusinessLane) -> String {
  match self {
    B2B => "B2B"
    B2G => "B2G"
    Dual => "B2B+B2G"
  }
}
