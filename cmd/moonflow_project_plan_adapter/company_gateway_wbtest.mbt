///|
test "normal gateway CLI rejects unsafe identities" {
  for value in ["", ".", "..", "a/b", "a?token=secret", "a\nCookie"] {
    assert_false(gateway_segment(value))
  }
  assert_true(gateway_segment("PT-owner:revision-2"))
}

///|
async test "normal CLI helper uses exact HTTP routes and only environment session" {
  let session = @env.get_env_var("MOONPROJ_FLOW_TEST_SESSION").unwrap_or("")
  if session.is_empty() {
    return
  }
  let root = @fs.tmpdir(prefix="moonproj-flow-cli")
  let body_file = root + "/body.json"
  @fs.write_file(
    body_file,
    "{\"request_ref\":\"runtime/request-r2.json\"}",
    create_mode=@fs.CreateNew,
  )
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let uri = "http://127.0.0.1:" + server.addr().port().to_string()
  let paths : Array[String] = []
  @async.with_timeout(10000, fn() {
    @async.with_task_group(fn(group) {
      group.spawn_bg(fn() {
        server.run_forever(fn(request, _, conn) {
          assert_eq(
            request.headers
            .get("cookie")
            .unwrap_or(request.headers.get("Cookie").unwrap_or("")),
            "moonproj_session=" + session,
          )
          assert_false(request.path.contains(session))
          paths.push(request.path)
          conn.skip_request_body()
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write_string("{\"state\":\"synthetic-cli-route-ok\"}")
          conn.end_response()
        })
      })
      let args = [
        "--gateway", uri, "--task", "PT-revised", "--session-env", "MOONPROJ_FLOW_TEST_SESSION",
        "--body", body_file, "--report-key", "plan-output",
      ]
      for
        action in [
          "gateway-snapshot", "gateway-approve", "gateway-execute", "gateway-return",
          "gateway-status",
        ] {
        assert_eq(
          company_gateway(action, args),
          ({ "state": "synthetic-cli-route-ok" } : Json),
        )
      }
      assert_eq(paths, [
        "/api/company/plan/tasks/PT-revised/flow-snapshot", "/api/company/plan/tasks/PT-revised/flow-bindings",
        "/api/company/plan/tasks/PT-revised/flow-execute", "/api/company/plan/tasks/PT-revised/flow-reports/plan-output/return",
        "/api/company/plan/tasks/PT-revised/flow-reports/plan-output/status",
      ])
      group.return_immediately(())
    })
  })
  let unsafe = [
    "--gateway", "https://example.invalid", "--task", "PT-revised", "--session-env",
    "MOONPROJ_FLOW_TEST_SESSION",
  ]
  try company_gateway("gateway-snapshot", unsafe) catch {
    _ => ()
  } noraise {
    _ => fail("session must not leave configured loopback gateway")
  }
}
