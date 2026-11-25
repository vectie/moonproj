///|
fn charter_toggle_critical_task(
  charter : CompanyCharter,
  task_id : String,
) -> CompanyCharter {
  let trimmed = task_id.trim().to_owned()
  if trimmed.is_empty() {
    return charter
  }
  let next_ids = if charter.critical_task_ids.contains(trimmed) {
    charter.critical_task_ids.filter(id => id != trimmed)
  } else {
    let copied = charter.critical_task_ids.copy()
    copied.push(trimmed)
    copied
  }
  { ..charter, critical_task_ids: next_ids }
}

///|
fn charter_add_role(
  charter : CompanyCharter,
  role : CharterRole,
) -> CompanyCharter {
  let next_roles = charter.roles.copy()
  next_roles.push(role)
  { ..charter, roles: next_roles }
}

///|
fn charter_add_evolution(
  charter : CompanyCharter,
  entry : CharterEvolution,
) -> CompanyCharter {
  let next_log = charter.evolution_log.copy()
  next_log.push(entry)
  { ..charter, evolution_log: next_log }
}

///|
fn charter_add_resource(
  charter : CompanyCharter,
  resource : CharterResource,
) -> CompanyCharter {
  let next_resources = charter.resources.copy()
  next_resources.push(resource)
  { ..charter, resources: next_resources }
}

///|
fn charter_load(emit : @rabbita.Emit[Msg], request : Int) -> Cmd {
  @cmd.custom_cmd(scheduler => {
    charter_fetch("/api/company/charter", "GET", "", "", (status, body) => {
      scheduler.add(emit(CharterAction(Loaded(request, status, body))))
    })
  })
}

///|
fn charter_save(
  emit : @rabbita.Emit[Msg],
  request : Int,
  charter : CompanyCharter,
  expected_revision : Int?,
) -> Cmd {
  let key = "charter-" + dispatch_command_nonce()
  let body = charter_encode_payload(charter, expected_revision).stringify()
  @cmd.custom_cmd(scheduler => {
    charter_fetch("/api/company/charter", "PUT", key, body, (status, response) => {
      scheduler.add(emit(CharterAction(Saved(request, status, response))))
    })
  })
}

///|
fn charter_parse_tier(value : String) -> Int {
  match value.trim().to_owned() {
    "0" => 0
    "1" => 1
    _ => 2
  }
}

