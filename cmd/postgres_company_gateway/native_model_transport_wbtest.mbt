///|
fn native_hosted_route() -> Json {
  {
    "contract": "moonclaw.moongate-route.v1",
    "ready": false,
    "default_ready": false,
    "catalog_ready": true,
    "default_model": "",
    "models": [{ "name": "moongate/explicit" }],
    "status": "unavailable",
    "error": "MoonGate default model is not configured",
  }
}

///|
fn native_transport_fixture(
  text : String,
  status? : Int = 503,
  method? : @http.RequestMethod = @http.Get,
  path? : String = "/v1/moongate-route",
  body? : String = "",
  instance? : String = "fixture-instance",
) -> Json raise {
  native_validate_response(
    {
      uri: "http://unused.invalid",
      instance_id: "fixture-instance",
      auth_token: "fixture-token-never-real",
    },
    method,
    path,
    body,
    status,
    instance,
    @encoding/utf8.encode(text),
  )
}

///|
test "hosted route 503 reaches exact explicit selection without a default" {
  let route = native_transport_fixture(native_hosted_route().stringify())
  assert_eq(native_model(route, "moongate/explicit"), "moongate/explicit")
  for requested in ["", "moongate/absent", "codex/legacy", "default"] {
    try native_model(route, requested) catch {
      _ => ()
    } noraise {
      _ => assert_true(false, msg="unavailable selector must not fall back")
    }
  }
}

///|
test "hosted route exception is limited to exact read-only endpoint and status" {
  let text = native_hosted_route().stringify()
  for status in [401, 403, 404, 409, 500, 502] {
    try native_transport_fixture(text, status~) catch {
      _ => ()
    } noraise {
      _ => assert_true(false, msg="failed HTTP status must remain rejected")
    }
  }
  for
    path in [
      "/v1/code/capabilities", "/v1/moongate-route?cached=true", "/v1/moongate-route/",
      "/v1/code/sessions/exact/turns",
    ] {
    try native_transport_fixture(text, path~) catch {
      _ => ()
    } noraise {
      _ => assert_true(false, msg="another endpoint must remain rejected")
    }
  }
  for method in [@http.Post, @http.Put, @http.Delete, @http.Patch] {
    try native_transport_fixture(text, method~) catch {
      _ => ()
    } noraise {
      _ => assert_true(false, msg="another method must remain rejected")
    }
  }
  try native_transport_fixture(text, body="{}") catch {
    _ => ()
  } noraise {
    _ => assert_true(false, msg="GET body must remain rejected")
  }
}

///|
test "hosted route 503 requires a genuine catalog-only readiness projection" {
  let route = native_hosted_route()
  for
    (key, value) in [
      ("contract", ("other.v1" : Json)),
      ("ready", true),
      ("default_ready", true),
      ("default_ready", Json::null()),
      ("default_model", "moongate/explicit"),
      ("default_model", Json::null()),
      ("catalog_ready", false),
      ("catalog_ready", Json::null()),
      ("catalog_ready", "true"),
      ("catalog_ready", 1),
      ("models", []),
      ("models", Json::null()),
      ("models", [{ "name": "codex/legacy" }]),
      ("models", [{ "name": "moongate/" }]),
      ("models", [{ "name": "moongate/explicit " }]),
      ("models", [{ "name": "moongate/explicit" }, {}]),
    ] {
    try
      native_transport_fixture(
        native_route_override(route, key, value).stringify(),
      )
    catch {
      _ => ()
    } noraise {
      _ =>
        assert_true(
          false,
          msg="malformed or unavailable 503 must remain rejected: " + key,
        )
    }
  }
  try
    native_transport_fixture(
      native_route_fixture(true, "moongate/configured").stringify(),
    )
  catch {
    _ => ()
  } noraise {
    _ => assert_true(false, msg="legacy ready-only 503 is not catalog evidence")
  }
}

///|
test "hosted route transport preserves response authority and legacy success" {
  let text = native_hosted_route().stringify()
  for
    bad in [
      "{",
      "null",
      text + " ".repeat(2_000_001),
      native_route_override(
        native_hosted_route(),
        "error",
        "fixture-token-never-real",
      ).stringify(),
    ] {
    try native_transport_fixture(bad) catch {
      _ => ()
    } noraise {
      _ => assert_true(false, msg="invalid response data must remain rejected")
    }
  }
  try native_transport_fixture(text, instance="different") catch {
    _ => ()
  } noraise {
    _ => assert_true(false, msg="instance mismatch must remain rejected")
  }
  let legacy = native_transport_fixture(
    native_route_fixture(true, "moongate/configured").stringify(),
    status=200,
  )
  assert_eq(native_model(legacy, ""), "moongate/configured")
  assert_eq(native_model(legacy, "moongate/explicit"), "moongate/explicit")
}
