///|
fn workbench_route(path : String) -> (String, String)? {
  let parts = path.split("/").map(v => v.to_owned()).collect()
  match parts {
    ["", "api", "company", "projects", project, "prepared-plans"] if valid_identifier(
        project,
      ) => Some((project, ""))
    ["", "api", "company", "projects", project, "prepared-plans", key] if valid_identifier(
        project,
      ) &&
      valid_identifier(key) => Some((project, key))
    _ => None
  }
}

///|
fn workbench_error(error : Error) -> ProxyResult {
  let (status, message) = match error {
    GatewayError::InvalidInput(message) => (422, message)
    GatewayError::Upstream(_) =>
      (
        503, "Company service is unavailable. Keep the draft, restore the existing gateway/service connection, then retry.",
      )
    @project_plan.ProjectPlanCapabilityError::Invalid(message) => (422, message)
    @project_plan.ProjectPlanCapabilityError::Plan(error) =>
      (
        422,
        "Task dependencies must precede their dependent task: \{Repr(error)}",
      )
    @project_plan.ProjectPlanCapabilityError::Project(_) =>
      (422, "The selected project cannot form a native planning proposal")
    @project_plan.ProjectPlanCapabilityError::Money(_) =>
      (422, "Check the budget currency and task costs")
    @plan_workbench.InputError::Invalid(message) => (422, message)
    _ =>
      (
        503, "The exact prepared plan could not be stored or reopened. Check the existing --moonsuite-workspace-root/moonproj workspace and preserve this draft. If the same version conflicts, edit to create a new version.",
      )
  }
  native_json_result(status, {
    "error": message,
    "persisted": if status == 422 {
      Json::boolean(false)
    } else {
      Json::null()
    },
    "state": if status == 422 {
      "invalid"
    } else {
      "unconfirmed"
    },
  })
}

///|
async fn workbench_handle(
  bridge : NativeBridge,
  workspace : String,
  project_id : String,
  key : String,
  method : @http.RequestMethod,
  body : Json,
) -> ProxyResult {
  // Re-read the exact company project through the existing signed service on every operation.
  // No project, task, cash, acceptance or authorization command is sent.
  let detail = native_company_request(
    bridge,
    @http.Get,
    "/api/company/projects/" + project_id,
    Json::null(),
  )
  if detail.status != 200 {
    return detail
  }
  let project = native_result_json(detail)
  if native_text(project, "project_id") != project_id {
    raise fail("Company service returned another project")
  }
  if method == @http.Post && key.is_empty() {
    let _ : @plan_workbench.Draft = @json.from_json(body) catch {
      _ =>
        raise fail(
          "Plan form is malformed; restore all owners, tasks, milestones, risk and budget fields",
        )
    }
    if native_text(body, "project_id") != project_id {
      raise fail("Plan draft belongs to another project")
    }
    native_json_result(
      200,
      @moonflow_adapter.prepare_workbench(
        workspace,
        bridge.actor,
        project,
        body,
      ),
    )
  } else if method == @http.Get && key.is_empty() {
    native_json_result(
      200,
      @moonflow_adapter.list_workbench(workspace, bridge.actor, project_id),
    )
  } else if method == @http.Get {
    native_json_result(
      200,
      @moonflow_adapter.read_workbench(workspace, bridge.actor, project_id, key),
    )
  } else {
    native_json_result(405, {
      "error": "Use GET to reopen or POST to prepare and save a plan",
    })
  }
}
