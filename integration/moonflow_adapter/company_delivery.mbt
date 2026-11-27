///|
fn company_field(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn company_text(value : Json, key : String) -> String {
  match company_field(value, key) {
    String(text) => text
    _ => ""
  }
}

///|
fn company_identifier(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 128 &&
  value
  .iter()
  .all(ch => {
    ch.is_ascii_alphabetic() ||
    ch.is_ascii_digit() ||
    ch == '_' ||
    ch == '.' ||
    ch == ':' ||
    ch == '-'
  })
}

///|
/// A company command is optional input evidence, never dispatch authority.
/// The caller obtains it through the existing authenticated company gateway.
async fn company_binding(
  root : String,
  flow : FlowRequest,
  plan : @project_plan.ProjectPlanRequest,
) -> Json? {
  let mut found : Json? = None
  for reference in flow.input_artifacts {
    let bytes = read_text_ref(root, reference)
    let value = @json.parse(bytes) catch { _ => continue }
    if company_text(value, "contract_id") == "moonproj.company-task-snapshot.v1" {
      if found is Some(_) ||
        company_text(value, "project_id") != plan.project.project_id ||
        !plan.source_evidence.any(evidence => {
          evidence.artifact_ref == reference &&
          evidence.digest == sha256_text(bytes)
        }) {
        fail(
          "MoonProj revised task snapshot must be the single exact project source",
        )
      }
      found = Some(
        @company_flow.binding(
          value,
          ToJson::to_json(flow),
          reference,
          sha256_text(bytes),
        ),
      )
      continue
    }
    if company_text(value, "kind") != "company_command" ||
      company_text(value, "command_family") != "plan_task" {
      continue
    }
    if found is Some(_) {
      fail("MoonProj Flow attempt must bind only one company task command")
    }
    let request = company_field(value, "request")
    let result = company_field(value, "result")
    let task_id = company_text(request, "task_id")
    let actor_id = company_text(value, "actor_id")
    let revision = json_int_field(
      json_object(result, "company result"),
      "revision",
    )
    if company_text(value, "command_type") != "create" ||
      company_text(request, "command_type") != "create" ||
      !company_identifier(task_id) ||
      company_text(value, "aggregate_id") != task_id ||
      company_text(result, "task_id") != task_id ||
      company_text(request, "project_id") != plan.project.project_id ||
      company_text(request, "created_by") != actor_id ||
      company_text(result, "actor_id") != actor_id ||
      actor_id.is_empty() ||
      revision != 1 ||
      company_field(result, "revision") != Json::number(1) ||
      !plan.source_evidence.any(evidence => {
        evidence.artifact_ref == reference &&
        evidence.digest == sha256_text(bytes)
      }) ||
      company_text(result, "event_id").is_empty() ||
      company_text(result, "audit_id").is_empty() {
      fail("MoonProj Flow company task snapshot identities do not match")
    }
    found = Some({
      "contract_id": "moonproj.flow-task-binding.v1",
      "task_id": task_id,
      "project_id": plan.project.project_id,
      "source_revision": revision,
      "company_event_id": company_text(result, "event_id"),
      "company_audit_id": company_text(result, "audit_id"),
      "company_command_ref": reference,
      "company_command_digest": sha256_text(bytes),
      "run_id": flow.run_id,
      "work_item_id": flow.work_item_id,
      "declaration_id": flow.declaration_id,
      "request_id": flow.request_id,
      "attempt_id": flow.attempt_id,
      "idempotency_key": flow.idempotency_key,
      "input_digest": flow.input_digest,
      "authorizing": false,
    })
  }
  found
}

///|
fn company_binding_ref(flow : FlowRequest) -> String {
  attempt_base(flow) + "/company-task-binding.json"
}

///|
/// Explicitly bind the company command already named among a plan attempt's
/// source inputs. Existing execute/reconcile calls do not opt in implicitly.
/// This prepares correlation only; it does not dispatch or grant authority.
pub async fn bind_company_task(
  workspace : String,
  request_ref : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, plan) = load_bound_inputs(root, request_ref)
  guard company_binding(root, flow, plan) is Some(binding) else {
    fail("MoonProj Flow attempt has no company task input")
  }
  require_company_approval(root, flow, binding)
  ignore(immutable_json_ref(root, company_binding_ref(flow), binding))
  binding
}

