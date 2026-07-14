///|
/// MoonBit inventory of the ERP route-handler surface.
pub(all) suberror RouteInventoryError {
  InvalidInput(String)
  Io(@fs.IOError)
} derive(Debug)

///|
struct Handler {
  file : String
  http_method : String
  path : String
  capability_id : String
}

///|
struct FileReport {
  file : String
  capability_id : String
  handler_count : Int
  middleware_count : Int
}

///|
let capability_ids : Array[String] = [
  "FND-02", "FND-03", "FND-04", "FND-05", "FND-07", "FND-08", "CST-01", "CST-03",
  "CST-04", "EXP-03", "FIN-03", "FIN-08", "FIN-09", "INV-01", "PRJ-02", "PRJ-03",
  "RPT-01", "RPT-02", "RPT-03", "RPT-04", "RPT-06", "RPT-07", "SAL-02", "SAL-03",
  "SRM-01", "SRM-04", "WF-01",
]

///|
fn capability_id(file : String) -> String {
  match file {
    "admin.js" => "FND-08"
    "ai-hub.js" => "RPT-06"
    "ai-stats.js" => "RPT-07"
    "attachment.js" => "FND-05"
    "auth.js" => "FND-02"
    "budget.js" => "CST-03"
    "cashflow.js" => "FIN-08"
    "cbs.js" => "CST-01"
    "cost.js" => "CST-04"
    "dashboard.js" => "RPT-01"
    "export.js" => "RPT-02"
    "fund.js" => "FIN-09"
    "import.js" => "FND-08"
    "investment.js" => "INV-01"
    "invoice.js" => "FIN-03"
    "loan.js" => "EXP-03"
    "marketing.js" => "SAL-02"
    "mdm.js" => "FND-04"
    "notify.js" => "FND-07"
    "plan.js" => "PRJ-02"
    "progress.js" => "PRJ-03"
    "rbac.js" => "FND-03"
    "reports.js" => "RPT-02"
    "sales.js" => "SAL-03"
    "share.js" => "RPT-03"
    "srm.js" => "SRM-01"
    "tender.js" => "SRM-04"
    "warning.js" => "RPT-04"
    "webhook.js" => "FND-07"
    "workflow.js" => "WF-01"
    _ => "RPT-01"
  }
}

///|
fn fail(message : String) -> RouteInventoryError {
  RouteInventoryError::InvalidInput(message)
}

///|
fn basename(path : String) -> String {
  match path.rev_after("/") {
    Some(value) => value.to_owned()
    None => path
  }
}

///|
fn route_from_tail(tail : String) -> String? {
  let trimmed = tail.trim_start().to_owned()
  if !trimmed.has_prefix("(") {
    return None
  }
  let argument = trimmed.sub(start=1).trim_start().to_owned()
  match argument.get_char(0) {
    Some('\'') =>
      match argument.sub(start=1).before("'") {
        Some(value) => Some(value.to_owned())
        None => None
      }
    Some('"') =>
      match argument.sub(start=1).before("\"") {
        Some(value) => Some(value.to_owned())
        None => None
      }
    _ => None
  }
}

///|
fn is_identifier_char(value : Char) -> Bool {
  value.is_ascii_alphabetic() || value.is_ascii_digit() || value == '_'
}

///|
fn handlers_in_line(
  line : String,
  file : String,
  capability : String,
) -> Array[Handler] {
  let methods : Array[String] = ["get", "post", "put", "patch", "delete"]
  let result : Array[Handler] = []
  for verb in methods {
    let marker = "r." + verb
    let mut cursor = 0
    while cursor < line.length() {
      let remaining = line.sub(start=cursor)
      match remaining.find(marker) {
        Some(offset) => {
          let start = cursor + offset
          let boundary_ok = match line.get_char(start - 1) {
            Some(value) => !is_identifier_char(value)
            None => true
          }
          if boundary_ok {
            match
              route_from_tail(
                line.sub(start=start + marker.length()).to_owned(),
              ) {
              Some(path) =>
                result.push(Handler::{
                  file,
                  http_method: verb.to_upper(),
                  path,
                  capability_id: capability,
                })
              None => ()
            }
          }
          cursor = start + marker.length()
        }
        None => cursor = line.length()
      }
    }
  }
  result
}

