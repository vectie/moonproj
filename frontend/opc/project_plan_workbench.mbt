///|
struct PlanWorkbench {
  actor : String
  epoch : Int
  revision : Int
  projects : Array[ProductCompanyProject]
  selected : String
  draft : @plan_workbench.Draft?
  prepared : Json?
  history : Array[Json]
  history_request : Int
  comparison : PlanCompareState
  phase : String
  note : String
  task_table : String
  task_table_tsv : Bool
  task_table_owner : String
  task_table_milestone : String
  task_finder : PlanTaskFinder
  checklist : PlanChecklistState
  task_edits : PlanTaskEdits?
  risk_table : PlanRiskTableState
  text_replace : PlanTextReplaceState
  owner_table : PlanOwnerTableState
  milestone_table : PlanMilestoneTableState
  dependency_focus : String
  risk_focus : String
  brief_owner : String
  template : PlanTemplateState
  schedule : PlanScheduleState
  handoff : PlanHandoffState
  consolidation : PlanConsolidationState
  breakdown : PlanBreakdownState
  transfer : PlanTransferState
  extract : PlanExtractState
} derive(Debug, Eq)

///|
enum PlanMsg {
  Refresh
  PlanProjectsRead(String, Int, Int, String)
  Choose(String)
  Edit(String, String, String, String)
  Add(String)
  Remove(String, String)
  Toggle(String, String, String)
  ShiftTask(String, Int)
  Prepare
  Open(String)
  Read(String, Int, Int, String, String, Int, String)
  History(String, Int, String, Int, Int, String)
  Download(Bool)
  Compare(PlanCompareMsg)
  ImportTasks
  ExportTasks
  TaskFinder(PlanTaskFinderMsg)
  Checklist(PlanChecklistMsg)
  TaskEdits(PlanTaskEditMsg)
  RiskTable(PlanRiskTableMsg)
  TextReplace(PlanTextReplaceMsg)
  OwnerTable(PlanOwnerTableMsg)
  MilestoneTable(PlanMilestoneTableMsg)
  TaskTableFormat(Bool)
  DependencyFocus(String)
  RiskFocus(String)
  ExportRiskImpact
  OrderDependencies
  ExportDependencies
  ExportDependencyDiagram
  ExportCalendar
  BriefOwner(String)
  ExportOwnerBrief
  ExportBudgetBreakdown
  Template(PlanTemplateMsg)
  Schedule(PlanScheduleMsg)
  Handoff(PlanHandoffMsg)
  Consolidation(PlanConsolidationMsg)
  Breakdown(PlanBreakdownMsg)
  Transfer(PlanTransferMsg)
  Extract(PlanExtractMsg)
} derive(Debug, Eq)

///|
fn plan_initial() -> PlanWorkbench {
  {
    actor: "",
    epoch: 0,
    revision: 0,
    projects: [],
    selected: "",
    draft: None,
    prepared: None,
    history: [],
    history_request: 0,
    comparison: plan_compare_initial(),
    phase: "idle",
    note: "",
    task_table: "",
    task_table_tsv: false,
    task_table_owner: "",
    task_table_milestone: "",
    task_edits: None,
    task_finder: plan_task_finder_initial(),
    checklist: plan_checklist_initial(),
    text_replace: plan_text_replace_initial(),
    owner_table: plan_owner_table_initial(),
    milestone_table: plan_milestone_table_initial(),
    risk_table: plan_risk_table_initial(),
    dependency_focus: "",
    risk_focus: "",
    brief_owner: "",
    template: plan_template_initial(),
    schedule: plan_schedule_initial(),
    transfer: plan_transfer_initial(),
    breakdown: plan_breakdown_initial(),
    handoff: plan_handoff_initial(),
    consolidation: plan_consolidation_initial(),
    extract: plan_extract_initial(),
  }
}

///|
extern "js" fn plan_nonce() -> String =
  #| () => "plan-" + crypto.randomUUID()

///|
extern "js" fn plan_now() -> String =
  #| () => new Date().toISOString().replace(/\.\d{3}Z$/, "Z")

