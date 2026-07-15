///|
/// Native source-backed core reports.
///
/// These reads deliberately operate on imported raw envelopes. They do not
/// turn report observations into accounting, budget, approval, or cash
/// authority. Missing source tables remain visible in the overview envelope.
fn report_text(value : Json, key : String, fallback : String) -> String {
  json_text(value, key, fallback)
}

///|
fn report_amount(value : Json, key : String) -> Double {
  json_number(value, key, 0.0)
}

///|
fn report_is_end_cost(value : Json) -> Bool {
  json_bool(value, "is_end_cost", false)
}

///|
fn report_coverage(table_counts : Map[String, Int]) -> Json {
  let fields : Map[String, Json] = {}
  for key, value in table_counts {
    fields.set(key, Json::number(value.to_double()))
  }
  Json::object(fields)
}

///|
fn report_missing(table_counts : Map[String, Int]) -> Array[Json] {
  let result : Array[Json] = []
  for key, value in table_counts {
    if value == 0 {
      result.push(Json::string(key))
    }
  }
  result.sort_by(fn(left, right) { left.stringify().compare(right.stringify()) })
  result
}

///|
fn report_distinct_count(values : Array[String]) -> Int {
  let seen : Map[String, Bool] = {}
  for value in values {
    seen.set(value, true)
  }
  seen.length()
}

///|
async fn report_cost_summary() -> Json raise CompanyServiceError {
  let projects = raw_source_rows("ep_project", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let costs = raw_source_rows("cb_cost", 500)
  let target : Map[String, Double] = {}
  let d : Map[String, Double] = {}
  let e : Map[String, Double] = {}
  let f : Map[String, Double] = {}
  let g : Map[String, Double] = {}
  for row in costs {
    let payload = row.payload
    if report_is_end_cost(payload) {
      let project_id = report_text(payload, "proj_guid", "")
      target.set(
        project_id,
        target.get_or_default(project_id, 0.0) +
        report_amount(payload, "target_cost"),
      )
      d.set(
        project_id,
        d.get_or_default(project_id, 0.0) +
        report_amount(payload, "ht_alter_amount"),
      )
      e.set(
        project_id,
        e.get_or_default(project_id, 0.0) + report_amount(payload, "zt_cost"),
      )
      f.set(
        project_id,
        f.get_or_default(project_id, 0.0) + report_amount(payload, "dfs_budget"),
      )
      g.set(
        project_id,
        g.get_or_default(project_id, 0.0) + report_amount(payload, "yg_alter"),
      )
    }
  }
  let rows : Array[Json] = []
  for row in projects {
    let payload = row.payload
    let project_id = report_text(payload, "proj_guid", row.record_id)
    let target_value = target.get_or_default(project_id, 0.0)
    let d_value = d.get_or_default(project_id, 0.0)
    let e_value = e.get_or_default(project_id, 0.0)
    let f_value = f.get_or_default(project_id, 0.0)
    let g_value = g.get_or_default(project_id, 0.0)
    let dynamic = d_value + e_value + f_value + g_value
    let deviation = if target_value == 0.0 {
      0.0
    } else {
      round_places((target_value - dynamic) / target_value * 100.0, 2)
    }
    let bu_id = report_text(payload, "bu_guid", "")
    rows.push(
      Json::object({
        "buName": Json::string(unit_name(units, bu_id)),
        "projCode": Json::string(report_text(payload, "proj_code", project_id)),
        "projName": Json::string(report_text(payload, "proj_name", project_id)),
        "projStatus": Json::string(report_text(payload, "proj_status", "")),
        "targetCost": Json::number(target_value),
        "dynamicCost": Json::number(dynamic),
        "spare": Json::number(target_value - dynamic),
        "deviationPct": Json::number(deviation),
        "d": Json::number(d_value),
        "e": Json::number(e_value),
        "f": Json::number(f_value),
        "g": Json::number(g_value),
        "source_kind": Json::string("imported"),
      }),
    )
  }
  let total_target = rows.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row, "targetCost")
  })
  let total_dynamic = rows.fold(init=0.0, fn(sum, row) {
    sum + report_amount(row, "dynamicCost")
  })
  let total = Json::object({
    "targetCost": Json::number(total_target),
    "dynamicCost": Json::number(total_dynamic),
    "spare": Json::number(total_target - total_dynamic),
    "deviationPct": Json::number(
      if total_target == 0.0 {
        0.0
      } else {
        round_places((total_target - total_dynamic) / total_target * 100.0, 2)
      },
    ),
    "d": Json::number(
      rows.fold(init=0.0, fn(sum, row) { sum + report_amount(row, "d") }),
    ),
    "e": Json::number(
      rows.fold(init=0.0, fn(sum, row) { sum + report_amount(row, "e") }),
    ),
    "f": Json::number(
      rows.fold(init=0.0, fn(sum, row) { sum + report_amount(row, "f") }),
    ),
    "g": Json::number(
      rows.fold(init=0.0, fn(sum, row) { sum + report_amount(row, "g") }),
    ),
  })
  Json::object({
    "rows": Json::array(rows),
    "total": total,
    "source_kind": Json::string("imported"),
  })
}

