///|
fn is_clause_delimiter(char : Char) -> Bool {
  char == '\n' ||
  char == '。' ||
  char == '！' ||
  char == '？' ||
  char == '；' ||
  char == ';'
}

///|
fn policy_clauses(text : String) -> Array[String] {
  let clauses : Array[String] = []
  let buffer = StringBuilder()
  for char in text {
    if is_clause_delimiter(char) {
      let clause = buffer.to_string().trim().to_owned()
      if !clause.is_empty() && !clauses.contains(clause) {
        clauses.push(clause)
      }
      buffer.reset()
    } else {
      buffer.write_char(char)
    }
  }
  let tail = buffer.to_string().trim().to_owned()
  if !tail.is_empty() && !clauses.contains(tail) {
    clauses.push(tail)
  }
  clauses
}

///|
fn is_open_quote(char : Char) -> Bool {
  char == '“' || char == '「' || char == '『'
}

///|
fn is_close_quote(char : Char) -> Bool {
  char == '”' || char == '」' || char == '』'
}

///|
/// Discover policy-shaped terms without requiring them to exist in the rule
/// catalog first. Chinese title quotes and ASCII double quotes are supported.
pub fn discover_policy_terms(text : String) -> Array[String] {
  let terms : Array[String] = []
  let buffer = StringBuilder()
  let mut reading = false
  let mut ascii_quote = false
  for char in text {
    if is_open_quote(char) && !reading {
      reading = true
      ascii_quote = false
      buffer.reset()
    } else if is_close_quote(char) && reading && !ascii_quote {
      let term = buffer.to_string().trim().to_owned()
      if !term.is_empty() && !terms.contains(term) {
        terms.push(term)
      }
      reading = false
      buffer.reset()
    } else if char == '"' {
      if reading && ascii_quote {
        let term = buffer.to_string().trim().to_owned()
        if !term.is_empty() && !terms.contains(term) {
          terms.push(term)
        }
        reading = false
        ascii_quote = false
        buffer.reset()
      } else if !reading {
        reading = true
        ascii_quote = true
        buffer.reset()
      } else {
        buffer.write_char(char)
      }
    } else if reading {
      buffer.write_char(char)
    }
  }
  terms
}

///|
fn matched_signal(
  document : PolicyDocument,
  rule : PolicySignalRule,
) -> (Int, String)? {
  let mut matched : (Int, String)? = None
  for index, phrase in rule.phrases {
    if document.body.contains(phrase) {
      matched = Some((index, phrase))
    }
  }
  matched
}

///|
fn rule_contains_phrase(
  rules : Array[PolicySignalRule],
  phrase : String,
) -> Bool {
  for rule in rules {
    if rule.phrases.contains(phrase) {
      return true
    }
  }
  false
}

///|
fn push_node(
  nodes : Array[PolicyGraphNode],
  node_id : String,
  kind : PolicyGraphNodeKind,
  label : String,
) -> Unit {
  for node in nodes {
    if node.node_id == node_id {
      return
    }
  }
  nodes.push({ node_id, kind, label })
}

///|
fn push_edge(
  edges : Array[PolicyGraphEdge],
  document : PolicyDocument,
  from_id : String,
  to_id : String,
  relation : String,
  evidence : String,
) -> Unit {
  edges.push({
    from_id,
    to_id,
    relation,
    evidence,
    source_document_id: document.document_id,
  })
}

///|
fn momentum_reason(momentum : SignalMomentum) -> String {
  match momentum {
    New => "该政策信号在本版本首次出现"
    Strengthened => "本版本使用了更强或更具体的政策表述"
    Stable => "该政策信号持续有效，适合进入验证和跟踪队列"
    Weakened =>
      "本版本表述有所弱化，应降低承诺并先核验口径"
  }
}

///|
fn score_opportunity(
  document : PolicyDocument,
  rule : PolicySignalRule,
  momentum : SignalMomentum,
) -> Int {
  let momentum_bonus = match momentum {
    New => 18
    Strengthened => 12
    Stable => 4
    Weakened => -8
  }
  let score = rule.base_score + document.authority_rank * 4 + momentum_bonus
  if score < 0 {
    0
  } else if score > 100 {
    100
  } else {
    score
  }
}

///|
fn lane_validation_action(lane : BusinessLane) -> String {
  match lane {
    B2B =>
      "访谈至少三家目标企业，确认付费问题、采购人和预算周期"
    B2G =>
      "先核验主管部门职责与采购路径，再形成可量化的小范围试点"
    Dual =>
      "分别验证政府场景价值和企业付费价值，避免用同一套销售假设"
  }
}

///|
fn add_clause_changes(
  previous : PolicyDocument?,
  current : PolicyDocument,
  changes : Array[PolicyChange],
) -> Unit {
  guard previous is Some(previous) else { return }
  let before = policy_clauses(previous.body)
  let after = policy_clauses(current.body)
  for clause in after {
    if !before.contains(clause) {
      changes.push({
        kind: ClauseAdded,
        subject: current.title,
        before: None,
        after: Some(clause),
        importance: 45,
        evidence: clause,
      })
    }
  }
  for clause in before {
    if !after.contains(clause) {
      changes.push({
        kind: ClauseRemoved,
        subject: current.title,
        before: Some(clause),
        after: None,
        importance: 45,
        evidence: clause,
      })
    }
  }
}

