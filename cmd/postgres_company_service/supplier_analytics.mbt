///|
struct SupplierRiskMetrics {
  score : Double
  rating : String
  tags : Array[String]
  contract_count : Int
  contract_total : Double
  overdue_count : Int
  overdue_amount : Double
}

///|
fn supplier_risk_source_tables() -> Array[String] {
  [
    "cb_contract", "cb_contract_milestone", "srm_category", "srm_provider", "srm_provider_bu",
  ]
}

///|
fn supplier_risk_source_coverage(
  contracts : Array[SourceRow],
  milestones : Array[SourceRow],
  categories : Array[SourceRow],
  providers : Array[SourceRow],
  links : Array[SourceRow],
) -> Map[String, Int] {
  {
    "cb_contract": contracts.length(),
    "cb_contract_milestone": milestones.length(),
    "srm_category": categories.length(),
    "srm_provider": providers.length(),
    "srm_provider_bu": links.length(),
  }
}

///|
fn supplier_risk_source_missing(coverage : Map[String, Int]) -> Array[Json] {
  let result : Array[Json] = []
  for table in supplier_risk_source_tables() {
    if coverage.get_or_default(table, 0) == 0 {
      result.push(Json::string(table))
    }
  }
  result
}

///|
fn supplier_risk_source_envelope(
  data : Json,
  coverage : Map[String, Int],
) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("imported_or_empty"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(
      supplier_risk_source_missing(coverage),
    ),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
  })
}

///|
fn supplier_source_risk_metrics(
  provider : SourceRow,
  contracts : Array[SourceRow],
  milestones : Array[SourceRow],
) -> SupplierRiskMetrics {
  let payload = provider.payload
  let provider_name = report_text(payload, "provider_name", "")
  let short_name = report_text(payload, "short_name", provider_name)
  let evaluation = report_text(payload, "eval_result", "")
  if evaluation == "黑名单" || evaluation == "不合格" {
    return {
      score: 0.0,
      rating: "E",
      tags: ["blacklist"],
      contract_count: 0,
      contract_total: 0.0,
      overdue_count: 0,
      overdue_amount: 0.0,
    }
  }
  let matching_contracts : Array[SourceRow] = []
  for row in contracts {
    if !dashboard_active(row.payload) {
      continue
    }
    let name = report_text(row.payload, "yf_provider_name", "")
    if name == provider_name ||
      (!short_name.is_empty() && name.contains(short_name)) {
      matching_contracts.push(row)
    }
  }
  let contract_ids : Map[String, Bool] = {}
  for row in matching_contracts {
    contract_ids.set(
      report_text(row.payload, "contract_guid", row.record_id),
      true,
    )
  }
  let overdue_count = milestones.fold(init=0, fn(count, row) {
    if contract_ids.contains(report_text(row.payload, "contract_guid", "")) &&
      report_text(row.payload, "state", "") == "overdue" {
      count + 1
    } else {
      count
    }
  })
  let overdue_amount = milestones.fold(init=0.0, fn(total, row) {
    if contract_ids.contains(report_text(row.payload, "contract_guid", "")) &&
      report_text(row.payload, "state", "") == "overdue" {
      total + report_amount(row.payload, "plan_amount")
    } else {
      total
    }
  })
  let contract_total = matching_contracts.fold(init=0.0, fn(total, row) {
    total +
    report_amount(row.payload, "ht_amount") +
    report_amount(row.payload, "sum_alter_amount")
  })
  let contract_bonus = if matching_contracts.length() > 15 {
    15.0
  } else {
    matching_contracts.length().to_double()
  }
  let overdue_penalty = if overdue_count * 5 > 35 {
    35.0
  } else {
    (overdue_count * 5).to_double()
  }
  let concentration_penalty = if contract_total > 0.0 {
    let value = overdue_amount / contract_total * 50.0
    if value > 30.0 {
      30.0
    } else {
      value
    }
  } else {
    0.0
  }
  let mut score = 70.0 +
    contract_bonus -
    overdue_penalty -
    concentration_penalty
  let tags : Array[String] = []
  if report_text(payload, "inspect_state", "") == "不合格" {
    score -= 15.0
    tags.push("inspect_failed")
  }
  if overdue_count > 0 {
    tags.push("overdue")
  }
  if contract_total > 50000000.0 {
    tags.push("heavy_concentration")
  }
  if score < 0.0 {
    score = 0.0
  }
  if score > 100.0 {
    score = 100.0
  }
  score = round_places(score, 1)
  let rating = if score >= 85.0 {
    "A"
  } else if score >= 70.0 {
    "B"
  } else if score >= 55.0 {
    "C"
  } else if score >= 40.0 {
    "D"
  } else {
    "E"
  }
  {
    score,
    rating,
    tags,
    contract_count: matching_contracts.length(),
    contract_total,
    overdue_count,
    overdue_amount,
  }
}

///|
fn supplier_count_rows(counts : Map[String, Int]) -> Array[Json] {
  let keys : Array[String] = []
  for key, _ in counts {
    keys.push(key)
  }
  keys.sort_by(fn(left, right) { left.compare(right) })
  keys.map(fn(key) {
    Json::object({
      "name": Json::string(key),
      "count": Json::number(counts.get_or_default(key, 0).to_double()),
    })
  })
}