///|
extern "js" fn plan_store(
  actor : String,
  project : String,
  value : String,
) -> Bool =
  #| (actor, project, value) => { try { window.localStorage.setItem("moonproj.plan.draft.v1." + encodeURIComponent(JSON.stringify([actor, project])), value); return true; } catch (_) { return false; } }

///|
extern "js" fn plan_restore(actor : String, project : String) -> String =
  #| (actor, project) => { try { return window.localStorage.getItem("moonproj.plan.draft.v1." + encodeURIComponent(JSON.stringify([actor, project]))) || ""; } catch (_) { return ""; } }

///|
extern "js" fn plan_fetch(
  url : String,
  method : String,
  body : String,
  receive : (Int, String) -> Unit,
) =
  #| (url, method, body, receive) => fetch(url, {method, credentials: "same-origin", headers: {"Content-Type":"application/json"}, ...(method === "POST" ? {body} : {})}).then(async r => receive(r.status, await r.text())).catch(() => receive(0, ""))

///|
extern "js" fn plan_download(text : String, name : String, typed : Bool) =
  #| (text, name, typed) => { const u = URL.createObjectURL(new Blob([text],{type: typed ? "application/json;charset=utf-8" : "text/plain;charset=utf-8"})); const a=document.createElement("a"); a.href=u; a.download=name; a.click(); setTimeout(()=>URL.revokeObjectURL(u),1000); }

///|
fn plan_url(project : String) -> String {
  // The company service accepts ':' in an opaque project identifier. It does
  // not decode path segments, so preserve that URI-safe character explicitly.
  "/api/company/projects/" +
  dispatch_url_encode(project).replace_all(old="%3A", new=":") +
  "/prepared-plans"
}

///|
fn plan_new(actor : String, project : String) -> @plan_workbench.Draft {
  {
    key: plan_nonce(),
    project_id: project,
    prepared_at: plan_now(),
    notes: "",
    currency: "CNY",
    limit: "0",
    contingency: "0",
    owners: [{ id: actor, name: "", role: "Plan preparer", }],
    tasks: [],
    milestones: [],
    risks: [],
  }
}

///|
fn plan_reconcile(model : Model) -> Model {
  if model.plan.actor == model.dispatch_task_actor_id {
    model
  } else {
    {
      ..model,
      plan: {
        ..plan_initial(),
        actor: model.dispatch_task_actor_id,
        epoch: model.plan.epoch + 1,
      },
    }
  }
}

///|
fn plan_history(emit : @rabbita.Emit[Msg], state : PlanWorkbench) -> Cmd {
  company_setup_get(plan_url(state.selected), (status, body) => {
    emit(
      PlanAction(
        History(
          state.actor,
          state.epoch,
          state.selected,
          state.history_request,
          status,
          body,
        ),
      ),
    )
  })
}

///|
fn plan_save_edit(
  state : PlanWorkbench,
  draft : @plan_workbench.Draft,
) -> PlanWorkbench {
  let draft = { ..draft, key: plan_nonce(), prepared_at: plan_now(), }
  let stored = plan_store(
    state.actor,
    state.selected,
    draft.to_json().stringify(),
  )
  {
    ..state,
    draft: Some(draft),
    prepared: None,
    revision: state.revision + 1,
    schedule: plan_schedule_initial(),
    transfer: plan_transfer_initial(),
    breakdown: plan_breakdown_initial(),
    handoff: plan_handoff_initial(),
    consolidation: plan_consolidation_initial(),
    extract: { ..state.extract, source: None, preview: None, note: "", },
    phase: "editing",
    task_edits: None,
    task_finder: plan_task_finder_after_edit(state, draft),
    checklist: { ..state.checklist, base: None, preview: None, note: "", },
    risk_table: { ..state.risk_table, base: None, preview: None, note: "", },
    text_replace: { ..state.text_replace, base: None, preview: None, note: "", },
    owner_table: { ..state.owner_table, base: None, preview: None, note: "", },
    milestone_table: {
      ..state.milestone_table,
      base: None,
      preview: None,
      note: "",
    },
    template: { ..state.template, append_before: None, append_after: None, },
    note: if stored {
      "编辑已保留在此浏览器；需要重新准备并保存原生计划。"
    } else {
      "浏览器存储不可用；编辑仅保留在本页面，请准备并保存后再离开。"
    },
  }
}

