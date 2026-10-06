///|
fn company_setup_reads(
  emit : @rabbita.Emit[Msg],
  state : CompanySetupState,
) -> Cmd {
  @cmd.batch([
    company_setup_get("/api/company/profile", (status, body) => {
      emit(
        CompanySetupAction(
          ProfileRead(
            state.actor,
            state.epoch,
            state.read_request,
            status,
            body,
          ),
        ),
      )
    }),
    company_setup_get("/api/company/business-units/tree", (status, body) => {
      emit(
        CompanySetupAction(
          UnitsRead(state.actor, state.epoch, state.read_request, status, body),
        ),
      )
    }),
  ])
}

///|
fn company_setup_store(state : CompanySetupState) -> String {
  ToJson::to_json(CompanySetupStore::{
    version: 1,
    company: state.company.request,
    project: state.project.request,
    recent_project: state.recent_project,
  }).stringify()
}

///|
extern "js" fn company_setup_write(actor : String, body : String) -> Bool =
  #| (actor, body) => {
  #|   if (!actor || typeof window === "undefined") return false;
  #|   try { window.localStorage.setItem("moonproj.bootstrap.v1." + encodeURIComponent(actor), body); return true; }
  #|   catch (_) { return false; }
  #| }

///|
extern "js" fn company_setup_read(actor : String) -> String =
  #| actor => {
  #|   if (!actor || typeof window === "undefined") return "storage-unavailable";
  #|   try { return window.localStorage.getItem("moonproj.bootstrap.v1." + encodeURIComponent(actor)) || ""; }
  #|   catch (_) { return "storage-unavailable"; }
  #| }

///|
fn company_setup_persist(
  emit : @rabbita.Emit[Msg],
  state : CompanySetupState,
  kind : String,
  key : String,
) -> Cmd {
  let body = company_setup_store(state)
  @cmd.custom_cmd(scheduler => {
    scheduler.add(
      emit(
        CompanySetupAction(
          Persisted(
            state.actor,
            state.epoch,
            kind,
            key,
            company_setup_write(state.actor, body),
          ),
        ),
      ),
    )
  })
}

///|
fn company_setup_post(
  emit : @rabbita.Emit[Msg],
  state : CompanySetupState,
  request : CompanySetupRequest,
) -> Cmd {
  let url = if request.kind == "company" {
    "/api/company/profile"
  } else {
    "/api/company/source/mdm/projects"
  }
  let body = company_setup_body(request)
  @cmd.custom_cmd(scheduler => {
    company_setup_fetch(url, "POST", request.key, body, (status, response) => {
      scheduler.add(
        emit(
          CompanySetupAction(
            Posted(
              state.actor,
              state.epoch,
              request.kind,
              request.key,
              status,
              response,
            ),
          ),
        ),
      )
    })
  })
}

///|
// Gateway owns signing and authenticated authority. Neither is client-stored.
// Bound the whole response, including body consumption. A deadline means
// unknown outcome, never proof that a command did not commit.
extern "js" fn company_setup_fetch(
  url : String,
  method : String,
  key : String,
  body : String,
  receive : (Int, String) -> Unit,
) =
  #| (url, method, key, body, receive) => {
  #|   const controller = typeof AbortController === "function" ? new AbortController() : null;
  #|   let settled = false;
  #|   let timer;
  #|   const finish = (status, text) => {
  #|     if (settled) return;
  #|     settled = true;
  #|     clearTimeout(timer);
  #|     receive(status, text);
  #|   };
  #|   timer = setTimeout(() => {
  #|     finish(0, '{"error":"request_timeout"}');
  #|     if (controller) controller.abort();
  #|   }, 30000);
  #|   const headers = {Accept: "application/json"};
  #|   if (method === "POST") { headers["Content-Type"] = "application/json"; headers["Idempotency-Key"] = key; }
  #|   const options = {method, credentials: "same-origin", headers};
  #|   if (method === "POST") options.body = body;
  #|   if (controller) options.signal = controller.signal;
  #|   try {
  #|     fetch(url, options).then(response => response.text().then(text => finish(response.status, text)))
  #|       .catch(() => finish(0, ""));
  #|   } catch (_) { finish(0, ""); }
  #| }

///|
fn company_setup_get(url : String, receive : (Int, String) -> Cmd) -> Cmd {
  @cmd.custom_cmd(scheduler => {
    company_setup_fetch(url, "GET", "", "", (status, body) => {
      scheduler.add(receive(status, body))
    })
  })
}

///|
fn company_setup_recover_project(
  emit : @rabbita.Emit[Msg],
  state : CompanySetupState,
  request : CompanySetupRequest,
) -> Cmd {
  company_setup_get(
    "/api/company/projects/" + dispatch_url_encode(request.project_id),
    (status, body) => {
      emit(
        CompanySetupAction(
          ExactRead(state.actor, state.epoch, request.key, status, body),
        ),
      )
    },
  )
}

///|
fn company_setup_session(
  emit : @rabbita.Emit[Msg],
  model : Model,
  actor : String,
) -> (Cmd, Model) {
  let (drafts, shared) = dispatch_draft_session(emit, model, actor)
  let state = model.company_setup
  if actor == state.actor && state.session_state == "ready" {
    return (drafts, shared)
  }
  let next = {
    ..company_setup_initial(),
    actor,
    epoch: state.epoch + 1,
    session_request: state.session_request,
    read_request: state.read_request + 1,
    session_state: if actor.is_empty() {
      "unauthorized"
    } else {
      "ready"
    },
    profile_state: if actor.is_empty() {
      "unauthorized"
    } else {
      "loading"
    },
    units_state: if actor.is_empty() {
      "unauthorized"
    } else {
      "loading"
    },
  }
  let loaded = {
    ..shared,
    company_setup: next,
    company_name: "",
    company_saved: false,
    products: {
      ..shared.products,
      projects: [],
      project_state: "idle",
      project_note: "",
      project_id: "",
      project_request: shared.products.project_request + 1,
    },
  }
  if actor.is_empty() {
    return (drafts, loaded)
  }
  (
    @cmd.batch([
      drafts,
      company_setup_reads(emit, next),
      @cmd.custom_cmd(scheduler => {
        scheduler.add(
          emit(
            CompanySetupAction(
              Restored(actor, next.epoch, company_setup_read(actor)),
            ),
          ),
        )
      }),
    ]),
    loaded,
  )
}