///|
fn company_report_base(flow : FlowRequest, report_key : String) -> String raise {
  if !safe_path_segment(report_key) || report_key.length() > 128 {
    fail("MoonProj Flow report key must be a bounded path segment")
  }
  attempt_base(flow) + "/company-reports/" + report_key
}

///|
async fn bound_company_input(
  root : String,
  flow : FlowRequest,
  plan : @project_plan.ProjectPlanRequest,
) -> Json {
  guard company_binding(root, flow, plan) is Some(expected) else {
    fail("MoonProj Flow attempt has no company task input")
  }
  if read_json_ref(root, company_binding_ref(flow)) != expected {
    fail("MoonProj Flow company binding changed")
  }
  require_company_approval(root, flow, expected)
  expected
}

///|
/// Prepare an immutable body for the existing explicit task-report gateway.
/// This performs no HTTP request and does not accept the task. Evidence is
/// carried by content digest, with exact file names retained in the envelope.
/// The report key identifies one report draft; retry with the same arguments.
pub async fn prepare_company_task_report(
  workspace : String,
  request_ref : String,
  result_ref : String,
  report_key : String,
  report_date : String,
  summary : String,
  evidence_refs : Array[String],
  progress_pct~ : Int32 = 0,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, plan) = load_bound_inputs(root, request_ref)
  let binding = bound_company_input(root, flow, plan)
  let envelope = make_company_task_report(
    root, flow, plan, binding, request_ref, result_ref, report_key, report_date,
    summary, evidence_refs, progress_pct,
  )
  let base = company_report_base(flow, report_key)
  ignore(immutable_json_ref(root, base + "/report.json", envelope))
  envelope
}

///|
/// Construct the same envelope for initial preparation and read-only recovery.
/// Correlation comes from the original binding, never from saved report fields.
async fn make_company_task_report(
  root : String,
  flow : FlowRequest,
  plan : @project_plan.ProjectPlanRequest,
  binding : Json,
  request_ref : String,
  result_ref : String,
  report_key : String,
  report_date : String,
  summary : String,
  evidence_refs : Array[String],
  progress_pct : Int32,
) -> Json {
  if read_json_ref(root, intent_ref(flow)) !=
    intent_json(request_ref, result_ref, flow, plan) {
    fail("MoonProj Flow report must use the original attempt intent")
  }
  let result = read_json_ref(root, result_ref)
  validate_result(root, flow, plan, result)
  if read_json_ref(root, internal_result_ref(flow)) != result {
    fail(
      "MoonProj Flow report result differs from the persisted adapter result",
    )
  }
  if !canonical_utc_timestamp(report_date + "T00:00:00Z") ||
    summary.trim().is_empty() ||
    progress_pct < 0 ||
    progress_pct > 100 {
    fail("MoonProj Flow report date, summary or progress is invalid")
  }
  ignore(company_report_base(flow, report_key))
  let identities : Array[String] = []
  let entries : Array[Json] = []
  let references = [company_binding_ref(flow), result_ref, artifact_ref(flow)]
  for reference in evidence_refs {
    if !references.contains(reference) {
      references.push(reference)
    }
  }
  for reference in references {
    let digest = digest_ref(root, reference)
    if !identities.contains(digest) {
      identities.push(digest)
    }
    entries.push({ "artifact_ref": reference, "digest": digest })
  }
  let identity = sha256_text(flow.idempotency_key + "\n" + report_key)
  let key = "flow-report-" + identity[7:].to_owned()
  let body : Json = {
    "report_id": "TR-" + key,
    "task_id": company_text(binding, "task_id"),
    "project_id": company_text(binding, "project_id"),
    "progress_pct": progress_pct,
    "report_date": report_date,
    "summary": summary.trim().to_owned(),
    "evidence_ids": identities,
  }
  if company_text(binding, "contract_id") == "moonproj.flow-task-binding.v2" {
    let approval = read_json_ref(root, company_approval_ref(flow))
    let fields = json_object(body, "report body")
    fields["flow_binding"] = binding
    fields["flow_approval_key"] = company_field(approval, "idempotency_key")
  }
  let envelope : Json = {
    "contract_id": "moonproj.flow-task-report.v1",
    "binding": binding,
    "request_ref": request_ref,
    "result_ref": result_ref,
    "result_digest": digest_ref(root, result_ref),
    "output_digest": company_text(result, "output_digest"),
    "evidence": entries,
    "method": "POST",
    "path": "/api/company/plan/tasks/" +
    company_text(binding, "task_id") +
    "/report",
    "idempotency_key": key,
    "report_body": body,
    "task_acceptance": "unchanged",
    "customer_acceptance": "not_recorded_here",
    "cash": "not_recorded_here",
  }
  envelope
}

