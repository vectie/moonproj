///|
test "Flow gateway routes reject traversal suffixes and unknown actions" {
  assert_eq(
    flow_gateway_route("/api/company/plan/tasks/PT-revised/flow-bindings"),
    Some(("PT-revised", "flow-bindings", "")),
  )
  assert_eq(
    flow_gateway_route(
      "/api/company/plan/tasks/PT-revised/flow-reports/plan-output/return",
    ),
    Some(("PT-revised", "return", "plan-output")),
  )
  for
    path in [
      "/api/company/plan/tasks/../flow-bindings", "/api/company/plan/tasks/t/flow-bindings/extra",
      "/api/company/plan/tasks/t/flow-reports/../return", "/api/company/plan/tasks/t/flow-reports/k/execute",
    ] {
    assert_true(flow_gateway_route(path) is None)
  }
}

///|
fn flow_wire_report(body : Json, key : String) -> Json {
  let fields = match body {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  fields.remove("progress_pct")
  fields["progress_bps"] = Json::number(0)
  fields["actor_id"] = Json::string("owner-plan")
  fields["command_type"] = Json::string("report")
  fields["state"] = Json::string("observed")
  fields["flow_source_revision"] = native_field(
    native_field(body, "flow_binding"),
    "source_revision",
  )
  let event = "delivery:task_report:report:" + key
  {
    "kind": "company_command",
    "command_family": "delivery",
    "family": "task_report",
    "aggregate_type": "task_report",
    "command_type": "report",
    "idempotency_key": key,
    "aggregate_id": native_field(body, "report_id"),
    "actor_id": "owner-plan",
    "request": Json::object(fields),
    "result": {
      "aggregate_id": native_field(body, "report_id"),
      "state": "observed",
      "revision": 1,
      "event_id": event,
      "audit_id": event + ":audit",
      "actor_id": "owner-plan",
      "delivery_effect": false,
      "cash_effect": false,
      "accounting_effect": false,
      "tax_effect": false,
    },
  }
}

///|
async test "actual authenticated gateway approves revised task executes once and returns report after lost acknowledgements" {
  let pointer = @env.get_env_var("MOONPROJ_FLOW_V2_FIXTURE_POINTER").unwrap_or(
    "",
  )
  if pointer.is_empty() {
    return
  }
  let fixture = @json.parse(@fs.read_file(pointer).text())
  let root = native_text(fixture, "workspace")
  let scratch = @fs.tmpdir(prefix="moonproj-flow-wire")
  let suffix = scratch[scratch.rev_find("/").unwrap() + 1:].to_owned()
  let parent = native_control_root(pointer) + "/" + suffix
  @fs.mkdir(parent)
  // Copy only immutable declared inputs into a fresh private runtime on each
  // wire replay. Prior approval, output, and reporting history remain intact.
  let workspace = parent + "/moonproj"
  @fs.mkdir(workspace)
  let refs = native_array(
    native_field(native_field(fixture, "binding"), "flow_request"),
    "input_artifacts",
  ).map(value => {
    match value {
      String(text) => text
      _ => abort("fixture input")
    }
  })
  refs.push(native_text(fixture, "request_ref"))
  for reference in refs {
    let directory = native_control_root(workspace + "/" + reference)
    if !@fs.exists(directory) {
      @fs.mkdir(directory, recursive=true)
    }
    @fs.write_file(
      workspace + "/" + reference,
      @fs.read_file(root + "/" + reference).binary(),
      create_mode=@fs.CreateNew,
    )
  }
  let review_evidence : Array[String] = []
  if @fs.exists(root + "/flow-review.json") {
    @fs.write_file(
      workspace + "/flow-review.json",
      @fs.read_file(root + "/flow-review.json").binary(),
      create_mode=@fs.CreateNew,
    )
    review_evidence.push("flow-review.json")
  }
  let fields = match fixture {
    Object(fields) => fields.copy()
    _ => Map::new()
  }
  fields["workspace"] = Json::string(workspace)
  @fs.write_file(
    pointer,
    Json::object(fields).stringify(),
    create_mode=@fs.CreateOrTruncate,
  )
  let request_ref = native_text(fixture, "request_ref")
  let result_ref = native_text(fixture, "result_ref")
  let binding = native_field(fixture, "binding")
  let snapshot = Ref(native_field(binding, "snapshot"))
  let approval = native_field(fixture, "approval")
  let approval_effects = Ref(0)
  let approval_requests = Ref(0)
  let report_effects = Ref(0)
  let report_requests = Ref(0)
  let report : Ref[Json?] = Ref(None)
  let service_reads = Ref(0)
  let service = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer service.close()
  let gateway = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer gateway.close()
  let service_uri = "http://127.0.0.1:" + service.addr().port().to_string()
  let gateway_uri = "http://127.0.0.1:" + gateway.addr().port().to_string()
  let path = "/api/company/plan/tasks/PT-revised"
  let sessions : Map[String, String] = { "fixture-session": "owner-plan" }
  let resources : ProductResources = {
    catalog_path: "unused",
    document_root: "unused",
    workspace_root: parent,
  }
  @async.with_timeout(30000, fn() {
    @async.with_task_group(fn(group) {
      group.spawn_bg(fn() {
        service.run_forever(fn(request, reader, conn) {
          assert_eq(
            header(request, "Authorization"),
            "Bearer synthetic-test-token",
          )
          assert_eq(header(request, "X-Moonproj-Actor"), "owner-plan")
          assert_eq(
            header(request, "X-Moonproj-Actor-Signature"),
            hmac_hex("synthetic-signing-secret", "owner-plan"),
          )
          if request.meth == @http.Get &&
            request.path == path + "/flow-snapshot" {
            service_reads.val += 1
            send_json(conn, request.meth, 200, snapshot.val)
          } else if request.meth == @http.Get &&
            request.path ==
            "/api/company/internal/plan/tasks/PT-revised/flow-approvals/approve-r2" {
            if approval_effects.val == 0 {
              send_json(conn, request.meth, 404, {
                "error": "approval not persisted",
              })
            } else {
              send_json(conn, request.meth, 200, approval)
            }
          } else if request.meth == @http.Get &&
            request.path.has_prefix(
              "/api/company/internal/plan/tasks/PT-revised/flow-report-receipts/",
            ) {
            match report.val {
              Some(saved) if request.path.has_suffix(
                  "/" + native_text(saved, "idempotency_key"),
                ) => send_json(conn, request.meth, 200, { "command": saved })
              _ =>
                send_json(conn, request.meth, 404, {
                  "error": "report not persisted",
                })
            }
          } else if request.meth == @http.Post &&
            request.path == path + "/flow-bindings" {
            approval_requests.val += 1
            let body = @json.parse(
              @encoding/utf8.decode(read_body(reader, request)),
            )
            assert_eq(native_field(body, "binding"), binding)
            assert_eq(header(request, "Idempotency-Key"), "approve-r2")
            @fs.write_file(
              parent + "/wire-approval-body.json",
              body.stringify(),
              create_mode=@fs.CreateOrTruncate,
            )
            if approval_effects.val == 0 {
              approval_effects.val = 1
              send_json(conn, request.meth, 503, {
                "error": "synthetic acknowledgement lost after approval persistence",
              })
            } else {
              send_json(conn, request.meth, 200, approval)
            }
          } else if request.meth == @http.Post &&
            request.path == path + "/report" {
            report_requests.val += 1
            let body = @json.parse(
              @encoding/utf8.decode(read_body(reader, request)),
            )
            let key = header(request, "Idempotency-Key")
            let command = flow_wire_report(body, key)
            @fs.write_file(
              parent + "/wire-report-body.json",
              body.stringify(),
              create_mode=@fs.CreateOrTruncate,
            )
            if report.val is Some(saved) {
              assert_eq(command, saved)
              send_json(conn, request.meth, 200, {
                "command": saved,
                "idempotent_replay": true,
              })
            } else {
              report.val = Some(command)
              report_effects.val += 1
              send_json(conn, request.meth, 503, {
                "error": "synthetic acknowledgement lost after report persistence",
              })
            }
          } else {
            send_json(conn, request.meth, 404, {
              "error": "fixture route missing",
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
            parent,
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
        "X-Moonproj-Actor": "forged-browser-actor",
      }
      let approve_body : Json = {
        "request_ref": request_ref,
        "approval_key": "approve-r2",
        "authority": native_field(
          native_field(native_field(approval, "command"), "request"),
          "authority",
        ),
      }
      let execute_body : Json = {
        "request_ref": request_ref,
        "result_ref": result_ref,
      }
      let return_body : Json = { "request_ref": request_ref }
      let (unauth, _) = @http.post(
        gateway_uri + path + "/flow-bindings",
        approve_body.stringify(),
      )
      assert_eq(unauth.code, 401)
      assert_eq(approval_requests.val, 0)
      let (captured, capture_data) = @http.get(
        gateway_uri + path + "/flow-snapshot",
        headers~,
      )
      assert_eq(captured.code, 200)
      assert_eq(@json.parse(capture_data.text()), snapshot.val)
      let (unapproved, _) = @http.post(
        gateway_uri + path + "/flow-execute",
        execute_body.stringify(),
        headers~,
      )
      assert_eq(unapproved.code, 409)
      // A structurally valid local file is still not authenticated approval.
      ignore(
        @moonflow_adapter.record_company_task_approval(
          workspace, request_ref, approval,
        ),
      )
      let (forged_local, _) = @http.post(
        gateway_uri + path + "/flow-execute",
        execute_body.stringify(),
        headers~,
      )
      assert_eq(forged_local.code, 404)
      assert_false(@fs.exists(workspace + "/" + result_ref))
      let (lost_approval, _) = @http.post(
        gateway_uri + path + "/flow-bindings",
        approve_body.stringify(),
        headers~,
      )
      assert_eq(lost_approval.code, 503)
      let (approved, approved_data) = @http.post(
        gateway_uri + path + "/flow-bindings",
        approve_body.stringify(),
        headers~,
      )
      assert_eq(approved.code, 200, msg=approved_data.text())
      assert_eq(approval_effects.val, 1)
      let (executed, execution_data) = @http.post(
        gateway_uri + path + "/flow-execute",
        execute_body.stringify(),
        headers~,
      )
      assert_eq(executed.code, 200, msg=execution_data.text())
      let result_before = @fs.read_file(workspace + "/" + result_ref).text()
      let (retry, retry_data) = @http.post(
        gateway_uri + path + "/flow-execute",
        execute_body.stringify(),
        headers~,
      )
      assert_eq(retry.code, 200)
      assert_eq(retry_data.text(), execution_data.text())
      let forged_envelope = @moonflow_adapter.prepare_company_task_report(
        workspace,
        request_ref,
        result_ref,
        "forged-report",
        "2026-10-08",
        "Unsubmitted cached report",
        [],
      )
      let forged_command = flow_wire_report(
        native_field(forged_envelope, "report_body"),
        native_text(forged_envelope, "idempotency_key"),
      )
      let forged_cache = @moonflow_adapter.record_company_task_report_response(
        workspace,
        request_ref,
        "forged-report",
        { "command": forged_command },
      )
      assert_eq(native_text(forged_cache, "state"), "reported_local_cache")
      for action in ["status", "return"] {
        let (rejected_cache, cache_data) = @http.post(
          gateway_uri + path + "/flow-reports/forged-report/" + action,
          return_body.stringify(),
          headers~,
        )
        assert_eq(rejected_cache.code, 409)
        assert_eq(
          native_text(@json.parse(cache_data.text()), "state"),
          "unverified_receipt",
        )
      }
      assert_eq(report_requests.val, 0)
      let envelope = @moonflow_adapter.prepare_company_task_report(
        workspace, request_ref, result_ref, "plan-output", "2026-10-08", "Revised plan ready for review",
        review_evidence,
      )
      let (lost_report, _) = @http.post(
        gateway_uri + path + "/flow-reports/plan-output/return",
        return_body.stringify(),
        headers~,
      )
      assert_eq(lost_report.code, 503)
      let (pending, pending_data) = @http.post(
        gateway_uri + path + "/flow-reports/plan-output/status",
        return_body.stringify(),
        headers~,
      )
      assert_eq(pending.code, 200)
      assert_eq(
        native_text(@json.parse(pending_data.text()), "state"),
        "pending_report",
      )
      let (settled, settled_data) = @http.post(
        gateway_uri + path + "/flow-reports/plan-output/return",
        return_body.stringify(),
        headers~,
      )
      assert_eq(settled.code, 200, msg=settled_data.text())
      let status = @json.parse(settled_data.text())
      assert_eq(native_text(status, "state"), "reported")
      assert_eq(report_effects.val, 1)
      let (again, again_data) = @http.post(
        gateway_uri + path + "/flow-reports/plan-output/return",
        return_body.stringify(),
        headers~,
      )
      assert_eq(again.code, 200)
      assert_eq(again_data.text(), settled_data.text())
      assert_eq(report_requests.val, 2)
      assert_eq(
        @fs.read_file(workspace + "/" + result_ref).text(),
        result_before,
      )
      let changed = match snapshot.val {
        Object(fields) => fields.copy()
        _ => Map::new()
      }
      changed["source_revision"] = Json::number(3)
      snapshot.val = Json::object(changed)
      let (stale, _) = @http.post(
        gateway_uri + path + "/flow-execute",
        execute_body.stringify(),
        headers~,
      )
      assert_eq(stale.code, 409)
      @fs.write_file(
        parent + "/wire-report-envelope.json",
        envelope.stringify(),
        create_mode=@fs.CreateOrTruncate,
      )
      @fs.write_file(
        parent + "/wire-report-command.json",
        report.val.unwrap().stringify(),
        create_mode=@fs.CreateOrTruncate,
      )
      @fs.write_file(
        parent + "/wire-receipt.json",
        (
          {
            "gateway": "actual production handler over authenticated loopback HTTP",
            "service": "synthetic deterministic company store; not PostgreSQL",
            "signing_identity": "synthetic fixture only",
            "approval_requests": approval_requests.val,
            "approval_effects": approval_effects.val,
            "report_requests": report_requests.val,
            "report_effects": report_effects.val,
            "auth_rejection": 401,
            "unpersisted_local_approval_rejection": 404,
            "forged_local_report_receipt_rejection": 409,
            "stale_rejection": 409,
            "saved_report_state": native_text(status, "state"),
            "adapter_result_unchanged": true,
            "flow_review_evidence_returned": review_evidence.contains(
              "flow-review.json",
            ),
            "task_acceptance": "unchanged",
            "customer_acceptance": "not_recorded_here",
            "cash": "not_recorded_here",
          } : Json).stringify(indent=2),
        create_mode=@fs.CreateOrTruncate,
      )
      group.return_immediately(())
    })
  })
}
