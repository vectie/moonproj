///|
fn field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn text(value : Json, key : String, fallback : String) -> String {
  match field(value, key) {
    Some(String(result)) => result
    _ => fallback
  }
}

///|
/// Pure persisted projection contract kept outside the service executable.
/// Product admission remains explicitly independent from engineering Exit
/// Gates G1-G9.
pub fn persisted(
  product~ : String,
  normalized~ : Json,
  owner~ : String,
  revision~ : Int,
  event_id~ : String,
  updated_at_ms~ : UInt64,
) -> Json {
  {
    "schema": "moonproj.product-in-gate-projection.v2",
    "product": product,
    "decision": text(normalized, "decision", "unknown"),
    "primary_value": text(normalized, "primary_value", "unknown"),
    "segment": text(normalized, "segment", ""),
    "workflow": text(normalized, "workflow", ""),
    "decided_at": text(normalized, "decided_at", ""),
    "problem_evidence": field(normalized, "problem_evidence").unwrap_or([]),
    "commitment_evidence": field(normalized, "commitment_evidence").unwrap_or([]),
    "current_behavior_cost": text(normalized, "current_behavior_cost", ""),
    "outcome_metric": text(normalized, "outcome_metric", ""),
    "adoption_path": text(normalized, "adoption_path", ""),
    "unresolved_risks": text(normalized, "unresolved_risks", ""),
    "next_experiment": text(normalized, "next_experiment", ""),
    "review_by": text(normalized, "review_by", ""),
    "owner": owner,
    "revision": revision,
    "event_id": event_id,
    "updated_at_ms": updated_at_ms,
    "persisted": true,
    "exit_gate_effect": false,
  }
}

///|
pub fn unknown(product~ : String) -> Json {
  {
    "schema": "moonproj.product-in-gate-projection.v2",
    "product": product,
    "decision": "unknown",
    "primary_value": "unknown",
    "segment": "",
    "workflow": "",
    "decided_at": "",
    "problem_evidence": [],
    "commitment_evidence": [],
    "current_behavior_cost": "",
    "outcome_metric": "",
    "adoption_path": "",
    "unresolved_risks": "",
    "next_experiment": "",
    "review_by": "",
    "owner": "",
    "revision": 0,
    "event_id": "",
    "updated_at_ms": 0,
    "persisted": false,
    "exit_gate_effect": false,
  }
}
