///|
// Compatibility reads only. Legacy global keys remain untouched; current
// persistence and task recovery belong to the authenticated R560 draft flow.
extern "js" fn founder_read_draft() -> String =
  #| () => { try { return localStorage.getItem("moonproj.founder-draft.v1") || "" } catch (_) { return "" } }

///|
extern "js" fn founder_legacy_pending_task_id() -> String =
  #| () => { try { return localStorage.getItem("moonproj.pending-task.v1") || "" } catch (_) { return "storage-unavailable" } }

///|
extern "js" fn founder_url_task_id() -> String =
  #| () => { try { const value = new URL(location.href).searchParams.get("opc_task") || ""; return value ? (/^[A-Za-z0-9_.:-]{1,128}$/.test(value) && value !== "." && value !== ".." ? value : "invalid-legacy-link") : "" } catch (_) { return "invalid-legacy-link" } }

///|
extern "js" fn founder_download_packet(content : String) -> Bool =
  #| (content) => { try { const url = URL.createObjectURL(new Blob([content], { type: "text/markdown;charset=utf-8" })); const link = document.createElement("a"); link.href = url; link.download = "moonproj-founder-work.md"; document.body.appendChild(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 10000); return true } catch (_) { return false } }

///|
struct LegacyFounderDraft {
  kind : String
  title : String
  source_ref : String
  problem : String
  acceptance : String
  project_id : String
  owner_id : String
  begin_date : String
  end_date : String
} derive(Debug, Eq, FromJson)

///|
fn founder_legacy_draft(text : String) -> LegacyFounderDraft? {
  if text.is_empty() || text.length() > 262144 {
    return None
  }
  let draft : LegacyFounderDraft = @json.from_json(@json.parse(text)) catch {
    _ => return None
  }
  if draft.kind == "moonproj-founder-draft-v1" {
    Some(draft)
  } else {
    None
  }
}

///|
fn founder_legacy_import_allowed(model : Model, actor : String) -> Bool {
  !actor.is_empty() &&
  actor == model.dispatch_task_actor_id &&
  actor == model.company_setup.actor &&
  model.company_setup.session_state == "ready" &&
  model.dispatch_draft_storage == "已读取此浏览器草稿" &&
  model.dispatch_drafts.is_empty() &&
  model.dispatch_recent_tasks.is_empty() &&
  model.dispatch_draft_id.is_empty() &&
  !model.dispatch_task_form_open &&
  model.dispatch_task_id.is_empty() &&
  model.dispatch_task_open_id.is_empty() &&
  model.dispatch_task_pending_action.is_empty() &&
  model.products.prepared_product_id.is_empty() &&
  model.products.prepared_project_id.is_empty()
}

///|
fn founder_import_legacy_draft(
  emit : @rabbita.Emit[Msg],
  model : Model,
  actor : String,
  text : String,
  pending_task : String,
  linked_task : String,
) -> (Cmd, Model) {
  if !founder_legacy_import_allowed(model, actor) {
    return (none, model)
  }
  // An old pending identity may already exist formally. Do not turn its text
  // into a second createable identity before the user recovers that task.
  if !pending_task.is_empty() || !linked_task.is_empty() {
    return (
      none,
      {
        ..model,
        notice: "发现旧工作包任务提示；旧存储和链接保持不变。请先按旧任务 ID 在任务编排中只读恢复正式记录，不要重复创建。",
      },
    )
  }
  let legacy = match founder_legacy_draft(text) {
    Some(draft) => draft
    None => return (none, model)
  }
  let (_, prepared) = dispatch_prepare_draft(
    emit,
    model,
    "",
    legacy.project_id,
    None,
    true,
  )
  let fresh = dispatch_active_draft(prepared).unwrap()
  dispatch_save_draft(
    emit,
    {
      ..prepared,
      // Import is parked ordinary context, never a navigation or selection.
      page: model.page,
      products: model.products,
      dispatch_draft_id: "",
      dispatch_task_form_open: false,
      notice: "旧工作包上下文已复制为当前登录身份的新本地草稿；原存储保留，尚未创建或重试正式任务。请在任务编排中检查来源、范围和日期。",
    },
    {
      ..fresh,
      title: legacy.title,
      source_reference: Some(legacy.source_ref),
      observed_problem: Some(legacy.problem),
      acceptance: legacy.acceptance,
      owner_id: legacy.owner_id,
      begin_date: legacy.begin_date,
      end_date: legacy.end_date,
      note: "由旧浏览器工作包复制的普通草稿；旧记录未删除，身份和授权仅来自当前网关会话。",
    },
  )
}

