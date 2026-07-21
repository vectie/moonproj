///|
/// Evidence-first Moon Suite engineering audit ingestion and projection.
///
/// The agent-produced envelope is deliberately stricter than ordinary company
/// command payloads. Unknown fields are rejected so contract drift cannot be
/// mistaken for reviewed production evidence.

///|
const ENGINEERING_FRESHNESS_MS : UInt64 = 7UL * 24UL * 60UL * 60UL * 1000UL

///|
fn engineering_object(
  value : Json,
  contract : String,
) -> Map[String, Json] raise CompanyServiceError {
  match value {
    Object(fields) => fields
    _ => raise fail(contract + " must be a JSON object")
  }
}

///|
fn engineering_exact_keys(
  fields : Map[String, Json],
  allowed : Array[String],
  contract : String,
) -> Unit raise CompanyServiceError {
  for key in fields.keys() {
    if !allowed.contains(key) {
      raise fail(contract + " contains unknown field: " + key)
    }
  }
  for key in allowed {
    if !fields.contains(key) {
      raise fail(contract + " is missing field: " + key)
    }
  }
}

///|
fn engineering_required_text(
  fields : Map[String, Json],
  key : String,
  contract : String,
) -> String raise CompanyServiceError {
  match fields.get(key) {
    Some(String(value)) if !value.trim().is_empty() => value
    _ => raise fail(contract + "." + key + " must be a non-empty string")
  }
}

///|
fn engineering_array(
  fields : Map[String, Json],
  key : String,
  contract : String,
) -> Array[Json] raise CompanyServiceError {
  match fields.get(key) {
    Some(Array(values)) => values
    _ => raise fail(contract + "." + key + " must be an array")
  }
}

///|
fn engineering_string_array(
  fields : Map[String, Json],
  key : String,
  contract : String,
) -> Array[String] raise CompanyServiceError {
  let result : Array[String] = []
  for value in engineering_array(fields, key, contract) {
    match value {
      String(text) if !text.trim().is_empty() => result.push(text)
      _ => raise fail(contract + "." + key + " must contain only strings")
    }
  }
  result
}

///|
fn engineering_enum(
  fields : Map[String, Json],
  key : String,
  allowed : Array[String],
  contract : String,
) -> String raise CompanyServiceError {
  let value = engineering_required_text(fields, key, contract)
  if !allowed.contains(value) {
    raise fail(contract + "." + key + " has an unsupported value")
  }
  value
}

///|
fn engineering_validate_commit(
  commit : String,
) -> Unit raise CompanyServiceError {
  if commit.length() != 40 && commit.length() != 64 {
    raise fail("engineering evidence commit must be a full hexadecimal digest")
  }
  if !commit
    .iter()
    .all(fn(char) {
      char.is_ascii_digit() ||
      (char >= 'a' && char <= 'f') ||
      (char >= 'A' && char <= 'F')
    }) {
    raise fail("engineering evidence commit must be hexadecimal")
  }
}

///|
fn validate_progress_evidence(
  value : Json,
  project : String,
) -> String raise CompanyServiceError {
  let contract = "moonsuite.project-progress-evidence.v1"
  let fields = engineering_object(value, contract)
  engineering_exact_keys(
    fields,
    [
      "schema", "project", "commit", "observed_at", "lifecycle", "stage", "gate_state",
      "completed_milestones", "current_work", "blockers", "next_gate", "unknowns",
    ],
    contract,
  )
  if engineering_required_text(fields, "schema", contract) != contract ||
    engineering_required_text(fields, "project", contract) != project {
    raise fail(contract + " schema or project mismatch")
  }
  let commit = engineering_required_text(fields, "commit", contract)
  engineering_validate_commit(commit)
  let _ = engineering_required_text(fields, "observed_at", contract)
  let _ = engineering_required_text(fields, "lifecycle", contract)
  let _ = engineering_required_text(fields, "stage", contract)
  let _ = engineering_enum(
    fields,
    "gate_state",
    ["pass", "fail", "blocked", "unknown"],
    contract,
  )
  let _ = engineering_string_array(fields, "completed_milestones", contract)
  let _ = engineering_string_array(fields, "current_work", contract)
  let _ = engineering_string_array(fields, "blockers", contract)
  let _ = engineering_string_array(fields, "unknowns", contract)
  let next_gate = engineering_object(
    fields["next_gate"],
    contract + ".next_gate",
  )
  engineering_exact_keys(
    next_gate,
    ["id", "name", "criteria", "evidence"],
    contract + ".next_gate",
  )
  let _ = engineering_required_text(next_gate, "id", contract + ".next_gate")
  let _ = engineering_required_text(next_gate, "name", contract + ".next_gate")
  let _ = engineering_string_array(
    next_gate,
    "criteria",
    contract + ".next_gate",
  )
  let _ = engineering_string_array(
    next_gate,
    "evidence",
    contract + ".next_gate",
  )
  commit
}

