///|
pub fn adapter_id() -> String {
  "moonproj-project-plan-v1"
}

///|
pub fn protocol() -> String {
  "moonflow.adapter.v2"
}

///|
pub fn capability_json(healthy? : Bool = false) -> Json {
  {
    "adapter_id": adapter_id(),
    "product_id": "moonproj",
    "pack_id": "moonproj",
    "pack_version": @project_plan.pack_version(),
    "protocol": protocol(),
    "operations": [@project_plan.operation_ref()],
    "authority_classes": ["workspace-mutation"],
    "input_contracts": [@project_plan.input_schema_ref()],
    "output_contracts": [@project_plan.output_schema_ref()],
    "claim_ceiling": "digital-artifact",
    "healthy": healthy,
    "supports_cancel": false,
    "supports_reconcile": true,
  }
}

///|
struct FlowRequest {
  request_id : String
  run_id : String
  book_id : String
  work_item_id : String
  declaration_id : String
  attempt_id : String
  idempotency_key : String
  product_id : String
  operation : String
  requested_authority : String
  acceptance_criteria : Array[String]
  input_contracts : Array[String]
  output_contracts : Array[String]
  required_claim : String
  input_digest : String
  input_artifacts : Array[String]
  timeout_ms : Int
  created_at : String
} derive(Debug, Eq)

///|
fn json_object(value : Json, label : String) -> Map[String, Json] raise {
  match value {
    Object(fields) => fields
    _ => fail("MoonProj adapter requires \{label} to be an object")
  }
}

///|
fn json_string_field(fields : Map[String, Json], name : String) -> String raise {
  match fields.get(name) {
    Some(String(value)) if !value.trim().is_empty() => value
    _ => fail("MoonProj adapter requires \{name}")
  }
}

///|
fn json_int_field(fields : Map[String, Json], name : String) -> Int raise {
  match fields.get(name) {
    Some(Number(value, ..)) if value == value.trunc() => value.to_int()
    _ => fail("MoonProj adapter requires integer \{name}")
  }
}

///|
fn json_strings_field(
  fields : Map[String, Json],
  name : String,
) -> Array[String] raise {
  guard fields.get(name) is Some(Array(values)) else {
    fail("MoonProj adapter requires array \{name}")
  }
  values.map(value => {
    match value {
      String(text) if !text.trim().is_empty() => text
      _ => fail("MoonProj adapter requires non-empty strings in \{name}")
    }
  })
}

///|
fn safe_path_segment(value : String) -> Bool {
  if value.trim().is_empty() {
    return false
  }
  for ch in value {
    if !(ch.is_ascii_alphabetic() ||
      ch.is_ascii_digit() ||
      ch == '-' ||
      ch == '_' ||
      ch == '.') {
      return false
    }
  }
  value != "." && value != ".."
}

///|
fn canonical_utc_timestamp(value : String) -> Bool {
  if value.length() != 20 ||
    value[4] != '-' ||
    value[7] != '-' ||
    value[10] != 'T' ||
    value[13] != ':' ||
    value[16] != ':' ||
    value[19] != 'Z' {
    return false
  }
  try @time.PlainDateTime::from_str(value[0:19]) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
fn sha256_digest(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:].iter().all(ch => ch.is_ascii_digit() || (ch >= 'a' && ch <= 'f'))
}

///|
fn decode_flow_request(value : Json) -> FlowRequest raise {
  let fields = json_object(value, "request")
  let request = {
    request_id: json_string_field(fields, "request_id"),
    run_id: json_string_field(fields, "run_id"),
    book_id: json_string_field(fields, "book_id"),
    work_item_id: json_string_field(fields, "work_item_id"),
    declaration_id: json_string_field(fields, "declaration_id"),
    attempt_id: json_string_field(fields, "attempt_id"),
    idempotency_key: json_string_field(fields, "idempotency_key"),
    product_id: json_string_field(fields, "product_id"),
    operation: json_string_field(fields, "operation"),
    requested_authority: json_string_field(fields, "requested_authority"),
    acceptance_criteria: json_strings_field(fields, "acceptance_criteria"),
    input_contracts: json_strings_field(fields, "input_contracts"),
    output_contracts: json_strings_field(fields, "output_contracts"),
    required_claim: json_string_field(fields, "required_claim"),
    input_digest: json_string_field(fields, "input_digest"),
    input_artifacts: json_strings_field(fields, "input_artifacts"),
    timeout_ms: json_int_field(fields, "timeout_ms"),
    created_at: json_string_field(fields, "created_at"),
  }
  validate_flow_request(request)
  request
}

///|
fn validate_flow_request(request : FlowRequest) -> Unit raise {
  if request.product_id != "moonproj" ||
    request.operation != @project_plan.operation_ref() {
    fail("MoonProj adapter owns only `\{@project_plan.operation_ref()}`")
  }
  if request.requested_authority != "workspace-mutation" {
    fail("MoonProj plan preparation requires workspace-mutation authority")
  }
  if request.required_claim != "digital-artifact" {
    fail("MoonProj plan preparation claim ceiling is digital-artifact")
  }
  if request.input_contracts != [@project_plan.input_schema_ref()] ||
    request.output_contracts != [@project_plan.output_schema_ref()] {
    fail("MoonProj Flow schema identities do not exactly match the pack")
  }
  if !safe_path_segment(request.run_id) ||
    !safe_path_segment(request.work_item_id) ||
    !safe_path_segment(request.attempt_id) {
    fail(
      "MoonProj Flow run, work item and attempt ids must be safe path segments",
    )
  }
  if request.idempotency_key.length() > 512 ||
    request.book_id.length() > 256 ||
    request.declaration_id.length() > 256 ||
    request.acceptance_criteria.is_empty() ||
    !sha256_digest(request.input_digest) ||
    request.input_artifacts.is_empty() ||
    request.timeout_ms <= 0 ||
    !canonical_utc_timestamp(request.created_at) {
    fail(
      "MoonProj Flow request has invalid idempotency, digest, input, timeout or time",
    )
  }
}

///|
fn attempt_base(request : FlowRequest) -> String {
  ".moonsuite/products/moonproj/adapter-attempts/\{request.attempt_id}"
}

///|
fn intent_ref(request : FlowRequest) -> String {
  "\{attempt_base(request)}/intent.json"
}

///|
fn artifact_ref(request : FlowRequest) -> String {
  "\{attempt_base(request)}/project-plan-artifact.json"
}

///|
fn internal_result_ref(request : FlowRequest) -> String {
  "\{attempt_base(request)}/adapter-result.json"
}

///|
fn idempotency_ref(request : FlowRequest) -> String {
  let digest = sha256_text(request.idempotency_key)
  ".moonsuite/products/moonproj/idempotency/\{digest[7:]}.json"
}
