///|
// Product links contain only one bounded catalog identity, never a source path,
// company project, draft, execution setting or command. Invalid links remain
// visibly invalid until the user makes a new explicit choice.
extern "js" fn saved_product_token() -> String =
  #| () => {
  #|   if (typeof window === "undefined") return "";
  #|   const ids = new URL(window.location.href).searchParams.getAll("product");
  #|   if (ids.length === 0) return "";
  #|   return ids.length === 1 && /^[a-z0-9_-]{1,96}$/.test(ids[0]) ? ids[0] : "!invalid";
  #| }

///|
extern "js" fn store_product_route(page : String, id : String) =
  #| (page, id) => {
  #|   if (typeof window === "undefined" || !/^[a-z0-9_-]{1,96}$/.test(id)) return;
  #|   const url = new URL(window.location.href);
  #|   url.searchParams.set("page", page);
  #|   url.searchParams.set("product", id);
  #|   if (url.href.split('#', 1)[0] !== window.location.href.split('#', 1)[0]) {
  #|     url.hash = "";
  #|     window.history.pushState(null, "", url);
  #|   }
  #|   window.__moonprojDispatchHistoryPage = url.href.split('#', 1)[0];
  #| }

///|
fn remember_product_route(page : Page, id : String) -> Cmd {
  @cmd.custom_cmd(_ => store_product_route(page_route_token(page), id))
}

///|
fn products_restore_route(
  emit : @rabbita.Emit[Msg],
  id : String,
  model : Model,
) -> (Cmd, Model) {
  let state = model.products
  if id == state.route_id && id == state.selected_id {
    return (none, model)
  }
  // Changing route invalidates all product-bound reads immediately. A later
  // catalog completion resolves the latest exact route_id without navigating.
  let next = {
    ..state,
    route_id: id,
    selected_id: "",
    pending_work_group_id: "",
    selection: state.selection + 1,
    admission_state: "idle",
    engineering_state: "idle",
    projects: [],
    project_id: "",
    project_state: "idle",
    project_note: "",
    project_request: state.project_request + 1,
    tasks: [],
    work_state: "idle",
    work_request: state.work_request + 1,
  }
  let cleared = { ..products_reset_evidence(model, ""), products: next, }
  if products_id_valid(id) &&
    state.state == "ready" &&
    products_find(state.rows, id) is Some(_) {
    products_update(emit, Select(id), cleared)
  } else {
    (none, cleared)
  }
}

///|
fn products_route_note(state : ProductsState) -> String {
  if state.route_id.is_empty() {
    "先看产品为什么存在，再看文档、证据与工作。"
  } else if !products_id_valid(state.route_id) {
    "链接中的产品 ID 无效或重复。请从目录重新选择一个产品。"
  } else if state.state == "ready" || state.state == "empty" {
    "当前目录中没有产品「" +
    state.route_id +
    "」。可以刷新目录，或明确选择其他产品。"
  } else if state.state == "idle" || state.state == "loading" {
    "正在读取目录，以恢复产品「" + state.route_id + "」。"
  } else {
    "尚未恢复产品「" +
    state.route_id +
    "」：目录读取未成功。请刷新目录后重试。"
  }
}