///|
async fn supplier_source_stats_response() -> Json raise CompanyServiceError {
  let providers = raw_source_rows("srm_provider", 500)
  let links = raw_source_rows("srm_provider_bu", 500)
  let categories = raw_source_rows("srm_category", 500)
  let contracts = raw_source_rows("cb_contract", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let coverage : Map[String, Int] = {
    "cb_contract": contracts.length(),
    "mu_business_unit": units.length(),
    "srm_category": categories.length(),
    "srm_provider": providers.length(),
    "srm_provider_bu": links.length(),
  }
  let visible = providers.filter(fn(row) {
    dashboard_active(row.payload) && json_bool(row.payload, "enabled", false)
  })
  let by_eval : Map[String, Int] = {}
  let by_source : Map[String, Int] = {}
  let by_category : Map[String, Int] = {}
  for row in visible {
    let payload = row.payload
    let evaluation = report_text(payload, "eval_result", "未定级")
    let source = report_text(payload, "source", "")
    let category = report_text(payload, "main_category_code", "")
    by_eval.set(evaluation, by_eval.get_or_default(evaluation, 0) + 1)
    by_source.set(source, by_source.get_or_default(source, 0) + 1)
    by_category.set(category, by_category.get_or_default(category, 0) + 1)
  }
  let category_names : Map[String, String] = {}
  for row in categories {
    category_names.set(
      report_text(row.payload, "category_code", ""),
      report_text(row.payload, "category_name", ""),
    )
  }
  let category_order = categories
  category_order.sort_by(fn(left, right) {
    let left_order = report_text(left.payload, "sort_order", "")
    let right_order = report_text(right.payload, "sort_order", "")
    let comparison = left_order.compare(right_order)
    if comparison == 0 {
      report_text(left.payload, "category_code", "").compare(
        report_text(right.payload, "category_code", ""),
      )
    } else {
      comparison
    }
  })
  let category_rows : Array[Json] = []
  for row in category_order {
    let code = report_text(row.payload, "category_code", "")
    category_rows.push(
      Json::object({
        "name": Json::string(category_names.get_or_default(code, code)),
        "count": Json::number(by_category.get_or_default(code, 0).to_double()),
      }),
    )
  }
  let top_business : Array[Json] = []
  for row in visible {
    let payload = row.payload
    let provider_name = report_text(payload, "provider_name", row.record_id)
    let short_name = report_text(payload, "short_name", "")
    let matches = contracts.filter(fn(contract) {
      if !dashboard_active(contract.payload) {
        false
      } else {
        let name = report_text(contract.payload, "yf_provider_name", "")
        name == provider_name ||
        name == short_name ||
        (!short_name.is_empty() && name.contains(short_name))
      }
    })
    let total_amount = matches.fold(init=0.0, fn(total, contract) {
      total +
      report_amount(contract.payload, "ht_amount") +
      report_amount(contract.payload, "sum_alter_amount")
    })
    top_business.push(
      Json::object({
        "name": Json::string(provider_name),
        "contractCount": Json::number(matches.length().to_double()),
        "totalAmount": Json::number(total_amount),
      }),
    )
  }
  top_business.sort_by(fn(left, right) {
    let amount_order = report_amount(right, "totalAmount").compare(
      report_amount(left, "totalAmount"),
    )
    if amount_order == 0 {
      report_text(left, "name", "").compare(report_text(right, "name", ""))
    } else {
      amount_order
    }
  })
  let top_business_limited = if top_business.length() > 10 {
    top_business[:10].to_owned()
  } else {
    top_business
  }
  supplier_source_stats_envelope(
    Json::object({
      "total": Json::number(visible.length().to_double()),
      "byEvalResult": Json::array(supplier_count_rows(by_eval)),
      "byCategory": Json::array(category_rows),
      "bySource": Json::array(supplier_count_rows(by_source)),
      "topBusiness": Json::array(top_business_limited),
    }),
    coverage,
  )
}

///|
fn supplier_source_stats_envelope(
  data : Json,
  coverage : Map[String, Int],
) -> Json {
  let missing : Array[Json] = []
  for table, count in coverage {
    if count == 0 {
      missing.push(Json::string(table))
    }
  }
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("imported_or_command"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(missing),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "command_projection": Json::boolean(true),
    "provider_execution": Json::boolean(false),
    "cash_effect": Json::boolean(false),
    "accounting_effect": Json::boolean(false),
    "tax_effect": Json::boolean(false),
  })
}

