///|
fn policy_document(version : String, body : String) -> PolicyDocument {
  PolicyDocument::new(
    document_id="changping-plan",
    title="昌平发展规划发布材料",
    issuer="北京市昌平区人民政府",
    jurisdiction="北京市昌平区",
    published_on="2026-01-20",
    version~,
    source_url="https://example.invalid/changping-plan",
    authority_rank=4,
    body~,
  ) catch {
    _ => abort("test document must be valid")
  }
}

///|
test "policy engine detects stronger wording and builds explainable opportunities" {
  let previous = policy_document(
    "v1", "昌平将布局算力中心，完善企业服务。持续建设回天大脑。",
  )
  let current = policy_document(
    "v2", "统筹布局“3+N算力中心体系”，建设“全市超级算力节点”。擦亮“昌相伴”品牌。建设好“千帆音乐公园”。",
  )
  let analysis = analyze_policy(
    Some(previous),
    current,
    changping_development_signal_rules(),
  )
  assert_true(
    analysis.changes.any(change => {
      change.kind == SignalStrengthened &&
      change.subject == "市级算力节点"
    }),
  )
  assert_true(
    analysis.changes.any(change => {
      change.kind == SignalStrengthened &&
      change.subject == "昌相伴企业服务"
    }),
  )
  assert_true(
    analysis.changes.any(change => {
      change.kind == TermIntroduced && change.subject == "AIGC产业生态"
    }),
  )
  assert_true(
    analysis.changes.any(change => {
      change.kind == TermRetired && change.subject == "回天大脑迭代"
    }),
  )
  assert_true(analysis.opportunities.length() == 3)
  assert_true(
    analysis.opportunities[0].score >= analysis.opportunities[1].score,
  )
  assert_true(
    analysis.opportunities.any(opportunity => {
      opportunity.lane == Dual &&
      opportunity.evidence_phrase == "全市超级算力节点" &&
      opportunity.recommended_actions.length() == 3
    }),
  )
  assert_true(
    analysis.edges.any(edge => {
      edge.relation == "ENABLES_HYPOTHESIS" &&
      edge.source_document_id == "changping-plan"
    }),
  )
  assert_true(
    analysis.nodes.any(node => node.node_id == "signal:changping.aigc-park"),
  )
}

///|
test "quoted-term discovery works before the vocabulary is configured" {
  let terms = discover_policy_terms(
    "建设“昌慧达”和「未来大学科技园」，并形成\"3+N\"体系。",
  )
  assert_eq(terms, ["昌慧达", "未来大学科技园", "3+N"])
}

///|
test "initial analysis separates B2B and B2G hypotheses" {
  let current = policy_document(
    "v1", "先进能源产业收入目标达到4500亿元，迭代升级“回天大脑”。",
  )
  let analysis = analyze_policy(
    None,
    current,
    changping_development_signal_rules(),
  )
  assert_true(
    analysis.opportunities.any(opportunity => opportunity.lane == B2B),
  )
  assert_true(
    analysis.opportunities.any(opportunity => opportunity.lane == B2G),
  )
  assert_true(
    analysis.opportunities.all(opportunity => {
      opportunity.source_url == "https://example.invalid/changping-plan" &&
      opportunity.score <= 100
    }),
  )
}