///|
fn plan_toggle(values : Array[String], value : String) -> Array[String] {
  if values.contains(value) {
    values.filter(v => v != value)
  } else {
    [..values, value]
  }
}

///|
fn plan_edit(
  d : @plan_workbench.Draft,
  kind : String,
  id : String,
  field : String,
  value : String,
) -> @plan_workbench.Draft {
  match kind {
    "plan" =>
      match field {
        "notes" => { ..d, notes: value, }
        "currency" => { ..d, currency: value, }
        "limit" => { ..d, limit: value, }
        "contingency" => { ..d, contingency: value, }
        _ => d
      }
    "owner" =>
      {
        ..d,
        owners: d.owners.map(o => {
          if o.id != id {
            o
          } else {
            match field {
              "name" => { ..o, name: value, }
              "role" => { ..o, role: value, }
              _ => o
            }
          }
        }),
      }
    "task" =>
      {
        ..d,
        tasks: d.tasks.map(t => {
          if t.id != id {
            t
          } else {
            match field {
              "name" => { ..t, name: value, }
              "owner" => { ..t, owner: value, }
              "milestone" => { ..t, milestone: value, }
              "cost" => { ..t, cost: value, }
              _ => t
            }
          }
        }),
      }
    "milestone" =>
      {
        ..d,
        milestones: d.milestones.map(m => {
          if m.id != id {
            m
          } else {
            match field {
              "name" => { ..m, name: value, }
              "owner" => { ..m, owner: value, }
              "date" => { ..m, date: value, }
              "criteria" => { ..m, criteria: value, }
              "evidence" => { ..m, evidence: value, }
              _ => m
            }
          }
        }),
      }
    "risk" =>
      {
        ..d,
        risks: d.risks.map(r => {
          if r.id != id {
            r
          } else {
            match field {
              "summary" => { ..r, summary: value, }
              "severity" => { ..r, severity: value, }
              "owner" => { ..r, owner: value, }
              "mitigation" => { ..r, mitigation: value, }
              _ => r
            }
          }
        }),
      }
    _ => d
  }
}

///|
fn plan_decode_saved(
  body : String,
  actor : String,
  project : String,
  key : String,
) -> Json? {
  let value = @json.parse(body) catch { _ => return None }
  guard value
    is {
      "contract": "moonproj.project-plan-workbench.v1",
      "actor": String(a),
      "project_id": String(p),
      "key": String(k),
      "persisted": true,
      "draft": draft_json,
      "artifact": artifact,
      "artifact_json": String(text),
      "readable": String(readable),
      ..
    } &&
    a == actor &&
    p == project &&
    k == key &&
    !readable.is_empty() else {
    return None
  }
  let d : @plan_workbench.Draft = @json.from_json(draft_json) catch {
    _ => return None
  }
  let decoded = @json.parse(text) catch { _ => return None }
  let effects = products_field(artifact, "authority_effects")
  if d.project_id != project ||
    d.key != key ||
    decoded != artifact ||
    products_text(artifact, "operation_ref") !=
    "moonproj/project.plan.prepare@0.1.0" ||
    products_text(artifact, "plan_request_id") != key ||
    products_text(products_field(artifact, "project"), "project_id") != project ||
    !(products_field(artifact, "workflow")
    is {
      "status": "pending_review",
      "accepted": false,
      "review_required": true,
      ..
    }) ||
    ![
      "spend_authorized", "accounting_posted", "payment_released", "contract_signed",
      "work_executed",
    ].all(k => products_field(effects, k) is False) {
    None
  } else {
    Some(value)
  }
}

