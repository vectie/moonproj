///|
/// Persisted policy-review projection.
///
/// The service exposes candidate policy evidence for human review. Reviewing a
/// source or interpretation creates command and audit receipts, but never
/// proves legal effect, funding, procurement intent, or permission to contact
/// an external party.

///|
fn policy_review_path_id(path : String, prefix : String) -> String? {
  let suffix = "/reviews"
  if !path.has_prefix(prefix) || !path.has_suffix(suffix) {
    return None
  }
  let id = path[prefix.length():path.length() - suffix.length()].to_owned()
  if valid_identifier(id) {
    Some(id)
  } else {
    None
  }
}

///|
fn policy_source_review_path(path : String) -> String? {
  policy_review_path_id(path, "/api/company/policy/sources/")
}

///|
fn policy_change_review_path(path : String) -> String? {
  policy_review_path_id(path, "/api/company/policy/changes/")
}

///|
fn policy_review_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> (String, String)? {
  if !(request_method is @http.Post) {
    return None
  }
  match policy_source_review_path(path) {
    Some(id) => Some(("source", id))
    None =>
      match policy_change_review_path(path) {
        Some(id) => Some(("change", id))
        None => None
      }
  }
}

///|
fn policy_change_source(change_id : String) -> String? {
  match change_id {
    "compute-node-wording"
    | "compute-network-strengthened"
    | "advanced-energy-target"
    | "changhuida-platform" =>
      Some("beijing-changping-15th-five-year-plan-2026")
    _ => None
  }
}

///|
fn policy_source_known(source_id : String) -> Bool {
  source_id == "beijing-changping-15th-five-year-plan-2026" ||
  source_id == "beijing-fgw-yinli-changping-2026"
}

///|
fn normalize_policy_review(
  kind : String,
  id : String,
  body : Json,
) -> Json raise CompanyServiceError {
  if (kind == "source" && !policy_source_known(id)) ||
    (kind == "change" && policy_change_source(id) is None) {
    raise reject(404, "policy review target was not found")
  }
  let fields = engineering_object(body, "policy review")
  engineering_exact_keys(
    fields,
    ["decision", "evidence", "reviewed_at"],
    "policy review",
  )
  let decision = engineering_enum(
    fields,
    "decision",
    if kind == "source" {
      ["verified", "rejected"]
    } else {
      ["confirmed", "rejected"]
    },
    "policy review",
  )
  let evidence = engineering_required_text(fields, "evidence", "policy review")
    .trim()
    .to_owned()
  if evidence.length() > 2048 {
    raise reject(422, "policy review evidence is too long")
  }
  let reviewed_at = engineering_required_text(
      fields, "reviewed_at", "policy review",
    )
    .trim()
    .to_owned()
  if reviewed_at.length() != 10 || cashflow_date_parts(reviewed_at) is None {
    raise reject(422, "policy review reviewed_at must be an ISO date")
  }
  Json::object({
    "kind": Json::string(kind),
    "target_id": Json::string(id),
    "decision": Json::string(decision),
    "evidence": Json::string(evidence),
    "reviewed_at": Json::string(reviewed_at),
  })
}

///|
fn policy_review_projection(
  normalized : Json,
  actor : String,
  revision : Int,
  event_id : String,
  audit_id : String,
) -> Json {
  Json::object({
    "schema": Json::string("moonproj.policy-review-projection.v1"),
    "kind": Json::string(json_text(normalized, "kind", "")),
    "target_id": Json::string(json_text(normalized, "target_id", "")),
    "decision": Json::string(json_text(normalized, "decision", "pending")),
    "evidence": Json::string(json_text(normalized, "evidence", "")),
    "reviewed_at": Json::string(json_text(normalized, "reviewed_at", "")),
    "reviewed_by": Json::string(actor),
    "revision": Json::number(revision.to_double()),
    "event_id": Json::string(event_id),
    "audit_id": Json::string(audit_id),
    "updated_at_ms": Json::number(@env.now().to_double()),
    "persisted": Json::boolean(true),
    "legal_effect": Json::boolean(false),
    "procurement_effect": Json::boolean(false),
  })
}

