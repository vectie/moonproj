///|
// The page is an allowlisted display route, not a command or a pathname. Keep
// the current mount path and unrelated query parameters intact.
fn page_route_token(page : Page) -> String {
  if page == Overview {
    "overview"
  } else {
    page_path(page).strip_prefix("/").unwrap().to_owned()
  }
}

///|
fn page_route_parse(token : String) -> Page? {
  match token {
    "workspace" => Some(Workspace)
    "overview" => Some(Overview)
    "objectives" => Some(Objectives)
    "fleet" => Some(Fleet)
    "dispatch" => Some(Dispatch)
    "projects" => Some(Projects)
    "products" => Some(Products)
    "moon" => Some(MoonSuite)
    "quality" => Some(Quality)
    "observe" => Some(Observe)
    "operate" => Some(Operate)
    "company" => Some(Company)
    "policy-radar" => Some(PolicyRadar)
    "evidence" => Some(Evidence)
    "guide" => Some(Guide)
    "market" => Some(Market)
    "delivery" => Some(Delivery)
    "commerce" => Some(Commerce)
    "finance" => Some(Finance)
    "assurance" => Some(Assurance)
    "extensions" => Some(Extensions)
    _ => None
  }
}

///|
fn page_route_message(page : String, task : String, product : String) -> Msg {
  if !product.is_empty() {
    RestoreProductPageRoute(
      if page.is_empty() {
        if task.is_empty() {
          Products
        } else {
          Dispatch
        }
      } else {
        page_route_parse(page).unwrap_or(Products)
      },
      task,
      product,
    )
  } else if page.is_empty() {
    RestoreDispatchTask(task)
  } else {
    RestorePageRoute(page_route_parse(page).unwrap_or(Products), task)
  }
}

///|
extern "js" fn saved_page_token() -> String =
  #| () => {
  #|   if (typeof window === "undefined") return "";
  #|   const pages = new URL(window.location.href).searchParams.getAll("page");
  #|   return pages.length === 0 ? "" : pages.length === 1 && pages[0] ? pages[0] : "!invalid";
  #| }

///|
fn saved_page_route() -> Msg {
  page_route_message(
    saved_page_token(),
    dispatch_saved_task(),
    saved_product_token(),
  )
}

///|
extern "js" fn store_page_route(page : String, task_id : String, push : Bool) =
  #| (page, taskId, push) => {
  #|   if (typeof window === "undefined") return;
  #|   // A breadcrumb is only a legacy hint. Canonical GET remains authoritative.
  #|   try { if (taskId) window.localStorage.setItem("moonproj.dispatch.task", taskId); else window.localStorage.removeItem("moonproj.dispatch.task"); } catch (_) {}
  #|   const url = new URL(window.location.href);
  #|   url.searchParams.set("page", page);
  #|   if (taskId) url.searchParams.set("task", taskId); else url.searchParams.delete("task");
  #|   const changed = url.href.split('#', 1)[0] !== window.location.href.split('#', 1)[0];
  #|   if (push && changed) {
  #|     url.hash = "";
  #|     window.history.pushState(null, "", url);
  #|   } else window.history.replaceState(null, "", url);
  #|   // Keep the fragment-only history guard current after our own URL writes.
  #|   window.__moonprojDispatchHistoryPage = url.href.split('#', 1)[0];
  #| }

///|
fn remember_page_route(
  page : Page,
  task_id : String,
  push~ : Bool = false,
) -> Cmd {
  @cmd.custom_cmd(_ => {
    if page == Dispatch {
      dispatch_store_task(task_id, push)
    } else {
      store_page_route(page_route_token(page), task_id, push)
    }
  })
}

///|
fn restore_page_route(
  emit : @rabbita.Emit[Msg],
  page : Page,
  task_id : String,
  model : Model,
  product~ : String = "",
) -> (Cmd, Model) {
  let (page_command, next) = restore_page_task_route(emit, page, task_id, model)
  let next = if page == Workspace {
    {
      ..next,
      workspace: { ..next.workspace, job: task_id, pane: "materials", },
    }
  } else {
    next
  }
  let (product_command, restored) = products_restore_route(emit, product, next)
  (@cmd.batch([page_command, product_command]), restored)
}

///|
fn restore_page_task_route(
  emit : @rabbita.Emit[Msg],
  page : Page,
  task_id : String,
  model : Model,
) -> (Cmd, Model) {
  let task_id = task_id.trim().to_owned()
  // This message is only emitted for real path/query history (or boot), never
  // fragment-only entries. Invalidate URL-bound callbacks even when the parsed
  // page/task are unchanged, while retaining an unconfirmed immutable operation.
  let previous_page = model.page
  let model = {
    ..model,
    dispatch_desk_handoff: { ..model.dispatch_desk_handoff, pending: false, },
    dispatch_continuation: {
      ..model.dispatch_continuation,
      request: model.dispatch_continuation.request + 1,
      phase: "idle",
    },
  }
  // Switching only the displayed page must not re-select the same task, erase
  // local input, or duplicate a pending read/command. Returning to Dispatch
  // requests a fresh canonical GET through the existing read-only navigation.
  if task_id == model.dispatch_task_id {
    let (command, next) = update_model(emit, Navigate(page), model)
    return (
      @cmd.batch([
        remember_page_route(page, task_id),
        command,
        if page == Dispatch && previous_page == Dispatch {
          emit(RefreshDispatchTask(task_id, next.dispatch_task_selection))
        } else {
          none
        },
      ]),
      next,
    )
  }
  if !task_id.is_empty() {
    // Open a different canonical task without letting its breadcrumb choose
    // the displayed page. This path never emits create, start, submit or accept.
    let (command, next) = open_dispatch_task(
      emit,
      { ..model, dispatch_task_open_id: task_id, },
      push=false,
      page~,
    )
    if page == Dispatch {
      return (command, next)
    }
    let (page_command, displayed) = update_model(emit, Navigate(page), {
      ..next,
      page: model.page,
    })
    return (@cmd.batch([command, page_command]), displayed)
  }
  let (_, cleared) = update_model(emit, RestoreDispatchTask(""), model)
  let (command, next) = update_model(emit, Navigate(page), {
    ..cleared,
    page: model.page,
  })
  (@cmd.batch([remember_page_route(page, ""), command]), next)
}