///|
fn middleware_count(line : String) -> Int {
  let marker = "r.use"
  let mut count = 0
  let mut cursor = 0
  while cursor < line.length() {
    let remaining = line.sub(start=cursor)
    match remaining.find(marker) {
      Some(offset) => {
        let start = cursor + offset
        let boundary_ok = match line.get_char(start - 1) {
          Some(value) => !is_identifier_char(value)
          None => true
        }
        let tail = line.sub(start=start + marker.length()).trim_start()
        if boundary_ok && tail.has_prefix("(") {
          count += 1
        }
        cursor = start + marker.length()
      }
      None => cursor = line.length()
    }
  }
  count
}

///|
fn json_handler(handler : Handler) -> Json {
  Json::object({
    "file": Json::string(handler.file),
    "method": Json::string(handler.http_method),
    "path": Json::string(handler.path),
    "capability_id": Json::string(handler.capability_id),
    "migration_action": Json::string("specify_and_scenario_verify"),
  })
}

///|
fn run(
  routes_dir : String,
  files : Array[String],
) -> Json raise RouteInventoryError {
  if files.length() == 0 {
    raise fail("route directory has no JavaScript files: " + routes_dir)
  }
  let handlers : Array[Handler] = []
  let file_reports : Array[FileReport] = []
  let mut middleware_total = 0
  for path in files {
    let text = @fs.read_file_to_string(path) catch {
      error => raise RouteInventoryError::Io(error)
    }
    let file = basename(path)
    let capability = capability_id(file)
    let mut handler_count = 0
    let mut middleware = 0
    for line_view in text.split("\n") {
      let line = line_view.to_owned()
      let found = handlers_in_line(line, file, capability)
      handler_count += found.length()
      for handler in found {
        handlers.push(handler)
      }
      middleware += middleware_count(line)
    }
    middleware_total += middleware
    file_reports.push(FileReport::{
      file,
      capability_id: capability,
      handler_count,
      middleware_count: middleware,
    })
  }
  if files.length() != 30 || handlers.length() != 338 || middleware_total != 28 {
    raise fail(
      "route inventory counts changed: files=" +
      files.length().to_string() +
      ", handlers=" +
      handlers.length().to_string() +
      ", middleware=" +
      middleware_total.to_string(),
    )
  }
  let capability_counts : Map[String, Int] = Map::Map([])
  for handler in handlers {
    capability_counts.set(
      handler.capability_id,
      capability_counts.get_or_default(handler.capability_id, 0) + 1,
    )
  }
  let handlers_by_capability : Map[String, Json] = Map::Map([])
  for capability in capability_ids {
    match capability_counts.get(capability) {
      Some(count) =>
        handlers_by_capability.set(capability, Json::number(count.to_double()))
      None => ()
    }
  }
  let files_json = file_reports.map(fn(report) {
    Json::object({
      "file": Json::string(report.file),
      "capability_id": Json::string(report.capability_id),
      "handler_count": Json::number(report.handler_count.to_double()),
      "middleware_count": Json::number(report.middleware_count.to_double()),
    })
  })
  Json::object({
    "format": Json::string("moonproj.erp.route-inventory.v1"),
    "routes_dir": Json::string(routes_dir),
    "route_file_count": Json::number(files.length().to_double()),
    "handler_count": Json::number(handlers.length().to_double()),
    "middleware_count": Json::number(middleware_total.to_double()),
    "handlers_by_capability": Json::object(handlers_by_capability),
    "files": Json::array(files_json),
    "handlers": Json::array(handlers.map(json_handler)),
    "state": Json::string("route_surface_inventory_verified"),
    "cutover_authorized": Json::boolean(false),
  })
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 4 {
    println("usage: route_inventory <routes_dir> <output> <route.js>...")
    @sys.exit(2)
  }
  let files : Array[String] = []
  for index in 3..<args.length() {
    files.push(args[index])
  }
  let report = run(args[1], files) catch {
    error => {
      println("ERP route inventory failed: \{to_repr(error)}")
      @sys.exit(1)
      Json::null()
    }
  }
  let output = report.stringify(indent=2) + "\n"
  @fs.write_string_to_file(args[2], output) catch {
    _ => {
      println("ERP route inventory failed: filesystem error")
      @sys.exit(1)
    }
  }
  println(output)
}
