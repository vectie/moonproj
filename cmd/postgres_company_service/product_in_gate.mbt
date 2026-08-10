///|
/// Persisted product-demand admission marking.
///
/// Product In-Gate decisions are portfolio facts. They do not alter, satisfy,
/// waive, or renumber the candidate-bound engineering Exit Gate G1-G9.

///|
fn product_in_gate_project(path : String) -> String? {
  let prefix = "/api/company/products/"
  let suffix = "/in-gate"
  if !path.has_prefix(prefix) || !path.has_suffix(suffix) {
    return None
  }
  let product = path[prefix.length():path.length() - suffix.length()].to_owned()
  if valid_identifier(product) {
    Some(product)
  } else {
    None
  }
}

///|
fn product_in_gate_command_spec(
  request_method : @http.RequestMethod,
  path : String,
) -> String? {
  if request_method is @http.Put {
    product_in_gate_project(path)
  } else {
    None
  }
}

///|
fn product_in_gate_text(
  fields : Map[String, Json],
  key : String,
  max_length : Int,
) -> String raise CompanyServiceError {
  let value = engineering_required_text(fields, key, "product in-gate")
    .trim()
    .to_owned()
  if value.length() > max_length {
    raise reject(422, "product in-gate " + key + " is too long")
  }
  value
}

///|
fn product_in_gate_evidence(
  fields : Map[String, Json],
  key : String,
) -> Array[String] raise CompanyServiceError {
  let values = engineering_string_array(fields, key, "product in-gate")
  if values.length() > 20 {
    raise reject(422, "product in-gate " + key + " has too many receipts")
  }
  let result : Array[String] = []
  for raw in values {
    let value = raw.trim().to_owned()
    if value.length() > 512 {
      raise reject(422, "product in-gate evidence reference is too long")
    }
    if result.contains(value) {
      raise reject(422, "product in-gate evidence references must be unique")
    }
    result.push(value)
  }
  result
}

///|
fn normalize_product_in_gate_request(
  body : Json,
) -> Json raise CompanyServiceError {
  let fields = engineering_object(body, "product in-gate")
  engineering_exact_keys(
    fields,
    [
      "decision", "primary_value", "segment", "workflow", "decided_at", "problem_evidence",
      "commitment_evidence", "current_behavior_cost", "outcome_metric", "adoption_path",
      "unresolved_risks", "next_experiment", "review_by",
    ],
    "product in-gate",
  )
  let decision = engineering_enum(
    fields,
    "decision",
    ["pass", "experiment", "park"],
    "product in-gate",
  )
  let primary_value = engineering_enum(
    fields,
    "primary_value",
    ["solution", "convenience", "experience"],
    "product in-gate",
  )
  let segment = product_in_gate_text(fields, "segment", 512)
  let workflow = product_in_gate_text(fields, "workflow", 512)
  let decided_at = product_in_gate_text(fields, "decided_at", 64)
  if decided_at.length() != 10 || cashflow_date_parts(decided_at) is None {
    raise reject(422, "product in-gate decided_at must be an ISO date")
  }
  let problem_evidence = product_in_gate_evidence(fields, "problem_evidence")
  let commitment_evidence = product_in_gate_evidence(
    fields, "commitment_evidence",
  )
  let current_behavior_cost = product_in_gate_text(
    fields, "current_behavior_cost", 1024,
  )
  let outcome_metric = product_in_gate_text(fields, "outcome_metric", 512)
  let adoption_path = product_in_gate_text(fields, "adoption_path", 1024)
  let unresolved_risks = product_in_gate_text(fields, "unresolved_risks", 1024)
  let next_experiment = product_in_gate_text(fields, "next_experiment", 1024)
  let review_by = product_in_gate_text(fields, "review_by", 64)
  if review_by.length() != 10 || cashflow_date_parts(review_by) is None {
    raise reject(422, "product in-gate review_by must be an ISO date")
  }
  if review_by < decided_at || review_by > plan_shift_date(decided_at, 90) {
    raise reject(
      422, "product in-gate review_by must be on or after decided_at and within 90 days",
    )
  }
  if decision == "pass" && problem_evidence.length() < 3 {
    raise reject(
      422, "product in-gate pass requires at least three problem receipts",
    )
  }
  if decision == "pass" {
    let mut level4 = 0
    let mut level5 = 0
    for receipt in commitment_evidence {
      if receipt.has_prefix("level4:") {
        level4 += 1
      } else if receipt.has_prefix("level5:") {
        level5 += 1
      } else {
        raise reject(
          422, "product in-gate pass commitments must use level4: or level5: receipt references",
        )
      }
    }
    if level5 == 0 && level4 < 2 {
      raise reject(
        422, "product in-gate pass requires two level-4 commitments or one level-5 commitment",
      )
    }
  }
  Json::object({
    "decision": Json::string(decision),
    "primary_value": Json::string(primary_value),
    "segment": Json::string(segment),
    "workflow": Json::string(workflow),
    "decided_at": Json::string(decided_at),
    "problem_evidence": Json::array(
      problem_evidence.map(value => Json::string(value)),
    ),
    "commitment_evidence": Json::array(
      commitment_evidence.map(value => Json::string(value)),
    ),
    "current_behavior_cost": Json::string(current_behavior_cost),
    "outcome_metric": Json::string(outcome_metric),
    "adoption_path": Json::string(adoption_path),
    "unresolved_risks": Json::string(unresolved_risks),
    "next_experiment": Json::string(next_experiment),
    "review_by": Json::string(review_by),
  })
}

