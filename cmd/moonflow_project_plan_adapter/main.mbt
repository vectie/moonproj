///|
fn option(args : ArrayView[String], name : String) -> String raise {
  for index in 0..<(args.length() - 1) {
    if args[index] == name {
      return args[index + 1]
    }
  }
  fail("MoonProj Flow adapter requires \{name}")
}

///|
fn repeated_option(args : ArrayView[String], name : String) -> Array[String] {
  let values : Array[String] = []
  for index in 0..<(args.length() - 1) {
    if args[index] == name {
      values.push(args[index + 1])
    }
  }
  values
}

///|
async fn main {
  let args = @env.args()[1:].to_owned()
  let output = match args {
    [] | ["capability"] => @moonflow_adapter.capability_json()
    ["execute", .. rest] =>
      @moonflow_adapter.execute(
        option(rest, "--workspace"),
        option(rest, "--request"),
        option(rest, "--result"),
      )
    ["reconcile", .. rest] =>
      @moonflow_adapter.reconcile(
        option(rest, "--workspace"),
        option(rest, "--request"),
        option(rest, "--result"),
      )
    ["bind-company-task", .. rest] =>
      @moonflow_adapter.bind_company_task(
        option(rest, "--workspace"),
        option(rest, "--request"),
      )
    ["prepare-company-report", .. rest] =>
      @moonflow_adapter.prepare_company_task_report(
        option(rest, "--workspace"),
        option(rest, "--request"),
        option(rest, "--result"),
        option(rest, "--report-key"),
        option(rest, "--date"),
        option(rest, "--summary"),
        repeated_option(rest, "--evidence"),
      )
    ["company-report-status", .. rest] =>
      @moonflow_adapter.company_task_report_status(
        option(rest, "--workspace"),
        option(rest, "--request"),
        option(rest, "--report-key"),
      )
    ["record-company-report", .. rest] =>
      @moonflow_adapter.record_company_task_report_receipt(
        option(rest, "--workspace"),
        option(rest, "--request"),
        option(rest, "--report-key"),
        option(rest, "--response"),
      )
    ["health", .. rest] =>
      @moonflow_adapter.publish_health(
        option(rest, "--workspace"),
        option(rest, "--checked-at"),
        option(rest, "--valid-until"),
        option(rest, "--attestation"),
      )
    _ =>
      fail(
        "usage: moonflow_project_plan_adapter <capability|execute|reconcile|health|bind-company-task|prepare-company-report|company-report-status|record-company-report> [options]",
      )
  }
  println(output.stringify(indent=2))
}