///|
async fn report_contract_payment_ledger() -> Array[Json] raise CompanyServiceError {
  let projects = raw_source_rows("ep_project", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  let plans = raw_source_rows("cb_htfkplan", 500)
  let applies = raw_source_rows("cb_htfk_apply", 500)
  let contracts = raw_source_rows("cb_contract", 500)
  let plan_totals : Map[String, Double] = {}
  let applied_totals : Map[String, Double] = {}
  let paid_totals : Map[String, Double] = {}
  for row in plans {
    let id = report_text(row.payload, "contract_guid", "")
    plan_totals.set(
      id,
      plan_totals.get_or_default(id, 0.0) +
      report_amount(row.payload, "jhfk_amount"),
    )
  }
  for row in applies {
    let payload = row.payload
    let id = report_text(payload, "contract_guid", "")
    if report_text(payload, "apply_state", "") == "已审核" {
      applied_totals.set(
        id,
        applied_totals.get_or_default(id, 0.0) +
        report_amount(payload, "apply_amount"),
      )
    }
    if ["完全支付", "部分支付"].contains(
        report_text(payload, "pay_state", ""),
      ) {
      paid_totals.set(
        id,
        paid_totals.get_or_default(id, 0.0) +
        report_amount(payload, "apply_amount"),
      )
    }
  }
  contracts.sort_by(fn(left, right) {
    report_text(right.payload, "sign_date", "").lexical_compare(
      report_text(left.payload, "sign_date", ""),
    )
  })
  let result : Array[Json] = []
  for row in contracts {
    let payload = row.payload
    let id = report_text(payload, "contract_guid", row.record_id)
    let project_id = report_text(payload, "proj_guid", "")
    let bu_id = report_text(payload, "bu_guid", "")
    let amount = report_amount(payload, "ht_amount")
    let alteration = report_amount(payload, "sum_alter_amount")
    let current = amount + alteration
    let paid = paid_totals.get_or_default(id, 0.0)
    result.push(
      Json::object({
        "contractGuid": Json::string(id),
        "contractCode": Json::string(report_text(payload, "contract_code", id)),
        "contractName": Json::string(report_text(payload, "contract_name", id)),
        "buName": Json::string(unit_name(units, bu_id)),
        "projName": Json::string(
          source_name(projects, "proj_name", "proj_guid", project_id),
        ),
        "provider": Json::string(report_text(payload, "yf_provider_name", "")),
        "signDate": Json::string(report_text(payload, "sign_date", "")),
        "htCfState": Json::string(report_text(payload, "ht_cf_state", "")),
        "htAmount": Json::number(amount),
        "alterAmount": Json::number(alteration),
        "currentAmount": Json::number(current),
        "planTotal": Json::number(plan_totals.get_or_default(id, 0.0)),
        "appliedTotal": Json::number(applied_totals.get_or_default(id, 0.0)),
        "paidTotal": Json::number(paid),
        "remainAmount": Json::number(current - paid),
        "paidPct": Json::number(
          if current == 0.0 {
            0.0
          } else {
            round_places(paid / current * 100.0, 2)
          },
        ),
        "source_kind": Json::string("imported"),
      }),
    )
  }
  result
}

///|
async fn report_supplier_analysis() -> Array[Json] raise CompanyServiceError {
  let providers = raw_source_rows("srm_provider", 500)
  let categories = raw_source_rows("srm_category", 500)
  let contracts = raw_source_rows("cb_contract", 500)
  let result : Array[Json] = []
  for row in providers {
    let payload = row.payload
    let name = report_text(payload, "provider_name", row.record_id)
    let short_name = report_text(payload, "short_name", "")
    let matched : Array[Json] = []
    for contract in contracts {
      let provider = report_text(contract.payload, "yf_provider_name", "")
      if provider == name ||
        (!short_name.is_empty() && provider.contains(short_name)) {
        matched.push(contract.payload)
      }
    }
    if matched.is_empty() {
      continue
    }
    let total = matched.fold(init=0.0, fn(sum, contract) {
      sum +
      report_amount(contract, "ht_amount") +
      report_amount(contract, "sum_alter_amount")
    })
    let category_code = report_text(payload, "main_category_code", "")
    let mut category_name = category_code
    for category in categories {
      if report_text(category.payload, "category_code", category.record_id) ==
        category_code {
        category_name = report_text(
          category.payload,
          "category_name",
          category_code,
        )
      }
    }
    result.push(
      Json::object({
        "providerGuid": Json::string(
          report_text(payload, "provider_guid", row.record_id),
        ),
        "providerName": Json::string(name),
        "shortName": Json::string(short_name),
        "evalResult": Json::string(report_text(payload, "eval_result", "")),
        "categoryName": Json::string(category_name),
        "contractCount": Json::number(matched.length().to_double()),
        "buCount": Json::number(
          report_distinct_count(
            matched.map(fn(item) { report_text(item, "bu_guid", "") }),
          ).to_double(),
        ),
        "projCount": Json::number(
          report_distinct_count(
            matched.map(fn(item) { report_text(item, "proj_guid", "") }),
          ).to_double(),
        ),
        "totalAmount": Json::number(total),
        "recentAmount": Json::number(total),
        "source_kind": Json::string("imported"),
      }),
    )
  }
  result.sort_by(fn(left, right) {
    report_amount(right, "totalAmount").compare(
      report_amount(left, "totalAmount"),
    )
  })
  result
}

///|
async fn report_approval_efficiency() -> Json raise CompanyServiceError {
  let instances = raw_source_rows("wf_process_instance", 500)
  let by_type : Map[String, Array[Json]] = {}
  for row in instances {
    let key = report_text(row.payload, "biz_type", "")
    let values = by_type.get_or_default(key, [])
    values.push(row.payload)
    by_type.set(key, values)
  }
  let rows : Array[Json] = []
  for biz_type, values in by_type {
    let total = values.length()
    let completed = values
      .filter(fn(value) {
        ["Completed", "Archived"].contains(report_text(value, "status", ""))
      })
      .length()
    let rejected = values
      .filter(fn(value) { report_text(value, "status", "") == "Rejected" })
      .length()
    let running = values
      .filter(fn(value) { report_text(value, "status", "") == "Running" })
      .length()
    rows.push(
      Json::object({
        "bizType": Json::string(biz_type),
        "total": Json::number(total.to_double()),
        "completed": Json::number(completed.to_double()),
        "rejected": Json::number(rejected.to_double()),
        "running": Json::number(running.to_double()),
        "overdue": Json::number(0),
        "avgDays": Json::null(),
        "rejectRate": Json::number(
          if total == 0 {
            0.0
          } else {
            rejected.to_double() / total.to_double() * 100.0
          },
        ),
      }),
    )
  }
  rows.sort_by(fn(left, right) {
    json_int(right, "total", 0).compare(json_int(left, "total", 0))
  })
  Json::object({
    "byType": Json::array(rows),
    "slowSteps": Json::array([]),
    "source_kind": Json::string("imported"),
  })
}

///|
async fn report_project_stage_matrix() -> Json raise CompanyServiceError {
  let stages = raw_source_rows("proj_lifecycle_stage", 500)
  let instances = raw_source_rows("proj_lifecycle_instance", 500)
  let projects = raw_source_rows("ep_project", 500)
  let units = raw_source_rows("mu_business_unit", 500)
  stages.sort_by(fn(left, right) {
    report_amount(left.payload, "stage_order").compare(
      report_amount(right.payload, "stage_order"),
    )
  })
  let matrix : Array[Json] = []
  for project in projects {
    let project_id = report_text(
      project.payload,
      "proj_guid",
      project.record_id,
    )
    let cells : Array[Json] = []
    for stage in stages {
      let stage_code = report_text(stage.payload, "stage_code", "")
      let mut status = "pending"
      let mut progress = 0.0
      for instance in instances {
        if report_text(instance.payload, "proj_guid", "") == project_id &&
          report_text(instance.payload, "stage_code", "") == stage_code {
          status = report_text(instance.payload, "status", "pending")
          progress = report_amount(instance.payload, "progress_pct")
        }
      }
      cells.push(
        Json::object({
          "stageCode": Json::string(stage_code),
          "stageName": Json::string(
            report_text(stage.payload, "stage_name", stage_code),
          ),
          "status": Json::string(status),
          "progressPct": Json::number(progress),
        }),
      )
    }
    let bu_id = report_text(project.payload, "bu_guid", "")
    matrix.push(
      Json::object({
        "projGuid": Json::string(project_id),
        "projCode": Json::string(
          report_text(project.payload, "proj_code", project_id),
        ),
        "projName": Json::string(
          report_text(project.payload, "proj_name", project_id),
        ),
        "buName": Json::string(unit_name(units, bu_id)),
        "projStatus": Json::string(
          report_text(project.payload, "proj_status", ""),
        ),
        "beginDate": Json::string(
          report_text(project.payload, "begin_date", ""),
        ),
        "endDate": Json::string(report_text(project.payload, "end_date", "")),
        "cells": Json::array(cells),
        "source_kind": Json::string("imported"),
      }),
    )
  }
  let stage_json : Array[Json] = stages.map(fn(row) {
    Json::object({
      "code": Json::string(report_text(row.payload, "stage_code", "")),
      "name": Json::string(report_text(row.payload, "stage_name", "")),
    })
  })
  Json::object({
    "stages": Json::array(stage_json),
    "projects": Json::array(matrix),
    "source_kind": Json::string("imported"),
  })
}

///|
async fn reports_overview_response() -> Json raise CompanyServiceError {
  let cost_summary = report_cost_summary()
  let contract_payment_ledger = report_contract_payment_ledger()
  let supplier_analysis = report_supplier_analysis()
  let approval_efficiency = report_approval_efficiency()
  let project_stage_matrix = report_project_stage_matrix()
  let table_counts : Map[String, Int] = {}
  for
    table in [
      "cb_cost", "cb_contract", "cb_htfk_apply", "cb_htfkplan", "srm_provider", "wf_process_instance",
      "proj_lifecycle_stage", "proj_lifecycle_instance", "ep_project", "mu_business_unit",
    ] {
    table_counts.set(table, raw_source_rows(table, 500).length())
  }
  Json::object({
    "cost_summary": cost_summary,
    "contract_payment_ledger": Json::array(contract_payment_ledger),
    "supplier_analysis": supplier_analysis,
    "approval_efficiency": approval_efficiency,
    "project_stage_matrix": project_stage_matrix,
    "source_kind": Json::string("imported"),
    "source_coverage": report_coverage(table_counts),
    "missing_source_tables": Json::array(report_missing(table_counts)),
  })
}
