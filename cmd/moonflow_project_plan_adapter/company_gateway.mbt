///|
fn gateway_segment(value : String) -> Bool {
  !value.is_empty() &&
  value != "." &&
  value != ".." &&
  value.length() <= 128 &&
  value
  .iter()
  .all(c => {
    c.is_ascii_alphabetic() ||
    c.is_ascii_digit() ||
    c == '-' ||
    c == '_' ||
    c == ':' ||
    c == '.'
  })
}

///|
/// Explicit owner operation through the existing authenticated local gateway.
/// The session comes from a named process environment variable, never a flag,
/// saved request, adapter evidence, URL, or printed result.
async fn company_gateway(action : String, args : ArrayView[String]) -> Json {
  let gateway = option(args, "--gateway")
  let prefix = "http://127.0.0.1:"
  if !gateway.has_prefix(prefix) {
    fail("use the configured loopback MoonProj gateway")
  }
  let port = gateway[prefix.length():].to_owned()
  if port.is_empty() ||
    !port.iter().all(c => c.is_ascii_digit()) ||
    port.length() > 5 {
    fail(
      "gateway must be one loopback origin without path, query or credentials",
    )
  }
  let task = option(args, "--task")
  if !gateway_segment(task) {
    fail("invalid company task identity")
  }
  let session = @env.get_env_var(option(args, "--session-env")).unwrap_or("")
  if session.is_empty() ||
    session.iter().any(c => c == '\r' || c == '\n' || c == ';') {
    fail("existing gateway session is missing or invalid")
  }
  let headers : @http.Headers = {
    "Cookie": "moonproj_session=" + session,
    "Content-Type": "application/json",
  }
  let base = gateway + "/api/company/plan/tasks/" + task
  let (response, data) = if action == "gateway-snapshot" {
    @http.get(base + "/flow-snapshot", headers~)
  } else {
    let suffix = match action {
      "gateway-approve" => "/flow-bindings"
      "gateway-execute" => "/flow-execute"
      "gateway-return" | "gateway-status" => {
        let key = option(args, "--report-key")
        if !gateway_segment(key) {
          fail("invalid report key")
        }
        "/flow-reports/" +
        key +
        (if action == "gateway-return" { "/return" } else { "/status" })
      }
      _ => fail("unknown gateway company operation")
    }
    let body = @fs.read_file(option(args, "--body")).text()
    ignore(@json.parse(body))
    @http.post(base + suffix, body, headers~)
  }
  let value = @json.parse(data.text())
  if response.code < 200 || response.code >= 300 {
    fail(
      "company gateway refused the operation (HTTP \{response.code}): " +
      value.stringify(),
    )
  }
  value
}