///|
fn plan_update(
  emit : @rabbita.Emit[Msg],
  action : PlanMsg,
  model : Model,
) -> (Cmd, Model) {
  let model = plan_reconcile(model)
  let s = model.plan
  match action {
    Refresh => {
      let next = {
        ..s,
        epoch: s.epoch + 1,
        comparison: plan_compare_initial(),
        template: plan_template_initial(),
        schedule: plan_schedule_initial(),
        transfer: plan_transfer_initial(),
        breakdown: plan_breakdown_initial(),
        handoff: plan_handoff_initial(),
        consolidation: plan_consolidation_initial(),
        extract: plan_extract_initial(),
        phase: "loading",
        task_edits: None,
        task_finder: plan_task_finder_initial(),
        checklist: plan_checklist_initial(),
        text_replace: plan_text_replace_initial(),
        owner_table: plan_owner_table_initial(),
        milestone_table: plan_milestone_table_initial(),
        risk_table: plan_risk_table_initial(),
        prepared: None,
        note: "",
      }
      if s.actor.is_empty() {
        return (
          emit(CompanySetupAction(Refresh)),
          {
            ..model,
            plan: {
              ..next,
              phase: "error",
              note: "请先登录公司服务，然后重新读取项目。",
            },
          },
        )
      }
      (
        company_setup_get("/api/company/projects", (status, body) => {
          emit(
            PlanAction(PlanProjectsRead(next.actor, next.epoch, status, body)),
          )
        }),
        { ..model, plan: next, },
      )
    }
    PlanProjectsRead(actor, epoch, status, body) => {
      if s.actor != actor || s.epoch != epoch || s.phase != "loading" {
        return (none, model)
      }
      let projects = if status == 200 {
        products_decode_projects(body)
      } else {
        None
      }
      match projects {
        Some(rows) =>
          (
            none,
            {
              ..model,
              plan: {
                ..s,
                projects: rows,
                selected: "",
                draft: None,
                history: [],
                phase: "ready",
                note: if rows.is_empty() {
                  "公司服务未返回项目。请先在公司设置建立项目。"
                } else {
                  "选择实际公司项目后编制计划。"
                },
              },
            },
          )
        None =>
          (
            none,
            {
              ..model,
              plan: {
                ..s,
                projects: [],
                selected: "",
                draft: None,
                history: [],
                phase: "error",
                note: "公司项目读取失败；没有使用示例数据。请检查登录、公司服务与网关后重试。",
              },
            },
          )
      }
    }
    Choose(id) => {
      if !s.projects.any(p => p.id == id) {
        return (none, model)
      }
      let restored : @plan_workbench.Draft? = try
        @json.from_json(@json.parse(plan_restore(s.actor, id)))
      catch {
        _ => None
      } noraise {
        d => Some(d)
      }
      let draft = match restored {
        Some(d) if d.project_id == id && d.owners.any(o => o.id == s.actor) => d
        _ => plan_new(s.actor, id)
      }
      let next = {
        ..s,
        selected: id,
        comparison: plan_compare_initial(),
        epoch: s.epoch + 1,
        revision: 0,
        draft: Some(draft),
        prepared: None,
        history: [],
        history_request: s.history_request + 1,
        phase: "editing",
        note: "浏览器草稿不是已保存计划；下方历史从网关持久化存储读取。",
        task_table: "",
        task_edits: None,
        task_finder: plan_task_finder_initial(),
        checklist: plan_checklist_initial(),
        text_replace: plan_text_replace_initial(),
        owner_table: plan_owner_table_initial(),
        milestone_table: plan_milestone_table_initial(),
        risk_table: plan_risk_table_initial(),
        template: plan_template_initial(),
        schedule: plan_schedule_initial(),
        transfer: plan_transfer_initial(),
        breakdown: plan_breakdown_initial(),
        handoff: plan_handoff_initial(),
        consolidation: plan_consolidation_initial(),
        extract: plan_extract_initial(),
        dependency_focus: "",
        risk_focus: "",
        brief_owner: "",
        task_table_owner: s.actor,
        task_table_milestone: draft.milestones
        .get(0)
        .map(m => m.id)
        .unwrap_or(""),
      }
      (plan_history(emit, next), { ..model, plan: next, })
    }
    TaskTableFormat(tsv) =>
      (
        none,
        { ..model, plan: { ..s, task_table_tsv: tsv, task_edits: None, }, },
      )
    TaskFinder(action) => plan_task_finder_update(action, model)
    Checklist(action) => plan_checklist_update(action, model)
    TaskEdits(action) => plan_task_edits_update(action, model)
    RiskTable(action) => plan_risk_table_update(action, model)
    TextReplace(action) => plan_text_replace_update(action, model)
    OwnerTable(action) => plan_owner_table_update(action, model)
    MilestoneTable(action) => plan_milestone_table_update(action, model)
    BriefOwner(id) => {
      guard s.draft is Some(d) && d.owners.any(o => o.id == id) else {
        return (none, model)
      }
      (none, { ..model, plan: { ..s, brief_owner: id, }, })
    }
    ExportBudgetBreakdown => {
      guard s.draft is Some(d) &&
        d.project_id == s.selected &&
        s.projects.filter(p => p.id == s.selected).get(0) is Some(project) else {
        return (none, model)
      }
      let report = @plan_workbench.budget_report(d, project.name)
      (
        @cmd.custom_cmd(_ => {
          plan_download(report, "plan-budget-breakdown.txt", false)
        }),
        model,
      )
    }
    ExportOwnerBrief => {
      guard s.draft is Some(d) &&
        d.project_id == s.selected &&
        s.projects.filter(p => p.id == s.selected).get(0) is Some(project) else {
        return (none, model)
      }
      let brief = @plan_workbench.owner_brief(d, s.brief_owner, project.name) catch {
        _ => return (none, model)
      }
      (
        @cmd.custom_cmd(_ => plan_download(brief, "plan-owner-brief.txt", false)),
        model,
      )
    }
    Template(action) => plan_template_update(action, model)
    Schedule(action) => plan_schedule_update(action, model)
    Handoff(action) => plan_handoff_update(emit, action, model)
    Consolidation(action) => plan_consolidation_update(action, model)
    Breakdown(action) => plan_breakdown_update(action, model)
    Transfer(action) => plan_transfer_update(action, model)
    Extract(action) => plan_extract_update(action, model)
    DependencyFocus(id) =>
      (none, { ..model, plan: { ..s, dependency_focus: id, }, })
    ExportDependencies => {
      if s.draft is Some(d) {
        plan_download(
          @plan_workbench.dependency_report(d, s.dependency_focus),
          "plan-dependencies.txt",
          false,
        )
      }
      (none, model)
    }
    ExportDependencyDiagram => plan_diagram_export(model)
    RiskFocus(id) => (none, { ..model, plan: { ..s, risk_focus: id, }, })
    ExportRiskImpact => plan_risk_impact_export(model)
    OrderDependencies => {
      guard s.draft is Some(d) else { return (none, model) }
      let ordered = @plan_workbench.order_dependencies(d) catch {
        @plan_workbench.Invalid(message) =>
          return (none, { ..model, plan: { ..s, note: message, }, })
      }
      if ordered == d {
        return (
          none,
          {
            ..model,
            plan: { ..s, note: "Task order already respects dependencies.", },
          },
        )
      }
      (none, { ..model, plan: plan_save_edit(s, ordered), })
    }
    ExportTasks => {
      if s.draft is Some(d) {
        plan_download(
          @plan_workbench.export_task_table(d),
          "plan-tasks.csv",
          false,
        )
      }
      (none, model)
    }
    ExportCalendar => {
      guard s.draft is Some(d) &&
        d.project_id == s.selected &&
        s.projects.filter(p => p.id == s.selected).get(0) is Some(project) else {
        return (none, model)
      }
      let calendar = @plan_workbench.export_milestone_calendar(d, project.name) catch {
        @plan_workbench.Invalid(message) =>
          return (none, { ..model, plan: { ..s, note: message, }, })
      }
      (@cmd.custom_cmd(_ => plan_calendar_download(calendar)), model)
    }
    ImportTasks => {
      guard s.draft is Some(d) else { return (none, model) }
      let (draft, ignored) = @plan_workbench.import_task_table(
        d,
        s.task_table,
        s.task_table_tsv,
        s.task_table_owner,
        s.task_table_milestone,
      ) catch {
        @plan_workbench.Invalid(message) =>
          return (none, { ..model, plan: { ..s, note: message, }, })
      }
      let next = plan_save_edit(s, draft)
      (
        none,
        {
          ..model,
          plan: {
            ..next,
            task_table: "",
            note: next.note +
            " 已导入 " +
            (draft.tasks.length() - d.tasks.length()).to_string() +
            " 个任务。忽略的列：" +
            ignored.join(", "),
          },
        },
      )
    }
    Edit("task-table", _, field, value) => {
      let next = match field {
        "source" => { ..s, task_table: value, task_edits: None, }
        "owner" => { ..s, task_table_owner: value, }
        "milestone" => { ..s, task_table_milestone: value, }
        _ => s
      }
      (none, { ..model, plan: next, })
    }
    Edit(kind, id, field, value) =>
      match s.draft {
        Some(d) =>
          (
            none,
            {
              ..model,
              plan: plan_save_edit(s, plan_edit(d, kind, id, field, value)),
            },
          )
        None => (none, model)
      }
    Add(kind) => {
      guard s.draft is Some(d) else { return (none, model) }
      let id = plan_nonce()
      let d = match kind {
        "owner" => { ..d, owners: [..d.owners, { id, name: "", role: "", }], }
        "task" =>
          {
            ..d,
            tasks: [
              ..d.tasks,
              {
                id,
                name: "",
                owner: s.actor,
                milestone: d.milestones.get(0).map(m => m.id).unwrap_or(""),
                cost: "0",
                dependencies: [],
              },
            ],
          }
        "milestone" =>
          {
            ..d,
            milestones: [
              ..d.milestones,
              {
                id,
                name: "",
                owner: s.actor,
                date: "",
                criteria: "",
                evidence: "",
              },
            ],
          }
        "risk" =>
          {
            ..d,
            risks: [
              ..d.risks,
              {
                id,
                summary: "",
                severity: "medium",
                owner: s.actor,
                mitigation: "",
                tasks: [],
              },
            ],
          }
        _ => d
      }
      (none, { ..model, plan: plan_save_edit(s, d), })
    }
    Remove(kind, id) => {
      guard s.draft is Some(d) else { return (none, model) }
      let d = match kind {
        "owner" if id != s.actor =>
          { ..d, owners: d.owners.filter(o => o.id != id), }
        "task" => { ..d, tasks: d.tasks.filter(t => t.id != id), }
        "milestone" =>
          { ..d, milestones: d.milestones.filter(m => m.id != id), }
        "risk" => { ..d, risks: d.risks.filter(r => r.id != id), }
        _ => d
      }
      (none, { ..model, plan: plan_save_edit(s, d), })
    }
    Toggle(kind, id, dependency) => {
      guard s.draft is Some(d) else { return (none, model) }
      let d = if kind == "task" {
        {
          ..d,
          tasks: d.tasks.map(t => {
            if t.id == id {
              { ..t, dependencies: plan_toggle(t.dependencies, dependency), }
            } else {
              t
            }
          }),
        }
      } else {
        {
          ..d,
          risks: d.risks.map(r => {
            if r.id == id {
              { ..r, tasks: plan_toggle(r.tasks, dependency), }
            } else {
              r
            }
          }),
        }
      }
      (none, { ..model, plan: plan_save_edit(s, d), })
    }
    ShiftTask(id, delta) => {
      guard s.draft is Some(d) else { return (none, model) }
      let tasks = d.tasks.copy()
      for i, task in tasks {
        if task.id == id && i + delta >= 0 && i + delta < tasks.length() {
          let other = tasks[i + delta]
          tasks[i + delta] = task
          tasks[i] = other
          break
        }
      }
      (none, { ..model, plan: plan_save_edit(s, { ..d, tasks, }), })
    }
    Prepare | Open(_) => {
      guard s.draft is Some(d) && s.phase != "saving" && s.phase != "opening" else {
        return (none, model)
      }
      let (key, method, url, phase) = match action {
        Open(key) =>
          (
            key,
            "GET",
            plan_url(s.selected) + "/" + dispatch_url_encode(key),
            "opening",
          )
        _ => (d.key, "POST", plan_url(s.selected), "saving")
      }
      let sent = if method == "POST" { d.to_json().stringify() } else { "" }
      let cmd = @cmd.custom_cmd(scheduler => {
        plan_fetch(url, method, sent, (status, body) => {
          scheduler.add(
            emit(
              PlanAction(
                Read(s.actor, s.epoch, s.revision, key, sent, status, body),
              ),
            ),
          )
        })
      })
      (
        cmd,
        {
          ..model,
          plan: {
            ..s,
            phase,
            handoff: plan_handoff_initial(),
            prepared: None,
            note: "正在读取原生网关…",
          },
        },
      )
    }
    Read(actor, epoch, revision, key, sent, status, body) => {
      if actor != s.actor ||
        epoch != s.epoch ||
        revision != s.revision ||
        !["saving", "opening"].contains(s.phase) {
        return (none, model)
      }
      let value = if status == 200 {
        plan_decode_saved(body, actor, s.selected, key)
      } else {
        None
      }
      match value {
        Some(saved) => {
          let input = products_field(saved, "draft")
          if !sent.is_empty() && input.stringify() != sent {
            return (
              none,
              {
                ..model,
                plan: {
                  ..s,
                  phase: "error",
                  note: "返回计划与本次编辑不一致，已拒绝显示。",
                },
              },
            )
          }
          let draft : @plan_workbench.Draft = @json.from_json(input) catch {
            _ => return (none, model)
          }
          let stored = plan_store(actor, s.selected, input.stringify())
          let next = {
            ..s,
            draft: Some(draft),
            prepared: Some(saved),
            task_edits: None,
            task_finder: plan_task_finder_initial(),
            checklist: plan_checklist_initial(),
            text_replace: plan_text_replace_initial(),
            owner_table: plan_owner_table_initial(),
            milestone_table: plan_milestone_table_initial(),
            risk_table: plan_risk_table_initial(),
            schedule: plan_schedule_initial(),
            transfer: plan_transfer_initial(),
            breakdown: plan_breakdown_initial(),
            handoff: plan_handoff_initial(),
            consolidation: plan_consolidation_initial(),
            extract: plan_extract_initial(),
            phase: "prepared",
            history_request: s.history_request + 1,
            note: if stored {
              "已保存并重新验证原生计划；等待具名人工复核。"
            } else {
              "原生计划已保存；浏览器草稿存储不可用，可从保存历史重新打开。"
            },
          }
          (plan_history(emit, next), { ..model, plan: next, })
        }
        None => {
          let parsed = @json.parse(body) catch { _ => Json::null() }
          let error = products_text(parsed, "error")
          (
            none,
            {
              ..model,
              plan: {
                ..s,
                phase: "error",
                note: if error.is_empty() {
                  "原生计划暂不可用或返回格式不符；编辑已保留。检查公司服务、网关及其工作区后重试。"
                } else {
                  error
                },
              },
            },
          )
        }
      }
    }
    History(actor, epoch, project, request, status, body) => {
      if actor != s.actor ||
        epoch != s.epoch ||
        project != s.selected ||
        request != s.history_request {
        return (none, model)
      }
      let parsed = @json.parse(body) catch { _ => Json::null() }
      if status != 200 ||
        products_text(parsed, "project_id") != project ||
        !(products_field(parsed, "items") is Array(_)) {
        (
          none,
          {
            ..model,
            plan: {
              ..s,
              history: [],
              note: s.note +
              " 保存历史暂不可读取；这不表示没有已保存计划。",
            },
          },
        )
      } else {
        (
          none,
          {
            ..model,
            plan: { ..s, history: @plan_workbench.items(parsed, "items"), },
          },
        )
      }
    }
    Download(typed) => {
      guard s.prepared is Some(saved) && s.phase == "prepared" else {
        return (none, model)
      }
      let text = products_text(
        saved,
        if typed {
          "artifact_json"
        } else {
          "readable"
        },
      )
      let name = products_text(saved, "key") +
        (if typed { ".json" } else { ".txt" })
      (@cmd.custom_cmd(_ => plan_download(text, name, typed)), model)
    }
    Compare(message) => {
      let (command, comparison) = plan_compare_update(emit, message, s)
      (command, { ..model, plan: { ..s, comparison, }, })
    }
  }
}
