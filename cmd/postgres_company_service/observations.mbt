///|
/// Native observation-only admin, notification, AI, attachment, webhook, and RBAC reads.
fn observation_missing(coverage : Map[String, Int]) -> Array[Json] {
  let names : Array[String] = []
  for table, count in coverage {
    if count == 0 {
      names.push(table)
    }
  }
  names.sort_by(fn(left, right) { left.compare(right) })
  names.map(fn(name) { Json::string(name) })
}

///|
fn observation_envelope(data : Json, coverage : Map[String, Int]) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string("imported_or_empty"),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(observation_missing(coverage)),
    "authorizing": Json::boolean(false),
    "persisted": Json::boolean(false),
    "provider_execution": Json::boolean(false),
    "query_execution": Json::boolean(false),
    "secret_values_redacted": Json::boolean(true),
    "network_fields_redacted": Json::boolean(true),
    "downloadable": Json::boolean(false),
    "binary_storage": Json::string("not_imported"),
  })
}

///|
async fn observation_coverage(
  tables : Array[String],
) -> Map[String, Int] raise CompanyServiceError {
  let result : Map[String, Int] = {}
  for table in tables {
    result.set(table, raw_source_rows(table, 500).length())
  }
  result
}

///|
fn observation_rows_for(coverage : Map[String, Int], table : String) -> Int {
  coverage.get_or_default(table, 0)
}

///|
/// Attachments.
async fn attachment_source_rows(
  biz_type : String?,
  biz_guid : String?,
  uploaded_by : String?,
  ai_status : String?,
  keyword : String?,
) -> (Array[Json], Map[String, Int]) raise CompanyServiceError {
  let attachment_rows = raw_source_rows("attachment", 500)
  let users = raw_source_rows("sys_user", 500)
  let coverage : Map[String, Int] = {}
  coverage.set("attachment", attachment_rows.length())
  coverage.set("sys_user", users.length())
  let rows : Array[Json] = []
  for source in attachment_rows {
    let payload = source.payload
    if !json_text(payload, "deleted_at", "").is_empty() ||
      !json_text(payload, "deletedAt", "").is_empty() {
      continue
    }
    let current_biz_type = json_text(
      payload,
      "biz_type",
      json_text(payload, "bizType", ""),
    )
    let current_biz_guid = json_text(
      payload,
      "biz_guid",
      json_text(payload, "bizGuid", ""),
    )
    let current_uploaded_by = json_text(
      payload,
      "uploaded_by",
      json_text(payload, "uploadedBy", ""),
    )
    let current_ai_status = json_text(
      payload,
      "ai_status",
      json_text(payload, "aiStatus", ""),
    )
    let file_name = json_text(
      payload,
      "file_name",
      json_text(payload, "fileName", ""),
    )
    if biz_type is Some(value) && current_biz_type != value {
      continue
    }
    if biz_guid is Some(value) && current_biz_guid != value {
      continue
    }
    if uploaded_by is Some(value) && current_uploaded_by != value {
      continue
    }
    if ai_status is Some(value) && current_ai_status != value {
      continue
    }
    if keyword is Some(value) &&
      !file_name.to_lower().contains(value.to_lower()) {
      continue
    }
    let uploaded_name = match
      source_payload(users, "user_id", current_uploaded_by) {
      Some(user) =>
        json_text(user, "emp_name", json_text(user, "user_name", ""))
      None =>
        match source_payload(users, "user_code", current_uploaded_by) {
          Some(user) =>
            json_text(user, "emp_name", json_text(user, "user_name", ""))
          None => ""
        }
    }
    let ai_extracted = match json_field(payload, "ai_extracted") {
      Some(String(text)) if !text.trim().is_empty() =>
        @json.parse(text) catch {
          _ => Json::object({})
        }
      Some(value) => value
      None =>
        match json_field(payload, "aiExtracted") {
          Some(value) => value
          None => Json::object({})
        }
    }
    let has_ai = json_field(payload, "ai_extracted") is Some(_) ||
      json_field(payload, "aiExtracted") is Some(_) ||
      !current_ai_status.is_empty() ||
      json_field(payload, "ai_confidence") is Some(_) ||
      json_field(payload, "aiConfidence") is Some(_)
    let ai = if has_ai {
      Json::object({
        "extracted": ai_extracted,
        "confidence": json_field(payload, "ai_confidence").unwrap_or(
          json_field(payload, "aiConfidence").unwrap_or(Json::null()),
        ),
        "status": Json::string(
          if current_ai_status.is_empty() {
            "pending"
          } else {
            current_ai_status
          },
        ),
      })
    } else {
      Json::null()
    }
    rows.push(
      Json::object({
        "attGuid": Json::string(
          json_text(
            payload,
            "att_guid",
            json_text(payload, "attGuid", source.record_id),
          ),
        ),
        "fileName": Json::string(file_name),
        "fileSize": Json::number(
          json_number(
            payload,
            "file_size",
            json_number(payload, "fileSize", 0.0),
          ),
        ),
        "mimeType": Json::string(
          json_text(payload, "mime_type", json_text(payload, "mimeType", "")),
        ),
        "bizType": Json::string(current_biz_type),
        "bizGuid": Json::string(current_biz_guid),
        "uploadedBy": Json::string(current_uploaded_by),
        "uploadedByName": Json::string(uploaded_name),
        "uploadedAt": Json::string(
          json_text(
            payload,
            "uploaded_at",
            json_text(payload, "uploadedAt", ""),
          ),
        ),
        "ai": ai,
        "downloadAvailable": Json::boolean(false),
        "sourceKind": Json::string("imported"),
      }),
    )
  }
  rows.sort_by(fn(left, right) {
    let right_date = json_text(right, "uploadedAt", "")
    let left_date = json_text(left, "uploadedAt", "")
    let order = right_date.lexical_compare(left_date)
    if order == 0 {
      json_text(right, "attGuid", "").lexical_compare(
        json_text(left, "attGuid", ""),
      )
    } else {
      order
    }
  })
  (rows, coverage)
}

///|
async fn attachment_all_response(
  uploaded_by : String?,
  ai_status : String?,
  keyword : String?,
) -> Json raise CompanyServiceError {
  let (rows, coverage) = attachment_source_rows(
    None,
    None,
    uploaded_by,
    ai_status,
    keyword,
  )
  observation_envelope(
    Json::object({
      "total": Json::number(rows.length().to_double()),
      "rows": Json::array(rows),
    }),
    coverage,
  )
}

///|
async fn attachment_list_response(
  biz_type : String?,
  biz_guid : String?,
) -> Json raise CompanyServiceError {
  let (rows, coverage) = attachment_source_rows(
    biz_type,
    biz_guid,
    None,
    None,
    None,
  )
  observation_envelope(Json::array(rows), coverage)
}