///|
fn product_in_gate_projection(
  product : String,
  normalized : Json,
  owner : String,
  revision : Int,
  event_id : String,
) -> Json {
  Json::object({
    "schema": Json::string("moonproj.product-in-gate-projection.v2"),
    "product": Json::string(product),
    "decision": Json::string(json_text(normalized, "decision", "unknown")),
    "primary_value": Json::string(
      json_text(normalized, "primary_value", "unknown"),
    ),
    "segment": Json::string(json_text(normalized, "segment", "")),
    "workflow": Json::string(json_text(normalized, "workflow", "")),
    "decided_at": Json::string(json_text(normalized, "decided_at", "")),
    "problem_evidence": json_field(normalized, "problem_evidence").unwrap_or(
      Json::array([]),
    ),
    "commitment_evidence": json_field(normalized, "commitment_evidence").unwrap_or(
      Json::array([]),
    ),
    "current_behavior_cost": Json::string(
      json_text(normalized, "current_behavior_cost", ""),
    ),
    "outcome_metric": Json::string(json_text(normalized, "outcome_metric", "")),
    "adoption_path": Json::string(json_text(normalized, "adoption_path", "")),
    "unresolved_risks": Json::string(
      json_text(normalized, "unresolved_risks", ""),
    ),
    "next_experiment": Json::string(
      json_text(normalized, "next_experiment", ""),
    ),
    "review_by": Json::string(json_text(normalized, "review_by", "")),
    "owner": Json::string(owner),
    "revision": Json::number(revision.to_double()),
    "event_id": Json::string(event_id),
    "updated_at_ms": Json::number(@env.now().to_double()),
    "persisted": Json::boolean(true),
    "exit_gate_effect": Json::boolean(false),
  })
}

///|
fn product_in_gate_unknown_projection(product : String) -> Json {
  Json::object({
    "schema": Json::string("moonproj.product-in-gate-projection.v2"),
    "product": Json::string(product),
    "decision": Json::string("unknown"),
    "primary_value": Json::string("unknown"),
    "segment": Json::string(""),
    "workflow": Json::string(""),
    "decided_at": Json::string(""),
    "problem_evidence": Json::array([]),
    "commitment_evidence": Json::array([]),
    "current_behavior_cost": Json::string(""),
    "outcome_metric": Json::string(""),
    "adoption_path": Json::string(""),
    "unresolved_risks": Json::string(""),
    "next_experiment": Json::string(""),
    "review_by": Json::string(""),
    "owner": Json::string(""),
    "revision": Json::number(0),
    "event_id": Json::string(""),
    "updated_at_ms": Json::number(0),
    "persisted": Json::boolean(false),
    "exit_gate_effect": Json::boolean(false),
  })
}

