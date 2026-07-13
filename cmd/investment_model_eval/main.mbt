///|
pub(all) suberror ModelEvaluationPromotionError {
  InvalidInput
  Io(@fs.IOError)
  Model(@model.ModelError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise ModelEvaluationPromotionError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise ModelEvaluationPromotionError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise ModelEvaluationPromotionError::InvalidInput
  }
}

///|
fn object(
  value : Json,
) -> Map[String, Json] raise ModelEvaluationPromotionError {
  match value {
    Object(value) => value
    _ => raise ModelEvaluationPromotionError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise ModelEvaluationPromotionError {
  match obj.get(key) {
    Some(value) => value
    None => raise ModelEvaluationPromotionError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise ModelEvaluationPromotionError {
  match required(obj, key) {
    String(value) => value
    _ => raise ModelEvaluationPromotionError::InvalidInput
  }
}

///|
fn optional_string(
  obj : Map[String, Json],
  key : String,
) -> String? raise ModelEvaluationPromotionError {
  match required(obj, key) {
    Null => None
    String(value) => Some(value)
    _ => raise ModelEvaluationPromotionError::InvalidInput
  }
}

///|
fn required_int(
  obj : Map[String, Json],
  key : String,
) -> Int raise ModelEvaluationPromotionError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int()
    _ => raise ModelEvaluationPromotionError::InvalidInput
  }
}

///|
fn required_bool(
  obj : Map[String, Json],
  key : String,
) -> Bool raise ModelEvaluationPromotionError {
  match required(obj, key) {
    True => true
    False => false
    _ => raise ModelEvaluationPromotionError::InvalidInput
  }
}

///|
fn required_array(
  obj : Map[String, Json],
  key : String,
) -> Array[Json] raise ModelEvaluationPromotionError {
  match required(obj, key) {
    Array(value) => value
    _ => raise ModelEvaluationPromotionError::InvalidInput
  }
}

///|
fn grant(
  grant_id : String,
  principal_id : String,
  capability : String,
  scope : String,
) -> @foundation.AuthorityGrant {
  {
    grant_id,
    principal_id,
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: 0L,
    active: true,
  }
}

///|
fn string_array(values : Array[String]) -> Json {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(Json::string(value))
  }
  Json::array(encoded)
}

///|
fn kind_name(kind : @model.ModelValueKind) -> String {
  match kind {
    @model.ModelValueKind::Numeric => "numeric"
    @model.ModelValueKind::DateSerial => "date_serial"
    @model.ModelValueKind::Unparsed => "unparsed"
    @model.ModelValueKind::Missing => "missing"
  }
}

///|
fn values_json(values : Array[@model.ModelEvaluatedValue]) -> Json {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(
      Json::object({
        "index_id": Json::string(value.index_id),
        "full_code": Json::string(value.full_code),
        "unit": match value.unit {
          Some(unit) => Json::string(unit)
          None => Json::null()
        },
        "raw_value": match value.raw_value {
          Some(raw) => Json::string(raw)
          None => Json::null()
        },
        "numeric_value": match value.numeric_value {
          Some(number) => Json::number(number, repr=number.to_string())
          None => Json::null()
        },
        "kind": Json::string(kind_name(value.kind)),
      }),
    )
  }
  Json::array(encoded)
}

///|
fn metrics_json(metrics : Array[@model.ModelDerivedMetric]) -> Json {
  let encoded : Array[Json] = []
  for metric in metrics {
    encoded.push(
      Json::object({
        "metric_code": Json::string(metric.metric_code),
        "numerator_code": Json::string(metric.numerator_code),
        "denominator_code": Json::string(metric.denominator_code),
        "value_bps": Json::number(
          metric.value_bps.to_double(),
          repr=metric.value_bps.to_string(),
        ),
      }),
    )
  }
  Json::array(encoded)
}