///|
/// Compare two document versions, build an evidence-linked knowledge graph,
/// and rank B2B/B2G hypotheses. With `previous=None`, the current version is
/// treated as the baseline and active signals receive `New` momentum.
pub fn analyze_policy(
  previous : PolicyDocument?,
  current : PolicyDocument,
  rules : Array[PolicySignalRule],
) -> PolicyAnalysis {
  let changes : Array[PolicyChange] = []
  let nodes : Array[PolicyGraphNode] = []
  let edges : Array[PolicyGraphEdge] = []
  let opportunities : Array[PolicyOpportunity] = []
  add_clause_changes(previous, current, changes)
  let document_node = "document:\{current.document_id}"
  let authority_node = "authority:\{current.issuer}"
  let jurisdiction_node = "jurisdiction:\{current.jurisdiction}"
  push_node(nodes, document_node, Document, current.title)
  push_node(nodes, authority_node, Authority, current.issuer)
  push_node(nodes, jurisdiction_node, Jurisdiction, current.jurisdiction)
  push_edge(
    edges,
    current,
    document_node,
    authority_node,
    "ISSUED_BY",
    current.issuer,
  )
  push_edge(
    edges,
    current,
    document_node,
    jurisdiction_node,
    "APPLIES_TO",
    current.jurisdiction,
  )
  let before_terms = match previous {
    Some(document) => discover_policy_terms(document.body)
    None => []
  }
  let after_terms = discover_policy_terms(current.body)
  for term in after_terms {
    if !before_terms.contains(term) && !rule_contains_phrase(rules, term) {
      changes.push({
        kind: TermIntroduced,
        subject: term,
        before: None,
        after: Some(term),
        importance: 55,
        evidence: term,
      })
      let term_node = "signal:discovered:\{term}"
      push_node(nodes, term_node, Signal, term)
      push_edge(edges, current, document_node, term_node, "INTRODUCES", term)
    }
  }
  for term in before_terms {
    if !after_terms.contains(term) && !rule_contains_phrase(rules, term) {
      changes.push({
        kind: TermRetired,
        subject: term,
        before: Some(term),
        after: None,
        importance: 55,
        evidence: term,
      })
    }
  }
  for rule in rules {
    let before_match = match previous {
      Some(document) => matched_signal(document, rule)
      None => None
    }
    let current_match = matched_signal(current, rule)
    match (before_match, current_match) {
      (_, None) =>
        if before_match is Some((_, phrase)) {
          changes.push({
            kind: TermRetired,
            subject: rule.topic,
            before: Some(phrase),
            after: None,
            importance: 65,
            evidence: phrase,
          })
        }
      (before_match, Some((current_level, current_phrase))) => {
        let momentum = match before_match {
          None => SignalMomentum::New
          Some((before_level, _)) =>
            if current_level > before_level {
              Strengthened
            } else if current_level < before_level {
              Weakened
            } else {
              Stable
            }
        }
        match (before_match, momentum) {
          (None, _) =>
            changes.push({
              kind: TermIntroduced,
              subject: rule.topic,
              before: None,
              after: Some(current_phrase),
              importance: 75,
              evidence: current_phrase,
            })
          (Some((_, before_phrase)), Strengthened) =>
            changes.push({
              kind: SignalStrengthened,
              subject: rule.topic,
              before: Some(before_phrase),
              after: Some(current_phrase),
              importance: 85,
              evidence: current_phrase,
            })
          (Some((_, before_phrase)), Weakened) =>
            changes.push({
              kind: SignalWeakened,
              subject: rule.topic,
              before: Some(before_phrase),
              after: Some(current_phrase),
              importance: 70,
              evidence: current_phrase,
            })
          _ => ()
        }
        let signal_node = "signal:\{rule.rule_id}"
        let opportunity_node = "opportunity:\{rule.rule_id}:\{current.version}"
        let audience_node = "audience:\{rule.audience}"
        push_node(nodes, signal_node, Signal, rule.topic)
        push_node(
          nodes,
          opportunity_node,
          Opportunity,
          "\{rule.topic}: \{rule.proposed_offer}",
        )
        push_node(nodes, audience_node, Audience, rule.audience)
        push_edge(
          edges,
          current,
          document_node,
          signal_node,
          match momentum {
            New => "INTRODUCES"
            Strengthened => "STRENGTHENS"
            Stable => "REINFORCES"
            Weakened => "WEAKENS"
          },
          current_phrase,
        )
        push_edge(
          edges, current, signal_node, opportunity_node, "ENABLES_HYPOTHESIS", current_phrase,
        )
        push_edge(
          edges,
          current,
          opportunity_node,
          audience_node,
          "TARGETS",
          rule.audience,
        )
        opportunities.push({
          opportunity_id: "\{rule.rule_id}:\{current.document_id}:\{current.version}",
          lane: rule.lane,
          topic: rule.topic,
          score: score_opportunity(current, rule, momentum),
          title: "\{rule.topic}: \{rule.proposed_offer}",
          why_now: momentum_reason(momentum),
          audience: rule.audience,
          proposed_offer: rule.proposed_offer,
          recommended_actions: [
            rule.next_action,
            lane_validation_action(rule.lane),
            "保存原文、发布日期和版本证据；涉及合规或采购结论时交由专业人员复核",
          ],
          evidence_phrase: current_phrase,
          source_document_id: current.document_id,
          source_url: current.source_url,
        })
      }
    }
  }
  opportunities.sort_by((left, right) => right.score - left.score)
  {
    current_document_id: current.document_id,
    previous_document_id: previous.map(document => document.document_id),
    current_version: current.version,
    current_source_url: current.source_url,
    changes,
    nodes,
    edges,
    opportunities,
  }
}
