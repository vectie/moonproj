///|
/// Resolve an exact public project identity from every authoritative source.
/// Migration projections are deliberately excluded. Revisions are selected
/// before inspecting mutable payload identity, source kind, or tombstone state.
fn project_identity_sql(project_id : String, include_deleted : Bool) -> String {
  let id = @postgres.sql_literal(project_id)
  let raw_identity = plan_task_json_text_sql("proj_guid", "record_id")
  let projection_identity = plan_task_json_text_sql("proj_guid", "aggregate_id")
  let state_filter = if include_deleted {
    ""
  } else {
    " WHERE coalesce(payload->>'state', '') <> 'deleted' AND " +
    plan_task_json_text_sql("deleted_at", "''") +
    " = '' AND " +
    plan_task_json_text_sql("deletedAt", "''") +
    " = ''"
  }
  "WITH latest_project_import AS (" +
  "SELECT DISTINCT ON (aggregate_id) aggregate_id, payload, source_event_id, revision " +
  "FROM company_aggregate_projection WHERE aggregate_type = 'project_import' " +
  "ORDER BY aggregate_id, revision DESC), latest_native_project AS (" +
  "SELECT DISTINCT ON (aggregate_id) aggregate_id, payload, source_event_id, revision " +
  "FROM company_aggregate_projection WHERE aggregate_type = 'project' " +
  "ORDER BY aggregate_id, revision DESC) " +
  "SELECT encode(convert_to(record_id, 'UTF8'), 'hex'), " +
  "encode(convert_to(source_id, 'UTF8'), 'hex'), " +
  "encode(convert_to(payload::text, 'UTF8'), 'hex'), revision::text FROM (" +
  "SELECT record_id, source_id, payload, 0 AS revision FROM company_record " +
  "WHERE record_type = 'legacy/raw/ep_project' AND " +
  raw_identity +
  " = " +
  id +
  " UNION ALL SELECT aggregate_id AS record_id, source_event_id AS source_id, payload, revision " +
  "FROM latest_project_import WHERE " +
  projection_identity +
  " = " +
  id +
  " UNION ALL SELECT aggregate_id AS record_id, source_event_id AS source_id, payload, revision " +
  "FROM latest_native_project WHERE payload->>'source_kind' = 'command' AND " +
  projection_identity +
  " = " +
  id +
  ") authoritative" +
  state_filter +
  " ORDER BY record_id, source_id"
}

///|
fn project_identity_decode_rows(
  output : String,
) -> Array[SourceRow] raise CompanyServiceError {
  let result : Array[SourceRow] = []
  for line_view in output.split("\n") {
    let line = line_view.to_owned()
    if line.is_empty() {
      continue
    }
    let row = fields(line, 4)
    let payload = @json.parse(decode_hex(row[2])) catch {
      _ => raise fail("invalid project identity JSON")
    }
    match payload {
      Object(values) => {
        let revision = parse_decimal(row[3])
        if revision > 0 {
          values.set("__revision", Json::number(revision.to_double()))
        }
        result.push({
          record_id: decode_hex(row[0]),
          source_id: decode_hex(row[1]),
          payload: Json::object(values),
        })
      }
      _ => raise fail("project identity payload is not an object")
    }
  }
  result
}

///|
/// Return all current matching sources without merging or selecting a winner.
/// include_deleted=true is required for create collision checks and exact
/// resolution, so a competing tombstone cannot silently expose another source.
async fn project_identity_rows(
  project_id : String,
  include_deleted : Bool,
) -> Array[SourceRow] raise CompanyServiceError {
  project_identity_decode_rows(
    run_sql(project_identity_sql(project_id, include_deleted)),
  )
}

///|
fn project_identity_live_rows(
  rows : Array[SourceRow],
  project_id : String,
) -> Array[SourceRow] raise CompanyServiceError {
  let matches = rows.filter(row => {
    json_text(row.payload, "proj_guid", row.record_id) == project_id
  })
  if matches.length() > 1 {
    raise reject(
      409,
      "project identity is ambiguous across authoritative sources: " +
      project_id,
    )
  }
  matches.filter(project_identity_is_live)
}

///|
fn project_identity_is_live(row : SourceRow) -> Bool {
  json_text(row.payload, "state", "") != "deleted" &&
  json_text(row.payload, "deleted_at", "").is_empty() &&
  json_text(row.payload, "deletedAt", "").is_empty()
}

///|
/// Omit only ambiguous choices from a bounded listing. Unrelated projects stay
/// selectable; exact reads still perform the complete database identity lookup.
fn project_identity_catalog(
  rows : Array[SourceRow],
) -> (Array[SourceRow], Array[Json]) {
  let grouped : Map[String, Array[SourceRow]] = Map([])
  for row in rows {
    let id = json_text(row.payload, "proj_guid", row.record_id)
    match grouped.get(id) {
      Some(matches) => matches.push(row)
      None => grouped.set(id, [row])
    }
  }
  let selectable : Array[SourceRow] = []
  let diagnostics : Array[Json] = []
  for id, matches in grouped {
    if matches.length() > 1 {
      diagnostics.push({
        "code": "ambiguous_project_identity",
        "projectId": Json::string(id),
        "message": "Project ID has competing sources and is omitted from selection",
        "sources": Json::array(
          matches.map(row => {
            Json::object({
              "record_id": Json::string(row.record_id),
              "source_id": Json::string(row.source_id),
            })
          }),
        ),
      })
    } else if project_identity_is_live(matches[0]) {
      selectable.push(matches[0])
    }
  }
  (selectable, diagnostics)
}

///|
/// Ambiguous unit names are local diagnostics in a project listing. Returning
/// no name candidate leaves the project's own bu_guid untouched.
fn project_catalog_unit_rows(
  project_id : String,
  bu_id : String,
  units : Array[SourceRow],
  exact : Bool,
  diagnostics : Array[Json],
) -> Array[SourceRow] raise CompanyServiceError {
  if units.length() <= 1 {
    return units
  }
  if exact {
    raise reject(
      409,
      "business unit identity is ambiguous across authoritative sources: " +
      bu_id,
    )
  }
  diagnostics.push({
    "code": "ambiguous_project_business_unit",
    "projectId": Json::string(project_id),
    "buGuid": Json::string(bu_id),
    "message": "Business unit name is unresolved because the ID has competing sources",
    "sources": Json::array(
      units.map(row => {
        Json::object({
          "record_id": Json::string(row.record_id),
          "source_id": Json::string(row.source_id),
        })
      }),
    ),
  })
  []
}