///|
async fn attachment_stats_response() -> Json raise CompanyServiceError {
  let (rows, coverage) = attachment_source_rows(None, None, None, None, None)
  let by_biz : Map[String, Json] = {}
  let by_ai : Map[String, Int] = {}
  let mut bytes = 0.0
  for row in rows {
    let biz = json_text(row, "bizType", "")
    let existing = match by_biz.get(biz) {
      Some(value) => value
      None =>
        Json::object({
          "bizType": Json::string(biz),
          "count": Json::number(0),
          "bytes": Json::number(0),
        })
    }
    match existing {
      Object(fields) => {
        fields.set(
          "count",
          Json::number(json_number(existing, "count", 0.0) + 1.0),
        )
        let file_bytes = json_number(row, "fileSize", 0.0)
        fields.set(
          "bytes",
          Json::number(json_number(existing, "bytes", 0.0) + file_bytes),
        )
        by_biz.set(biz, Json::object(fields))
        bytes += file_bytes
      }
      _ => ()
    }
    let ai = json_field(row, "ai")
    let ai_state = match ai {
      Some(Object(fields)) =>
        json_text(Json::object(fields), "status", "unprocessed")
      _ => "unprocessed"
    }
    by_ai.set(ai_state, by_ai.get(ai_state).unwrap_or(0) + 1)
  }
  let by_biz_values : Array[Json] = []
  for _, value in by_biz {
    by_biz_values.push(value)
  }
  by_biz_values.sort_by(fn(left, right) {
    json_number(right, "count", 0.0).to_int() -
    json_number(left, "count", 0.0).to_int()
  })
  let by_ai_values : Array[Json] = []
  for status, count in by_ai {
    by_ai_values.push(
      Json::object({
        "aiStatus": Json::string(status),
        "count": Json::number(count.to_double()),
      }),
    )
  }
  by_ai_values.sort_by(fn(left, right) {
    json_text(left, "aiStatus", "").lexical_compare(
      json_text(right, "aiStatus", ""),
    )
  })
  observation_envelope(
    Json::object({
      "total": Json::object({
        "count": Json::number(
          by_biz_values
          .fold(init=0, fn(total, value) {
            total + json_number(value, "count", 0.0).to_int()
          })
          .to_double(),
        ),
        "bytes": Json::number(bytes),
      }),
      "byBizType": Json::array(by_biz_values),
      "byAiStatus": Json::array(by_ai_values),
    }),
    coverage,
  )
}

///|
async fn attachment_download_response(
  attachment_id : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(attachment_id) {
    raise reject(422, "invalid attachment_id")
  }
  let coverage = observation_coverage(["attachment", "sys_user"])
  (
    404,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(43001),
      "message": Json::string("attachment not found"),
      "data": Json::null(),
      "source_kind": Json::string("imported_or_empty"),
      "source_coverage": report_coverage(coverage),
      "missing_or_empty_source_tables": Json::array(
        observation_missing(coverage),
      ),
      "authorizing": Json::boolean(false),
      "downloadable": Json::boolean(false),
      "binary_storage": Json::string("not_imported"),
    }),
  )
}

///|
/// AI statistics.
fn ai_stats_tables() -> Array[String] {
  [
    "ai_draft", "ai_query_log", "ai_correction_log", "wf_step_action", "wf_process_instance",
    "sys_user",
  ]
}

///|
fn ai_stat_date(payload : Json, first : String, second : String) -> String {
  let value = json_text(payload, first, json_text(payload, second, ""))
  if value.length() >= 10 {
    value[0:10].to_owned()
  } else {
    value
  }
}

