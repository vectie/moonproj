///|
pub(all) suberror WarningPromotionError {
  InvalidInput
  Io(@fs.IOError)
  Warning(@warning_domain.WarningError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise WarningPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise WarningPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise WarningPromotionError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise WarningPromotionError {
  match value {
    Object(value) => value
    _ => raise WarningPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise WarningPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise WarningPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise WarningPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise WarningPromotionError::InvalidInput
  }
}

///|
fn severity(
  value : String,
) -> @warning_domain.WarningSeverity raise WarningPromotionError {
  match value {
    "info" => @warning_domain.WarningSeverity::Info
    "warning" => @warning_domain.WarningSeverity::Warning
    "critical" => @warning_domain.WarningSeverity::Critical
    _ => raise WarningPromotionError::InvalidInput
  }
}

///|
fn grant(principal_id : String, scope : String) -> @foundation.AuthorityGrant {
  {
    grant_id: "warning-promotion/migration",
    principal_id,
    actor_id: "migration",
    capability: "warning:create",
    scope,
    max_amount_minor: 0L,
    active: true,
  }
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise WarningPromotionError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.company.warning-plan.v1" {
    raise WarningPromotionError::InvalidInput
  }
  let warning_id = required_string(root, "warning_id")
  let principal_id = required_string(root, "principal_id")
  let scope = required_string(root, "scope")
  let rule_code = required_string(root, "rule_code")
  let target_type = required_string(root, "target_type")
  let target_id = required_string(root, "target_id")
  let message = required_string(root, "message")
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let evidence_id = required_string(root, "evidence_id")
  let source_table = match root.get("source_table") {
    Some(String(value)) => value
    _ => "sys_warning"
  }
  let source_ids = match root.get("source_ids") {
    Some(value) => value
    None => Json::array([])
  }
  let overrun_minor = match root.get("overrun_minor") {
    Some(Number(value, ..)) =>
      Json::number(value, repr=value.to_int().to_int64().to_string())
    _ => Json::number(0.0, repr="0")
  }
  let scan_policy = match root.get("scan_policy") {
    Some(String(value)) => value
    _ => "legacy-warning-plan"
  }
  let finding_severity = severity(required_string(root, "severity"))
  let finding = @warning_domain.WarningFinding::new(
    warning_id~,
    principal_id~,
    scope~,
    rule_code~,
    target_type~,
    target_id~,
    message~,
    severity=finding_severity,
    actor_id="migration",
    grant=grant(principal_id, scope),
  ) catch {
    error => raise WarningPromotionError::Warning(error)
  }
  let evidence = finding.bind_evidence(
    source_snapshot_id~,
    mapping_version~,
    evidence_id~,
  ) catch {
    error => raise WarningPromotionError::Warning(error)
  }
  let candidate = Json::object({
    "warning_id": Json::string(finding.warning_id),
    "principal_id": Json::string(finding.principal_id),
    "scope": Json::string(finding.scope),
    "rule_code": Json::string(finding.rule_code),
    "target_type": Json::string(finding.target_type),
    "target_id": Json::string(finding.target_id),
    "message": Json::string(finding.message),
    "severity": Json::string(
      match finding.severity {
        @warning_domain.WarningSeverity::Info => "info"
        @warning_domain.WarningSeverity::Warning => "warning"
        @warning_domain.WarningSeverity::Critical => "critical"
      },
    ),
    "state": Json::string("open"),
    "source_snapshot_id": Json::string(evidence.source_snapshot_id),
    "mapping_version": Json::string(evidence.mapping_version),
    "evidence_id": Json::string(evidence.evidence_id),
    "notification_delivered": Json::boolean(false),
    "workflow_mutated": Json::boolean(false),
    "cash_released": Json::boolean(false),
    "source_table": Json::string(source_table),
    "source_ids": source_ids,
    "overrun_minor": overrun_minor,
    "scan_policy": Json::string(scan_policy),
  })
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("warning-finding-v1"),
    "accepted_items": Json::array([
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(warning_id),
        "target_type": Json::string("warning_finding"),
        "target_id": Json::string(warning_id),
        "target_candidate": candidate,
      }),
    ]),
    "notification_delivered": Json::boolean(false),
    "workflow_mutated": Json::boolean(false),
    "cash_released": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise WarningPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: warning <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      WarningPromotionError::InvalidInput => {
        println("warning promotion failed: invalid input")
        @sys.exit(1)
      }
      WarningPromotionError::Io(_) => {
        println("warning promotion failed: filesystem error")
        @sys.exit(1)
      }
      WarningPromotionError::Warning(_) => {
        println("warning promotion failed: warning validation")
        @sys.exit(1)
      }
    }
  }
}