///|
async fn supplier_risk_board_source_response() -> Json raise CompanyServiceError {
  let providers = raw_source_rows("srm_provider", 500)
  let links = raw_source_rows("srm_provider_bu", 500)
  let categories = raw_source_rows("srm_category", 500)
  let contracts = raw_source_rows("cb_contract", 500)
  let milestones = raw_source_rows("cb_contract_milestone", 500)
  let coverage = supplier_risk_source_coverage(
    contracts, milestones, categories, providers, links,
  )
  let distribution : Map[String, Int] = {}
  let high_risk : Array[Json] = []
  for provider in providers {
    if !dashboard_active(provider.payload) {
      continue
    }
    let risk = supplier_source_risk_metrics(provider, contracts, milestones)
    distribution.set(
      risk.rating,
      distribution.get_or_default(risk.rating, 0) + 1,
    )
    if risk.rating != "D" && risk.rating != "E" {
      continue
    }
    high_risk.push(
      Json::object({
        "providerGuid": Json::string(
          report_text(provider.payload, "provider_guid", provider.record_id),
        ),
        "providerCode": Json::string(
          report_text(provider.payload, "provider_code", ""),
        ),
        "providerName": Json::string(
          report_text(provider.payload, "provider_name", ""),
        ),
        "shortName": Json::string(
          report_text(provider.payload, "short_name", ""),
        ),
        "mainCategoryCode": Json::string(
          report_text(provider.payload, "main_category_code", ""),
        ),
        "rating": Json::string(risk.rating),
        "riskScore": Json::number(risk.score),
        "riskTags": Json::string(risk.tags.join(",")),
        "ratingUpdatedAt": Json::string(
          report_text(provider.payload, "rating_updated_at", ""),
        ),
        "contractCount": Json::number(risk.contract_count.to_double()),
        "contractTotal": Json::number(risk.contract_total),
        "overdueCount": Json::number(risk.overdue_count.to_double()),
        "overdueAmount": Json::number(risk.overdue_amount),
        "sourceKind": Json::string("imported"),
      }),
    )
  }
  high_risk.sort_by(fn(left, right) {
    let score_order = report_amount(left, "riskScore").compare(
      report_amount(right, "riskScore"),
    )
    if score_order == 0 {
      report_text(left, "providerGuid", "").compare(
        report_text(right, "providerGuid", ""),
      )
    } else {
      score_order
    }
  })
  let distribution_rows : Array[Json] = []
  for item in supplier_count_rows(distribution) {
    distribution_rows.push(
      Json::object({
        "rating": Json::string(report_text(item, "name", "")),
        "c": json_field(item, "count").unwrap_or(Json::number(0)),
      }),
    )
  }
  supplier_risk_source_envelope(
    Json::object({
      "highRisk": Json::array(high_risk),
      "distribution": Json::array(distribution_rows),
    }),
    coverage,
  )
}

///|
async fn supplier_command_risk_board_response() -> Json raise CompanyServiceError {
  let source = supplier_command_items()
  let result : Array[Json] = []
  for item in source {
    let state = json_text(item, "auditState", "")
    let evaluation = match json_text(item, "evalResult", "") {
      "战略" => "strategic"
      "合格" => "qualified"
      "不合格" => "unqualified"
      _ => "unrated"
    }
    let persisted_rating = json_text(item, "riskRating", "")
    let score = if !persisted_rating.is_empty() {
      json_number(item, "riskScore", 0.0).to_int()
    } else if state == "voided" ||
      state == "blacklisted" ||
      evaluation == "unqualified" {
      0
    } else if state == "active" && evaluation == "strategic" {
      95
    } else if state == "active" && evaluation == "qualified" {
      85
    } else if state == "pending_review" {
      60
    } else if state == "suspended" {
      35
    } else {
      50
    }
    let rating = if !persisted_rating.is_empty() {
      persisted_rating
    } else if score >= 95 {
      "A"
    } else if score >= 85 {
      "B"
    } else if score == 0 {
      "E"
    } else if score == 35 {
      "D"
    } else {
      "C"
    }
    let tags : Array[Json] = if !json_text(item, "riskTags", "").is_empty() {
      json_text(item, "riskTags", "")
      .split(",")
      .to_array()
      .map(fn(tag) { Json::string(tag.to_owned()) })
    } else {
      []
    }
    if state == "pending_review" {
      tags.push(Json::string("pending_review"))
    }
    if state == "suspended" {
      tags.push(Json::string("suspended"))
    }
    if state == "blacklisted" {
      tags.push(Json::string("blacklist"))
    }
    if evaluation == "unqualified" {
      tags.push(Json::string("unqualified"))
    }
    match item {
      Object(fields) => {
        fields.set(
          "supplier_id",
          Json::string(json_text(item, "providerGuid", "")),
        )
        fields.set("score", Json::number(score.to_double()))
        fields.set("rating", Json::string(rating))
        fields.set("tags", Json::array(tags))
        fields.set("state", Json::string(state))
        fields.set("evaluation", Json::string(evaluation))
        fields.set("source_kind", Json::string("command"))
        result.push(Json::object(fields))
      }
      _ => ()
    }
  }
  result.sort_by(fn(left, right) {
    let score_order = report_amount(left, "score").compare(
      report_amount(right, "score"),
    )
    if score_order == 0 {
      report_text(left, "supplier_id", "").compare(
        report_text(right, "supplier_id", ""),
      )
    } else {
      score_order
    }
  })
  Json::object({ "items": Json::array(result) })
}