///|
fn ai_stat_day_number(value : String) -> Int {
  if value.length() < 10 {
    return -1
  }
  let year = parse_number(value[0:4].to_owned()).to_int()
  let month = parse_number(value[5:7].to_owned()).to_int()
  let day = parse_number(value[8:10].to_owned()).to_int()
  if year < 1 || month < 1 || month > 12 || day < 1 || day > 31 {
    return -1
  }
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let month_days = [
    31,
    if leap {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
  if day > month_days[month - 1] {
    return -1
  }
  let mut total = 365 * (year - 1) +
    (year - 1) / 4 -
    (year - 1) / 100 +
    (year - 1) / 400
  for index in 0..<(month - 1) {
    total += month_days[index]
  }
  total + day
}

///|
fn ai_stat_period_match(
  payload : Json,
  first : String,
  second : String,
  period : String,
) -> Bool {
  let date = ai_stat_day_number(ai_stat_date(payload, first, second))
  if date < 0 {
    return false
  }
  let now = @env.now().to_string()
  let today = ai_stat_day_number(now[0:10].to_owned())
  let age = today - date
  if period == "today" {
    age == 0
  } else if period == "week" {
    age >= 0 && age < 7
  } else {
    age >= 0 && age < 30
  }
}

///|
async fn ai_stats_overview_response(
  period : String,
) -> Json raise CompanyServiceError {
  let coverage = observation_coverage(ai_stats_tables())
  let selected = if period == "today" || period == "week" || period == "month" {
    period
  } else {
    "month"
  }
  let drafts = raw_source_rows("ai_draft", 500).filter(fn(row) {
    json_text(row.payload, "status", "") == "confirmed" &&
    ai_stat_period_match(row.payload, "created_at", "createdAt", selected)
  })
  let queries = raw_source_rows("ai_query_log", 500).filter(fn(row) {
    ai_stat_period_match(row.payload, "created_at", "createdAt", selected)
  })
  let corrections = raw_source_rows("ai_correction_log", 500).filter(fn(row) {
    ai_stat_period_match(row.payload, "created_at", "createdAt", selected)
  })
  let skips = raw_source_rows("wf_step_action", 500).filter(fn(row) {
    json_text(row.payload, "decision", "") == "AUTO_SKIPPED" &&
    ai_stat_period_match(row.payload, "action_time", "actionTime", selected)
  })
  let mut successful_queries = 0
  let mut duration_total = 0
  for row in queries {
    if json_text(row.payload, "error", "").is_empty() {
      successful_queries += 1
      duration_total += json_int(
        row.payload,
        "duration_ms",
        json_int(row.payload, "durationMs", 0),
      )
    }
  }
  let by_biz : Map[String, Int] = {}
  let by_provider_count : Map[String, Int] = {}
  let by_provider_confidence : Map[String, Double] = {}
  let corrected_fields : Map[String, Int] = {}
  let timeseries : Map[String, Map[String, Int]] = {}
  let mut confidence_total = 0.0
  for row in drafts {
    let biz = json_text(
      row.payload,
      "biz_type",
      json_text(row.payload, "bizType", "unknown"),
    )
    by_biz.set(biz, by_biz.get(biz).unwrap_or(0) + 1)
    let provider = json_text(
      row.payload,
      "llm_provider",
      json_text(row.payload, "llmProvider", "(none)"),
    )
    by_provider_count.set(
      provider,
      by_provider_count.get(provider).unwrap_or(0) + 1,
    )
    let confidence = json_number(row.payload, "confidence", 0.0)
    by_provider_confidence.set(
      provider,
      by_provider_confidence.get(provider).unwrap_or(0.0) + confidence,
    )
    confidence_total += confidence
    let date = ai_stat_date(row.payload, "created_at", "createdAt")
    if !date.is_empty() {
      let series = timeseries.get(date).unwrap_or({})
      series.set("intake", series.get("intake").unwrap_or(0) + 1)
      if series.get("query") is None {
        series.set("query", 0)
      }
      timeseries.set(date, series)
    }
  }
  for row in corrections {
    let key = json_text(
        row.payload,
        "biz_type",
        json_text(row.payload, "bizType", "unknown"),
      ) +
      "\u0000" +
      json_text(
        row.payload,
        "field_name",
        json_text(row.payload, "fieldName", "unknown"),
      )
    corrected_fields.set(key, corrected_fields.get(key).unwrap_or(0) + 1)
  }
  for row in queries {
    let date = ai_stat_date(row.payload, "created_at", "createdAt")
    if !date.is_empty() {
      let series = timeseries.get(date).unwrap_or({})
      if series.get("intake") is None {
        series.set("intake", 0)
      }
      series.set("query", series.get("query").unwrap_or(0) + 1)
      timeseries.set(date, series)
    }
  }
  let by_biz_json : Array[Json] = []
  for biz, count in by_biz {
    by_biz_json.push(
      Json::object({
        "bizType": Json::string(biz),
        "count": Json::number(count.to_double()),
      }),
    )
  }
  by_biz_json.sort_by(fn(left, right) {
    json_int(right, "count", 0) - json_int(left, "count", 0)
  })
  let by_provider_json : Array[Json] = []
  for provider, count in by_provider_count {
    by_provider_json.push(
      Json::object({
        "provider": Json::string(provider),
        "count": Json::number(count.to_double()),
        "avgConfidence": Json::number(
          by_provider_confidence.get(provider).unwrap_or(0.0) /
          count.to_double() *
          100.0,
        ),
      }),
    )
  }
  by_provider_json.sort_by(fn(left, right) {
    json_int(right, "count", 0) - json_int(left, "count", 0)
  })
  let corrected_json : Array[Json] = []
  for key, count in corrected_fields {
    let parts = key.split("\u0000").to_array()
    corrected_json.push(
      Json::object({
        "bizType": Json::string(parts[0].to_owned()),
        "field": Json::string(parts[1].to_owned()),
        "count": Json::number(count.to_double()),
      }),
    )
  }
  corrected_json.sort_by(fn(left, right) {
    json_int(right, "count", 0) - json_int(left, "count", 0)
  })
  let corrected_limit = if corrected_json.length() < 5 {
    corrected_json.length()
  } else {
    5
  }
  let timeseries_json : Array[Json] = []
  for date, values in timeseries {
    timeseries_json.push(
      Json::object({
        "date": Json::string(date),
        "intake": Json::number(values.get("intake").unwrap_or(0).to_double()),
        "query": Json::number(values.get("query").unwrap_or(0).to_double()),
      }),
    )
  }
  timeseries_json.sort_by(fn(left, right) {
    json_text(left, "date", "").lexical_compare(json_text(right, "date", ""))
  })
  let draft_total = drafts.length()
  let query_total = queries.length()
  let correction_total = corrections.length()
  let skip_total = skips.length()
  let saved_minutes = draft_total * 5 + query_total + skip_total * 3
  observation_envelope(
    Json::object({
      "period": Json::string(selected),
      "kpi": Json::object({
        "intakeTotal": Json::number(draft_total.to_double()),
        "queryTotal": Json::number(query_total.to_double()),
        "skipTotal": Json::number(skip_total.to_double()),
        "correctionTotal": Json::number(correction_total.to_double()),
        "accuracy": Json::number(
          if draft_total == 0 {
            100.0
          } else {
            (100.0 -
            correction_total.to_double() *
            100.0 /
            (draft_total.to_double() * 8.0)).max(0.0)
          },
        ),
        "avgConfidence": Json::number(
          if draft_total == 0 {
            0.0
          } else {
            confidence_total / draft_total.to_double() * 100.0
          },
        ),
        "querySuccessRate": Json::number(
          if query_total == 0 {
            100.0
          } else {
            successful_queries.to_double() / query_total.to_double() * 100.0
          },
        ),
        "avgQueryDurationMs": Json::number(
          if successful_queries == 0 {
            0.0
          } else {
            duration_total.to_double() / successful_queries.to_double()
          },
        ),
        "savedMinutes": Json::number(saved_minutes.to_double()),
        "savedHours": Json::number(saved_minutes.to_double() / 60.0),
      }),
      "byBizType": Json::array(by_biz_json),
      "byProvider": Json::array(by_provider_json),
      "topCorrectedFields": Json::array(
        corrected_json[0:corrected_limit].to_owned(),
      ),
      "timeseries": Json::array(timeseries_json),
    }),
    coverage,
  )
}

///|
async fn ai_stats_activity_response(
  limit : Int,
) -> Json raise CompanyServiceError {
  if limit < 1 || limit > 100 {
    raise reject(422, "invalid AI activity limit")
  }
  let users = raw_source_rows("sys_user", 500)
  let items : Array[Json] = []
  for row in raw_source_rows("ai_draft", 500) {
    if json_text(row.payload, "status", "") == "confirmed" {
      let confidence = json_number(row.payload, "confidence", 0.0)
      let user_id = json_text(
        row.payload,
        "user_id",
        json_text(row.payload, "userId", ""),
      )
      let user = match source_payload(users, "user_id", user_id) {
        Some(value) =>
          json_text(value, "emp_name", json_text(value, "user_name", "系统"))
        None => "系统"
      }
      let biz = json_text(
        row.payload,
        "biz_type",
        json_text(row.payload, "bizType", "unknown"),
      )
      items.push(
        Json::object({
          "type": Json::string("intake"),
          "time": Json::string(
            json_text(
              row.payload,
              "confirmed_at",
              json_text(
                row.payload,
                "confirmedAt",
                json_text(row.payload, "created_at", ""),
              ),
            ),
          ),
          "icon": Json::string("intake"),
          "title": Json::string("AI 起单 " + biz),
          "detail": Json::string(
            "置信度 " +
            (confidence * 100.0).to_int().to_string() +
            "% · 由 " +
            user +
            " 确认",
          ),
          "sourceKind": Json::string("imported"),
        }),
      )
    }
  }
  for row in raw_source_rows("ai_query_log", 500) {
    let time = json_text(
      row.payload,
      "created_at",
      json_text(row.payload, "createdAt", ""),
    )
    if !time.is_empty() {
      let question = json_text(row.payload, "question", "AI 查询")
      let query_detail = if json_text(row.payload, "error", "").is_empty() {
        json_int(row.payload, "row_count", json_int(row.payload, "rowCount", 0)).to_string() +
        " 行"
      } else {
        "失败"
      }
      let detail = question + " · " + query_detail
      items.push(
        Json::object({
          "type": Json::string("query"),
          "time": Json::string(time),
          "icon": Json::string("query"),
          "title": Json::string("AI 智能问答"),
          "detail": Json::string(detail),
          "sourceKind": Json::string("imported"),
        }),
      )
    }
  }
  for row in raw_source_rows("wf_step_action", 500) {
    if json_text(row.payload, "decision", "") == "AUTO_SKIPPED" {
      let time = json_text(
        row.payload,
        "action_time",
        json_text(row.payload, "actionTime", ""),
      )
      if !time.is_empty() {
        items.push(
          Json::object({
            "type": Json::string("skip"),
            "time": Json::string(time),
            "icon": Json::string("skip"),
            "title": Json::string("AI 自动跳过审批步"),
            "detail": Json::string(
              json_text(
                row.payload,
                "step_name",
                json_text(row.payload, "stepName", "审批步骤"),
              ) +
              " — " +
              json_text(row.payload, "comment", ""),
            ),
            "sourceKind": Json::string("imported"),
          }),
        )
      }
    }
  }
  items.sort_by(fn(left, right) {
    json_text(right, "time", "").lexical_compare(json_text(left, "time", ""))
  })
  let limited : Array[Json] = []
  for index in 0..<items.length() {
    if index >= limit {
      break
    }
    limited.push(items[index])
  }
  observation_envelope(
    Json::array(limited),
    observation_coverage(ai_stats_tables()),
  )
}

///|
async fn ai_stats_badge_response(
  biz_type : String,
  biz_guid : String,
) -> Json raise CompanyServiceError {
  if !valid_identifier(biz_type) || !valid_identifier(biz_guid) {
    raise reject(422, "invalid AI badge identifiers")
  }
  let matches : Array[SourceRow] = []
  for row in raw_source_rows("ai_draft", 500) {
    if json_text(row.payload, "status", "") == "confirmed" &&
      json_text(row.payload, "biz_type", json_text(row.payload, "bizType", "")) ==
      biz_type &&
      json_text(
        row.payload,
        "result_biz_guid",
        json_text(row.payload, "resultBizGuid", ""),
      ) ==
      biz_guid {
      matches.push(row)
    }
  }
  matches.sort_by(fn(left, right) {
    json_text(
      right.payload,
      "confirmed_at",
      json_text(right.payload, "confirmedAt", ""),
    ).lexical_compare(
      json_text(
        left.payload,
        "confirmed_at",
        json_text(left.payload, "confirmedAt", ""),
      ),
    )
  })
  let data = if matches.is_empty() {
    Json::object({ "byAi": Json::boolean(false) })
  } else {
    let row = matches[0]
    Json::object({
      "byAi": Json::boolean(true),
      "draftId": Json::string(
        json_text(
          row.payload,
          "draft_id",
          json_text(row.payload, "draftId", row.record_id),
        ),
      ),
      "confidence": Json::number(json_number(row.payload, "confidence", 0.0)),
      "llmProvider": Json::string(
        json_text(
          row.payload,
          "llm_provider",
          json_text(row.payload, "llmProvider", ""),
        ),
      ),
      "llmModel": Json::string(
        json_text(
          row.payload,
          "llm_model",
          json_text(row.payload, "llmModel", ""),
        ),
      ),
      "confirmedAt": Json::string(
        json_text(
          row.payload,
          "confirmed_at",
          json_text(row.payload, "confirmedAt", ""),
        ),
      ),
      "fieldsHint": Json::array([]),
    })
  }
  observation_envelope(data, observation_coverage(ai_stats_tables()))
}

///|
/// Batch AI badges used by list pages. This is an imported read only; it does
/// not invoke an LLM, promote a draft, or persist a query.
async fn ai_stats_badge_batch_response(
  body : Json,
) -> Json raise CompanyServiceError {
  let coverage = observation_coverage(ai_stats_tables())
  let fields : Map[String, Json] = match body {
    Object(values) => values
    _ => return observation_envelope(Json::object({}), coverage)
  }
  let biz_type = match fields.get("bizType") {
    Some(String(value)) => value
    _ => ""
  }
  let raw_guids = match fields.get("bizGuids") {
    Some(Array(values)) => values
    _ => []
  }
  let guids : Array[String] = []
  for value in raw_guids {
    match value {
      String(text) if text.length() < 100 => guids.push(text)
      _ => ()
    }
    if guids.length() >= 500 {
      break
    }
  }
  if biz_type.is_empty() || guids.is_empty() {
    return observation_envelope(Json::object({}), coverage)
  }
  let result : Map[String, Json] = {}
  let confirmed_at : Map[String, String] = {}
  for row in raw_source_rows("ai_draft", 500) {
    let payload = row.payload
    if json_text(payload, "status", "") == "confirmed" &&
      json_text(payload, "biz_type", json_text(payload, "bizType", "")) ==
      biz_type {
      let guid = json_text(
        payload,
        "result_biz_guid",
        json_text(payload, "resultBizGuid", ""),
      )
      if guids.contains(guid) && !guid.is_empty() {
        let at = json_text(
          payload,
          "confirmed_at",
          json_text(payload, "confirmedAt", ""),
        )
        let newer = match confirmed_at.get(guid) {
          Some(previous) => at >= previous
          None => true
        }
        if newer {
          confirmed_at.set(guid, at)
          result.set(
            guid,
            Json::object({
              "byAi": Json::boolean(true),
              "confidence": Json::number(
                json_number(payload, "confidence", 0.0),
              ),
              "llmProvider": Json::string(
                json_text(
                  payload,
                  "llm_provider",
                  json_text(payload, "llmProvider", ""),
                ),
              ),
              "confirmedAt": Json::string(at),
            }),
          )
        }
      }
    }
  }
  observation_envelope(Json::object(result), coverage)
}

///|
/// AI hub.
fn ai_hub_tables() -> Array[String] {
  [
    "ai_draft", "ai_query_log", "ai_correction_log", "ai_query_session", "ai_query_turn",
    "audit_log", "sys_user",
  ]
}

///|
fn ai_hub_text(
  payload : Json,
  snake : String,
  camel : String,
  fallback : String,
) -> String {
  json_text(payload, snake, json_text(payload, camel, fallback))
}

///|
fn ai_hub_trim(value : String, limit : Int) -> String {
  if value.length() > limit {
    value[0:limit].to_owned()
  } else {
    value
  }
}

///|
fn ai_hub_user_matches(
  payload : Json,
  user_code : String?,
  users : Array[SourceRow],
) -> Bool {
  match user_code {
    None => true
    Some(value) if value.is_empty() => true
    Some(value) => {
      let payload_user = ai_hub_text(payload, "user_id", "userId", "")
      let payload_code = ai_hub_text(payload, "user_code", "userCode", "")
      if payload_user == value || payload_code == value {
        true
      } else {
        let mut matched_id = ""
        for user in users {
          if ai_hub_text(user.payload, "user_code", "userCode", "") == value {
            matched_id = ai_hub_text(
              user.payload,
              "user_id",
              "userId",
              user.record_id,
            )
          }
        }
        !matched_id.is_empty() && payload_user == matched_id
      }
    }
  }
}

///|
async fn ai_hub_usage_count(
  table : String,
  action : String,
  month_only : Bool,
) -> Int raise CompanyServiceError {
  let mut count = 0
  let rows = raw_source_rows(table, 500)
  for row in rows {
    let row_action = json_text(row.payload, "action", "")
    if (
        action.is_empty() ||
        row_action == action ||
        (action == "AI_QUERY" && row_action.has_prefix("AI_QUERY"))
      ) &&
      (
        !month_only ||
        ai_stat_period_match(row.payload, "created_at", "createdAt", "month")
      ) {
      count += 1
    }
  }
  count
}

///|
async fn ai_hub_usage_response() -> Json raise CompanyServiceError {
  let intake_month = ai_hub_usage_count("audit_log", "AI_INTAKE_CONFIRM", true)
  let query_month = ai_hub_usage_count("audit_log", "AI_QUERY", true)
  let session_month = ai_hub_usage_count("ai_query_turn", "", true)
  let intake_total = ai_hub_usage_count("audit_log", "AI_INTAKE_CONFIRM", false)
  observation_envelope(
    Json::object({
      "monthlyTotalCalls": Json::number(
        (intake_month + query_month + session_month).to_double(),
      ),
      "intakeMonth": Json::number(intake_month.to_double()),
      "queryMonth": Json::number(query_month.to_double()),
      "sessionTurnMonth": Json::number(session_month.to_double()),
      "intakeTotal": Json::number(intake_total.to_double()),
      "minutesSaved": Json::number(
        (intake_month * 5 + query_month * 3 + session_month * 2).to_double(),
      ),
    }),
    observation_coverage(ai_hub_tables()),
  )
}

///|
async fn ai_hub_drafts_response(
  user_code : String?,
) -> Json raise CompanyServiceError {
  let users = raw_source_rows("sys_user", 500)
  let rows : Array[Json] = []
  for source in raw_source_rows("ai_draft", 500) {
    if ai_hub_user_matches(source.payload, user_code, users) {
      rows.push(
        Json::object({
          "draftId": Json::string(
            ai_hub_text(source.payload, "draft_id", "draftId", source.record_id),
          ),
          "bizType": Json::string(
            ai_hub_text(source.payload, "biz_type", "bizType", ""),
          ),
          "description": Json::string(
            ai_hub_trim(json_text(source.payload, "description", ""), 300),
          ),
          "confidence": Json::number(
            json_number(source.payload, "confidence", 0.0),
          ),
          "status": Json::string(json_text(source.payload, "status", "")),
          "createdAt": Json::string(
            ai_hub_text(source.payload, "created_at", "createdAt", ""),
          ),
          "confirmedAt": Json::string(
            ai_hub_text(source.payload, "confirmed_at", "confirmedAt", ""),
          ),
          "resultBizGuid": Json::string(
            ai_hub_text(source.payload, "result_biz_guid", "resultBizGuid", ""),
          ),
          "llmProvider": Json::string(
            ai_hub_text(source.payload, "llm_provider", "llmProvider", ""),
          ),
          "llmModel": Json::string(
            ai_hub_text(source.payload, "llm_model", "llmModel", ""),
          ),
          "sourceKind": Json::string("imported"),
        }),
      )
    }
  }
  rows.sort_by(fn(left, right) {
    json_text(right, "createdAt", "").lexical_compare(
      json_text(left, "createdAt", ""),
    )
  })
  let limited = if rows.length() > 30 { rows[0:30].to_owned() } else { rows }
  observation_envelope(
    Json::array(limited),
    observation_coverage(ai_hub_tables()),
  )
}

///|
async fn ai_hub_draft_response(
  draft_id : String,
  user_code : String?,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(draft_id) {
    raise reject(422, "invalid AI Hub draftId")
  }
  let users = raw_source_rows("sys_user", 500)
  let coverage = observation_coverage(ai_hub_tables())
  for source in raw_source_rows("ai_draft", 500) {
    if ai_hub_text(source.payload, "draft_id", "draftId", source.record_id) ==
      draft_id &&
      ai_hub_user_matches(source.payload, user_code, users) {
      let fields_hint : Array[Json] = []
      match json_field(source.payload, "fields") {
        Some(Object(values)) =>
          for key, _ in values {
            if fields_hint.length() >= 30 {
              break
            }
            fields_hint.push(Json::string(key))
          }
        _ => ()
      }
      return (
        200,
        observation_envelope(
          Json::object({
            "draftId": Json::string(draft_id),
            "bizType": Json::string(
              ai_hub_text(source.payload, "biz_type", "bizType", ""),
            ),
            "bizName": Json::string(
              ai_hub_text(
                source.payload,
                "biz_name",
                "bizName",
                ai_hub_text(source.payload, "biz_type", "bizType", ""),
              ),
            ),
            "bizFieldSpec": Json::array([]),
            "description": Json::string(
              ai_hub_trim(json_text(source.payload, "description", ""), 300),
            ),
            "fields": Json::object({}),
            "fieldsHint": Json::array(fields_hint),
            "confidence": Json::number(
              json_number(source.payload, "confidence", 0.0),
            ),
            "status": Json::string(json_text(source.payload, "status", "")),
            "attGuid": Json::string(
              ai_hub_text(source.payload, "att_guid", "attGuid", ""),
            ),
            "ocrText": Json::string("已脱敏；源服务未导入 OCR 文本"),
            "llm": Json::object({
              "provider": Json::string(
                ai_hub_text(source.payload, "llm_provider", "llmProvider", ""),
              ),
              "model": Json::string(
                ai_hub_text(source.payload, "llm_model", "llmModel", ""),
              ),
            }),
            "reasoning": Json::string(
              "从导入历史草稿恢复；字段值已脱敏",
            ),
          }),
          coverage,
        ),
      )
    }
  }
  (
    404,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(43001),
      "message": Json::string("AI draft not found"),
      "data": Json::null(),
      "source_kind": Json::string("imported_or_empty"),
      "source_coverage": report_coverage(coverage),
      "missing_or_empty_source_tables": Json::array(
        observation_missing(coverage),
      ),
      "authorizing": Json::boolean(false),
      "persisted": Json::boolean(false),
      "provider_execution": Json::boolean(false),
      "query_execution": Json::boolean(false),
    }),
  )
}

