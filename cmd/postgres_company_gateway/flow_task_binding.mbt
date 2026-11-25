///|
fn flow_gateway_route(path : String) -> (String, String, String)? {
  match path.split("/").map(part => part.to_owned()).collect() {
    ["", "api", "company", "plan", "tasks", task, action] if valid_identifier(
        task,
      ) &&
      ["flow-snapshot", "flow-bindings", "flow-execute"].contains(action) =>
      Some((task, action, ""))
    ["", "api", "company", "plan", "tasks", task, "flow-reports", key, action] if valid_identifier(
        task,
      ) &&
      valid_identifier(key) &&
      ["return", "status"].contains(action) => Some((task, action, key))
    _ => None
  }
}

///|
async fn flow_gateway_command(
  bridge : NativeBridge,
  path : String,
  body : Json,
  key : String,
) -> ProxyResult raise GatewayError {
  if !valid_identifier(key) {
    raise fail("a bounded immutable command key is required")
  }
  let request : @http.Request = {
    meth: @http.Post,
    path,
    headers: {
      "X-Moonproj-Actor": bridge.actor,
      "Content-Type": "application/json",
    },
  }
  proxy_request(
    bridge.service_uri,
    bridge.service_token,
    bridge.actor_signing_secret,
    @http.Post,
    path,
    request,
    @encoding/utf8.encode(body.stringify()),
    Some(key),
  )
}

///|
async fn flow_gateway_handle(
  bridge : NativeBridge,
  workspace : String,
  task : String,
  action : String,
  report_key : String,
  method : @http.RequestMethod,
  body : Json,
) -> ProxyResult {
  let prefix = "/api/company/plan/tasks/" + task
  if action == "flow-snapshot" {
    if method != @http.Get {
      return native_json_result(405, {
        "error": "use GET to capture the current snapshot",
      })
    }
    return native_company_request(
      bridge,
      @http.Get,
      prefix + "/flow-snapshot",
      Json::null(),
    )
  }
  if method != @http.Post {
    return native_json_result(405, {
      "error": "use POST for this explicit Flow operation",
    })
  }
  let request_ref = native_text(body, "request_ref")
  let binding = @moonflow_adapter.company_task_binding_proposal(
    workspace, request_ref,
  )
  if native_text(binding, "task_id") != task ||
    native_text(
      native_field(native_field(binding, "snapshot"), "task"),
      "created_by",
    ) !=
    bridge.actor {
    return native_json_result(403, {
      "error": "Flow request must belong to the signed task owner and exact task",
    })
  }
  if action == "flow-bindings" {
    let result = flow_gateway_command(
      bridge,
      prefix + "/flow-bindings",
      { "binding": binding, "authority": native_field(body, "authority") },
      native_text(body, "approval_key"),
    )
    if result.status != 200 && result.status != 201 {
      return result
    }
    let receipt = native_result_json(result)
    let persisted = @moonflow_adapter.record_company_task_approval(
      workspace, request_ref, receipt,
    )
    return native_json_result(200, {
      "binding": persisted,
      "approval": native_field(receipt, "command"),
      "next_action": "execute_exact_approved_plan",
      "task_acceptance": "unchanged",
    })
  }
  if action == "flow-execute" {
    let result = @moonflow_adapter.execute_approved_company_task(
      workspace,
      request_ref,
      native_text(body, "result_ref"),
      service_uri=bridge.service_uri,
      service_token=bridge.service_token,
      actor_id=bridge.actor,
      actor_signature=hmac_hex(bridge.actor_signing_secret, bridge.actor),
    )
    return native_json_result(200, {
      "result": result,
      "task_acceptance": "unchanged",
      "next_action": "prepare_exact_report",
    })
  }
  let status = @moonflow_adapter.company_task_report_status(
    workspace, request_ref, report_key,
  )
  if action == "status" && native_text(status, "state") == "pending_report" {
    return native_json_result(200, status)
  }
  // A pending saved report is the only return input. No execute/reconcile call
  // occurs here, including after service outage or lost acknowledgement.
  let envelope = @moonflow_adapter.saved_company_task_report(
    workspace, request_ref, report_key,
  )
  if native_text(envelope, "path") != prefix + "/report" {
    raise fail("saved report targets another task")
  }
  if native_text(status, "state") == "reported_local_cache" {
    return flow_gateway_verified_report(
      bridge, workspace, request_ref, report_key, task, envelope,
    )
  }
  let result = flow_gateway_command(
    bridge,
    native_text(envelope, "path"),
    native_field(envelope, "report_body"),
    native_text(envelope, "idempotency_key"),
  )
  if result.status != 200 && result.status != 201 {
    return result
  }
  let observed = flow_gateway_read_report(bridge, task, envelope)
  if observed.status != 200 {
    return observed
  }
  if native_field(native_result_json(result), "command") !=
    native_field(native_result_json(observed), "command") {
    raise fail("Report acknowledgement differs from persisted service readback")
  }
  flow_gateway_report_result(
    workspace,
    request_ref,
    report_key,
    native_result_json(observed),
  )
}

