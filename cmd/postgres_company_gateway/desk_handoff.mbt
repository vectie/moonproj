///|
/// A browser destination is operator configuration, never a discovered daemon port.
fn desk_handoff_config(cli : String?, environment : String?) -> String {
  cli.unwrap_or(environment.unwrap_or(""))
}

///|
fn desk_handoff_origin(configured : String) -> String? {
  let value = configured.trim().to_owned()
  let prefix = if value.has_prefix("https://") {
    "https://"
  } else if value.has_prefix("http://") {
    "http://"
  } else {
    return None
  }
  let origin = if value.has_suffix("/") {
    value[:value.length() - 1].to_owned()
  } else {
    value
  }
  let authority = origin[prefix.length():].to_owned()
  if authority.is_empty() ||
    authority
    .iter()
    .any(c => {
      c <= ' ' ||
      c == '/' ||
      c == '\\' ||
      c == '?' ||
      c == '#' ||
      c == '@' ||
      c == '%' ||
      c == '\u007f'
    }) {
    return None
  }
  let (host, port) = if authority.has_prefix("[") {
    let close = match authority.find("]") {
      Some(index) => index
      None => return None
    }
    let host = authority[:close + 1].to_owned()
    let rest = authority[close + 1:].to_owned()
    ignore(@socket.Addr::parse(host + ":80") catch { _ => return None })
    if rest == "" {
      (host, None)
    } else if rest.has_prefix(":") {
      (host, Some(rest[1:].to_owned()))
    } else {
      return None
    }
  } else {
    let parts = authority.split(":").to_array()
    if parts.length() > 2 {
      return None
    }
    let host = parts[0].to_owned()
    if host.is_empty() ||
      !host
      .iter()
      .all(c => {
        c.is_ascii_digit() ||
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        c == '-' ||
        c == '.'
      }) {
      return None
    }
    (host, parts.get(1).map(value => value.to_owned()))
  }
  if host.is_empty() {
    return None
  }
  if port is Some(port) {
    if !port.iter().all(c => c.is_ascii_digit()) {
      return None
    }
    let number = parse_uint(port)
    if number is None || number.unwrap() == 0UL || number.unwrap() > 65535UL {
      return None
    }
  }
  Some(origin)
}

///|
fn desk_handoff_task_id(path : String) -> String? {
  let prefix = "/api/company/tasks/"
  let suffix = "/desk-handoff"
  if path.has_prefix(prefix) && path.has_suffix(suffix) {
    let id = path[prefix.length():path.length() - suffix.length()].to_owned()
    if valid_identifier(id) {
      return Some(id)
    }
  }
  None
}

///|
fn desk_handoff_projection(
  task : Json,
  destination : String,
  requested_mode? : String = "inspect",
) -> Json {
  let execution = native_field(task, "execution")
  let origin = desk_handoff_origin(destination)
  let has_execution = execution is Object(_)
  let complete = has_execution &&
    native_text(execution, "task_id") == native_text(task, "taskGuid") &&
    !native_text(execution, "task_id").is_empty() &&
    !native_text(execution, "run_id").is_empty() &&
    !native_text(execution, "session_id").is_empty() &&
    !native_text(execution, "command_id").is_empty() &&
    native_text(execution, "workspace").has_prefix("/")
  let (state, message) = if !has_execution {
    ("no_execution", "This task has no captured native execution to inspect")
  } else if !complete {
    (
      "execution_unavailable", "The captured native execution identity is incomplete",
    )
  } else if destination.trim().is_empty() {
    (
      "destination_unconfigured", "Configure MOONDESK_ORIGIN or --moondesk-origin to open this work in MoonDesk",
    )
  } else if origin is None {
    (
      "destination_invalid", "MoonDesk destination must be an HTTP(S) origin with the application at /; credentials, query strings and deployment subpaths are unsupported",
    )
  } else {
    ("ready", "Open the captured native work for inspection")
  }
  let context = native_field(execution, "product_context")
  {
    "schema": "moonproj.desk-handoff.v1",
    "state": state,
    "message": message,
    "desk_origin": match origin {
      Some(value) => Json::string(value)
      None => Json::null()
    },
    "work": if has_execution {
      {
        "task_id": native_text(execution, "task_id"),
        "run_id": native_text(execution, "run_id"),
        "session_id": native_text(execution, "session_id"),
        "original_command_id": native_text(execution, "command_id"),
        "book_root": native_text(execution, "workspace"),
        "model": native_text(execution, "model"),
      }
    } else {
      Json::null()
    },
    "task_accepted": native_text(task, "status") == "done" ||
    native_text(execution, "acceptance") == "accepted",
    "mode": if requested_mode == "follow_up" &&
      !native_continuation_accepted(task) {
      "follow_up"
    } else {
      "inspect"
    },
    "product_context": if context is Object(_) {
      {
        "product_id": native_text(context, "product_id"),
        "context_path": native_text(context, "context_path"),
        "sha256": native_text(context, "sha256"),
        "coverage": native_text(context, "coverage"),
      }
    } else {
      Json::null()
    },
  }
}

///|
async fn desk_handoff_task(
  bridge : NativeBridge,
  task_id : String,
  destination : String,
  requested_mode? : String = "inspect",
) -> ProxyResult raise GatewayError {
  // Unlike native_refresh_task, this read never observes or resumes execution.
  let detail = native_company_request(
    bridge,
    @http.Get,
    "/api/company/tasks/" + task_id,
    Json::null(),
  )
  if detail.status == 401 || detail.status == 404 {
    return detail
  }
  if detail.status != 200 {
    raise GatewayError::Upstream("Company task read is unavailable")
  }
  let task = native_field(
    native_field(native_result_json(detail), "data"),
    "task",
  )
  if native_text(task, "taskGuid") != task_id {
    raise GatewayError::Upstream(
      "Company service did not return the requested task",
    )
  }
  native_json_result(
    200,
    desk_handoff_projection(task, destination, requested_mode~),
  )
}