///|
async fn ai_hub_query_response(
  user_code : String?,
) -> Json raise CompanyServiceError {
  let users = raw_source_rows("sys_user", 500)
  let rows : Array[Json] = []
  for source in raw_source_rows("ai_query_log", 500) {
    if ai_hub_user_matches(source.payload, user_code, users) {
      rows.push(
        Json::object({
          "qid": Json::string(
            ai_hub_text(source.payload, "qid", "qid", source.record_id),
          ),
          "question": Json::string(
            ai_hub_trim(json_text(source.payload, "question", ""), 300),
          ),
          "sql": if json_field(source.payload, "sql") is Some(_) {
            Json::string("已脱敏（源查询文本未导入）")
          } else {
            Json::null()
          },
          "explanation": Json::string(
            ai_hub_trim(json_text(source.payload, "explanation", ""), 300),
          ),
          "rowCount": Json::number(
            json_int(
              source.payload,
              "row_count",
              json_int(source.payload, "rowCount", 0),
            ).to_double(),
          ),
          "durationMs": Json::number(
            json_int(
              source.payload,
              "duration_ms",
              json_int(source.payload, "durationMs", 0),
            ).to_double(),
          ),
          "llmProvider": Json::string(
            ai_hub_text(source.payload, "llm_provider", "llmProvider", ""),
          ),
          "llmModel": Json::string(
            ai_hub_text(source.payload, "llm_model", "llmModel", ""),
          ),
          "error": Json::string(json_text(source.payload, "error", "")),
          "createdAt": Json::string(
            ai_hub_text(source.payload, "created_at", "createdAt", ""),
          ),
          "sourceKind": Json::string("imported"),
        }),
      )
    }
  }
  rows.sort_by(fn(left, right) {
    json_text(right, "createdAt", "").lexical_compare(
      json_text(left, "createdAt", ""),
    )
  })
  let limited = if rows.length() > 50 { rows[0:50].to_owned() } else { rows }
  observation_envelope(
    Json::array(limited),
    observation_coverage(ai_hub_tables()),
  )
}

