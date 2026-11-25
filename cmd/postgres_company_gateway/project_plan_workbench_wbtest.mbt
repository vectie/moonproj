///|
test "project plan routes are exact and reject traversal and extra suffixes" {
  assert_eq(
    workbench_route("/api/company/projects/company-actual/prepared-plans"),
    Some(("company-actual", "")),
  )
  assert_eq(
    workbench_route(
      "/api/company/projects/company-actual/prepared-plans/plan-one",
    ),
    Some(("company-actual", "plan-one")),
  )
  for
    path in [
      "/api/company/projects/../prepared-plans", "/api/company/projects/p/prepared-plans/..",
      "/api/company/projects/p/prepared-plans/k/execute",
    ] {
    assert_true(workbench_route(path) is None)
  }
}

///|
async test "actual UI wire request authenticated gateway native prepare durable reopen and downloads" {
  let fixture = @env.get_env_var("MOONPROJ_PLAN_FIXTURE_DIR").unwrap_or("")
  if fixture.is_empty() {
    return
  }
  let body = @fs.read_file(fixture + "/ui-request.json").text()
  let root = @fs.tmpdir(prefix="moonproj-gateway-plan-wire")
  @fs.mkdir(root + "/moonproj")
  let service = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer service.close()
  let gateway = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer gateway.close()
  let service_uri = "http://127.0.0.1:" + service.addr().port().to_string()
  let gateway_uri = "http://127.0.0.1:" + gateway.addr().port().to_string()
  let sessions : Map[String, String] = { "fixture-session": "owner-test" }
  let reads = Ref(0)
  let resources : ProductResources = {
    catalog_path: "unused",
    document_root: "unused",
    workspace_root: root,
  }
  let path = "/api/company/projects/company-actual/prepared-plans"
  @async.with_timeout(15000, fn() {
    @async.with_task_group(fn(group) {
      group.spawn_bg(fn() {
        service.run_forever(fn(request, _, conn) {
          assert_eq(request.meth, @http.Get)
          assert_eq(header(request, "X-Moonproj-Actor"), "owner-test")
          assert_eq(
            header(request, "Authorization"),
            "Bearer synthetic-test-token",
          )
          reads.val += 1
          if request.path == "/api/company/projects/company-actual" ||
            request.path == "/api/company/projects/company-second" ||
            request.path == "/api/company/projects/company:actual" {
            send_json(conn, request.meth, 200, {
              "project_id": if request.path.has_suffix("company:actual") {
                "company:actual"
              } else if request.path.has_suffix("company-second") {
                "company-second"
              } else {
                "company-actual"
              },
              "project_code": "TEST",
              "project_name": "Synthetic test project",
              "bu_guid": "unit-test",
            })
          } else {
            send_json(conn, request.meth, 404, {
              "error": "test project missing",
            })
          }
        })
      })
      group.spawn_bg(fn() {
        gateway.run_forever(fn(request, reader, conn) {
          handle(
            request,
            reader,
            conn,
            service_uri,
            "",
            "",
            "",
            root,
            resources,
            "synthetic-test-token",
            "synthetic-signing-secret",
            "synthetic-session-secret",
            "",
            "",
            "",
            None,
            None,
            None,
            sessions,
            Ref(0),
          )
        })
      })
      let headers : @http.Headers = {
        "Cookie": "moonproj_session=fixture-session",
        "Content-Type": "application/json",
      }
      let (unauth, _) = @http.post(gateway_uri + path, body)
      assert_eq(unauth.code, 401)
      assert_eq(reads.val, 0)
      for malformed in ["{", "{}"] {
        let (invalid_form, _) = @http.post(
          gateway_uri + path,
          malformed,
          headers~,
        )
        assert_eq(invalid_form.code, 422)
      }
      let (prepared, data) = @http.post(gateway_uri + path, body, headers~)
      let text = data.text()
      assert_eq(prepared.code, 200, msg=text)
      let record = @json.parse(text)
      assert_eq(
        native_text(record, "contract"),
        "moonproj.project-plan-workbench.v1",
      )
      assert_eq(native_text(record, "key"), "plan-fixture")
      assert_eq(native_field(record, "persisted"), Json::boolean(true))
      let (repeat, repeated) = @http.post(gateway_uri + path, body, headers~)
      assert_eq(repeat.code, 200)
      assert_eq(repeated.text(), text)
      let (opened, opened_data) = @http.get(
        gateway_uri + path + "/plan-fixture",
        headers~,
      )
      assert_eq(opened.code, 200)
      assert_eq(opened_data.text(), text)
      let (listed, listed_data) = @http.get(gateway_uri + path, headers~)
      assert_eq(listed.code, 200)
      assert_eq(
        native_array(@json.parse(listed_data.text()), "items").length(),
        1,
      )
      // Round 26 crossing: preserve the actual compiled-UI typed second input,
      // prepare it natively, then read both immutable versions via exact GET.
      let after_path = fixture + "/ui-compare-after-request.json"
      if @fs.exists(after_path) {
        let after_body = @fs.read_file(after_path).text()
        let (created_after, after_data) = @http.post(
          gateway_uri + path,
          after_body,
          headers~,
        )
        assert_eq(created_after.code, 200, msg=after_data.text())
        let (read_after, read_after_data) = @http.get(
          gateway_uri + path + "/plan-after",
          headers~,
        )
        assert_eq(read_after.code, 200)
        assert_eq(read_after_data.text(), after_data.text())
        let (read_before, read_before_data) = @http.get(
          gateway_uri + path + "/plan-fixture",
          headers~,
        )
        assert_eq(read_before.code, 200)
        assert_eq(read_before_data.text(), text)
        @fs.write_file(
          fixture + "/gateway-compare-after.json",
          read_after_data.text(),
          create_mode=@fs.CreateOrTruncate,
        )
      }
      // Exercise the actual compiled template import/edit request in another
      // project through the same authenticated handler and native plan path.
      let template_path = fixture + "/template-ui-request.json"
      if @fs.exists(template_path) {
        let template_body = @fs.read_file(template_path).text()
        let template_url = gateway_uri +
          "/api/company/projects/company-second/prepared-plans"
        let (created, created_data) = @http.post(
          template_url,
          template_body,
          headers~,
        )
        assert_eq(created.code, 200, msg=created_data.text())
        let saved_template = @json.parse(created_data.text())
        let template_key = native_text(saved_template, "key")
        let (reopened, reopened_data) = @http.get(
          template_url + "/" + template_key,
          headers~,
        )
        assert_eq(reopened.code, 200)
        assert_eq(reopened_data.text(), created_data.text())
        assert_eq(
          native_field(saved_template, "draft"),
          @json.parse(template_body),
        )
        let artifact = native_field(saved_template, "artifact")
        assert_eq(
          native_text(native_field(artifact, "project"), "project_id"),
          "company-second",
        )
        assert_eq(
          native_text(native_field(artifact, "budget"), "planned_total_minor"),
          "60090",
        )
        assert_eq(
          native_text(native_field(artifact, "workflow"), "status"),
          "pending_review",
        )
        assert_eq(
          native_field(native_field(artifact, "workflow"), "accepted"),
          Json::boolean(false),
        )
        assert_eq(native_array(artifact, "tasks").length(), 4)
        assert_eq(native_array(artifact, "milestones").length(), 2)
        assert_eq(native_array(artifact, "risks").length(), 1)
        for
          effect in [
            "spend_authorized", "accounting_posted", "payment_released", "contract_signed",
            "work_executed",
          ] {
          assert_eq(
            native_field(native_field(artifact, "authority_effects"), effect),
            Json::boolean(false),
          )
        }
        @fs.write_file(
          fixture + "/template-gateway-response.json",
          reopened_data.text(),
          create_mode=@fs.CreateOrTruncate,
        )
        @fs.write_file(
          fixture + "/template-native-readable.txt",
          native_text(saved_template, "readable"),
          create_mode=@fs.CreateOrTruncate,
        )
        @fs.write_file(
          fixture + "/template-native-artifact.json",
          native_text(saved_template, "artifact_json"),
          create_mode=@fs.CreateOrTruncate,
        )
      }
      let wrong = body.replace_all(old="company-actual", new="company-second")
      let (mismatched, _) = @http.post(gateway_uri + path, wrong, headers~)
      assert_eq(mismatched.code, 422)
      let invalid = body.replace_all(old="1000.00", new="1.00")
      let (rejected, rejected_data) = @http.post(
        gateway_uri + path,
        invalid,
        headers~,
      )
      assert_eq(rejected.code, 422)
      assert_true(rejected_data.text().contains("budget"))
      let (missing, _) = @http.get(
        gateway_uri + "/api/company/projects/company-missing/prepared-plans",
        headers~,
      )
      assert_eq(missing.code, 404)
      let colon_path = @fs.read_file(fixture + "/ui-colon-url.txt").text()
      assert_eq(
        colon_path, "/api/company/projects/company:actual/prepared-plans",
      )
      let colon_body = body.replace_all(
        old="company-actual",
        new="company:actual",
      )
      let (colon_response, colon_data) = @http.post(
        gateway_uri + colon_path,
        colon_body,
        headers~,
      )
      assert_eq(colon_response.code, 200, msg=colon_data.text())
      let (colon_opened, _) = @http.get(
        gateway_uri + colon_path + "/plan-fixture",
        headers~,
      )
      assert_eq(colon_opened.code, 200)
      @fs.write_file(
        fixture + "/gateway-response.json",
        text,
        create_mode=@fs.CreateOrTruncate,
      )
      @fs.write_file(
        fixture + "/native-artifact.json",
        native_text(record, "artifact_json"),
        create_mode=@fs.CreateOrTruncate,
      )
      @fs.write_file(
        fixture + "/native-readable.txt",
        native_text(record, "readable"),
        create_mode=@fs.CreateOrTruncate,
      )
      @fs.write_file(
        fixture + "/wire-receipt.json",
        (
          {
            "company_service": "synthetic read-only company projection fixture",
            "gateway": "actual authenticated production handler over loopback HTTP",
            "native_prepare": "actual moonproj/project.plan.prepare@0.1.0 in process",
            "durable_root": root,
            "company_reads": reads.val,
            "company_commands": 0,
            "provider_calls": 0,
            "standalone_plan_executable_required": false,
          } : Json).stringify(indent=2),
        create_mode=@fs.CreateOrTruncate,
      )
      group.return_immediately(())
    })
  })
}