///|
async fn latest_product_in_gate_projection(
  product : String,
) -> (Json, Int)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'product_in_gate' AND aggregate_id = " +
    @postgres.sql_literal(product) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let value = output.trim().to_owned()
  if value.is_empty() {
    return None
  }
  let row = fields(value, 2)
  let payload = @json.parse(decode_hex(row[1])) catch {
    _ => raise fail("invalid product in-gate projection JSON")
  }
  Some((payload, parse_decimal(row[0])))
}

///|
async fn product_in_gate_response(
  product : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(product) {
    raise reject(422, "invalid product in-gate identifier")
  }
  match latest_product_in_gate_projection(product) {
    Some((projection, revision)) =>
      (
        200,
        Json::object({
          "revision": Json::number(revision.to_double()),
          "product_in_gate": projection,
        }),
      )
    None =>
      (
        200,
        Json::object({
          "revision": Json::number(0),
          "product_in_gate": product_in_gate_unknown_projection(product),
        }),
      )
  }
}

///|
async fn mark_product_in_gate(
  product : String,
  body : Json,
  actor : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(product) || !valid_identifier(actor) {
    raise reject(422, "invalid product in-gate identity")
  }
  if !valid_identifier(idempotency_key) {
    raise reject(422, "Idempotency-Key contains unsupported characters")
  }
  let normalized = normalize_product_in_gate_request(body)
  let request = Json::object({
    "command_type": Json::string("mark_product_in_gate"),
    "product": Json::string(product),
    "actor_id": Json::string(actor),
    "decision": normalized,
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
          "product_in_gate": json_field(existing, "result").unwrap_or(
            Json::null(),
          ),
          "idempotent_replay": Json::boolean(true),
        }),
      )
    }
    None => ()
  }
  let current = latest_product_in_gate_projection(product)
  let revision = match current {
    Some((_, value)) => value + 1
    None => 1
  }
  let event_id = "product-in-gate:mark:" + idempotency_key
  let audit_id = event_id + ":audit"
  let projection = product_in_gate_projection(
    product, normalized, actor, revision, event_id,
  )
  let command = Json::object({
    "kind": Json::string("company_command"),
    "command_family": Json::string("product_in_gate"),
    "command_type": Json::string("mark_product_in_gate"),
    "idempotency_key": Json::string(idempotency_key),
    "aggregate_type": Json::string("product_in_gate"),
    "aggregate_id": Json::string(product),
    "actor_id": Json::string(actor),
    "request": request,
    "result": projection,
  })
  let audit = Json::object({
    "schema": Json::string("moonproj.product-in-gate-audit.v1"),
    "audit_id": Json::string(audit_id),
    "action": Json::string("product_in_gate.mark"),
    "aggregate_type": Json::string("product_in_gate"),
    "aggregate_id": Json::string(product),
    "actor_id": Json::string(actor),
    "event_id": Json::string(event_id),
    "decision": Json::string(json_text(projection, "decision", "unknown")),
    "revision": Json::number(revision.to_double()),
    "exit_gate_effect": Json::boolean(false),
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_command', " +
    @postgres.sql_literal(event_id) +
    ", 4, " +
    @postgres.sql_literal(command.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal("moonproj:command:" + idempotency_key) +
    ") ON CONFLICT (source_id) DO NOTHING; INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('product_in_gate', " +
    @postgres.sql_literal(product) +
    ", " +
    revision.to_string() +
    ", " +
    @postgres.sql_literal(projection.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(event_id) +
    ") ON CONFLICT DO NOTHING; INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('company_audit_event', " +
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
      "product_in_gate": projection,
      "idempotent_replay": Json::boolean(false),
    }),
  )
}