///|
fn founder_after_draft_restore(
  emit : @rabbita.Emit[Msg],
  model : Model,
  actor : String,
  scoped_text : String,
) -> (Cmd, Model) {
  if !founder_legacy_import_allowed(model, actor) {
    return (none, model)
  }
  if !scoped_text.is_empty() {
    let saved : DispatchDraftStore = @json.from_json(@json.parse(scoped_text)) catch {
      _ => return (none, model)
    }
    if saved.version != 1 ||
      !saved.drafts.is_empty() ||
      !saved.recent_tasks.is_empty() {
      return (none, model)
    }
  }
  founder_import_legacy_draft(
    emit,
    model,
    actor,
    founder_read_draft(),
    founder_legacy_pending_task_id(),
    founder_url_task_id(),
  )
}

///|
struct FounderPacketContext {
  status : String
  task_id : String
  title : String
  source_reference : String
  observed_problem : String
  acceptance : String
  project_id : String
  owner_id : String
  begin_date : String
  end_date : String
} derive(Debug, Eq)

///|
fn founder_packet_context(model : Model) -> FounderPacketContext? {
  if model.company_setup.session_state != "ready" ||
    model.dispatch_task_actor_id.is_empty() ||
    model.company_setup.actor != model.dispatch_task_actor_id {
    return None
  }
  if model.dispatch_task_form_open {
    return dispatch_active_draft(model).map(draft => {
      status: "local draft; no formal task receipt",
      task_id: "",
      title: draft.title,
      source_reference: draft.source_reference.unwrap_or(""),
      observed_problem: draft.observed_problem.unwrap_or(""),
      acceptance: draft.acceptance,
      project_id: draft.project_id,
      owner_id: draft.owner_id,
      begin_date: draft.begin_date,
      end_date: draft.end_date,
    })
  }
  if model.dispatch_task_id.is_empty() ||
    model.dispatch_journey_read_state != "loaded" ||
    !["pending", "in_progress", "submitted", "accepted"].contains(
      model.dispatch_task_stage,
    ) {
    return None
  }
  Some({
    status: "MoonProj internal task " + model.dispatch_task_stage,
    task_id: model.dispatch_task_id,
    title: model.dispatch_task_title,
    source_reference: dispatch_json_text(
      model.dispatch_task_source_context,
      "reference",
    ),
    observed_problem: dispatch_json_text(
      model.dispatch_task_source_context,
      "problem",
    ),
    acceptance: model.dispatch_task_acceptance,
    project_id: model.dispatch_task_project_id,
    owner_id: model.dispatch_task_owner_id,
    begin_date: model.dispatch_task_begin_date,
    end_date: model.dispatch_task_end_date,
  })
}

///|
fn founder_packet_markdown(packet : FounderPacketContext) -> String {
  "# Founder work packet\n\n" +
  "This packet carries context for a founder review. A source reference is not proof of customer demand. Internal task completion is not customer acceptance, an invoice, or cash received.\n\n" +
  [
    ("Status", packet.status),
    ("MoonProj task ID", packet.task_id),
    ("Work title", packet.title),
    ("Source reference", packet.source_reference),
    ("Customer problem hypothesis", packet.observed_problem),
    ("Internal acceptance criterion", packet.acceptance),
    ("Project ID", packet.project_id),
    ("Owner ID", packet.owner_id),
    ("Planned start", packet.begin_date),
    ("Planned end", packet.end_date),
  ]
  .map(pair => "- " + pair.0 + ": " + Json::string(pair.1).stringify())
  .join("\n") +
  "\n\n## Facts still requiring accountable review\n\n" +
  "- Source provenance and claims: unchecked in this packet.\n" +
  "- Customer acceptance: no evidence in this packet.\n" +
  "- Invoice and payment: no evidence in this packet.\n" +
  "- Learning: capture an outcome and review it before reuse.\n"
}

///|
fn founder_export_packet(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> (Cmd, Model) {
  let context = match founder_packet_context(model) {
    Some(context) => context
    None =>
      return (
        none,
        {
          ..model,
          notice: "先登录并打开本地草稿或已核实的正式任务，再下载工作包。",
        },
      )
  }
  let text = founder_packet_markdown(context)
  (
    @cmd.custom_cmd(scheduler => {
      scheduler.add(
        emit(
          FounderPacketDownloaded(
            model.dispatch_task_actor_id,
            model.company_setup.epoch,
            model.dispatch_task_selection,
            model.page,
            model.dispatch_draft_id,
            founder_download_packet(text),
          ),
        ),
      )
    }),
    model,
  )
}