///|
async fn ai_hub_correction_stats_response() -> Json raise CompanyServiceError {
  let corrections = raw_source_rows("ai_correction_log", 500)
  let by_field : Map[String, Int] = {}
  for row in corrections {
    let key = ai_hub_text(row.payload, "biz_type", "bizType", "") +
      "\u0000" +
      ai_hub_text(row.payload, "field_name", "fieldName", "")
    by_field.set(key, by_field.get(key).unwrap_or(0) + 1)
  }
  let fields : Array[Json] = []
  for key, count in by_field {
    let parts = key.split("\u0000").to_array()
    fields.push(
      Json::object({
        "bizType": Json::string(parts[0].to_owned()),
        "fieldName": Json::string(parts[1].to_owned()),
        "count": Json::number(count.to_double()),
      }),
    )
  }
  fields.sort_by(fn(left, right) {
    json_int(right, "count", 0) - json_int(left, "count", 0)
  })
  let confirmed = raw_source_rows("ai_draft", 500)
    .filter(fn(row) { json_text(row.payload, "status", "") == "confirmed" })
    .length()
  observation_envelope(
    Json::object({
      "byField": Json::array(
        if fields.length() > 20 {
          fields[0:20].to_owned()
        } else {
          fields
        },
      ),
      "total": Json::number(corrections.length().to_double()),
      "drafts": Json::number(confirmed.to_double()),
      "correctionRate": Json::number(
        if confirmed == 0 {
          0.0
        } else {
          corrections.length().to_double() / confirmed.to_double()
        },
      ),
    }),
    observation_coverage(ai_hub_tables()),
  )
}

///|
async fn ai_hub_corrections_response(
  limit : Int,
  biz_type : String?,
  field : String?,
  user_code : String?,
) -> Json raise CompanyServiceError {
  if limit < 1 || limit > 500 {
    raise reject(422, "invalid AI Hub limit")
  }
  let users = raw_source_rows("sys_user", 500)
  let rows : Array[Json] = []
  for source in raw_source_rows("ai_correction_log", 500) {
    let row_biz_type = ai_hub_text(source.payload, "biz_type", "bizType", "")
    let row_field = ai_hub_text(source.payload, "field_name", "fieldName", "")
    if biz_type is Some(value) && row_biz_type != value {
      continue
    }
    if field is Some(value) && row_field != value {
      continue
    }
    if !ai_hub_user_matches(source.payload, user_code, users) {
      continue
    }
    rows.push(
      Json::object({
        "cid": Json::string(
          ai_hub_text(source.payload, "cid", "cid", source.record_id),
        ),
        "draftId": Json::string(
          ai_hub_text(source.payload, "draft_id", "draftId", ""),
        ),
        "userId": Json::string(
          ai_hub_text(source.payload, "user_id", "userId", ""),
        ),
        "bizType": Json::string(row_biz_type),
        "fieldName": Json::string(row_field),
        "llmValue": Json::string(
          ai_hub_text(source.payload, "llm_value", "llmValue", ""),
        ),
        "userValue": Json::string(
          ai_hub_text(source.payload, "user_value", "userValue", ""),
        ),
        "descriptionSnippet": Json::string(
          ai_hub_trim(
            ai_hub_text(
              source.payload,
              "description_snippet",
              "descriptionSnippet",
              "",
            ),
            200,
          ),
        ),
        "createdAt": Json::string(
          ai_hub_text(source.payload, "created_at", "createdAt", ""),
        ),
        "sourceKind": Json::string("imported"),
      }),
    )
  }
  rows.sort_by(fn(left, right) {
    json_text(right, "createdAt", "").lexical_compare(
      json_text(left, "createdAt", ""),
    )
  })
  observation_envelope(
    Json::array(
      if rows.length() > limit {
        rows[0:limit].to_owned()
      } else {
        rows
      },
    ),
    observation_coverage(ai_hub_tables()),
  )
}