///|
/// Reconstruct every saved envelope field from its bound task, attempt and
/// actual result/evidence. A readable JSON value is not a valid checkpoint.
async fn load_company_task_report(
  root : String,
  flow : FlowRequest,
  plan : @project_plan.ProjectPlanRequest,
  request_ref : String,
  report_key : String,
) -> Json {
  let binding = bound_company_input(root, flow, plan)
  let base = company_report_base(flow, report_key)
  let saved = read_json_ref(root, base + "/report.json")
  let fields = json_object(saved, "saved company report")
  let body = json_object(
    company_field(saved, "report_body"),
    "saved report body",
  )
  let progress = json_int_field(body, "progress_pct")
  if body.get("progress_pct") != Some(ToJson::to_json(progress)) {
    fail("MoonProj Flow report checkpoint has invalid progress")
  }
  let evidence = match fields.get("evidence") {
    Some(Array(entries)) =>
      entries.map(entry => {
        json_string_field(
          json_object(entry, "saved report evidence"),
          "artifact_ref",
        )
      })
    _ => fail("MoonProj Flow report checkpoint requires evidence")
  }
  let expected = make_company_task_report(
    root,
    flow,
    plan,
    binding,
    request_ref,
    json_string_field(fields, "result_ref"),
    report_key,
    json_string_field(body, "report_date"),
    json_string_field(body, "summary"),
    evidence,
    progress,
  )
  if saved != expected {
    fail(
      "MoonProj Flow report checkpoint does not match its bound task, attempt, result or evidence",
    )
  }
  saved
}

///|
/// Retain the actual company service command returned after explicit report
/// submission. HTTP replay flags are not part of that durable identity.
/// Only a matching observed report marks reporting complete; no work runs here.
pub async fn record_company_task_report_receipt(
  workspace : String,
  request_ref : String,
  report_key : String,
  response_ref : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let response = read_json_ref(root, response_ref)
  record_company_task_report_response(
    workspace, request_ref, report_key, response,
  )
}

///|
/// Gateway return records the actual signed-service response without a mutable
/// scratch response file. Recovery still reconstructs the saved report first.
pub async fn record_company_task_report_response(
  workspace : String,
  request_ref : String,
  report_key : String,
  response : Json,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, plan) = load_bound_inputs(root, request_ref)
  let base = company_report_base(flow, report_key)
  let envelope = load_company_task_report(
    root, flow, plan, request_ref, report_key,
  )
  let command = company_field(response, "command")
  validate_company_report_command(envelope, command)
  match read_optional_json_ref(root, base + "/receipt.json") {
    Some(existing) =>
      if existing != command {
        fail("MoonProj Flow report command receipt conflicts")
      }
    None => ignore(immutable_json_ref(root, base + "/receipt.json", command))
  }
  company_task_report_status(workspace, request_ref, report_key)
}