///|
async fn latest_policy_review(
  aggregate_type : String,
  target_id : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = " +
    @postgres.sql_literal(aggregate_type) +
    " AND aggregate_id = " +
    @postgres.sql_literal(target_id) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid policy review projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
fn policy_review_state(review : (Json, Int)?) -> String {
  match review {
    Some((payload, _)) => json_text(payload, "decision", "pending")
    None => "pending"
  }
}

///|
fn policy_review_audit(review : (Json, Int)?) -> String {
  match review {
    Some((payload, _)) => json_text(payload, "audit_id", "")
    None => ""
  }
}

///|
fn policy_review_owner(review : (Json, Int)?) -> String {
  match review {
    Some((payload, _)) => json_text(payload, "reviewed_by", "")
    None => ""
  }
}

///|
fn policy_reviewed_at(review : (Json, Int)?) -> String {
  match review {
    Some((payload, _)) => json_text(payload, "reviewed_at", "")
    None => ""
  }
}

///|
fn policy_source_item(
  source_id : String,
  name : String,
  publisher : String,
  format : String,
  cadence : String,
  url : String,
  review : (Json, Int)?,
) -> Json {
  Json::object({
    "source_id": Json::string(source_id),
    "name": Json::string(name),
    "publisher": Json::string(publisher),
    "format": Json::string(format),
    "cadence": Json::string(cadence),
    "url": Json::string(url),
    "verification_state": Json::string(policy_review_state(review)),
    "reviewed_by": Json::string(policy_review_owner(review)),
    "reviewed_at": Json::string(policy_reviewed_at(review)),
    "audit_id": Json::string(policy_review_audit(review)),
    "active": Json::boolean(false),
  })
}

///|
fn policy_change_item(
  change_id : String,
  source_id : String,
  impact : String,
  title : String,
  evidence : String,
  location : String,
  review : (Json, Int)?,
) -> Json {
  let state = policy_review_state(review)
  Json::object({
    "change_id": Json::string(change_id),
    "source_id": Json::string(source_id),
    "impact": Json::string(impact),
    "title": Json::string(title),
    "evidence": Json::string(evidence),
    "location": Json::string(location),
    "review_state": Json::string(state),
    "reviewed_by": Json::string(policy_review_owner(review)),
    "reviewed_at": Json::string(policy_reviewed_at(review)),
    "audit_id": Json::string(policy_review_audit(review)),
    "notification_state": Json::string(
      if state == "confirmed" {
        "draft"
      } else {
        "none"
      },
    ),
  })
}

///|
fn policy_opportunity_item(
  opportunity_id : String,
  lane : String,
  title : String,
  why_now : String,
  next_validation : String,
  gate : String,
  source_change_id : String,
) -> Json {
  Json::object({
    "opportunity_id": Json::string(opportunity_id),
    "lane": Json::string(lane),
    "title": Json::string(title),
    "why_now": Json::string(why_now),
    "next_validation": Json::string(next_validation),
    "gate": Json::string(gate),
    "source_change_id": Json::string(source_change_id),
  })
}

///|
async fn policy_radar_response() -> (Int, Json) raise CompanyServiceError {
  let plan_source = latest_policy_review(
    "policy_source_review", "beijing-changping-15th-five-year-plan-2026",
  )
  let yinli_source = latest_policy_review(
    "policy_source_review", "beijing-fgw-yinli-changping-2026",
  )
  let compute_wording = latest_policy_review(
    "policy_change_review", "compute-node-wording",
  )
  let compute_network = latest_policy_review(
    "policy_change_review", "compute-network-strengthened",
  )
  let energy_target = latest_policy_review(
    "policy_change_review", "advanced-energy-target",
  )
  let changhuida = latest_policy_review(
    "policy_change_review", "changhuida-platform",
  )
  let sources = [
    policy_source_item(
      "beijing-changping-15th-five-year-plan-2026", "昌平区十五五规划文件",
      "北京市人民政府门户网站", "PDF · 139页", "每日", "https://www.beijing.gov.cn/zhengce/zhengcefagui/202604/W020260421383231367836.pdf",
      plan_source,
    ),
    policy_source_item(
      "beijing-fgw-yinli-changping-2026", "尹力参加昌平团审议相关报道",
      "北京市发展和改革委员会", "HTML", "每6小时", "https://fgw.beijing.gov.cn/fzggzl/bjlh2026/lhyw/202601/t20260128_4471877.htm",
      yinli_source,
    ),
  ]
  let plan_id = "beijing-changping-15th-five-year-plan-2026"
  let changes = [
    policy_change_item(
      "compute-network-strengthened", plan_id, "表述强化", "算力基础设施从中心建设走向全域网络",
      "统筹布局‘3+N’算力中心体系，构建全域协同算力网络。",
      "PDF PAGE 58", compute_network,
    ),
    policy_change_item(
      "compute-node-wording", plan_id, "口径修正", "官方候选文本使用北京市级算力节点",
      "规划建设昌平人工智能公共算力中心，加快打造北京市级算力节点。",
      "PDF PAGE 58", compute_wording,
    ),
    policy_change_item(
      "advanced-energy-target", plan_id, "量化目标", "先进能源产业收入目标4500亿元以上",
      "到2030年，先进能源产业规上企业收入达4500亿元以上。",
      "PDF PAGE 46", energy_target,
    ),
    policy_change_item(
      "changhuida-platform", plan_id, "平台实体", "昌慧达被表述为人工智能政策计算器",
      "在全国首创‘昌慧达’人工智能政策计算器。", "PDF PAGE 14",
      changhuida,
    ),
  ]
  let opportunities = [
    policy_opportunity_item(
      "b2g-edge-node-validation", "B2G", "3+N边缘节点与治理Agent试点", "候选文本出现全域协同算力网络",
      "确认主管部门、现有平台接口和只读试点边界", "采购路径未知",
      "compute-network-strengthened",
    ),
    policy_opportunity_item(
      "b2b-energy-agent-validation", "B2B", "先进能源企业经营与生产Agent",
      "量化产业目标与人工智能加能源信号并存", "访谈研发、生产、供应链各一家企业",
      "付费问题未知", "advanced-energy-target",
    ),
    policy_opportunity_item(
      "dual-policy-service-validation", "B2B+B2G", "昌慧达政策解释与企业反馈闭环",
      "候选文本确认政策计算器这一平台定位", "确认数据授权、接口责任和十家企业样例",
      "数据授权未知", "changhuida-platform",
    ),
  ]
  let receipts : Array[Json] = []
  for
    review in [
      plan_source, yinli_source, compute_wording, compute_network, energy_target,
      changhuida,
    ] {
    match review {
      Some((payload, _)) =>
        receipts.push(
          Json::object({
            "audit_id": Json::string(json_text(payload, "audit_id", "")),
            "target_id": Json::string(json_text(payload, "target_id", "")),
            "decision": Json::string(json_text(payload, "decision", "")),
            "reviewed_by": Json::string(json_text(payload, "reviewed_by", "")),
            "reviewed_at": Json::string(json_text(payload, "reviewed_at", "")),
          }),
        )
      None => ()
    }
  }
  (
    200,
    Json::object({
      "schema": Json::string("moonproj.policy-radar-projection.v1"),
      "freshness": Json::string("stale"),
      "capture_state": Json::string("manual_refresh"),
      "generated_at_ms": Json::number(@env.now().to_double()),
      "sources": Json::array(sources),
      "changes": Json::array(changes),
      "opportunities": Json::array(opportunities),
      "review_receipts": Json::array(receipts),
      "boundary": Json::string(
        "Policy review does not establish law, funding, procurement intent, or authority to act.",
      ),
    }),
  )
}

///|
async fn persist_policy_review(
  kind : String,
  target_id : String,
  body : Json,
  actor : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(actor) || !valid_identifier(idempotency_key) {
    raise reject(422, "invalid policy review identity")
  }
  let normalized = normalize_policy_review(kind, target_id, body)
  let request = Json::object({
    "command_type": Json::string("review_policy_" + kind),
    "target_id": Json::string(target_id),
    "actor_id": Json::string(actor),
    "review": normalized,
  })
  match existing_company_command(idempotency_key) {
    Some(existing) => {
      if !json_equal(
          json_field(existing, "request").unwrap_or(Json::null()),
          request,
        ) {
        raise reject(
          409, "Idempotency-Key was already used for another request",
        )
      }
      return (
        200,
        Json::object({
          "policy_review": json_field(existing, "result").unwrap_or(
            Json::null(),
          ),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  if kind == "change" {
    let source_id = policy_change_source(target_id).unwrap()
    match latest_policy_review("policy_source_review", source_id) {
      Some((source_review, _)) if json_text(source_review, "decision", "") ==
        "verified" => ()
      _ =>
        raise reject(
          409, "policy source must be verified before interpreting a change",
        )
    }
  }
  let aggregate_type = "policy_" + kind + "_review"
  let current = latest_policy_review(aggregate_type, target_id)
  let revision = match current {
    Some((_, value)) => value + 1
    None => 1
  }
  let event_id = "policy:" + kind + "-review:" + idempotency_key
  let audit_id = event_id + ":audit"
  let projection = policy_review_projection(
    normalized, actor, revision, event_id, audit_id,
  )
  let command = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("policy_review"),
    "command_type": Json::string("review_policy_" + kind),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(target_id),
    "actor_id": Json::string(actor),
    "request": request,
    "result": projection,
  })
  let audit = Json::object({
    "schema": Json::string("moonproj.policy-review-audit.v1"),
    "audit_id": Json::string(audit_id),
    "action": Json::string("policy." + kind + ".review"),
    "aggregate_type": Json::string(aggregate_type),
    "aggregate_id": Json::string(target_id),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
    "decision": Json::string(json_text(projection, "decision", "pending")),
    "revision": Json::number(revision.to_double()),
    "legal_effect": Json::boolean(false),
    "procurement_effect": Json::boolean(false),
  })
  let notification = Json::object({
    "schema": Json::string("moonproj.policy-notification-draft.v1"),
    "notification_id": Json::string("notification:" + event_id),
    "source_event_id": Json::string(event_id),
    "change_id": Json::string(target_id),
    "state": Json::string("draft"),
    "channel": Json::string("in_app"),
    "delivery_effect": Json::boolean(false),
  })
  let notification_sql = if kind == "change" &&
    json_text(projection, "decision", "") == "confirmed" {
    " INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('policy_notification_draft', " +
    @postgres.sql_literal(target_id) +
    ", " +
    revision.to_string() +
    ", " +
    @postgres.sql_literal(notification.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING;"
  } else {
    ""
  }
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES (" +
    @postgres.sql_literal(aggregate_type) +
    ", " +
    @postgres.sql_literal(target_id) +
    ", " +
    revision.to_string() +
    ", " +
    @postgres.sql_literal(projection.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING;" +
    notification_sql +
    " INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
    @postgres.sql_literal(audit_id) +
    ", 4, " +
    @postgres.sql_literal(audit.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:audit:" + event_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    201,
    Json::object({
      "policy_review": projection,
      "notification_draft": if kind == "change" &&
        json_text(projection, "decision", "") == "confirmed" {
        notification
      } else {
        Json::null()
      },
      "idempotent_replay": Json::boolean(false),
    }),
  )
}
