///|
fn main {
  let previous = try! @policy.PolicyDocument::new(
    document_id="changping-guidance",
    title="昌平政策情报演示",
    issuer="演示数据源",
    jurisdiction="北京市昌平区",
    published_on="2026-01-01",
    version="v1",
    source_url="https://example.invalid/policy-v1",
    authority_rank=3,
    body="布局算力中心，完善企业服务。",
  )
  let current = try! @policy.PolicyDocument::new(
    document_id="changping-guidance",
    title="昌平政策情报演示",
    issuer="演示数据源",
    jurisdiction="北京市昌平区",
    published_on="2026-02-01",
    version="v2",
    source_url="https://example.invalid/policy-v2",
    authority_rank=3,
    body=(
      #|统筹布局“3+N算力中心体系”，加快打造“北京市级算力节点”。
      #|擦亮“昌相伴”品牌，拓展“昌慧达”人工智能政策平台供需对接功能。
      #|先进能源产业收入目标达到4500亿元。
    ),
  )
  let analysis = @policy.analyze_policy(
    Some(previous),
    current,
    @policy.changping_development_signal_rules(),
  )
  println(
    "发现 \{analysis.changes.length()} 项变化、\{analysis.nodes.length()} 个图谱节点、\{analysis.opportunities.length()} 条机会假设",
  )
  for opportunity in analysis.opportunities {
    println(
      "[\{opportunity.lane.label()}][\{opportunity.score}] \{opportunity.title}",
    )
    println(
      "  依据：\{opportunity.evidence_phrase}；\{opportunity.why_now}",
    )
    println("  下一步：\{opportunity.recommended_actions[0]}")
  }
}
