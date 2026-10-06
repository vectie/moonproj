///|
fn native_route_fixture(ready : Bool, default_model : String) -> Json {
  {
    "contract": "moonclaw.moongate-route.v1",
    "ready": ready,
    "default_model": default_model,
    "models": [
      { "name": "moongate/configured" },
      { "name": "moongate/explicit" },
    ],
  }
}

///|
fn native_route_override(route : Json, key : String, value : Json) -> Json {
  guard route is Object(fields) else { abort("fixture") }
  let next = fields.copy()
  next[key] = value
  Json::object(next)
}

///|
fn native_route_without(route : Json, key : String) -> Json {
  guard route is Object(fields) else { abort("fixture") }
  let next = fields.copy()
  next.remove(key)
  Json::object(next)
}

///|
fn assert_native_model_unavailable(
  route : Json,
  requested : String,
) -> Unit raise {
  try native_model(route, requested) catch {
    _ => ()
  } noraise {
    _ => assert_true(false, msg="unavailable selection must not fall back")
  }
}

///|
test "native explicit selection needs a live catalog without a configured default" {
  let route = native_route_override(
    native_route_fixture(false, ""),
    "catalog_ready",
    true,
  )
  assert_eq(native_model(route, "moongate/explicit"), "moongate/explicit")
  assert_native_model_unavailable(route, "")
  let unavailable_default = native_route_override(
    route, "default_model", "moongate/absent",
  )
  assert_eq(
    native_model(unavailable_default, "moongate/explicit"),
    "moongate/explicit",
  )
  assert_native_model_unavailable(unavailable_default, "")
  for
    projection in [
      native_route_without(route, "default_model"),
      native_route_override(route, "default_model", Json::null()),
      native_route_override(route, "default_model", 1),
      native_route_without(route, "ready"),
    ] {
    assert_eq(
      native_model(projection, "moongate/explicit"),
      "moongate/explicit",
    )
    assert_native_model_unavailable(projection, "")
  }
}

///|
test "native automatic selection requires ready exact configured default" {
  let route = native_route_override(
    native_route_fixture(true, "moongate/configured"),
    "catalog_ready",
    true,
  )
  assert_eq(native_model(route, ""), "moongate/configured")
  for
    default_model in [
      "", "moongate/absent", "default", "codex/configured", "moongate/",
    ] {
    assert_native_model_unavailable(
      native_route_override(route, "default_model", default_model.to_json()),
      "",
    )
  }
  for ready in [(false : Json), Json::null(), "true", 1] {
    assert_native_model_unavailable(
      native_route_override(route, "ready", ready),
      "",
    )
  }
  assert_native_model_unavailable(native_route_without(route, "ready"), "")
}

///|
test "native unavailable stale and malformed catalogs never fall back" {
  let route = native_route_fixture(true, "moongate/configured")
  for
    unavailable in [
      Json::null(),
      native_route_override(route, "contract", "unknown.v1"),
      native_route_override(route, "catalog_ready", false),
      native_route_override(route, "catalog_ready", Json::null()),
      native_route_override(route, "catalog_ready", "true"),
      native_route_override(route, "catalog_ready", 1),
      native_route_override(route, "catalog_ready", {}),
      native_route_override(route, "models", []),
      native_route_override(route, "models", Json::null()),
    ] {
    for requested in ["", "moongate/explicit"] {
      assert_native_model_unavailable(unavailable, requested)
    }
  }
}

///|
test "native legacy payloads remain compatible but selectors stay exact" {
  let route = native_route_fixture(true, "moongate/configured")
  assert_eq(native_model(route, ""), "moongate/configured")
  assert_eq(native_model(route, "moongate/explicit"), "moongate/explicit")
  assert_native_model_unavailable(
    native_route_fixture(false, ""),
    "moongate/explicit",
  )
  let route = native_route_override(route, "models", [
    { "name": "moongate/configured" },
    { "name": "codex/legacy" },
    { "name": "default" },
    { "name": "moongate/" },
  ])
  for
    requested in [
      "moongate/absent", "codex/legacy", "default", "moongate/", " moongate/configured",
      "moongate/configured ",
    ] {
    assert_native_model_unavailable(route, requested)
  }
}

///|
test "native explicit identity survives default changes and snapshot persistence" {
  let route = native_route_override(
    native_route_fixture(false, ""),
    "catalog_ready",
    true,
  )
  let before = route.stringify()
  let selected = native_model(route, "moongate/explicit")
  let snapshot = native_execution_snapshot(
    native_test_task(),
    selected,
    "founder",
  )
  assert_eq(route.stringify(), before)
  let saved = @json.parse(snapshot.stringify())
  assert_eq(native_text(saved, "model"), "moongate/explicit")
  assert_eq(
    native_text(@json.parse(native_text(saved, "request_body")), "model"),
    "moongate/explicit",
  )
  assert_eq(
    native_model(native_route_fixture(true, "moongate/configured"), selected),
    selected,
  )
}