///|
async fn flow_gateway_read_report(
  bridge : NativeBridge,
  task : String,
  envelope : Json,
) -> ProxyResult {
  let observed = native_company_request(
    bridge,
    @http.Get,
    "/api/company/internal/plan/tasks/" +
    task +
    "/flow-report-receipts/" +
    native_text(envelope, "idempotency_key"),
    Json::null(),
  )
  if observed.status == 404 {
    return native_json_result(409, {
      "state": "unverified_receipt",
      "acknowledgement": "not_confirmed_by_company_service",
      "error": "No persisted company report matches this local receipt. Preserve the files and inspect the saved report before recovery.",
    })
  }
  observed
}

///|
async fn flow_gateway_report_result(
  workspace : String,
  request_ref : String,
  report_key : String,
  response : Json,
) -> ProxyResult {
  let cached = @moonflow_adapter.record_company_task_report_response(
    workspace, request_ref, report_key, response,
  )
  let fields = match cached {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  fields["state"] = Json::string("reported")
  fields["next_action"] = Json::string("inspect_report")
  fields["acknowledgement"] = Json::string("verified_company_service_readback")
  native_json_result(200, Json::object(fields))
}

///|
async fn flow_gateway_verified_report(
  bridge : NativeBridge,
  workspace : String,
  request_ref : String,
  report_key : String,
  task : String,
  envelope : Json,
) -> ProxyResult {
  let observed = flow_gateway_read_report(bridge, task, envelope)
  if observed.status != 200 {
    return observed
  }
  flow_gateway_report_result(
    workspace,
    request_ref,
    report_key,
    native_result_json(observed),
  )
}

///|
fn flow_gateway_error(error : Error) -> ProxyResult {
  match error {
    @moonflow_adapter.CompanyApprovalError::ServiceRejected(status) =>
      native_json_result(status, {
        "state": "blocked",
        "error": "The signed company service did not confirm this approval and task revision.",
      })
    @moonflow_adapter.CompanyApprovalError::ServiceUnavailable =>
      native_json_result(503, {
        "state": "unconfirmed",
        "error": "The signed company service is unavailable; local approval files cannot authorize execution.",
      })
    GatewayError::InvalidInput(message) =>
      native_json_result(422, { "error": message, "state": "blocked" })
    GatewayError::Upstream(_) =>
      native_json_result(503, {
        "error": "Company service unavailable. Preserve the same approval or report key and retry the saved operation.",
        "state": "unconfirmed",
      })
    _ =>
      native_json_result(409, {
        "error": "Exact task, approval, attempt, or report checkpoint differs or is incomplete. Preserve prior files; inspect and approve a new revision when scope changed.",
        "state": "blocked",
      })
  }
}
