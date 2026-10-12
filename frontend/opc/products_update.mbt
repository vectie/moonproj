///|
fn products_reset_evidence(model : Model, id : String) -> Model {
  {
    ..model,
    engineering_project: id,
    engineering_audit_state: "idle",
    engineering_audit_id: "",
    engineering_task_id: "",
    engineering_commit: "unknown",
    engineering_repository: "unknown",
    engineering_review: "needs_evidence",
    engineering_gate_states: [
      "unknown", "unknown", "unknown", "unknown", "unknown", "unknown", "unknown",
      "unknown", "unknown",
    ],
    engineering_progress: "unknown",
    engineering_health: "unknown",
    engineering_production: "unknown",
    engineering_freshness: "missing",
    engineering_findings: 0,
    engineering_poll_attempts: 0,
    product_in_gate_decision: "unknown",
    product_in_gate_primary_value: "solution",
    product_in_gate_segment: "",
    product_in_gate_workflow: "",
    product_in_gate_problem_evidence: "",
    product_in_gate_commitment_evidence: "",
    product_in_gate_current_behavior_cost: "",
    product_in_gate_outcome_metric: "",
    product_in_gate_adoption_path: "",
    product_in_gate_unresolved_risks: "",
    product_in_gate_next_experiment: "",
    product_in_gate_review_by: "",
    product_in_gate_owner: "",
    product_in_gate_persisted: false,
  }
}

