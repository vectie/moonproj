///|
fn dispatch_draft_store(model : Model) -> String {
  ToJson::to_json(DispatchDraftStore::{
    version: 1,
    drafts: model.dispatch_drafts,
    recent_tasks: model.dispatch_recent_tasks,
  }).stringify()
}

///|
fn dispatch_persist_drafts(
  emit : @rabbita.Emit[Msg],
  model : Model,
  create_id : String,
) -> Cmd {
  let actor = model.dispatch_task_actor_id
  let body = dispatch_draft_store(model)
  @cmd.custom_cmd(scheduler => {
    scheduler.add(
      emit(
        DraftAction(
          Stored(actor, create_id, dispatch_write_drafts(actor, body)),
        ),
      ),
    )
  })
}

///|
extern "js" fn dispatch_write_drafts(actor : String, body : String) -> Bool =
  #| (actor, body) => {
  #|   if (!actor || typeof window === "undefined") return false;
  #|   try { window.localStorage.setItem("moonproj.dispatch.drafts.v1." + encodeURIComponent(actor), body); return true; }
  #|   catch (_) { return false; }
  #| }

///|
extern "js" fn dispatch_read_drafts(actor : String) -> String =
  #| actor => {
  #|   if (!actor || typeof window === "undefined") return "";
  #|   try { return window.localStorage.getItem("moonproj.dispatch.drafts.v1." + encodeURIComponent(actor)) || ""; }
  #|   catch (_) { return "storage-unavailable"; }
  #| }

///|
fn dispatch_draft_create_body(draft : DispatchDraft, actor : String) -> Json {
  let fields = {
    "idempotency_key": Json::string(draft.idempotency_key),
    "task_id": Json::string(draft.task_id),
    "task_code": Json::string(draft.task_id),
    "task_name": Json::string(draft.title.trim().to_owned()),
    "project_id": Json::string(draft.project_id.trim().to_owned()),
    "task_type": Json::string("task"),
    "plan_begin_date": Json::string(draft.begin_date.trim().to_owned()),
    "plan_end_date": Json::string(draft.end_date.trim().to_owned()),
    "owner_id": Json::string(draft.owner_id.trim().to_owned()),
    "execution_workspace": Json::string(draft.workspace.trim().to_owned()),
    "execution_model": Json::string(draft.model.trim().to_owned()),
    "remarks": Json::string(
      "验收标准：" + draft.acceptance.trim().to_owned(),
    ),
    "authority": Json::object({
      "active": Json::boolean(true),
      "principal_id": Json::string("principal-opc-dispatch"),
      "actor_id": Json::string(actor),
      "capability": Json::string("project:task:create"),
      "scope": Json::string("project:" + draft.project_id.trim().to_owned()),
    }),
  }
  if !draft.product_id.is_empty() {
    fields["product_id"] = Json::string(draft.product_id)
  }
  let reference = draft.source_reference.unwrap_or("").trim().to_owned()
  let problem = draft.observed_problem.unwrap_or("").trim().to_owned()
  if !reference.is_empty() || !problem.is_empty() {
    fields["source_context"] = { "reference": reference, "problem": problem }
  }
  if draft.offer_draft is Some(value) {
    fields["offer_draft"] = @task_evidence.normalize_offer_draft(value) catch {
      _ => value
    }
  }
  Json::object(fields)
}

///|
fn dispatch_create_draft(
  emit : @rabbita.Emit[Msg],
  draft : DispatchDraft,
  actor : String,
) -> Cmd {
  let body = dispatch_draft_create_body(draft, actor).stringify()
  @cmd.custom_cmd(scheduler => {
    dispatch_post_draft(body, (status, response) => {
      scheduler.add(
        emit(DraftAction(CreateRead(actor, draft.id, status, response))),
      )
    })
  })
}

///|
extern "js" fn dispatch_post_draft(
  body : String,
  receive : (Int, String) -> Unit,
) =
  #| (body, receive) => {
  #|   fetch("/api/company/plan/tasks", {method:"POST", credentials:"same-origin", headers:{"Content-Type":"application/json", Accept:"application/json"}, body})
  #|     .then(response => response.text().then(text => receive(response.status, text)))
  #|     .catch(() => receive(0, ""));
  #| }

///|
fn dispatch_recover_draft(
  emit : @rabbita.Emit[Msg],
  draft : DispatchDraft,
  actor : String,
) -> Cmd {
  products_read("/api/company/tasks/" + dispatch_url_encode(draft.task_id), (
    status,
    body,
  ) => emit(DraftAction(RecoveryRead(actor, draft.id, status, body))))
}

///|
fn dispatch_history_listener(emit : @rabbita.Emit[Msg]) -> Cmd {
  @cmd.custom_cmd(scheduler => {
    dispatch_listen_history((page, id) => {
      scheduler.add(emit(page_route_message(page, id, saved_product_token())))
    })
  })
}

///|
extern "js" fn dispatch_listen_history(receive : (String, String) -> Unit) =
  #| receive => {
  #|   if (typeof window === "undefined") return;
  #|   window.__moonprojDispatchHistoryPage = window.location.href.split('#', 1)[0];
  #|   window.addEventListener("popstate", () => {
  #|     const page = window.location.href.split('#', 1)[0];
  #|     if (page === window.__moonprojDispatchHistoryPage) return;
  #|     window.__moonprojDispatchHistoryPage = page;
  #|     const params = new URL(window.location.href).searchParams;
  #|     const pages = params.getAll("page");
  #|     receive(pages.length === 0 ? "" : pages.length === 1 && pages[0] ? pages[0] : "!invalid", params.get("task") || "");
  #|   });
  #| }