///|
fn run(
  input_path : String,
  output_path : String,
) -> Unit raise ModelEvaluationPromotionError {
  let root = object(read_json(input_path))
  if required_string(root, "format") != "moonproj.erp.domain-promotion.v1" {
    raise ModelEvaluationPromotionError::InvalidInput
  }
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let mut found = false
  let mut model : @model.InvestmentModel? = None
  let mut source_id = ""
  for item_value in required_array(root, "accepted_items") {
    let item = object(item_value)
    if required_string(item, "target_type") != "investment_model" {
      continue
    }
    if found {
      raise ModelEvaluationPromotionError::InvalidInput
    }
    found = true
    source_id = required_string(item, "source_id")
    let candidate = object(required(item, "target_candidate"))
    let version = object(required(candidate, "version"))
    let principal_id = required_string(candidate, "principal_id")
    let authority_scope = required_string(candidate, "authority_scope")
    let version_id = required_string(version, "version_guid")
    let project_id = required_string(version, "proj_guid")
    let version_name = required_string(version, "version_name")
    let version_no = required_int(version, "version_no")
    let current = required_bool(version, "current")
    let created_by = required_string(version, "created_by")
    let created_at = required_string(version, "created_at")
    let remark = optional_string(version, "remark")
    let version_model = @model.ModelVersion::new(
      version_id~,
      project_id~,
      principal_id~,
      name=version_name,
      version_no~,
      current~,
      created_by~,
      created_at~,
      remark~,
      actor_id="migration",
      grant=grant(
        "investment-model-evaluation/version/" + version_id,
        principal_id,
        "investment:model:version:create",
        authority_scope,
      ),
    ) catch {
      error => raise ModelEvaluationPromotionError::Model(error)
    }
    let mut next_model = @model.InvestmentModel::new(version_model)
    for index_value in required_array(candidate, "indexes") {
      let index = object(index_value)
      let index_id = required_string(index, "index_guid")
      let index_version_id = required_string(index, "version_guid")
      let index_project_id = required_string(index, "proj_guid")
      let dimension = required_string(index, "dimension")
      let full_code = required_string(index, "full_code")
      let name = required_string(index, "index_name")
      let parent_code = optional_string(index, "parent_code")
      let unit = optional_string(index, "unit")
      let value_repr = optional_string(index, "value_repr")
      let index_remark = optional_string(index, "remark")
      let sort_order = required_int(index, "sort_order")
      let index_model = @model.ModelIndex::new(
        index_id~,
        version_id=index_version_id,
        project_id=index_project_id,
        dimension~,
        full_code~,
        name~,
        parent_code~,
        unit~,
        value_repr~,
        remark=index_remark,
        sort_order~,
      ) catch {
        error => raise ModelEvaluationPromotionError::Model(error)
      }
      next_model = next_model.add_index(
        index_model,
        actor_id="migration",
        grant=grant(
          "investment-model-evaluation/index/" + index_model.index_id,
          principal_id,
          "investment:model:index:add",
          authority_scope,
        ),
      ) catch {
        error => raise ModelEvaluationPromotionError::Model(error)
      }
    }
    model = Some(next_model)
  }
  let model = match model {
    Some(model) => model
    None => raise ModelEvaluationPromotionError::InvalidInput
  }
  let evaluation_mapping_version = mapping_version + ":evaluation-v1"
  let evaluation = model.evaluate(
    source_snapshot_id~,
    mapping_version=evaluation_mapping_version,
  ) catch {
    error => raise ModelEvaluationPromotionError::Model(error)
  }
  let candidate = Json::object({
    "version_id": Json::string(evaluation.version_id),
    "project_id": Json::string(evaluation.project_id),
    "source_snapshot_id": Json::string(evaluation.source_snapshot_id),
    "mapping_version": Json::string(evaluation.mapping_version),
    "values": values_json(evaluation.values),
    "derived_metrics": metrics_json(evaluation.derived_metrics),
    "parent_check_count": Json::number(
      evaluation.parent_check_count.to_double(),
      repr=evaluation.parent_check_count.to_string(),
    ),
    "mismatch_count": Json::number(
      evaluation.mismatch_count.to_double(),
      repr=evaluation.mismatch_count.to_string(),
    ),
    "issues": string_array(evaluation.issues),
    "validated": Json::boolean(evaluation.validated),
    "analytics_only": Json::boolean(true),
    "investment_execution_authorized": Json::boolean(false),
    "position_mutated": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
  })
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(evaluation_mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("investment-model-evaluation-v1"),
    "accepted_items": Json::array([
      Json::object({
        "source_table": Json::string("tzsy_version"),
        "source_id": Json::string(source_id),
        "target_type": Json::string("investment_model_evaluation"),
        "target_id": Json::string(evaluation.version_id),
        "target_candidate": candidate,
      }),
    ]),
    "analytics_only": Json::boolean(true),
    "investment_execution_authorized": Json::boolean(false),
    "position_mutated": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise ModelEvaluationPromotionError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println(
      "usage: investment_model_eval <investment-promotion.json> <receipt.json>",
    )
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      ModelEvaluationPromotionError::InvalidInput => {
        println("investment model evaluation failed: invalid input")
        @sys.exit(1)
      }
      ModelEvaluationPromotionError::Io(_) => {
        println("investment model evaluation failed: filesystem error")
        @sys.exit(1)
      }
      ModelEvaluationPromotionError::Model(_) => {
        println("investment model evaluation failed: model validation")
        @sys.exit(1)
      }
    }
  }
}