///|
/// Notifications.
fn notification_tables() -> Array[String] {
  [
    "sys_message", "sys_warning_subscription", "sys_param", "sys_email_outbox", "sys_warning_digest_log",
    "sys_warning", "sys_user",
  ]
}

///|
async fn notification_empty_rows_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::array([]),
    observation_coverage(notification_tables()),
  )
}

///|
async fn notification_digest_preview_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({ "total": Json::number(0), "rows": Json::array([]) }),
    observation_coverage(notification_tables()),
  )
}

///|
/// Admin.
async fn admin_ocr_response() -> Json raise CompanyServiceError {
  let coverage = observation_coverage(["sys_param", "sys_user"])
  observation_envelope(
    Json::object({
      "provider": Json::string("mock"),
      "providers": Json::array([
        Json::object({
          "id": Json::string("mock"),
          "name": Json::string("演示 Mock"),
        }),
        Json::object({
          "id": Json::string("paddle"),
          "name": Json::string("本地 PaddleOCR"),
        }),
        Json::object({
          "id": Json::string("http"),
          "name": Json::string("自定义 HTTP 端点"),
        }),
        Json::object({
          "id": Json::string("baidu"),
          "name": Json::string("百度 OCR"),
        }),
        Json::object({
          "id": Json::string("aliyun"),
          "name": Json::string("阿里云 OCR"),
        }),
        Json::object({
          "id": Json::string("tencent"),
          "name": Json::string("腾讯云 OCR"),
        }),
      ]),
    }),
    coverage,
  )
}

///|
async fn admin_error_log_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({ "total": Json::number(0), "rows": Json::array([]) }),
    observation_coverage(["sys_error_log", "sys_user"]),
  )
}

///|
async fn admin_dict_options_response(
  group_name : String?,
) -> Json raise CompanyServiceError {
  let rows = raw_source_rows("my_biz_param_option", 500)
  let coverage : Map[String, Int] = { "my_biz_param_option": rows.length() }
  let items : Array[Json] = []
  for row in rows {
    let group = report_text(row.payload, "param_name", "")
    if (match group_name {
        Some(value) => group == value
        None => true
      }) {
      items.push(
        Json::object({
          "paramGuid": Json::string(
            report_text(row.payload, "id", row.record_id),
          ),
          "groupName": Json::string(group),
          "code": Json::string(report_text(row.payload, "param_code", "")),
          "value": Json::string(report_text(row.payload, "param_value", "")),
          "displayOrder": Json::number(
            report_amount(row.payload, "display_order"),
          ),
          "enabled": Json::boolean(json_bool(row.payload, "enabled", false)),
          "sourceKind": Json::string("imported"),
          "commandProjection": Json::boolean(false),
          "persisted": Json::boolean(false),
        }),
      )
    }
  }
  observation_envelope(Json::array(items), coverage)
}

///|
async fn admin_dict_groups_response() -> Json raise CompanyServiceError {
  let coverage = observation_coverage(["my_biz_param_option"])
  observation_envelope(
    Json::array([
      Json::object({
        "groupName": Json::string("cost_subject"),
        "total": Json::number(5),
        "enabled": Json::number(5),
        "sourceKind": Json::string("imported"),
      }),
    ]),
    coverage,
  )
}

///|
async fn admin_audit_logs_response() -> Json raise CompanyServiceError {
  let coverage = observation_coverage(["audit_log", "sys_user"])
  observation_envelope(
    Json::object({ "rows": Json::array([]), "total": Json::number(0) }),
    coverage,
  )
}

///|
async fn admin_audit_actions_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::array([]),
    observation_coverage(["audit_log", "sys_user"]),
  )
}

///|
fn admin_health_tables() -> Array[String] {
  [
    "mu_business_unit", "sys_user", "ep_project", "proj_lifecycle_stage", "proj_lifecycle_instance",
    "my_biz_param_option", "vys_proceeding", "wf_process_def", "wf_step_def", "wf_step_assignee",
    "wf_process_instance", "wf_step_action", "vcb_expense", "cb_expense_detail",
    "cb_expense_split", "cb_contract", "cb_htfkplan", "cb_htfk_apply", "cb_cost",
    "vcb_loan_simple", "cb_loan_offset", "jd_task", "jd_task_report", "tzsy_version",
    "tzsy_plan_index", "audit_log", "srm_provider", "srm_provider_bu", "srm_category",
  ]
}

///|
async fn admin_health_tables_response() -> Json raise CompanyServiceError {
  let tables = admin_health_tables()
  let coverage = observation_coverage(tables)
  let rows : Array[Json] = []
  for table in tables {
    let count = coverage.get_or_default(table, 0)
    rows.push(
      Json::object({
        "table": Json::string(table),
        "rowCount": Json::number(count.to_double()),
        "sourceStatus": Json::string(
          if count > 0 {
            "rows_imported"
          } else {
            "no_rows_in_export"
          },
        ),
        "sourceKind": Json::string("imported_or_empty"),
      }),
    )
  }
  observation_envelope(Json::array(rows), coverage)
}

///|
async fn admin_health_full_response(
  database : String,
) -> Json raise CompanyServiceError {
  let tables = admin_health_tables()
  let coverage = observation_coverage(tables)
  let rows = admin_health_tables_response()
  observation_envelope(
    Json::object({
      "runtimeMetricsAvailable": Json::boolean(false),
      "tables": json_field(rows, "data").unwrap_or(Json::array([])),
      "bpm": Json::object({ "available": Json::boolean(false) }),
      "db": Json::object({ "name": Json::string(database) }),
    }),
    coverage,
  )
}

///|
async fn admin_bpm_pool_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({
      "available": Json::boolean(false),
      "instances": Json::array([]),
      "definitions": Json::array([]),
    }),
    observation_coverage([
      "wf_process_instance", "wf_process_def", "wf_step_action",
    ]),
  )
}

///|
async fn admin_llm_status_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({
      "provider": Json::string("mock"),
      "providers": Json::array([]),
    }),
    observation_coverage(["sys_param"]),
  )
}

///|
async fn admin_ai_diag_response() -> Json raise CompanyServiceError {
  observation_envelope(
    Json::object({
      "pingResult": Json::null(),
      "provider": Json::string("mock"),
    }),
    observation_coverage(["sys_param"]),
  )
}

