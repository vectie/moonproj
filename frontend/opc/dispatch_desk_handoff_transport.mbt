///|
fn load_dispatch_desk_handoff(
  emit : @rabbita.Emit[Msg],
  state : DispatchDeskHandoff,
) -> Cmd {
  let page = dispatch_handoff_current_page()
  let return_to = dispatch_handoff_task_url(page, state.task_id)
  @http.get(
    "/api/company/tasks/" +
    dispatch_url_encode(state.task_id) +
    "/desk-handoff" +
    (if state.follow_up { "?mode=follow_up" } else { "" }),
  ).expect_text(result => {
    emit(
      DeskHandoffAction(
        Loaded(
          state.task_id,
          state.selection,
          state.request,
          page,
          return_to,
          match result {
            Ok(response) => Ok(response)
            Err(error) => Err(error.to_string())
          },
        ),
      ),
    )
  })
}

///|
#cfg(target="js")
extern "js" fn dispatch_handoff_current_page() -> String =
  #| () => globalThis.location?.href || ""

///|
#cfg(target="js")
extern "js" fn dispatch_handoff_task_url(
  page : String,
  task : String,
) -> String =
  #| (page, task) => {
  #|   try { const url = new URL(page); if (!['http:', 'https:'].includes(url.protocol)) return ''; url.searchParams.set('task', task); return url.href; } catch (_) { return ''; }
  #| }

///|
#cfg(target="js")
extern "js" fn dispatch_build_desk_url(
  origin : String,
  task : String,
  run : String,
  session : String,
  command : String,
  root : String,
  return_to : String,
) -> String =
  #| (origin, task, run, session, command, root, returnTo) => {
  #|   try {
  #|     const url = new URL(origin), back = new URL(returnTo);
  #|     if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.pathname !== '/' || url.search || url.hash) return '';
  #|     if (!['http:', 'https:'].includes(back.protocol) || back.username || back.password || back.searchParams.get('task') !== task) return '';
  #|     url.search = new URLSearchParams({activity:'code', session, book_root:root, command, work_task:task, work_run:run, work_mode:'inspect', return_to:back.href}).toString();
  #|     return url.href;
  #|   } catch (_) { return ''; }
  #| }

///|
#cfg(target="js")
extern "js" fn dispatch_desk_title_url(
  value : String,
  title : String,
) -> String =
  #| (value, title) => { const url = new URL(value); if (title) url.searchParams.set('work_title', title); return url.href; }

///|
#cfg(target="js")
extern "js" fn dispatch_navigate_desk(expected_page : String, url : String) =
  #| (expectedPage, url) => {
  #|   if (globalThis.location && globalThis.location.href.split('#', 1)[0] === expectedPage.split('#', 1)[0]) globalThis.location.assign(url);
  #| }

///|
#cfg(target="js")
extern "js" fn dispatch_desk_follow_up_url(value : String) -> String =
  #| value => { const url = new URL(value); url.searchParams.set('work_mode','follow_up'); return url.href; }

///|
#cfg(target="js")
extern "js" fn dispatch_desk_accepted_url(
  value : String,
  accepted : Bool,
) -> String =
  #| (value, accepted) => { const url = new URL(value); url.searchParams.set('work_accepted', accepted ? 'true' : 'false'); return url.href; }

///|
#cfg(target="js")
extern "js" fn dispatch_desk_output_url_raw(
  value : String,
  command : String,
  path : String,
  evidence : String,
) -> String =
  #| (value, command, path, evidence) => { const url = new URL(value); url.searchParams.set('work_mode','inspect'); for (const [key, value] of [['work_output_command',command],['work_output_path',path],['work_output_evidence',evidence]]) url.searchParams.set(key, value); return url.href; }

///|
fn dispatch_desk_output_url(value : String, output : Json) -> String {
  dispatch_desk_output_url_raw(
    value,
    dispatch_json_text(output, "command_id"),
    dispatch_json_text(output, "path"),
    dispatch_json_text(output, "evidence_id"),
  )
}
