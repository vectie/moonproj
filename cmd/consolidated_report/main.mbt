///|
pub(all) suberror ConsolidatedReportError {
  InvalidInput
  Io(@fs.IOError)
  Reporting(@reporting.ReportingError)
  Reconciliation(@reconciliation.ReconciliationError)
  Money(@finance.MoneyError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise ConsolidatedReportError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ConsolidatedReportError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise ConsolidatedReportError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise ConsolidatedReportError {
  match value {
    Object(value) => value
    _ => raise ConsolidatedReportError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise ConsolidatedReportError {
  match obj.get(key) {
    Some(value) => value
    None => raise ConsolidatedReportError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise ConsolidatedReportError {
  match required(obj, key) {
    String(value) => value
    _ => raise ConsolidatedReportError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise ConsolidatedReportError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise ConsolidatedReportError::InvalidInput
  }
}

///|
fn required_int(
  obj : Map[String, Json],
  key : String,
) -> Int raise ConsolidatedReportError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int()
    _ => raise ConsolidatedReportError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise ConsolidatedReportError {
  match required(obj, key) {
    Array(value) => value
    _ => raise ConsolidatedReportError::InvalidInput
  }
}

///|
fn strings_json(values : Array[String]) -> Json {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(Json::string(value))
  }
  Json::array(encoded)
}

///|
fn grant(principal_id : String, scope : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "consolidated-report/migration",
    principal_id,
    actor_id: "migration",
    capability: "report:consolidate",
    scope,
    max_amount_minor: 0,
    active: true,
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise ConsolidatedReportError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.company.consolidated-report-plan.v1" {
    raise ConsolidatedReportError::InvalidInput
  }
  let report_id = required_string(root, "report_id")
  let period_id = required_string(root, "period_id")
  let principal_id = required_string(root, "principal_id")
  let scope = required_string(root, "scope")
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_versions : Array[String] = []
  for value in required_array(root, "mapping_versions") {
    match value {
      String(value) => mapping_versions.push(value)
      _ => raise ConsolidatedReportError::InvalidInput
    }
  }
  let section_values = required_array(root, "sections")
  let reports : Array[@reconciliation.ReconciliationReport] = []
  let sections : Array[Json] = []
  for section_value in section_values {
    let section = object(section_value)
    let section_id = required_string(section, "section_id")
    let currency = required_string(section, "currency")
    let expected_minor = required_int64(section, "expected_minor")
    let actual_minor = required_int64(section, "actual_minor")
    let expected = @finance.Money::new(minor=expected_minor, currency~) catch {
      error => raise ConsolidatedReportError::Money(error)
    }
    let actual = @finance.Money::new(minor=actual_minor, currency~) catch {
      error => raise ConsolidatedReportError::Money(error)
    }
    let report = @reconciliation.ReconciliationReport::new(scope=section_id, lines=[
      { reference_id: section_id, expected, actual },
    ]) catch {
      error => raise ConsolidatedReportError::Reconciliation(error)
    }
    reports.push(report)
    sections.push(
      Json::object({
        "section_id": Json::string(section_id),
        "expected_minor": Json::number(
          expected_minor.to_double(),
          repr=expected_minor.to_string(),
        ),
        "actual_minor": Json::number(
          actual_minor.to_double(),
          repr=actual_minor.to_string(),
        ),
        "currency": Json::string(currency),
      }),
    )
  }
  let report = @reporting.ConsolidatedReport::new(
    report_id~,
    period_id~,
    principal_id~,
    scope~,
    source_snapshot_id~,
    mapping_versions~,
    reports~,
    accounting_link_count=required_int(root, "accounting_link_count"),
    reconciled_link_count=required_int(root, "reconciled_link_count"),
    actor_id="migration",
    grant=grant(principal_id, scope),
  ) catch {
    _ => raise ConsolidatedReportError::InvalidInput
  }
  let candidate = Json::object({
    "report_id": Json::string(report.report_id),
    "period_id": Json::string(report.period_id),
    "principal_id": Json::string(report.principal_id),
    "scope": Json::string(report.scope),
    "source_snapshot_id": Json::string(report.source_snapshot_id),
    "mapping_versions": strings_json(report.mapping_versions),
    "sections": Json::array(sections),
    "expected_total_minor": Json::number(
      report.expected_total.minor.to_double(),
      repr=report.expected_total.minor.to_string(),
    ),
    "actual_total_minor": Json::number(
      report.actual_total.minor.to_double(),
      repr=report.actual_total.minor.to_string(),
    ),
    "difference_minor": Json::number(
      report.difference_minor.to_double(),
      repr=report.difference_minor.to_string(),
    ),
    "currency": Json::string(report.expected_total.currency),
    "accounting_link_count": Json::number(
      report.accounting_link_count.to_double(),
      repr=report.accounting_link_count.to_string(),
    ),
    "reconciled_link_count": Json::number(
      report.reconciled_link_count.to_double(),
      repr=report.reconciled_link_count.to_string(),
    ),
    "state": Json::string("reconciled"),
    "cash_released": Json::boolean(false),
    "period_posted": Json::boolean(false),
    "tax_filed": Json::boolean(false),
  })
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(required_string(root, "mapping_version")),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("consolidated-report-v1"),
    "accepted_items": Json::array([
      Json::object({
        "source_table": Json::string("company_reconciliation"),
        "source_id": Json::string(report_id),
        "target_type": Json::string("consolidated_report"),
        "target_id": Json::string(report_id),
        "target_candidate": candidate,
      }),
    ]),
    "cash_released": Json::boolean(false),
    "period_posted": Json::boolean(false),
    "tax_filed": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise ConsolidatedReportError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: consolidated_report <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      ConsolidatedReportError::InvalidInput => {
        println("consolidated report failed: invalid input")
        @sys.exit(1)
      }
      ConsolidatedReportError::Io(_) => {
        println("consolidated report failed: filesystem error")
        @sys.exit(1)
      }
      ConsolidatedReportError::Reporting(_) => {
        println("consolidated report failed: reporting validation")
        @sys.exit(1)
      }
      ConsolidatedReportError::Reconciliation(_) => {
        println("consolidated report failed: reconciliation validation")
        @sys.exit(1)
      }
      ConsolidatedReportError::Money(_) => {
        println("consolidated report failed: invalid money")
        @sys.exit(1)
      }
    }
  }
}