///|
fn products_update(
  emit : @rabbita.Emit[Msg],
  action : ProductsMsg,
  model : Model,
) -> (Cmd, Model) {
  let state = model.products
  match action {
    Refresh => {
      let next = { ..state, state: "loading", request: state.request + 1, }
      (products_load_catalog(emit, next.request), { ..model, products: next, })
    }
    CatalogRead(request, status, body) => {
      if request != state.request {
        return (none, model)
      }
      let read_state = products_read_state(status, body)
      let inventories = if read_state == "ready" {
        products_decode_inventories(body)
      } else {
        None
      }
      let rows = if read_state == "ready" {
        products_decode(body)
      } else {
        None
      }
      match rows {
        None => {
          let next = {
            ..state,
            rows: [],
            inventories: [],
            inventory_state: "unavailable",
            state: if read_state == "ready" {
              "invalid"
            } else {
              read_state
            },
            selected_id: "",
            pending_work_group_id: "",
            selection: state.selection + 1,
            admission_state: "idle",
            engineering_state: "idle",
            projects: [],
            project_id: "",
            project_state: "idle",
            project_note: "",
            tasks: [],
            work_state: "idle",
          }
          (none, { ..products_reset_evidence(model, ""), products: next, })
        }
        Some(rows) => {
          let id = if rows.any(row => row.id == state.route_id) {
            state.route_id
          } else {
            ""
          }
          let next = {
            ..state,
            rows,
            inventories: inventories.unwrap_or([]),
            inventory_state: if inventories is None {
              "invalid"
            } else {
              products_inventory_read_state(body)
            },
            state: if rows.is_empty() {
              "empty"
            } else {
              "ready"
            },
            selected_id: id,
          }
          let loaded = { ..model, products: next, }
          if id.is_empty() {
            (
              none,
              {
                ..products_reset_evidence(loaded, ""),
                products: {
                  ..next,
                  selection: state.selection + 1,
                  admission_state: "idle",
                  engineering_state: "idle",
                  projects: [],
                  pending_work_group_id: "",
                  project_id: "",
                  project_state: "idle",
                  project_note: "",
                  tasks: [],
                  work_state: "idle",
                },
              },
            )
          } else {
            products_update(emit, Select(id), loaded)
          }
        }
      }
    }
    Search(query) => (none, { ..model, products: { ..state, search: query, }, })
    FilterWork(status) =>
      if ["all", "verified", "partial", "planned", "unverified", "missing"].contains(
          status,
        ) {
        (none, { ..model, products: { ..state, inventory_filter: status, }, })
      } else {
        (none, model)
      }
    SearchWork(query) =>
      (none, { ..model, products: { ..state, inventory_query: query, }, })
    PrepareWork(product_id, group_id) =>
      products_prepare_inventory_work(emit, model, product_id, group_id)
    CancelWorkChoice =>
      (
        none,
        {
          ..model,
          products: { ..state, pending_work_group_id: "", },
          notice: "已取消本次工作选择；已有草稿和正式任务不受影响。",
        },
      )
    Reverse =>
      (none, { ..model, products: { ..state, reverse: !state.reverse, }, })
    Select(id) => {
      let row = match products_find(state.rows, id) {
        Some(row) => row
        None => return (none, model)
      }
      if state.state != "ready" {
        return (none, model)
      }
      let next = {
        ..state,
        selected_id: id,
        inventory_filter: "all",
        inventory_query: "",
        pending_work_group_id: "",
        route_id: id,
        selection: state.selection + 1,
        admission_state: "loading",
        engineering_state: if row.engineering_target.is_empty() {
          "not_enrolled"
        } else {
          "loading"
        },
        projects: [],
        project_id: "",
        project_state: "idle",
        project_note: "",
        project_request: state.project_request + 1,
        tasks: [],
        work_state: "idle",
        work_request: state.work_request + 1,
      }
      (
        @cmd.batch([
          load_product_in_gate(emit, id, next.selection),
          if row.engineering_target.is_empty() {
            none
          } else {
            load_engineering_projection(
              emit,
              row.engineering_target,
              next.selection,
            )
          },
        ]),
        { ..products_reset_evidence(model, id), products: next, notice: "", },
      )
    }
    DetailRead(kind, id, selection, status, body) => {
      if id != state.selected_id ||
        selection != state.selection ||
        id != model.engineering_project {
        return (none, model)
      }
      let payload = @json.parse(body) catch { _ => Json::null() }
      let read_state = products_read_state(status, body)
      let valid = if kind == "engineering" {
        let audit = products_field(payload, "audit")
        audit is Object(_) &&
        products_text(audit, "project") == id &&
        ["missing", "stale", "fresh"].contains(
          products_text(audit, "freshness"),
        )
      } else {
        product_in_gate_response_valid(payload, id)
      }
      let result_state = if read_state == "ready" && !valid {
        "invalid"
      } else {
        read_state
      }
      let next = if kind == "engineering" {
        { ..state, engineering_state: result_state, }
      } else {
        { ..state, admission_state: result_state, }
      }
      let loaded = { ..model, products: next, }
      if result_state != "ready" {
        return (none, loaded)
      }
      update(
        emit,
        if kind == "engineering" {
          products_engineering_message(id, payload)
        } else {
          products_admission_message(id, payload)
        },
        loaded,
      )
    }
    OpenEngineering(page) => {
      let row = match products_selected(state) {
        Some(row) => row
        None => return (none, model)
      }
      if row.engineering_target.is_empty() ||
        (page != Quality && page != MoonSuite) {
        return (none, model)
      }
      (none, { ..model, page, mobile_nav: false, notice: "", })
    }
    LoadProjects => {
      if products_selected(state) is None {
        return (none, model)
      }
      let next = {
        ..state,
        project_state: "loading",
        project_note: "",
        project_request: state.project_request + 1,
        project_choice: state.project_choice + 1,
        project_id: "",
        projects: [],
      }
      (products_load_projects(emit, next), { ..model, products: next, })
    }
    ProjectsRead(id, selection, request, status, body) => {
      if id != state.selected_id ||
        selection != state.selection ||
        request != state.project_request {
        return (none, model)
      }
      let read_state = products_read_state(status, body)
      let rows = if read_state == "ready" {
        products_decode_projects(body)
      } else {
        None
      }
      match rows {
        None =>
          (
            none,
            {
              ..model,
              products: {
                ..state,
                project_state: if read_state == "ready" {
                  "invalid"
                } else {
                  read_state
                },
                projects: [],
                project_note: "",
                project_id: "",
              },
            },
          )
        Some(rows) => {
          let mapped = match products_selected(state) {
            Some(row) => row.company_project_id
            None => ""
          }
          let selected = if rows.any(row => row.id == mapped) {
            mapped
          } else {
            ""
          }
          (
            none,
            {
              ..model,
              products: {
                ..state,
                projects: rows,
                project_note: products_project_note(body),
                project_state: if rows.is_empty() {
                  "empty"
                } else {
                  "ready"
                },
                project_id: selected,
              },
            },
          )
        }
      }
    }
    SelectProject(id) => {
      if state.project_state != "ready" ||
        !state.projects.any(row => row.id == id) {
        return (none, model)
      }
      (
        none,
        {
          ..model,
          products: {
            ..state,
            project_id: id,
            project_choice: state.project_choice + 1,
            project_request: state.project_request + 1,
          },
        },
      )
    }
    LoadWork => {
      if state.state != "ready" || products_selected(state) is None {
        return (none, model)
      }
      let next = {
        ..state,
        work_state: "loading",
        tasks: [],
        work_request: state.work_request + 1,
      }
      (products_load_work(emit, next), { ..model, products: next, })
    }
    WorkRead(id, selection, _, request, status, body) => {
      if id != state.selected_id ||
        selection != state.selection ||
        request != state.work_request {
        return (none, model)
      }
      let read_state = products_read_state(status, body)
      let rows = if read_state == "ready" {
        products_decode_tasks(body, id)
      } else {
        None
      }
      match rows {
        None =>
          (
            none,
            {
              ..model,
              products: {
                ..state,
                work_state: if read_state == "ready" {
                  "invalid"
                } else {
                  read_state
                },
                tasks: [],
              },
            },
          )
        Some(rows) =>
          (
            none,
            {
              ..model,
              products: {
                ..state,
                tasks: rows,
                work_state: if rows.is_empty() {
                  "empty"
                } else {
                  "ready"
                },
              },
            },
          )
      }
    }
    Prepare => {
      if !state.pending_work_group_id.is_empty() {
        return products_prepare_inventory_work(
          emit,
          model,
          state.selected_id,
          state.pending_work_group_id,
        )
      }
      let row = match products_selected(state) {
        Some(row) => row
        None => return (none, model)
      }
      if !products_project_exists(state) {
        return (
          none,
          {
            ..model,
            notice: "没有可用的公司项目关联。请先读取并明确选择实际公司项目。",
          },
        )
      }
      dispatch_prepare_draft(
        emit,
        model,
        row.id,
        state.project_id,
        Some(row),
        false,
      )
    }
    CancelPreparation =>
      (
        none,
        {
          ..model,
          page: Products,
          products: products_clear_preparation(state),
          dispatch_task_form_open: false,
          notice: "已暂存草稿；没有创建或启动任务。",
        },
      )
    OpenTask(id) => {
      if state.work_state != "ready" ||
        state.state != "ready" ||
        products_selected(state) is None ||
        !state.tasks.any(task => {
          task.id == id && task.product_id == state.selected_id
        }) {
        return (none, model)
      }
      open_dispatch_task(emit, {
        ..model,
        products: products_clear_preparation(state),
        dispatch_task_open_id: id,
      })
    }
  }
}