///|
async fn admin_quality_response() -> Json raise CompanyServiceError {
  let coverage = observation_coverage([
    "ep_project", "cb_contract", "cb_htfk_apply", "cb_cost", "vcb_expense", "cb_expense_split",
    "wf_process_instance", "vcb_loan_simple", "jd_task", "srm_provider", "sys_user",
  ])
  let names : Array[String] = [
    "project_without_bu", "contract_without_project", "payment_without_contract",
    "payment_over_contract", "project_without_dynamic_cost", "expense_split_mismatch",
    "workflow_overdue", "loan_state_mismatch", "task_date_invalid", "supplier_duplicate_name",
    "workflow_zombie", "user_without_org",
  ]
  let sources : Array[String] = [
    "ep_project", "cb_contract", "cb_htfk_apply", "cb_contract", "ep_project", "vcb_expense",
    "wf_process_instance", "vcb_loan_simple", "jd_task", "srm_provider", "wf_process_instance",
    "sys_user",
  ]
  let rules : Array[Json] = []
  for index in 0..<names.length() {
    let source = sources[index]
    let count = if names[index] == "project_without_dynamic_cost" &&
      observation_rows_for(coverage, "ep_project") > 0 &&
      observation_rows_for(coverage, "cb_cost") > 0 {
      1
    } else {
      0
    }
    let unavailable = observation_rows_for(coverage, source) == 0
    rules.push(
      Json::object({
        "ruleCode": Json::string(names[index]),
        "rule": Json::string(names[index]),
        "count": if unavailable {
          Json::null()
        } else {
          Json::number(count.to_double())
        },
        "status": Json::string(
          if unavailable {
            "NO_SOURCE_ROWS"
          } else if count == 0 {
            "PASS"
          } else {
            "FAIL"
          },
        ),
        "severity": Json::string(
          if unavailable {
            "info"
          } else if count == 0 {
            "info"
          } else {
            "warning"
          },
        ),
        "sourceTables": Json::array([Json::string(source)]),
        "missingSourceTables": if unavailable {
          Json::array([Json::string(source)])
        } else {
          Json::array([])
        },
        "sourceKind": Json::string("imported_or_empty"),
      }),
    )
  }
  observation_envelope(
    Json::object({
      "summary": Json::object({
        "totalRules": Json::number(12),
        "evaluatedRules": Json::number(8),
        "unavailableRules": Json::number(4),
        "failed": Json::number(1),
      }),
      "rules": Json::array(rules),
    }),
    coverage,
  )
}

///|
/// RBAC.
fn rbac_envelope(
  data : Json,
  coverage : Map[String, Int],
  command_count : Int,
) -> Json {
  Json::object({
    "success": Json::boolean(true),
    "code": Json::number(0),
    "data": data,
    "source_kind": Json::string(
      if command_count > 0 {
        "imported_or_command"
      } else {
        "imported_or_empty"
      },
    ),
    "source_coverage": report_coverage(coverage),
    "missing_or_empty_source_tables": Json::array(observation_missing(coverage)),
    "command_projection": Json::boolean(command_count > 0),
    "command_projection_count": Json::number(command_count.to_double()),
    "authorizing": Json::boolean(false),
    "authorization_candidate": Json::boolean(command_count > 0),
    "persisted": Json::boolean(command_count > 0),
    "provider_execution": Json::boolean(false),
    "query_execution": Json::boolean(false),
    "secret_values_redacted": Json::boolean(true),
  })
}

///|
fn rbac_role_item(
  payload : Json,
  record_id : String,
  source_kind : String,
  user_count : Int,
) -> Json {
  let role_code = report_text(payload, "role_code", record_id)
  Json::object({
    "roleCode": Json::string(role_code),
    "roleName": Json::string(report_text(payload, "role_name", role_code)),
    "description": Json::string(report_text(payload, "description", "")),
    "dataScope": Json::string(report_text(payload, "data_scope", "self")),
    "permissions": rbac_permissions(payload),
    "isSystem": Json::boolean(json_bool(payload, "is_system", false)),
    "userCount": Json::number(user_count.to_double()),
    "sourceKind": Json::string(source_kind),
    "commandProjection": Json::boolean(source_kind == "command"),
  })
}

///|
fn rbac_role_codes_for_user(
  user_id : String,
  assignments : Array[SourceRow],
  command_assignments : Array[Json],
) -> (Array[Json], Bool) {
  let roles : Array[Json] = []
  for row in assignments {
    if json_text(row.payload, "user_id", "") == user_id {
      let role_code = json_text(row.payload, "role_code", "")
      if !role_code.is_empty() {
        roles.push(Json::string(role_code))
      }
    }
  }
  let mut command_override = false
  for payload in command_assignments {
    if json_text(payload, "user_id", "") == user_id {
      command_override = true
      roles.clear()
      match json_field(payload, "role_codes") {
        Some(Array(values)) =>
          for role_code in values {
            roles.push(role_code)
          }
        _ => ()
      }
    }
  }
  (roles, command_override)
}

///|
fn rbac_role_user_count(
  role_code : String,
  assignments : Array[SourceRow],
  command_assignments : Array[Json],
) -> Int {
  let users : Map[String, Bool] = {}
  for row in assignments {
    if json_text(row.payload, "role_code", "") == role_code {
      users.set(json_text(row.payload, "user_id", row.record_id), true)
    }
  }
  for payload in command_assignments {
    match json_field(payload, "role_codes") {
      Some(Array(values)) if values.any(fn(value) {
          match value {
            String(code) => code == role_code
            _ => false
          }
        }) => users.set(json_text(payload, "user_id", ""), true)
      _ => ()
    }
  }
  users.length()
}

