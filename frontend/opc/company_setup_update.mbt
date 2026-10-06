///|
fn company_setup_check_profile(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> (Cmd, Model) {
  let state = model.company_setup
  let loaded = company_setup_apply(model, state)
  if ["loading", "idle"].contains(state.profile_state) ||
    ["loading", "idle"].contains(state.units_state) {
    return (none, loaded)
  }
  let op = state.company
  if op.phase != "checking" {
    return (none, loaded)
  }
  if company_setup_profile_verified(state) {
    let matches = match op.request {
      Some(request) =>
        state.profile.unwrap().name == request.name &&
        (
          request.unit_id.is_empty() ||
          state.profile.unwrap().unit_id == request.unit_id
        )
      None => true
    }
    let next = {
      ..state,
      company: {
        ..company_setup_operation(),
        phase: "confirmed",
        note: if matches {
          "已从正式档案及组织单位读回核实。"
        } else {
          "已有正式档案；显示服务器实际记录，没有覆盖或改名。"
        },
      },
    }
    return (
      company_setup_persist(emit, next, "", ""),
      company_setup_apply(loaded, next),
    )
  }
  let next = {
    ..state,
    company: {
      ..op,
      phase: if state.profile_state == "empty" &&
        ["ready", "empty"].contains(state.units_state) {
        "retryable"
      } else {
        "uncertain"
      },
      note: if state.profile_state == "empty" {
        "正式档案尚未读到；可用相同请求重试。"
      } else {
        "尚未核实正式档案与组织单位；保留原请求，请重新读取。"
      },
    },
  }
  (none, company_setup_apply(loaded, next))
}

///|
fn company_setup_update(
  emit : @rabbita.Emit[Msg],
  action : CompanySetupMsg,
  model : Model,
) -> (Cmd, Model) {
  let state = model.company_setup
  match action {
    Refresh => {
      let next = {
        ..state,
        session_request: state.session_request + 1,
        session_state: "loading",
      }
      (
        company_setup_get("/api/session", (status, body) => {
          emit(
            CompanySetupAction(SessionRead(next.session_request, status, body)),
          )
        }),
        { ..model, company_setup: next, },
      )
    }
    SessionRead(request, status, body) => {
      if request != state.session_request {
        return (none, model)
      }
      let root = @json.parse(body) catch { _ => Json::null() }
      let actor = if status == 200 &&
        products_field(root, "authenticated") is True {
        products_text(root, "actor_id")
      } else {
        ""
      }
      if actor.is_empty() {
        let (cmd, reset) = company_setup_session(emit, model, "")
        let result = if status == 200 {
          "unauthorized"
        } else {
          products_read_state(status, body)
        }
        return (
          cmd,
          {
            ..reset,
            company_setup: {
              ..reset.company_setup,
              session_state: result,
              profile_state: result,
              units_state: result,
            },
          },
        )
      }
      // Preserve in-flight commands when merely refreshing the same actor.
      if actor == state.actor {
        let next = {
          ..state,
          session_state: "ready",
          read_request: state.read_request + 1,
          profile_state: "loading",
          units_state: "loading",
        }
        return (
          @cmd.batch([
            company_setup_reads(emit, next),
            if state.storage != "可恢复" &&
              state.company.request is None &&
              state.project.request is None {
              @cmd.custom_cmd(scheduler => {
                scheduler.add(
                  emit(
                    CompanySetupAction(
                      Restored(actor, next.epoch, company_setup_read(actor)),
                    ),
                  ),
                )
              })
            } else {
              none
            },
          ]),
          company_setup_apply(model, next),
        )
      }
      company_setup_session(emit, model, actor)
    }
    ProfileRead(actor, epoch, request, status, body) => {
      if actor != state.actor ||
        epoch != state.epoch ||
        request != state.read_request {
        return (none, model)
      }
      let decoded = if status == 200 {
        company_setup_profile(body)
      } else {
        None
      }
      let next = match decoded {
        Some(Some(profile)) =>
          { ..state, profile: Some(profile), profile_state: "ready", }
        Some(None) => { ..state, profile: None, profile_state: "empty", }
        None =>
          {
            ..state,
            profile: None,
            profile_state: if status == 200 {
              "invalid"
            } else {
              products_read_state(status, body)
            },
          }
      }
      company_setup_check_profile(emit, { ..model, company_setup: next, })
    }
    UnitsRead(actor, epoch, request, status, body) => {
      if actor != state.actor ||
        epoch != state.epoch ||
        request != state.read_request {
        return (none, model)
      }
      let decoded = if status == 200 { company_setup_units(body) } else { None }
      let next = match decoded {
        Some(result) =>
          {
            ..state,
            units: result.rows,
            units_note: result.note,
            units_state: if result.rows.is_empty() {
              "empty"
            } else {
              "ready"
            },
          }
        None =>
          {
            ..state,
            units: [],
            units_note: "",
            units_state: if status == 200 {
              "invalid"
            } else {
              products_read_state(status, body)
            },
          }
      }
      company_setup_check_profile(emit, { ..model, company_setup: next, })
    }
    Restored(actor, epoch, body) => {
      if actor != state.actor || epoch != state.epoch {
        return (none, model)
      }
      if body.is_empty() {
        return (
          none,
          { ..model, company_setup: { ..state, storage: "可恢复", }, },
        )
      }
      let store : CompanySetupStore = @json.from_json(@json.parse(body)) catch {
        _ =>
          return (
            none,
            {
              ..model,
              company_setup: {
                ..state,
                storage: "本地恢复不可用；请修复存储后再创建。",
              },
            },
          )
      }
      if store.version != 1 ||
        !store.company
        .map(r => company_setup_request_valid(r, "company"))
        .unwrap_or(true) ||
        !store.project
        .map(r => company_setup_request_valid(r, "project"))
        .unwrap_or(true) ||
        !store.recent_project
        .map(r => company_setup_request_valid(r, "project"))
        .unwrap_or(true) {
        return (
          none,
          {
            ..model,
            company_setup: {
              ..state,
              storage: "恢复记录无效；不会据此创建或声明已保存。",
            },
          },
        )
      }
      let restore = fn(
        request : CompanySetupRequest?,
      ) -> CompanySetupOperation {
        {
          ..company_setup_operation(),
          request,
          attempted: request is Some(_),
          phase: if request is Some(_) {
            "uncertain"
          } else {
            "idle"
          },
          note: if request is Some(_) {
            "发现待核实请求；先读取正式记录，可安全恢复。"
          } else {
            ""
          },
        }
      }
      let restored_project = restore(
        match store.project {
          Some(r) => Some(r)
          None => store.recent_project
        },
      )
      let next = {
        ..state,
        company: restore(store.company),
        project: {
          ..restored_project,
          recover_only: store.project is None && store.recent_project is Some(_),
        },
        recent_project: store.recent_project,
        storage: "可恢复",
      }
      (
        none,
        {
          ..model,
          company_setup: next,
          company_name: if model.company_saved {
            model.company_name
          } else {
            store.company.map(r => r.name).unwrap_or(model.company_name)
          },
        },
      )
    }
    Input(field, value) => {
      let next = match field {
        "company_name" if company_setup_company_editable(model) =>
          return (none, { ..model, company_name: value, })
        "company_unit" if company_setup_company_editable(model) &&
          (
            value.is_empty() ||
            state.units.any(unit => {
              unit.id == value && unit.source == "imported"
            })
          ) => { ..state, company_unit_id: value, }
        "project_name" if company_setup_editable(state.project) =>
          { ..state, project_name: value, }
        "project_code" if company_setup_editable(state.project) =>
          { ..state, project_code: value, }
        "project_unit" if company_setup_editable(state.project) &&
          state.units.any(unit => unit.id == value) =>
          { ..state, project_unit_id: value, }
        _ => state
      }
      (none, { ..model, company_setup: next, })
    }
    Save(kind) => {
      if !["company", "project"].contains(kind) ||
        state.actor.is_empty() ||
        state.session_state != "ready" ||
        state.storage != "可恢复" {
        return (
          none,
          {
            ..model,
            notice: "请先读取当前登录身份并确认本地恢复存储可用。",
          },
        )
      }
      let op = company_setup_op(state, kind)
      if company_setup_busy(op) || (kind == "company" && model.company_saved) {
        return (none, model)
      }
      let request = match op.request {
        Some(request) => {
          if op.phase != "retryable" {
            return company_setup_update(emit, Recover(kind), model)
          }
          request
        }
        None => {
          if kind == "company" &&
            (
              state.profile_state != "empty" ||
              !["ready", "empty"].contains(state.units_state)
            ) {
            return (
              none,
              {
                ..model,
                notice: "必须先成功读取，确认还没有公司工作区档案。",
              },
            )
          }
          if kind == "project" &&
            (
              products_selected(model.products) is None ||
              state.units_state != "ready" ||
              !state.units.any(unit => unit.id == state.project_unit_id)
            ) {
            return (
              none,
              {
                ..model,
                notice: "请选择已读取的实际组织单位，再创建公司项目。",
              },
            )
          }
          let nonce = dispatch_command_nonce()
          {
            kind,
            key: "opc-" + kind + "-" + nonce,
            name: if kind == "company" {
              model.company_name.trim().to_owned()
            } else {
              state.project_name.trim().to_owned()
            },
            unit_id: if kind == "company" {
              state.company_unit_id
            } else {
              state.project_unit_id
            },
            project_code: if kind == "project" {
              state.project_code.trim().to_owned()
            } else {
              ""
            },
            project_id: if kind == "project" {
              "PRJ-" + nonce
            } else {
              ""
            },
            product_id: if kind == "project" {
              model.products.selected_id
            } else {
              ""
            },
          }
        }
      }
      if !company_setup_request_valid(request, kind) {
        return (
          none,
          {
            ..model,
            notice: "填写有效名称（最多 256 字）和项目编号。",
          },
        )
      }
      let next = company_setup_set_op(state, kind, {
        ..op,
        request: Some(request),
        phase: "saving",
        note: "先保存恢复请求，再提交正式创建。",
        selection: if op.request is Some(_) {
          op.selection
        } else {
          model.products.selection
        },
        project_choice: if op.request is Some(_) {
          op.project_choice
        } else {
          model.products.project_choice
        },
        retrying: op.attempted,
      })
      (
        company_setup_persist(emit, next, kind, request.key),
        { ..model, company_setup: next, notice: "", },
      )
    }
    Persisted(actor, epoch, kind, key, ok) => {
      if actor != state.actor || epoch != state.epoch {
        return (none, model)
      }
      if kind.is_empty() {
        return (
          none,
          {
            ..model,
            company_setup: {
              ..state,
              storage: if ok {
                "可恢复"
              } else {
                "清理恢复记录失败；正式保存结果仍以服务器读取为准。"
              },
            },
          },
        )
      }
      let op = company_setup_op(state, kind)
      let request = match op.request {
        Some(r) if r.key == key && op.phase == "saving" => r
        _ => return (none, model)
      }
      if !ok {
        let next = company_setup_set_op(state, kind, {
          ..op,
          request: if op.attempted {
            op.request
          } else {
            None
          },
          phase: if op.attempted {
            "retryable"
          } else {
            "failed"
          },
          note: if op.attempted {
            "本地存储失败，没有重新提交；原创建请求仍保留。"
          } else {
            "本地存储失败，没有提交创建；输入仍可修改。"
          },
        })
        return (none, { ..model, company_setup: next, })
      }
      let next = company_setup_set_op(state, kind, {
        ..op,
        attempted: true,
        phase: "posting",
        note: "已提交，等待正式记录。",
      })
      (
        company_setup_post(emit, next, request),
        { ..model, company_setup: next, },
      )
    }
    Posted(actor, epoch, kind, key, status, _) => {
      if actor != state.actor || epoch != state.epoch {
        return (none, model)
      }
      let op = company_setup_op(state, kind)
      match op.request {
        Some(r) if r.key == key && op.phase == "posting" => ()
        _ => return (none, model)
      }
      if (
          [400, 401, 403, 404, 422].contains(status) ||
          (status == 409 && kind == "project")
        ) &&
        !op.retrying {
        let next = company_setup_set_op(state, kind, {
          ..op,
          request: None,
          attempted: false,
          phase: "failed",
          note: "服务明确拒绝创建（HTTP " +
          status.to_string() +
          "）；可修改后重新提交。",
        })
        return (
          company_setup_persist(emit, next, "", ""),
          { ..model, company_setup: next, },
        )
      }
      let next = company_setup_set_op(state, kind, {
        ..op,
        phase: "uncertain",
        note: "回复不能代替正式记录；正在核实。",
      })
      company_setup_update(emit, Recover(kind), {
        ..model,
        company_setup: next,
      })
    }
    Recover(kind) => {
      if !["company", "project"].contains(kind) || state.actor.is_empty() {
        return (none, model)
      }
      let op = company_setup_op(state, kind)
      let request = match op.request {
        Some(r) if !company_setup_busy(op) => r
        _ => return (none, model)
      }
      let checking = company_setup_set_op(state, kind, {
        ..op,
        phase: "checking",
        note: "正在读取正式记录，未重新提交。",
      })
      if kind == "company" {
        let next = {
          ..checking,
          read_request: state.read_request + 1,
          profile_state: "loading",
          units_state: "loading",
        }
        (company_setup_reads(emit, next), company_setup_apply(model, next))
      } else {
        (
          company_setup_recover_project(emit, checking, request),
          { ..model, company_setup: checking, },
        )
      }
    }
    ExactRead(actor, epoch, key, status, body) => {
      if actor != state.actor || epoch != state.epoch {
        return (none, model)
      }
      let op = state.project
      let request = match op.request {
        Some(r) if r.key == key && op.phase == "checking" => r
        _ => return (none, model)
      }
      match
        (if status == 200 { company_setup_exact(request, body) } else { None }) {
        Some(project) => {
          let next = {
            ..state,
            exact_project: Some(project),
            recent_project: Some(request),
            project: {
              ..company_setup_operation(),
              phase: "confirmed",
              note: "已按项目 ID 读回核实名称、编号、组织单位及命令来源；没有创建任务。",
            },
          }
          let loaded = { ..model, company_setup: next, }
          let selected = if request.product_id == model.products.selected_id &&
            op.selection == model.products.selection &&
            op.project_choice == model.products.project_choice {
            company_setup_with_project(loaded, project)
          } else {
            loaded
          }
          (company_setup_persist(emit, next, "", ""), selected)
        }
        None => {
          if status == 404 && op.recover_only {
            let next = {
              ..state,
              recent_project: None,
              exact_project: None,
              project: {
                ..company_setup_operation(),
                phase: "missing",
                note: "此前核实的项目现已无法读取；没有自动重新创建。",
              },
            }
            return (
              company_setup_persist(emit, next, "", ""),
              { ..model, company_setup: next, },
            )
          }
          let next = {
            ..state,
            project: {
              ..op,
              phase: if status == 404 {
                "retryable"
              } else {
                "uncertain"
              },
              note: if status == 404 {
                "精确读取未找到项目；可用相同 ID、内容及请求键重试。"
              } else if status == 200 {
                "精确记录与创建请求不一致或不完整；未选择，也未标记已保存。"
              } else {
                "精确读取失败：" +
                products_state_label(products_read_state(status, body)) +
                "；原请求保留。"
              },
            },
          }
          (none, { ..model, company_setup: next, })
        }
      }
    }
    DismissRecent => {
      if !state.project.recover_only {
        return (none, model)
      }
      let next = {
        ..state,
        project: company_setup_operation(),
        recent_project: None,
        exact_project: None,
      }
      (
        company_setup_persist(emit, next, "", ""),
        { ..model, company_setup: next, },
      )
    }
    UseProject =>
      match state.exact_project {
        Some(project) if products_selected(model.products) is Some(_) &&
          state.session_state == "ready" =>
          (none, company_setup_with_project(model, project))
        _ => (none, model)
      }
  }
}