///|
fn validate_health_evidence(
  value : Json,
  project : String,
  expected_commit : String,
) -> Unit raise CompanyServiceError {
  let contract = "moonsuite.project-health-evidence.v1"
  let fields = engineering_object(value, contract)
  engineering_exact_keys(
    fields,
    [
      "schema", "project", "commit", "observed_at", "checks", "delivery", "operations",
      "trend", "failures", "unknowns",
    ],
    contract,
  )
  if engineering_required_text(fields, "schema", contract) != contract ||
    engineering_required_text(fields, "project", contract) != project ||
    engineering_required_text(fields, "commit", contract) != expected_commit {
    raise fail(contract + " schema, project, or commit mismatch")
  }
  let statuses = ["pass", "fail", "degraded", "unknown", "not_applicable"]
  for check in engineering_array(fields, "checks", contract) {
    let item = engineering_object(check, contract + ".checks[]")
    engineering_exact_keys(
      item,
      ["dimension", "status", "command", "exit_code", "duration_ms", "evidence"],
      contract + ".checks[]",
    )
    let _ = engineering_required_text(item, "dimension", contract + ".checks[]")
    let _ = engineering_enum(item, "status", statuses, contract + ".checks[]")
    let _ = engineering_required_text(item, "command", contract + ".checks[]")
    match item["exit_code"] {
      Number(_) => ()
      _ => raise fail(contract + ".checks[].exit_code must be numeric")
    }
    match item["duration_ms"] {
      Number(_) => ()
      _ => raise fail(contract + ".checks[].duration_ms must be numeric")
    }
    let _ = engineering_string_array(item, "evidence", contract + ".checks[]")
  }
  for key in ["delivery", "operations", "trend"] {
    let item = engineering_object(fields[key], contract + "." + key)
    let keys = if key == "trend" {
      ["status", "baseline_evidence"]
    } else {
      ["status", "evidence"]
    }
    engineering_exact_keys(item, keys, contract + "." + key)
    let _ = engineering_enum(item, "status", statuses, contract + "." + key)
    let evidence_key = if key == "trend" {
      "baseline_evidence"
    } else {
      "evidence"
    }
    let _ = engineering_string_array(item, evidence_key, contract + "." + key)
  }
  let _ = engineering_required_text(fields, "observed_at", contract)
  let _ = engineering_string_array(fields, "failures", contract)
  let _ = engineering_string_array(fields, "unknowns", contract)
}