///|
fn charter_update(
  emit : @rabbita.Emit[Msg],
  action : CharterMsg,
  model : Model,
) -> (Cmd, Model) {
  let state = model.charter
  match action {
    Load => {
      let next_req = state.request + 1
      let next_status = if state.persisted { state.status } else { "loading" }
      (
        charter_load(emit, next_req),
        {
          ..model,
          charter: {
            ..state,
            request: next_req,
            status: next_status,
            error: "",
          },
        },
      )
    }
    Loaded(req, status, body) => {
      if req != state.request {
        return (none, model)
      }
      if status == 200 {
        let root = @json.parse(body) catch {
          _ =>
            return (
              none,
              {
                ..model,
                charter: {
                  ..state,
                  status: "error",
                  error: "公司章程响应无法解析，请重试读取。",
                },
              },
            )
        }
        let persisted = products_field(root, "persisted") is True
        let charter_json = products_field(root, "charter")
        if !persisted || charter_json is Null {
          return (
            none,
            {
              ..model,
              charter: {
                ..state,
                status: "empty",
                persisted: false,
                charter: None,
                error: "",
              },
            },
          )
        }
        match charter_decode_json(charter_json) {
          Some(decoded) =>
            (
              none,
              {
                ..model,
                charter: {
                  ..state,
                  status: "ready",
                  persisted: true,
                  charter: Some(decoded),
                  error: "",
                },
              },
            )
          None =>
            (
              none,
              {
                ..model,
                charter: {
                  ..state,
                  status: "error",
                  error: "公司章程字段不完整，未能载入。",
                },
              },
            )
        }
      } else if status == 401 || status == 403 {
        (
          none,
          {
            ..model,
            charter: {
              ..state,
              status: "error",
              error: "需要先登录公司会话才能读取公司章程。",
            },
          },
        )
      } else {
        let detail = dispatch_response_error(body)
        (
          none,
          {
            ..model,
            charter: {
              ..state,
              status: "error",
              error: if detail.is_empty() {
                "公司章程读取失败（状态码 " + status.to_string() + "），请重试。"
              } else {
                "公司章程读取失败：" + detail
              },
            },
          },
        )
      }
    }
    Saved(req, status, body) => {
      if req != state.request {
        return (none, model)
      }
      if status == 200 || status == 201 {
        let root = @json.parse(body) catch { _ => Json::null() }
        let charter_json = products_field(root, "charter")
        match charter_decode_json(charter_json) {
          Some(saved) =>
            (
              none,
              {
                ..model,
                charter: {
                  ..state,
                  status: "ready",
                  saving: false,
                  persisted: true,
                  charter: Some(saved),
                  error: "",
                  save_note: "已持久化公司章程（修订 v" +
                  saved.revision.to_string() +
                  "）。",
                  init_form_open: false,
                  init_title: "",
                  init_north_star: "",
                  role_form_open: false,
                  role_name: "",
                  role_tier: 2,
                  role_kind: "agent",
                  role_reports_to: "",
                  role_mission: "",
                  role_powers: "",
                  role_limits: "",
                  role_skill_ref: "",
                  role_model: "",
                  evo_form_open: false,
                  evo_target: "agent",
                  evo_target_id: "",
                  evo_change: "",
                  evo_evidence: "",
                  resource_form_open: false,
                  resource_name: "",
                  resource_kind: "moonbook",
                  resource_uri: "",
                  resource_desk_url: "",
                  resource_access: "read_only",
                  resource_owner_role: "",
                  resource_notes: "",
                },
              },
            )
          None =>
            (
              none,
              {
                ..model,
                charter: {
                  ..state,
                  saving: false,
                  error: "章程已写入但返回体无法解析，请刷新核实。",
                },
              },
            )
        }
      } else if status == 409 {
        (
          none,
          {
            ..model,
            charter: {
              ..state,
              saving: false,
              error: "公司章程存在并发更新，请先刷新再保存。",
            },
          },
        )
      } else {
        let detail = dispatch_response_error(body)
        (
          none,
          {
            ..model,
            charter: {
              ..state,
              saving: false,
              error: if detail.is_empty() {
                "保存公司章程失败（状态码 " + status.to_string() + "）。"
              } else {
                "保存公司章程失败：" + detail
              },
            },
          },
        )
      }
    }
    ToggleInitForm =>
      (
        none,
        {
          ..model,
          charter: {
            ..state,
            init_form_open: !state.init_form_open,
            error: "",
            save_note: "",
          },
        },
      )
    InputInit(field, value) => {
      let next = match field {
        "title" => { ..state, init_title: value }
        "north_star" => { ..state, init_north_star: value }
        _ => state
      }
      (none, { ..model, charter: next })
    }
    InitializeDefault => {
      if state.saving {
        return (none, model)
      }
      let next_req = state.request + 1
      let starter = charter_starter_template(model.company_name, "")
      let expected = match state.charter {
        Some(c) => Some(c.revision)
        None => Some(0)
      }
      (
        charter_save(emit, next_req, starter, expected),
        {
          ..model,
          charter: {
            ..state,
            request: next_req,
            saving: true,
            error: "",
            save_note: "",
          },
        },
      )
    }
    SubmitInitForm => {
      if state.saving {
        return (none, model)
      }
      let title = state.init_title.trim().to_owned()
      if title.is_empty() {
        return (
          none,
          {
            ..model,
            charter: { ..state, error: "请先填写公司核心使命标题。" },
          },
        )
      }
      let next_req = state.request + 1
      let starter = charter_starter_template(title, state.init_north_star)
      let expected = match state.charter {
        Some(c) => Some(c.revision)
        None => Some(0)
      }
      (
        charter_save(emit, next_req, starter, expected),
        {
          ..model,
          charter: {
            ..state,
            request: next_req,
            saving: true,
            error: "",
            save_note: "",
          },
        },
      )
    }
    ToggleCriticalTask(task_id) => {
      if state.saving || !state.persisted {
        return (none, model)
      }
      match state.charter {
        Some(current) => {
          let updated = charter_toggle_critical_task(current, task_id)
          let next_req = state.request + 1
          (
            charter_save(emit, next_req, updated, Some(current.revision)),
            {
              ..model,
              charter: {
                ..state,
                request: next_req,
                saving: true,
                error: "",
                save_note: "",
              },
            },
          )
        }
        None => (none, model)
      }
    }
    ToggleRoleForm =>
      (
        none,
        {
          ..model,
          charter: {
            ..state,
            role_form_open: !state.role_form_open,
            evo_form_open: false,
            error: "",
          },
        },
      )
    InputRole(field, value) => {
      let next = match field {
        "name" => { ..state, role_name: value }
        "tier" => { ..state, role_tier: charter_parse_tier(value) }
        "kind" =>
          {
            ..state,
            role_kind: if value == "human" { "human" } else { "agent" },
          }
        "reports_to" => { ..state, role_reports_to: value }
        "mission" => { ..state, role_mission: value }
        "powers" => { ..state, role_powers: value }
        "limits" => { ..state, role_limits: value }
        "skill_ref" => { ..state, role_skill_ref: value }
        "model" => { ..state, role_model: value }
        _ => state
      }
      (none, { ..model, charter: next })
    }
    SubmitRole => {
      if state.saving {
        return (none, model)
      }
      match state.charter {
        Some(current) => {
          let name = state.role_name.trim().to_owned()
          if name.is_empty() {
            return (
              none,
              {
                ..model,
                charter: { ..state, error: "请填写角色名称。" },
              },
            )
          }
          let id = charter_slug(
            name,
            "role",
            current.roles.map(r => r.id),
          )
          let role : CharterRole = {
            id,
            name,
            tier: state.role_tier,
            reports_to: state.role_reports_to.trim().to_owned(),
            kind: if state.role_kind == "human" { "human" } else { "agent" },
            mission: state.role_mission.trim().to_owned(),
            powers: charter_split_items(state.role_powers),
            limits: charter_split_items(state.role_limits),
            skill_ref: state.role_skill_ref.trim().to_owned(),
            model: state.role_model.trim().to_owned(),
            version: "v1",
            status: "active",
          }
          let updated = charter_add_role(current, role)
          let next_req = state.request + 1
          (
            charter_save(emit, next_req, updated, Some(current.revision)),
            {
              ..model,
              charter: {
                ..state,
                request: next_req,
                saving: true,
                error: "",
                save_note: "",
              },
            },
          )
        }
        None => (none, model)
      }
    }
    ToggleEvoForm =>
      (
        none,
        {
          ..model,
          charter: {
            ..state,
            evo_form_open: !state.evo_form_open,
            role_form_open: false,
            error: "",
          },
        },
      )
    InputEvo(field, value) => {
      let next = match field {
        "target" =>
          {
            ..state,
            evo_target: if value == "company" { "company" } else { "agent" },
          }
        "target_id" => { ..state, evo_target_id: value }
        "change" => { ..state, evo_change: value }
        "evidence" => { ..state, evo_evidence: value }
        _ => state
      }
      (none, { ..model, charter: next })
    }
    SubmitEvo => {
      if state.saving {
        return (none, model)
      }
      match state.charter {
        Some(current) => {
          let change = state.evo_change.trim().to_owned()
          if change.is_empty() {
            return (
              none,
              {
                ..model,
                charter: { ..state, error: "请填写本次演化升级的具体变更内容。" },
              },
            )
          }
          let id = charter_slug(
            "evo-" + (current.evolution_log.length() + 1).to_string(),
            "evo",
            current.evolution_log.map(e => e.id),
          )
          let entry : CharterEvolution = {
            id,
            date: policy_today(),
            target: if state.evo_target == "company" {
              "company"
            } else {
              "agent"
            },
            target_id: state.evo_target_id.trim().to_owned(),
            change,
            evidence: state.evo_evidence.trim().to_owned(),
          }
          let updated = charter_add_evolution(current, entry)
          let next_req = state.request + 1
          (
            charter_save(emit, next_req, updated, Some(current.revision)),
            {
              ..model,
              charter: {
                ..state,
                request: next_req,
                saving: true,
                error: "",
                save_note: "",
              },
            },
          )
        }
        None => (none, model)
      }
    }
    ToggleResourceForm =>
      (
        none,
        {
          ..model,
          charter: {
            ..state,
            resource_form_open: !state.resource_form_open,
            error: "",
          },
        },
      )
    InputResource(field, value) => {
      let next = match field {
        "name" => { ..state, resource_name: value }
        "kind" =>
          {
            ..state,
            resource_kind: if ["moonbook", "corpus", "tool", "runtime"].contains(
                value,
              ) {
              value
            } else {
              "tool"
            },
          }
        "uri" => { ..state, resource_uri: value }
        "desk_url" => { ..state, resource_desk_url: value }
        "access" =>
          {
            ..state,
            resource_access: if ["read_only", "read_write", "execute"].contains(
                value,
              ) {
              value
            } else {
              "read_only"
            },
          }
        "owner_role" => { ..state, resource_owner_role: value }
        "notes" => { ..state, resource_notes: value }
        _ => state
      }
      (none, { ..model, charter: next })
    }
    SubmitResource => {
      if state.saving {
        return (none, model)
      }
      match state.charter {
        Some(current) => {
          let name = state.resource_name.trim().to_owned()
          if name.is_empty() {
            return (
              none,
              {
                ..model,
                charter: { ..state, error: "请填写资源名称。" },
              },
            )
          }
          let id = charter_slug(
            name,
            "res",
            current.resources.map(r => r.id),
          )
          let resource : CharterResource = {
            id,
            name,
            kind: state.resource_kind,
            uri: state.resource_uri.trim().to_owned(),
            desk_url: state.resource_desk_url.trim().to_owned(),
            access: state.resource_access,
            owner_role: state.resource_owner_role.trim().to_owned(),
            notes: state.resource_notes.trim().to_owned(),
          }
          let updated = charter_add_resource(current, resource)
          let next_req = state.request + 1
          (
            charter_save(emit, next_req, updated, Some(current.revision)),
            {
              ..model,
              charter: {
                ..state,
                request: next_req,
                saving: true,
                error: "",
                save_note: "",
              },
            },
          )
        }
        None => (none, model)
      }
    }
  }
}