///|
fn validate_company_report_command(
  envelope : Json,
  command : Json,
) -> Unit raise {
  let body = company_field(envelope, "report_body")
  let request = company_field(command, "request")
  let result = company_field(command, "result")
  let key = company_text(envelope, "idempotency_key")
  if company_text(command, "kind") != "company_command" ||
    company_text(command, "command_family") != "delivery" ||
    company_text(command, "family") != "task_report" ||
    company_text(command, "aggregate_type") != "task_report" ||
    company_text(command, "command_type") != "report" ||
    company_text(command, "idempotency_key") != key ||
    company_text(command, "aggregate_id") != company_text(body, "report_id") ||
    company_text(result, "aggregate_id") != company_text(body, "report_id") ||
    company_text(request, "command_type") != "report" ||
    company_text(request, "state") != "observed" ||
    company_text(result, "state") != "observed" ||
    company_field(result, "revision") != Json::number(1) ||
    company_field(result, "delivery_effect") != Json::boolean(false) ||
    company_field(result, "cash_effect") != Json::boolean(false) ||
    company_field(result, "accounting_effect") != Json::boolean(false) ||
    company_field(result, "tax_effect") != Json::boolean(false) ||
    company_text(result, "event_id") != "delivery:task_report:report:" + key ||
    company_text(result, "audit_id") !=
    company_text(result, "event_id") + ":audit" ||
    !company_identifier(company_text(command, "actor_id")) ||
    company_text(request, "actor_id") != company_text(command, "actor_id") ||
    company_text(result, "actor_id") != company_text(command, "actor_id") {
    fail("MoonProj Flow report response does not match its prepared report")
  }
  for
    field in [
      "report_id", "task_id", "project_id", "report_date", "summary", "evidence_ids",
    ] {
    if company_field(request, field) != company_field(body, field) {
      fail("MoonProj Flow report response changed " + field)
    }
  }
  for field in ["flow_binding", "flow_approval_key"] {
    if company_field(request, field) != company_field(body, field) {
      fail("MoonProj Flow report response changed " + field)
    }
  }
  if company_field(body, "flow_binding") is Object(_) &&
    company_text(command, "actor_id") !=
    company_text(
      company_field(
        company_field(company_field(body, "flow_binding"), "snapshot"),
        "task",
      ),
      "created_by",
    ) {
    fail("MoonProj Flow report actor differs from its approved owner")
  }
  if company_field(body, "flow_binding") is Object(_) &&
    company_field(request, "flow_source_revision") !=
    company_field(company_field(body, "flow_binding"), "source_revision") {
    fail("MoonProj Flow report response changed the exact source revision")
  }
  let expected_bps = json_int_field(
      json_object(body, "report body"),
      "progress_pct",
    ) *
    100
  if company_field(request, "progress_bps") != ToJson::to_json(expected_bps) {
    fail("MoonProj Flow report response changed progress")
  }
}

///|
/// Recover reporting state separately from execution and acceptance. A pending
/// report is resubmitted with its saved body/key, never by executing work again.
pub async fn company_task_report_status(
  workspace : String,
  request_ref : String,
  report_key : String,
) -> Json {
  let root = resolve_workspace(workspace)
  let (flow, plan) = load_bound_inputs(root, request_ref)
  let base = company_report_base(flow, report_key)
  let envelope = load_company_task_report(
    root, flow, plan, request_ref, report_key,
  )
  let receipt = read_optional_json_ref(root, base + "/receipt.json")
  let revised = company_text(company_field(envelope, "binding"), "contract_id") ==
    "moonproj.flow-task-binding.v2"
  match receipt {
    Some(command) => validate_company_report_command(envelope, command)
    None => ()
  }
  {
    "contract_id": "moonproj.flow-task-report-status.v1",
    "task_id": company_field(company_field(envelope, "report_body"), "task_id"),
    "report_id": company_field(
      company_field(envelope, "report_body"),
      "report_id",
    ),
    "state": if receipt is Some(_) {
      if revised {
        "reported_local_cache"
      } else {
        "reported"
      }
    } else {
      "pending_report"
    },
    "next_action": if receipt is Some(_) {
      if revised {
        "verify_company_service_receipt"
      } else {
        "inspect_report"
      }
    } else {
      "submit_saved_report"
    },
    "report_ref": base + "/report.json",
    "receipt_ref": if receipt is Some(_) {
      Json::string(base + "/receipt.json")
    } else {
      Json::null()
    },
    "receipt": receipt.unwrap_or(Json::null()),
    "acknowledgement": if receipt is Some(_) {
      "local_cached_command_not_independently_verified"
    } else {
      "not_observed"
    },
    "task_acceptance": "unchanged",
  }
}