///|
fn validate_production_evidence(
  value : Json,
  project : String,
  expected_commit : String,
) -> Unit raise CompanyServiceError {
  let contract = "moonsuite.production-gate-evidence.v1"
  let fields = engineering_object(value, contract)
  engineering_exact_keys(
    fields,
    [
      "schema", "project", "commit", "candidate", "observed_at", "redlines", "gates",
      "computed_grade", "release_eligibility", "missing_evidence", "owner_decisions",
    ],
    contract,
  )
  if engineering_required_text(fields, "schema", contract) != contract ||
    engineering_required_text(fields, "project", contract) != project ||
    engineering_required_text(fields, "commit", contract) != expected_commit {
    raise fail(contract + " schema, project, or commit mismatch")
  }
  let _ = engineering_required_text(fields, "candidate", contract)
  let _ = engineering_required_text(fields, "observed_at", contract)
  let statuses = ["pass", "fail", "unknown", "not_applicable"]
  for key in ["redlines", "gates"] {
    for value in engineering_array(fields, key, contract) {
      let item = engineering_object(value, contract + "." + key + "[]")
      let keys = if key == "redlines" {
        ["id", "status", "evidence"]
      } else {
        ["id", "status", "criteria"]
      }
      engineering_exact_keys(item, keys, contract + "." + key + "[]")
      let _ = engineering_required_text(item, "id", contract + "." + key + "[]")
      let _ = engineering_enum(
        item,
        "status",
        statuses,
        contract + "." + key + "[]",
      )
      let evidence_key = if key == "redlines" { "evidence" } else { "criteria" }
      let _ = engineering_string_array(
        item,
        evidence_key,
        contract + "." + key + "[]",
      )
    }
  }
  let _ = engineering_required_text(fields, "computed_grade", contract)
  let _ = engineering_enum(
    fields,
    "release_eligibility",
    ["eligible", "ineligible", "needs_evidence", "unknown"],
    contract,
  )
  let _ = engineering_string_array(fields, "missing_evidence", contract)
  let _ = engineering_string_array(fields, "owner_decisions", contract)
}

///|
fn validate_review_evidence(
  value : Json,
  project : String,
  expected_commit : String,
) -> String raise CompanyServiceError {
  let contract = "moonsuite.evidence-review.v1"
  let fields = engineering_object(value, contract)
  engineering_exact_keys(
    fields,
    [
      "schema", "project", "producer_artifact", "producer_agent", "reviewer_agent",
      "commit", "observed_at", "verdict", "verified_claims", "rejected_claims", "rerun_receipts",
      "missing_evidence",
    ],
    contract,
  )
  if engineering_required_text(fields, "schema", contract) != contract ||
    engineering_required_text(fields, "project", contract) != project ||
    engineering_required_text(fields, "commit", contract) != expected_commit {
    raise fail(contract + " schema, project, or commit mismatch")
  }
  let producer = engineering_required_text(fields, "producer_agent", contract)
  let reviewer = engineering_required_text(fields, "reviewer_agent", contract)
  if producer == reviewer {
    raise fail("engineering evidence reviewer must be independent of producer")
  }
  let _ = engineering_required_text(fields, "producer_artifact", contract)
  let _ = engineering_required_text(fields, "observed_at", contract)
  let verdict = engineering_enum(
    fields,
    "verdict",
    ["accept", "reject", "needs_evidence"],
    contract,
  )
  let _ = engineering_string_array(fields, "verified_claims", contract)
  let _ = engineering_string_array(fields, "rejected_claims", contract)
  let _ = engineering_string_array(fields, "rerun_receipts", contract)
  let _ = engineering_string_array(fields, "missing_evidence", contract)
  verdict
}

///|
fn validate_engineering_envelope(
  value : Json,
  expected_project : String,
) -> (String, String) raise CompanyServiceError {
  let contract = "moonsuite.engineering-audit-envelope.v1"
  let fields = engineering_object(value, contract)
  engineering_exact_keys(
    fields,
    ["schema", "project", "progress", "health", "production", "review"],
    contract,
  )
  if engineering_required_text(fields, "schema", contract) != contract ||
    engineering_required_text(fields, "project", contract) != expected_project {
    raise fail(contract + " schema or project mismatch")
  }
  let commit = validate_progress_evidence(fields["progress"], expected_project)
  validate_health_evidence(fields["health"], expected_project, commit)
  validate_production_evidence(fields["production"], expected_project, commit)
  let verdict = validate_review_evidence(
    fields["review"],
    expected_project,
    commit,
  )
  (commit, verdict)
}

