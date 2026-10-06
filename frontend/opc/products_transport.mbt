///|
// Rabbita's generic HTTP helper does not expose status codes. These read-only
// requests preserve HTTP status so auth, missing evidence and offline differ.
fn products_read(url : String, receive : (Int, String) -> Cmd) -> Cmd {
  @cmd.custom_cmd(fn(scheduler) {
    products_fetch(url, (status, body) => scheduler.add(receive(status, body)))
  })
}

///|
extern "js" fn products_fetch(url : String, receive : (Int, String) -> Unit) =
  #| (url, receive) => {
  #|   fetch(url, {method: "GET", credentials: "same-origin", headers: {Accept: "application/json"}})
  #|     .then(async response => receive(response.status, await response.text()))
  #|     .catch(() => receive(0, ""));
  #| }

///|
fn products_load_catalog(emit : @rabbita.Emit[Msg], request : Int) -> Cmd {
  products_read("/api/moonsuite/products", (status, body) => {
    emit(ProductsAction(CatalogRead(request, status, body)))
  })
}

///|
fn products_load_detail(
  emit : @rabbita.Emit[Msg],
  kind : String,
  id : String,
  selection : Int,
) -> Cmd {
  if !products_id_valid(id) {
    return none
  }
  let url = if kind == "engineering" {
    "/api/company/engineering/projects/" + id
  } else {
    "/api/company/products/" + id + "/in-gate"
  }
  products_read(url, (status, body) => {
    emit(ProductsAction(DetailRead(kind, id, selection, status, body)))
  })
}

///|
fn products_load_projects(
  emit : @rabbita.Emit[Msg],
  state : ProductsState,
) -> Cmd {
  products_read("/api/company/projects", (status, body) => {
    emit(
      ProductsAction(
        ProjectsRead(
          state.selected_id,
          state.selection,
          state.project_request,
          status,
          body,
        ),
      ),
    )
  })
}

///|
fn products_load_work(emit : @rabbita.Emit[Msg], state : ProductsState) -> Cmd {
  if !products_id_valid(state.selected_id) {
    return none
  }
  products_read(products_work_url(state.selected_id), (status, body) => {
    emit(
      ProductsAction(
        WorkRead(
          state.selected_id,
          state.selection,
          "",
          state.work_request,
          status,
          body,
        ),
      ),
    )
  })
}

///|
fn products_work_url(product_id : String) -> String {
  "/api/company/tasks?product_id=" + dispatch_url_encode(product_id)
}

///|
fn products_admission_message(id : String, payload : Json) -> Msg {
  ProductInGateLoaded(
    id,
    product_in_gate_response_text(payload, "decision", "unknown"),
    product_in_gate_response_text(payload, "primary_value", "unknown"),
    product_in_gate_response_text(payload, "segment", ""),
    product_in_gate_response_text(payload, "workflow", ""),
    product_in_gate_response_refs(payload, "problem_evidence"),
    product_in_gate_response_refs(payload, "commitment_evidence"),
    product_in_gate_response_text(payload, "current_behavior_cost", ""),
    product_in_gate_response_text(payload, "outcome_metric", ""),
    product_in_gate_response_text(payload, "adoption_path", ""),
    product_in_gate_response_text(payload, "unresolved_risks", ""),
    product_in_gate_response_text(payload, "next_experiment", ""),
    product_in_gate_response_text(payload, "review_by", ""),
    product_in_gate_response_text(payload, "owner", ""),
    product_in_gate_response_persisted(payload),
  )
}

///|
fn products_engineering_message(id : String, payload : Json) -> Msg {
  let audit = products_field(payload, "audit")
  let findings = match products_field(audit, "accepted_findings") {
    Array(v) => v.length()
    _ => 0
  }
  EngineeringProjectionLoaded(
    id,
    projection_text(payload, "progress", "stage"),
    projection_text(payload, "health", "status"),
    projection_text(payload, "production", "release_eligibility"),
    projection_item_text(audit, "freshness", "missing"),
    projection_root_text(payload, "audit_id", ""),
    findings,
    projection_root_text(payload, "repository", "unknown"),
    projection_root_text(payload, "branch", "unknown"),
    projection_root_text(payload, "commit", "unknown"),
    projection_root_text(payload, "review_verdict", "needs_evidence"),
    projection_gate_states(payload),
  )
}
