///|
pub(all) suberror InvestmentBenchmarkError {
  InvalidInput
  Io(@fs.IOError)
  Portfolio(@portfolio.PortfolioError)
} derive(Debug)

///|
fn read_json(path : String) -> Json raise InvestmentBenchmarkError {
  let content = @fs.read_file_to_string(path) catch {
    error => raise InvestmentBenchmarkError::Io(error)
  }
  @json.parse(content) catch {
    _ => raise InvestmentBenchmarkError::InvalidInput
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise InvestmentBenchmarkError {
  match value {
    Object(value) => value
    _ => raise InvestmentBenchmarkError::InvalidInput
  }
}

///|
fn required(
  obj : Map[String, Json],
  key : String,
) -> Json raise InvestmentBenchmarkError {
  match obj.get(key) {
    Some(value) => value
    None => raise InvestmentBenchmarkError::InvalidInput
  }
}

///|
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> String raise InvestmentBenchmarkError {
  match required(obj, key) {
    String(value) => value
    _ => raise InvestmentBenchmarkError::InvalidInput
  }
}

///|
fn required_int64(
  obj : Map[String, Json],
  key : String,
) -> Int64 raise InvestmentBenchmarkError {
  match required(obj, key) {
    Number(value, ..) if value == value.trunc() => value.to_int().to_int64()
    _ => raise InvestmentBenchmarkError::InvalidInput
  }
}

///|
fn integer(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn run(
  plan_path : String,
  output_path : String,
) -> Unit raise InvestmentBenchmarkError {
  let root = object(read_json(plan_path))
  if required_string(root, "format") !=
    "moonproj.company.investment-benchmark-reconciliation-plan.v1" {
    raise InvestmentBenchmarkError::InvalidInput
  }
  let portfolio_id = required_string(root, "portfolio_id")
  let period_id = required_string(root, "period_id")
  let benchmark_id = required_string(root, "benchmark_id")
  let source_snapshot_id = required_string(root, "source_snapshot_id")
  let mapping_version = required_string(root, "mapping_version")
  let observation_id = required_string(root, "observation_id")
  let evidence_id = required_string(root, "evidence_id")
  let portfolio_return_bps = required_int64(root, "portfolio_return_bps")
  let benchmark_return_bps = required_int64(root, "benchmark_return_bps")
  let observed_return_bps = required_int64(root, "observed_return_bps")
  let tolerance_bps = required_int64(root, "tolerance_bps")
  let comparison = @portfolio.BenchmarkComparison::new(
    portfolio_id~,
    period_id~,
    benchmark_id~,
    portfolio_return_bps~,
    benchmark_return_bps~,
  ) catch {
    error => raise InvestmentBenchmarkError::Portfolio(error)
  }
  let observation = @portfolio.BenchmarkObservation::new(
    observation_id~,
    benchmark_id~,
    period_id~,
    source_snapshot_id~,
    mapping_version~,
    evidence_id~,
    return_bps=observed_return_bps,
  ) catch {
    error => raise InvestmentBenchmarkError::Portfolio(error)
  }
  let reconciliation = comparison.reconcile(observation, tolerance_bps~) catch {
    error => raise InvestmentBenchmarkError::Portfolio(error)
  }
  let candidate = Json::object({
    "reconciliation_id": Json::string(reconciliation.reconciliation_id),
    "portfolio_id": Json::string(reconciliation.portfolio_id),
    "period_id": Json::string(reconciliation.period_id),
    "benchmark_id": Json::string(reconciliation.benchmark_id),
    "observation_id": Json::string(reconciliation.observation_id),
    "source_snapshot_id": Json::string(reconciliation.source_snapshot_id),
    "mapping_version": Json::string(reconciliation.mapping_version),
    "evidence_id": Json::string(reconciliation.evidence_id),
    "portfolio_return_bps": integer(reconciliation.portfolio_return_bps),
    "observed_benchmark_return_bps": integer(
      reconciliation.observed_benchmark_return_bps,
    ),
    "comparison_benchmark_return_bps": integer(
      reconciliation.comparison_benchmark_return_bps,
    ),
    "active_return_bps": integer(reconciliation.active_return_bps),
    "difference_bps": integer(reconciliation.difference_bps),
    "tolerance_bps": integer(reconciliation.tolerance_bps),
    "reconciled": Json::boolean(reconciliation.reconciled),
    "analytics_only": Json::boolean(true),
    "position_mutated": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
  })
  let receipt = Json::object({
    "format": Json::string("moonproj.erp.domain-promotion.v1"),
    "source_snapshot_id": Json::string(source_snapshot_id),
    "mapping_version": Json::string(mapping_version),
    "state": Json::string("promoted_through_domain_importers"),
    "cohort": Json::string("investment-benchmark-reconciliation-v1"),
    "accepted_items": Json::array([
      Json::object({
        "source_table": Json::string("investment_benchmark_observation"),
        "source_id": Json::string(observation_id),
        "target_type": Json::string("investment_benchmark_reconciliation"),
        "target_id": Json::string(reconciliation.reconciliation_id),
        "target_candidate": candidate,
      }),
    ]),
    "analytics_only": Json::boolean(true),
    "position_mutated": Json::boolean(false),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
  }).stringify(indent=2)
  @fs.write_string_to_file(output_path, receipt) catch {
    error => raise InvestmentBenchmarkError::Io(error)
  }
}

///|
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    println("usage: investment_benchmark <plan.json> <receipt.json>")
    @sys.exit(2)
  } else {
    run(args[1], args[2]) catch {
      InvestmentBenchmarkError::InvalidInput => {
        println("investment benchmark failed: invalid input")
        @sys.exit(1)
      }
      InvestmentBenchmarkError::Io(_) => {
        println("investment benchmark failed: filesystem error")
        @sys.exit(1)
      }
      InvestmentBenchmarkError::Portfolio(_) => {
        println("investment benchmark failed: portfolio validation")
        @sys.exit(1)
      }
    }
  }
}