///|
fn engineering_health_status(health : Json) -> String {
  let mut saw_pass = false
  let mut saw_unknown = false
  let mut saw_degraded = false
  match json_field(health, "checks") {
    Some(Array(checks)) =>
      for check in checks {
        match json_text(check, "status", "unknown") {
          "fail" => return "fail"
          "degraded" => saw_degraded = true
          "unknown" => saw_unknown = true
          "pass" => saw_pass = true
          _ => ()
        }
      }
    _ => saw_unknown = true
  }
  if saw_degraded {
    "degraded"
  } else if saw_unknown || !saw_pass {
    "unknown"
  } else {
    "pass"
  }
}

///|
fn engineering_findings(envelope : Json) -> Array[Json] {
  let result : Array[Json] = []
  for
    pair in [
      (json_field(envelope, "health").unwrap_or(Json::null()), "failures"),
      (
        json_field(envelope, "production").unwrap_or(Json::null()),
        "missing_evidence",
      ),
      (
        json_field(envelope, "review").unwrap_or(Json::null()),
        "rejected_claims",
      ),
      (
        json_field(envelope, "review").unwrap_or(Json::null()),
        "missing_evidence",
      ),
    ] {
    let artifact = pair.0
    let key = pair.1
    match json_field(artifact, key) {
      Some(Array(values)) =>
        for value in values {
          match value {
            String(text) => result.push(Json::string(text))
            _ => ()
          }
        }
      _ => ()
    }
  }
  result
}

///|
fn engineering_projection(
  audit_id : String,
  task_id : String,
  project : String,
  commit : String,
  verdict : String,
  envelope : Json,
  supersedes : String,
) -> Json {
  let progress = json_field(envelope, "progress").unwrap_or(Json::null())
  let health = json_field(envelope, "health").unwrap_or(Json::null())
  let production = json_field(envelope, "production").unwrap_or(Json::null())
  let trusted = verdict == "accept"
  let candidate_digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(envelope.stringify())),
  )
  Json::object({
    "schema": Json::string("moonsuite.engineering-projection.v1"),
    "project": Json::string(project),
    "audit_id": Json::string(audit_id),
    "task_id": Json::string(task_id),
    "commit": Json::string(commit),
    "candidate_digest": Json::string(candidate_digest),
    "review_verdict": Json::string(verdict),
    "trusted": Json::boolean(trusted),
    "progress": if trusted {
      Json::object({
        "lifecycle": Json::string(json_text(progress, "lifecycle", "unknown")),
        "stage": Json::string(json_text(progress, "stage", "unknown")),
        "gate_state": Json::string(json_text(progress, "gate_state", "unknown")),
      })
    } else {
      Json::object({
        "lifecycle": "unknown",
        "stage": "unknown",
        "gate_state": "unknown",
      })
    },
    "health": Json::object({
      "status": Json::string(
        if trusted {
          engineering_health_status(health)
        } else {
          "unknown"
        },
      ),
    }),
    "production": Json::object({
      "grade": Json::string(
        if trusted {
          json_text(production, "computed_grade", "unknown")
        } else {
          "unknown"
        },
      ),
      "release_eligibility": Json::string(
        if trusted {
          json_text(production, "release_eligibility", "unknown")
        } else {
          "unknown"
        },
      ),
    }),
    "accepted_findings": Json::array(
      if trusted {
        engineering_findings(envelope)
      } else {
        []
      },
    ),
    "observed_at": Json::string(json_text(progress, "observed_at", "")),
    "ingested_at_ms": Json::number(@env.now().to_double()),
    "freshness": Json::string("fresh"),
    "supersedes": Json::string(supersedes),
  })
}