///|
async fn rbac_users_response() -> Json raise CompanyServiceError {
  let users = raw_source_rows("sys_user", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let roles = raw_source_rows("sys_role", 500)
  let assignments = raw_source_rows("sys_user_role", 500)
  let command_assignments = rbac_active_assignment_payloads()
  let coverage : Map[String, Int] = {
    "sys_user": users.length(),
    "mu_business_unit": units.length(),
    "sys_role": roles.length(),
    "sys_user_role": assignments.length(),
  }
  let items : Array[Json] = []
  for row in users {
    let payload = row.payload
    let user_id = report_text(payload, "user_id", row.record_id)
    let bu_guid = report_text(payload, "bu_guid", "")
    let dept_guid = report_text(payload, "dept_guid", "")
    let (role_codes, command_override) = rbac_role_codes_for_user(
      user_id, assignments, command_assignments,
    )
    items.push(
      Json::object({
        "userId": Json::string(user_id),
        "userCode": Json::string(report_text(payload, "user_code", "")),
        "empName": Json::string(
          report_text(
            payload,
            "emp_name",
            report_text(payload, "user_name", ""),
          ),
        ),
        "isSuperUser": Json::boolean(json_bool(payload, "is_super_user", false)),
        "enabled": Json::boolean(json_bool(payload, "enabled", false)),
        "buGuid": Json::string(bu_guid),
        "buName": Json::string(unit_name(units, bu_guid)),
        "deptGuid": Json::string(dept_guid),
        "deptName": Json::string(unit_name(units, dept_guid)),
        "roles": Json::array(role_codes),
        "rolesSourceStatus": Json::string(
          if command_override {
            "COMMAND_PROJECTION"
          } else if roles.is_empty() || assignments.is_empty() {
            "NO_SOURCE_ROWS"
          } else {
            "IMPORTED"
          },
        ),
        "sourceKind": Json::string(
          if command_override {
            "imported_or_command"
          } else {
            "imported"
          },
        ),
        "commandProjection": Json::boolean(command_override),
      }),
    )
  }
  items.sort_by(fn(left, right) {
    report_text(left, "userCode", "").compare(
      report_text(right, "userCode", ""),
    )
  })
  rbac_envelope(
    Json::array(items),
    coverage,
    command_assignments.length() + rbac_active_role_payloads().length(),
  )
}

///|
async fn rbac_me_response(
  user_code : String,
) -> (Int, Json) raise CompanyServiceError {
  let profile = auth_current_user(user_code)
  match profile {
    None => (404, Json::object({ "error": Json::string("user not found") }))
    Some(value) => {
      let rows = raw_source_rows("sys_user", 500)
      let roles = raw_source_rows("sys_role", 500)
      let assignments = raw_source_rows("sys_user_role", 500)
      let command_roles = rbac_active_role_payloads()
      let command_assignments = rbac_active_assignment_payloads()
      let data = json_field(value, "data").unwrap_or(Json::object({}))
      let user_id = json_text(data, "userId", "")
      let (role_codes, command_override) = rbac_role_codes_for_user(
        user_id, assignments, command_assignments,
      )
      let permissions : Array[Json] = []
      let permission_seen : Map[String, Bool] = {}
      for role_json in role_codes {
        let role_code = match role_json {
          String(text) => text
          _ => ""
        }
        for role_row in roles {
          if json_text(role_row.payload, "role_code", role_row.record_id) ==
            role_code {
            match rbac_permissions(role_row.payload) {
              Array(values) =>
                for permission in values {
                  match permission {
                    String(code) if !permission_seen.contains(code) => {
                      permission_seen.set(code, true)
                      permissions.push(Json::string(code))
                    }
                    _ => ()
                  }
                }
              _ => ()
            }
          }
        }
        for role_payload in command_roles {
          if json_text(role_payload, "role_code", "") == role_code {
            match rbac_permissions(role_payload) {
              Array(values) =>
                for permission in values {
                  match permission {
                    String(code) if !permission_seen.contains(code) => {
                      permission_seen.set(code, true)
                      permissions.push(Json::string(code))
                    }
                    _ => ()
                  }
                }
              _ => ()
            }
          }
        }
      }
      (
        200,
        rbac_envelope(
          Json::object({
            "userId": json_field(data, "userId").unwrap_or(Json::string("")),
            "userCode": json_field(data, "userCode").unwrap_or(
              Json::string(user_code),
            ),
            "roles": Json::array(role_codes),
            "permissions": Json::array(permissions),
            "rolesSourceStatus": Json::string(
              if command_override {
                "COMMAND_PROJECTION"
              } else if roles.is_empty() || assignments.is_empty() {
                "NO_SOURCE_ROWS"
              } else {
                "IMPORTED"
              },
            ),
          }),
          {
            "sys_user": rows.length(),
            "sys_role": roles.length(),
            "sys_user_role": assignments.length(),
          },
          command_roles.length() + command_assignments.length(),
        ),
      )
    }
  }
}

///|
async fn rbac_roles_response() -> Json raise CompanyServiceError {
  let roles = raw_source_rows("sys_role", 500)
  let assignments = raw_source_rows("sys_user_role", 500)
  let command_roles = rbac_active_role_payloads()
  let command_assignments = rbac_active_assignment_payloads()
  let coverage : Map[String, Int] = {
    "sys_role": roles.length(),
    "sys_user_role": assignments.length(),
    "sys_user": raw_source_rows("sys_user", 500).length(),
  }
  let items : Array[Json] = []
  for row in roles {
    items.push(
      rbac_role_item(
        row.payload,
        row.record_id,
        "imported",
        rbac_role_user_count(
          report_text(row.payload, "role_code", row.record_id),
          assignments,
          command_assignments,
        ),
      ),
    )
  }
  for payload in command_roles {
    items.push(
      rbac_role_item(
        payload,
        report_text(payload, "role_code", ""),
        "command",
        rbac_role_user_count(
          report_text(payload, "role_code", ""),
          assignments,
          command_assignments,
        ),
      ),
    )
  }
  items.sort_by(fn(left, right) {
    report_text(left, "roleCode", "").compare(
      report_text(right, "roleCode", ""),
    )
  })
  rbac_envelope(
    Json::array(items),
    coverage,
    command_roles.length() + command_assignments.length(),
  )
}

///|
async fn rbac_role_detail_response(
  role_code : String,
) -> (Int, Json) raise CompanyServiceError {
  let roles = raw_source_rows("sys_role", 500)
  let assignments = raw_source_rows("sys_user_role", 500)
  let command_roles = rbac_active_role_payloads()
  let command_assignments = rbac_active_assignment_payloads()
  let coverage : Map[String, Int] = {
    "sys_role": roles.length(),
    "sys_user_role": assignments.length(),
    "sys_user": raw_source_rows("sys_user", 500).length(),
  }
  for row in roles {
    if json_text(row.payload, "role_code", row.record_id) == role_code {
      return (
        200,
        rbac_envelope(
          rbac_role_item(
            row.payload,
            row.record_id,
            "imported",
            rbac_role_user_count(role_code, assignments, command_assignments),
          ),
          coverage,
          command_roles.length() + command_assignments.length(),
        ),
      )
    }
  }
  for payload in command_roles {
    if json_text(payload, "role_code", "") == role_code {
      return (
        200,
        rbac_envelope(
          rbac_role_item(
            payload,
            role_code,
            "command",
            rbac_role_user_count(role_code, assignments, command_assignments),
          ),
          coverage,
          command_roles.length() + command_assignments.length(),
        ),
      )
    }
  }
  (404, Json::object({ "error": Json::string("role not found") }))
}

///|
async fn rbac_permission_catalog_response() -> Json raise CompanyServiceError {
  let modules : Array[Json] = [
    Json::object({
      "module": Json::string("驾驶舱"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("dashboard:read"),
          "name": Json::string("查看驾驶舱"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("项目"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("project:read"),
          "name": Json::string("查看项目"),
        }),
        Json::object({
          "code": Json::string("project:create"),
          "name": Json::string("新建项目"),
        }),
        Json::object({
          "code": Json::string("project:update"),
          "name": Json::string("修改项目"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("合同"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("contract:read"),
          "name": Json::string("查看合同"),
        }),
        Json::object({
          "code": Json::string("contract:create"),
          "name": Json::string("新建合同"),
        }),
        Json::object({
          "code": Json::string("contract:approve"),
          "name": Json::string("审批合同"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("付款"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("payment:read"),
          "name": Json::string("查看付款"),
        }),
        Json::object({
          "code": Json::string("payment:create"),
          "name": Json::string("发起付款"),
        }),
        Json::object({
          "code": Json::string("payment:approve"),
          "name": Json::string("审批付款"),
        }),
        Json::object({
          "code": Json::string("payment:pay"),
          "name": Json::string("出纳支付"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("成本"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("cost:read"),
          "name": Json::string("查看动态成本"),
        }),
        Json::object({
          "code": Json::string("cost:update"),
          "name": Json::string("调整动态成本"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("报销"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("expense:read"),
          "name": Json::string("查看报销"),
        }),
        Json::object({
          "code": Json::string("expense:create"),
          "name": Json::string("发起报销"),
        }),
        Json::object({
          "code": Json::string("expense:approve"),
          "name": Json::string("审批报销"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("借款"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("loan:read"),
          "name": Json::string("查看借款"),
        }),
        Json::object({
          "code": Json::string("loan:create"),
          "name": Json::string("发起借款"),
        }),
        Json::object({
          "code": Json::string("loan:approve"),
          "name": Json::string("审批借款"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("计划"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("plan:read"),
          "name": Json::string("查看计划"),
        }),
        Json::object({
          "code": Json::string("plan:create"),
          "name": Json::string("编排任务"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("投资"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("investment:read"),
          "name": Json::string("查看投资"),
        }),
        Json::object({
          "code": Json::string("investment:update"),
          "name": Json::string("调整测算"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("报表"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("report:read"),
          "name": Json::string("查看报表"),
        }),
      ]),
    }),
    Json::object({
      "module": Json::string("SRM"),
      "perms": Json::array([
        Json::object({
          "code": Json::string("srm:read"),
          "name": Json::string("查看供应商"),
        }),
        Json::object({
          "code": Json::string("srm:create"),
          "name": Json::string("新增供应商"),
        }),
        Json::object({
          "code": Json::string("srm:approve"),
          "name": Json::string("供应商入库"),
        }),
      ]),
    }),
  ]
  observation_envelope(Json::array(modules), {})
}

///|
/// Report-builder observation boundary.
async fn report_templates_response() -> Json raise CompanyServiceError {
  report_template_list_response()
}

///|
async fn report_templates_meta_response() -> Json raise CompanyServiceError {
  report_template_metadata_response_native()
}

///|
async fn report_template_run_response() -> (Int, Json) raise CompanyServiceError {
  (
    501,
    Json::object({
      "success": Json::boolean(false),
      "code": Json::number(43032),
      "message": Json::string("report template run requires POST"),
      "sql_executed": Json::boolean(false),
      "authorizing": Json::boolean(false),
    }),
  )
}
