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
    ["health", .. rest] =>
      @moonflow_adapter.publish_health(
        option(rest, "--workspace"),
        option(rest, "--checked-at"),
        option(rest, "--valid-until"),
        option(rest, "--attestation"),
      )
    _ =>
      fail(
        "usage: moonflow_project_plan_adapter <capability|execute|reconcile|health> [options]",
      )
  }
  println(output.stringify(indent=2))
}