///|
async fn latest_engineering_projection(
  project : String,
) -> (Int, String, Json)? raise CompanyServiceError {
  let output = run_sql(
    "SELECT revision::text, encode(convert_to(source_event_id, 'UTF8'), 'hex'), encode(convert_to(payload::text, 'UTF8'), 'hex') FROM company_aggregate_projection WHERE aggregate_type = 'engineering_project' AND aggregate_id = " +
    @postgres.sql_literal(project) +
    " ORDER BY revision DESC LIMIT 1",
  )
  let line = output.trim().to_owned()
  if line.is_empty() {
    return None
  }
  let row = fields(line, 3)
  let payload = @json.parse(decode_hex(row[2])) catch {
    _ => raise fail("invalid engineering projection JSON")
  }
  Some((parse_decimal(row[0]), decode_hex(row[1]), payload))
}

///|
async fn ingest_engineering_audit(
  body : Json,
  actor : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  let request = engineering_object(body, "engineering audit ingest")
  engineering_exact_keys(
    request,
    ["audit_id", "project", "task_id", "envelope"],
    "engineering audit ingest",
  )
  let audit_id = engineering_required_text(
    request, "audit_id", "engineering audit ingest",
  )
  let project = engineering_required_text(
    request, "project", "engineering audit ingest",
  )
  let task_id = engineering_required_text(
    request, "task_id", "engineering audit ingest",
  )
  if !valid_identifier(audit_id) ||
    !valid_identifier(project) ||
    !valid_identifier(task_id) {
    raise fail("engineering audit identifiers are invalid")
  }
  let envelope = request["envelope"]
  let (commit, verdict) = validate_engineering_envelope(envelope, project)
  let source_id = "moonproj:engineering-audit:" + idempotency_key
  let existing = run_sql(
      "SELECT count(*)::text FROM company_record WHERE source_id = " +
      @postgres.sql_literal(source_id),
    )
    .trim()
    .to_owned()
  if existing != "0" {
    return match latest_engineering_projection(project) {
      Some((revision, _, projection)) =>
        (
          200,
          Json::object({
            "audit": projection,
            "revision": revision,
            "idempotent_replay": true,
          }),
        )
      None => raise fail("engineering audit receipt exists without projection")
    }
  }
  let previous = latest_engineering_projection(project)
  let revision = match previous {
    Some((value, _, _)) => value + 1
    None => 1
  }
  let supersedes = match previous {
    Some((_, source, _)) => source
    None => ""
  }
  let projection = engineering_projection(
    audit_id, task_id, project, commit, verdict, envelope, supersedes,
  )
  let review = json_field(envelope, "review").unwrap_or(Json::null())
  let digest = json_text(projection, "candidate_digest", "")
  let receipt = Json::object({
    "schema": "moonsuite.engineering-ingest-receipt.v1",
    "audit_id": audit_id,
    "project": project,
    "task_id": task_id,
    "commit": commit,
    "candidate_digest": digest,
    "review_verdict": verdict,
    "actor_id": actor,
    "supersedes": supersedes,
  })
  let sql = "BEGIN; LOCK TABLE company_aggregate_projection IN SHARE ROW EXCLUSIVE MODE; " +
    "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('engineering_audit_evidence', " +
    @postgres.sql_literal(audit_id) +
    ", 1, " +
    @postgres.sql_literal(envelope.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(source_id) +
    ") ON CONFLICT (source_id) DO NOTHING; " +
    "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('engineering_review_receipt', " +
    @postgres.sql_literal(audit_id + ":review") +
    ", 1, " +
    @postgres.sql_literal(review.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(source_id + ":review") +
    ") ON CONFLICT (source_id) DO NOTHING; " +
    "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('engineering_candidate_digest', " +
    @postgres.sql_literal(digest) +
    ", 1, " +
    @postgres.sql_literal(receipt.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(source_id + ":digest") +
    ") ON CONFLICT (source_id) DO NOTHING; " +
    "INSERT INTO company_aggregate_projection(aggregate_type, aggregate_id, revision, payload, source_event_id) VALUES ('engineering_project', " +
    @postgres.sql_literal(project) +
    ", " +
    revision.to_string() +
    ", " +
    @postgres.sql_literal(projection.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(audit_id) +
    ") ON CONFLICT DO NOTHING; COMMIT;"
  let _ = run_sql(sql)
  (
    201,
    Json::object({
      "audit": projection,
      "revision": revision,
      "idempotent_replay": false,
    }),
  )
}

///|
fn engineering_unknown_projection(project : String) -> Json {
  Json::object({
    "schema": "moonsuite.engineering-projection.v1",
    "project": project,
    "trusted": false,
    "freshness": "missing",
    "review_verdict": "needs_evidence",
    "progress": {
      "lifecycle": "unknown",
      "stage": "unknown",
      "gate_state": "unknown",
    },
    "health": { "status": "unknown" },
    "production": { "grade": "unknown", "release_eligibility": "unknown" },
    "accepted_findings": [],
  })
}

///|
async fn engineering_project_response(
  project : String,
) -> (Int, Json) raise CompanyServiceError {
  if !valid_identifier(project) {
    raise fail("invalid engineering project identifier")
  }
  match latest_engineering_projection(project) {
    None =>
      (
        200,
        Json::object({
          "revision": 0,
          "audit": engineering_unknown_projection(project),
        }),
      )
    Some((revision, _, payload)) => {
      let ingested = match json_field(payload, "ingested_at_ms") {
        Some(Number(value, ..)) => value.to_uint64()
        _ => 0UL
      }
      let now = @env.now()
      let stale = ingested == 0UL ||
        now < ingested ||
        now - ingested > ENGINEERING_FRESHNESS_MS
      if stale {
        let fields = engineering_object(payload, "engineering projection")
        fields["freshness"] = Json::string("stale")
        fields["trusted"] = Json::boolean(false)
      }
      (200, Json::object({ "revision": revision, "audit": payload }))
    }
  }
}

///|
async fn create_engineering_remediation(
  project : String,
  actor : String,
  idempotency_key : String,
) -> (Int, Json) raise CompanyServiceError {
  let latest = match latest_engineering_projection(project) {
    Some(value) => value
    None => raise reject(409, "accepted engineering evidence is required")
  }
  let projection = latest.2
  let ingested = match json_field(projection, "ingested_at_ms") {
    Some(Number(value, ..)) => value.to_uint64()
    _ => 0UL
  }
  let now = @env.now()
  if !json_bool(projection, "trusted", false) ||
    ingested == 0UL ||
    now < ingested ||
    now - ingested > ENGINEERING_FRESHNESS_MS {
    raise reject(409, "fresh accepted engineering evidence is required")
  }
  let findings = match json_field(projection, "accepted_findings") {
    Some(Array(values)) if !values.is_empty() => values
    _ => raise reject(409, "accepted audit contains no remediation findings")
  }
  let remediation_id = "REM-" +
    @crypto.bytes_to_hex_string(
      @crypto.sha256(@encoding/utf8.encode(project + ":" + idempotency_key)),
    )[:20].to_owned()
  let payload = Json::object({
    "schema": "moonsuite.engineering-remediation.v1",
    "remediation_id": remediation_id,
    "project": project,
    "source_audit_id": json_text(projection, "audit_id", ""),
    "source_candidate_digest": json_text(projection, "candidate_digest", ""),
    "findings": Json::array(findings),
    "state": "open",
    "created_by": actor,
    "created_at_ms": Json::number(@env.now().to_double()),
  })
  let source = "moonproj:engineering-remediation:" + idempotency_key
  let _ = run_sql(
    "INSERT INTO company_record(record_type, record_id, schema_version, payload, source_id) VALUES ('engineering_remediation', " +
    @postgres.sql_literal(remediation_id) +
    ", 1, " +
    @postgres.sql_literal(payload.stringify()) +
    "::jsonb, " +
    @postgres.sql_literal(source) +
    ") ON CONFLICT (source_id) DO NOTHING",
  )
  (201, Json::object({ "remediation": payload }))
}
