///|
fn policy_test_projection(
  source_state : String,
  change_state : String,
) -> PolicyRadarProjection {
  {
    freshness: "stale",
    capture_state: "manual_refresh",
    sources: [
      {
        source_id: "beijing-plan",
        name: "昌平区十五五规划文件",
        publisher: "北京市人民政府门户网站",
        format: "PDF",
        cadence: "每日",
        url: "https://example.gov.cn/plan.pdf",
        verification_state: source_state,
        reviewed_by: if source_state == "verified" {
          "owner-1"
        } else {
          ""
        },
        reviewed_at: if source_state == "verified" {
          "2026-08-10"
        } else {
          ""
        },
        audit_id: if source_state == "verified" {
          "audit-source-1"
        } else {
          ""
        },
        active: false,
      },
    ],
    changes: [
      {
        change_id: "compute-node-wording",
        source_id: "beijing-plan",
        impact: "口径修正",
        title: "北京市级算力节点",
        evidence: "加快打造北京市级算力节点。",
        location: "PDF PAGE 58",
        review_state: change_state,
        reviewed_by: if change_state == "confirmed" {
          "owner-1"
        } else {
          ""
        },
        reviewed_at: if change_state == "confirmed" {
          "2026-08-10"
        } else {
          ""
        },
        audit_id: if change_state == "confirmed" {
          "audit-change-1"
        } else {
          ""
        },
        notification_state: if change_state == "confirmed" {
          "draft"
        } else {
          "none"
        },
      },
    ],
    opportunities: [
      {
        opportunity_id: "edge-validation",
        lane: "B2G",
        title: "边缘节点试点验证",
        why_now: "候选文本出现3+N算力网络",
        next_validation: "确认主管部门和只读试点边界",
        gate: "采购路径未知",
        source_change_id: "compute-node-wording",
      },
    ],
    review_audit_ids: if change_state == "confirmed" {
      ["audit-change-1", "audit-source-1"]
    } else {
      []
    },
    boundary: "no legal or procurement effect",
  }
}

///|
fn render_policy_model(model : Model) -> String {
  let page = @rabbita.simple_cell(model~, update=(_ : Msg, model) => model, view=(
    emit,
    model,
  ) => policy_radar_view(msg => emit(msg), model))
  @rabbita.render_to_string(page)
}

///|
#warnings("-alert_unstable")
test "policy radar renders live stale and gated projection states" {
  let projection = policy_test_projection("pending", "pending")
  let html = render_policy_model({
    ..initial_model(),
    page: PolicyRadar,
    policy_radar_state: "ready",
    policy_radar_projection: Some(projection),
  })
  assert_true(html.contains("证据边界 · REVIEW REQUIRED"))
  assert_true(html.contains("采集投影尚未新鲜"))
  assert_true(html.contains("必须先核验来源"))
  assert_true(html.contains("北京市级算力节点"))
  assert_true(html.contains("查看等价关系表"))
  assert_true(html.contains("B2B / B2G 商机队列"))
  assert_true(html.contains("采购路径未知"))
}

///|
#warnings("-alert_unstable")
test "confirmed interpretation unlocks task preparation and audit navigation" {
  let projection = policy_test_projection("verified", "confirmed")
  let html = render_policy_model({
    ..initial_model(),
    page: PolicyRadar,
    policy_radar_state: "ready",
    policy_radar_projection: Some(projection),
  })
  assert_true(html.contains("解读已确认"))
  assert_true(html.contains("可准备验证"))
  assert_true(html.contains("准备任务"))
  assert_true(html.contains("政策复核收据已进入证据链"))
  assert_true(html.contains("在证据页查看"))
  assert_true(
    policy_opportunity_by_id(Some(projection), "edge-validation")
    is Some(
      {
        opportunity_id: "edge-validation",
        lane: "B2G",
        title: "边缘节点试点验证",
        why_now: "候选文本出现3+N算力网络",
        next_validation: "确认主管部门和只读试点边界",
        gate: "采购路径未知",
        source_change_id: "compute-node-wording",
      }
    ),
  )
}

///|
test "task preparation gate follows the persisted change review state" {
  let pending = policy_test_projection("verified", "pending")
  let confirmed = policy_test_projection("verified", "confirmed")
  let opportunity = policy_opportunity_by_id(Some(pending), "edge-validation").unwrap()
  assert_false(policy_opportunity_actionable(Some(pending), opportunity))
  assert_true(policy_opportunity_actionable(Some(confirmed), opportunity))
  assert_false(policy_opportunity_actionable(None, opportunity))
}

///|
#warnings("-alert_unstable")
test "policy radar has explicit loading and error recovery states" {
  let loading = render_policy_model({
    ..initial_model(),
    page: PolicyRadar,
    policy_radar_state: "loading",
  })
  assert_true(loading.contains("正在读取政策投影"))
  let failed = render_policy_model({
    ..initial_model(),
    page: PolicyRadar,
    policy_radar_state: "error",
    policy_radar_error: "gateway unavailable",
  })
  assert_true(failed.contains("政策投影不可用"))
  assert_true(failed.contains("gateway unavailable"))
  assert_true(failed.contains("重新加载"))
}

///|
test "policy projection decoder rejects schema drift" {
  assert_true(policy_projection_from_json({ "schema": "unknown" }) is None)
  let decoded = policy_projection_from_json({
    "schema": "moonproj.policy-radar-projection.v1",
    "freshness": "stale",
    "capture_state": "manual_refresh",
    "sources": [],
    "changes": [],
    "opportunities": [],
    "review_receipts": [],
    "boundary": "review required",
  })
  assert_true(
    decoded
    is Some(
      {
        freshness: "stale",
        capture_state: "manual_refresh",
        sources: [],
        changes: [],
        opportunities: [],
        review_audit_ids: [],
        boundary: "review required",
      }
    ),
  )
}
