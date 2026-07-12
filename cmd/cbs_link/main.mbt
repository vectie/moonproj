///|
pub(all) suberror CbsLinkError {
  InvalidInput
  Quarantined(String)
  Io(@fs.IOError)
  Cbs(@cbs.CbsError)
  Money(@finance.MoneyError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise CbsLinkError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise CbsLinkError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise CbsLinkError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise CbsLinkError {
  match value {
    Object(value) => value
    _ => raise CbsLinkError::InvalidInput
  }
}

///|
fn required(obj : Map[String, Json], key : String) -> Json raise CbsLinkError {
  match obj.get(key) {
    Some(value) => value
    None => raise CbsLinkError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise CbsLinkError {
  match required(obj, key) {
    String(value) => value
    _ => raise CbsLinkError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise CbsLinkError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise CbsLinkError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise CbsLinkError {
  match required(obj, key) {
    Array(value) => value
    _ => raise CbsLinkError::InvalidInput
  }
}

///|
fn grant(
  grant_id : String,
  principal_id : String,
  actor_id : String,
  capability : String,
  scope : String,
  amount_minor : Int64,
) -> @foundation.AuthorityGrant {
  {
    grant_id,
    principal_id,
    actor_id,
    capability,
    scope,
    max_amount_minor: amount_minor,
    active: true,
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
fn run(plan_path : String, output_path : String) -> Unit raise CbsLinkError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") != "moonproj.erp.cbs-cost-link-plan.v1" {
    raise CbsLinkError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let items = required_array(root, "items")
  let actor_id = "migration"
  let accepted : Array[Json] = []
  let link_ids : Array[String] = []
  let version_ids : Array[String] = []
  for item_value in items {
    let item = object(item_value)
    let source_table = required_string(item, "source_table")
    let source_id = required_string(item, "source_id")
    if required_string(item, "target_type") != "cbs_cost_link" {
      raise CbsLinkError::InvalidInput
    }
    if required_string(item, "disposition") != "ready_for_domain_import" {
      raise CbsLinkError::Quarantined(source_table + ":" + source_id)
    }
    let candidate = object(required(item, "target_candidate"))
    let version = object(required(candidate, "cbs_version"))
    let version_id = required_string(version, "version_id")
    let project_scope = required_string(version, "project_scope")
    let principal_id = required_string(version, "principal_id")
    if required_string(candidate, "version_id") != version_id ||
      required_string(candidate, "project_scope") != project_scope ||
      required_string(candidate, "principal_id") != principal_id {
      raise CbsLinkError::InvalidInput
    }
    let create_grant = grant(
      "cbs-link/" + source_id + "/create",
      principal_id,
      actor_id,
      "cbs:create",
      project_scope,
      0L,
    )
    let mut cbs_version = @cbs.CbsVersion::new(
      version_id~,
      project_scope~,
      actor_id~,
      grant=create_grant,
    ) catch {
      error => raise CbsLinkError::Cbs(error)
    }
    for subject_value in required_array(version, "subjects") {
      let subject = object(subject_value)
      let target_minor = required_int64(subject, "target_minor")
      let subject_model : @cbs.CostSubject = {
        subject_id: required_string(subject, "subject_id"),
        code: required_string(subject, "code"),
        name: required_string(subject, "name"),
        parent_code: required_string(subject, "parent_code"),
        target_minor,
      }
      cbs_version = cbs_version.add_subject(
        subject=subject_model,
        actor_id~,
        grant=grant(
          "cbs-link/" + source_id + "/subject/" + subject_model.code,
          principal_id,
          actor_id,
          "cbs:edit",
          project_scope,
          target_minor,
        ),
      ) catch {
        error => raise CbsLinkError::Cbs(error)
      }
    }
    cbs_version = cbs_version.activate(
      actor_id~,
      grant=grant(
        "cbs-link/" + source_id + "/activate",
        principal_id,
        actor_id,
        "cbs:activate",
        project_scope,
        0L,
      ),
    ) catch {
      error => raise CbsLinkError::Cbs(error)
    }
    let amount = @finance.Money::new(
      minor=required_int64(candidate, "amount_minor"),
      currency=required_string(candidate, "currency"),
    ) catch {
      _ => raise CbsLinkError::InvalidInput
    }
    let link_id = required_string(candidate, "link_id")
    let link = cbs_version.link_cost(
      link_id~,
      source_id~,
      subject_code=required_string(candidate, "subject_code"),
      amount~,
      actor_id~,
      grant=grant(
        "cbs-link/" + source_id + "/link",
        principal_id,
        actor_id,
        "cbs:cost:link",
        project_scope,
        amount.minor,
      ),
    ) catch {
      _ => raise CbsLinkError::InvalidInput
    }
    accepted.push(
      Json::object({
        "source_table": Json::string(source_table),
        "source_id": Json::string(source_id),
        "target_type": Json::string("cbs_cost_link"),
        "target_id": Json::string(link.link_id),
        "target_candidate": candidate,
      }),
    )
    link_ids.push(link.link_id)
    version_ids.push(link.version_id)
  }
  let report = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("cbs-cost-links-v1"),
    "accepted_items": Json::array(accepted),
    "cbs_cost_link_ids": strings_json(link_ids),
    "cbs_version_ids": strings_json(version_ids),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, report) catch {
    error => raise CbsLinkError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: cbs_link <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      CbsLinkError::Quarantined(source) => {
        println("CBS cost-link refused quarantined item: " + source)
        @sys.exit(1)
      }
      CbsLinkError::InvalidInput => {
        println("CBS cost-link failed: invalid input")
        @sys.exit(1)
      }
      CbsLinkError::Io(_) => {
        println("CBS cost-link failed: filesystem error")
        @sys.exit(1)
      }
      CbsLinkError::Cbs(_) => {
        println("CBS cost-link failed: \\{to_repr(error)}")
        @sys.exit(1)
      }
      CbsLinkError::Money(_) => {
        println("CBS cost-link failed: invalid money")
        @sys.exit(1)
      }
    }
  }
}
