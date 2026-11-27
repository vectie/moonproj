///|
fn moondesk_loopback_origin(origin : String) -> String? {
  let trimmed = origin.trim().to_owned()
  let clean = if trimmed.has_suffix("/") {
    trimmed[:trimmed.length() - 1].to_owned()
  } else {
    trimmed
  }
  match clean {
    "http://127.0.0.1:4201"
    | "http://127.0.0.1:4199"
    | "http://localhost:4201"
    | "http://localhost:4199" => Some(clean)
    _ => None
  }
}

///|
async fn moondesk_probe_reachable(origin : String) -> Bool {
  @async.with_timeout(1500, async fn() {
    let (response, _) = @http.get(origin + "/")
    response.code >= 200 && response.code < 400
  }) catch {
    _ => false
  }
}

///|
async fn moondesk_ensure_running(
  moondesk_origin : String,
  allow_launch : Bool,
) -> ProxyResult {
  let origin = match moondesk_loopback_origin(moondesk_origin) {
    Some(valid) => valid
    None =>
      return native_json_result(200, {
        "reachable": false,
        "started": false,
        "can_launch": false,
        "origin": moondesk_origin,
        "error": "MoonDesk local origin is not configured for loopback embedding",
      })
  }
  if moondesk_probe_reachable(origin) {
    return native_json_result(200, {
      "reachable": true,
      "started": false,
      "can_launch": allow_launch,
      "origin": origin,
    })
  }
  if !allow_launch {
    return native_json_result(200, {
      "reachable": false,
      "started": false,
      "can_launch": false,
      "origin": origin,
      "error": "本地 MoonDesk 服务（" + origin + "）尚未启动",
    })
  }
  let app_path = "/Applications/MoonDesk.app"
  let installed = @fs.exists(app_path) catch { _ => false }
  if !installed {
    return native_json_result(200, {
      "reachable": false,
      "started": false,
      "can_launch": false,
      "origin": origin,
      "error": "未找到 /Applications/MoonDesk.app，请先安装或手动启动 MoonDesk",
    })
  }
  let launched = try {
    let status = @process.run("/usr/bin/open", ["-g", "-a", app_path])
    status == 0
  } catch {
    _ => false
  }
  if !launched {
    return native_json_result(200, {
      "reachable": false,
      "started": false,
      "can_launch": true,
      "origin": origin,
      "error": "未能拉起 MoonDesk.app，请手动打开 MoonDesk 后重试",
    })
  }
  let mut ready = false
  for _ in 0..<18 {
    @async.sleep(350)
    if moondesk_probe_reachable(origin) {
      ready = true
      break
    }
  }
  native_json_result(200, {
    "reachable": ready,
    "started": true,
    "can_launch": true,
    "origin": origin,
    "error": if ready {
      ""
    } else {
      "已尝试启动 MoonDesk，但 " +
      origin +
      " 尚未就绪，请稍候点击重试"
    },
  })
}
