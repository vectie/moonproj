///|
fn adversarial_policy_document(
  version : String,
  body : String,
  authority_rank~ : Int32 = 3,
) -> @policy.PolicyDocument {
  @policy.PolicyDocument::new(
    document_id="adversarial-document",
    title="Adversarial policy fixture",
    issuer="Test authority",
    jurisdiction="Test jurisdiction",
    published_on="2026-08-10",
    version~,
    source_url="https://example.invalid/policy",
    authority_rank~,
    body~,
  ) catch {
    _ => abort("adversarial fixture must be valid")
  }
}

///|
fn adversarial_signal_rule(base_score : Int32) -> @policy.PolicySignalRule {
  @policy.PolicySignalRule::new(
    rule_id="compute-signal",
    phrases=["布局算力中心", "全市超级算力节点"],
    topic="compute",
    lane=Dual,
    base_score~,
    audience="operators",
    proposed_offer="read-only validation",
    next_action="verify source and interview users",
  ) catch {
    _ => abort("adversarial rule must be valid")
  }
}

///|
test "fuzzed quoted-term parser terminates, deduplicates, and ignores incomplete terms" {
  let corpus = [
    "plain text without quotes",
    "“”「」『』\"\"",
    "“unclosed",
    "close only”",
    "“same”“same”「same」\"same\"",
    "“<script>alert(1)</script>”",
    "“'); DROP TABLE policy; --”",
    "prefix \"ASCII term\" suffix",
    "nested “outer \"inner\" tail”",
    "“a”".repeat(256),
  ]
  for text in corpus {
    let terms = @policy.discover_policy_terms(text)
    let seen : Array[String] = []
    for term in terms {
      assert_true(!term.trim().is_empty())
      assert_true(!seen.contains(term))
      seen.push(term)
    }
  }
  assert_eq(
    @policy.discover_policy_terms("“same”“same”「same」\"same\""),
    ["same"],
  )
  assert_true(@policy.discover_policy_terms("“unclosed").is_empty())
}

///|
test "opportunity scoring remains deterministic and bounded across input extremes" {
  for authority_rank in 1..<=5 {
    for base_score in [0, 1, 50, 99, 100] {
      let rule = adversarial_signal_rule(base_score)
      let previous_bodies = [
        "no configured signal", "布局算力中心", "全市超级算力节点",
      ]
      let current_bodies = ["布局算力中心", "全市超级算力节点"]
      for previous_body in previous_bodies {
        for current_body in current_bodies {
          let previous = adversarial_policy_document(
            "v1",
            previous_body,
            authority_rank~,
          )
          let current = adversarial_policy_document(
            "v2",
            current_body,
            authority_rank~,
          )
          let first = @policy.analyze_policy(Some(previous), current, [rule])
          let second = @policy.analyze_policy(Some(previous), current, [rule])
          assert_eq(first, second)
          assert_eq(first.opportunities.length(), 1)
          assert_true(first.opportunities[0].score >= 0)
          assert_true(first.opportunities[0].score <= 100)
        }
      }
    }
  }
}

///|
test "fuzzed policy graph keeps every edge and opportunity evidence-linked" {
  let bodies = [
    "布局算力中心。", "建设“全市超级算力节点”。", "新增“未知术语”；建设全市超级算力节点。",
    "<script>布局算力中心</script>。'); DROP TABLE graph; --", "布局算力中心。布局算力中心。建设“重复术语”。建设“重复术语”。",
  ]
  for index, body in bodies {
    let current = adversarial_policy_document("v" + index.to_string(), body)
    let analysis = @policy.analyze_policy(None, current, [
      adversarial_signal_rule(80),
    ])
    let node_ids = analysis.nodes.map(node => node.node_id)
    for edge in analysis.edges {
      assert_true(node_ids.contains(edge.from_id))
      assert_true(node_ids.contains(edge.to_id))
      assert_eq(edge.source_document_id, current.document_id)
      assert_true(!edge.evidence.is_empty())
    }
    for opportunity in analysis.opportunities {
      assert_eq(opportunity.source_document_id, current.document_id)
      assert_eq(opportunity.source_url, current.source_url)
      assert_true(!opportunity.evidence_phrase.is_empty())
      assert_true(
        analysis.edges.any(edge => {
          edge.relation == "ENABLES_HYPOTHESIS" &&
          edge.evidence == opportunity.evidence_phrase
        }),
      )
    }
  }
}

///|
test "constructor fuzz rejects empty identities, invalid ranks, scores, and phrases" {
  for rank in [-100, -1, 0, 6, 100] {
    try
      @policy.PolicyDocument::new(
        document_id="doc",
        title="title",
        issuer="issuer",
        jurisdiction="jurisdiction",
        published_on="2026-08-10",
        version="v1",
        source_url="https://example.invalid",
        authority_rank=rank,
        body="body",
      )
    catch {
      InvalidAuthorityRank(value) => assert_eq(value, rank)
      _ => fail("expected authority-rank rejection")
    } noraise {
      _ => fail("invalid authority rank must be rejected")
    }
  }
  for blank in ["", " ", "\n\t"] {
    try
      @policy.PolicyDocument::new(
        document_id=blank,
        title="title",
        issuer="issuer",
        jurisdiction="jurisdiction",
        published_on="2026-08-10",
        version="v1",
        source_url="https://example.invalid",
        authority_rank=1,
        body="body",
      )
    catch {
      EmptyIdentifier => ()
      _ => fail("expected empty-identifier rejection")
    } noraise {
      _ => fail("blank identifier must be rejected")
    }
  }
  for score in [-100, -1, 101, 1000] {
    try
      @policy.PolicySignalRule::new(
        rule_id="rule",
        phrases=["signal"],
        topic="topic",
        lane=B2B,
        base_score=score,
        audience="audience",
        proposed_offer="offer",
        next_action="validate",
      )
    catch {
      InvalidScore(value) => assert_eq(value, score)
      _ => fail("expected score rejection")
    } noraise {
      _ => fail("invalid score must be rejected")
    }
  }
  try
    @policy.PolicySignalRule::new(
      rule_id="rule",
      phrases=[],
      topic="topic",
      lane=B2B,
      base_score=50,
      audience="audience",
      proposed_offer="offer",
      next_action="validate",
    )
  catch {
    EmptyPhrases => ()
    _ => fail("expected empty-phrases rejection")
  } noraise {
    _ => fail("empty phrase catalog must be rejected")
  }
}
