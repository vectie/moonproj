///|
fn report_state_name(state : ConsolidatedReportState) -> String {
  match state {
    ConsolidatedReportState::Reconciled => "reconciled"
  }
}

///|
fn mapping_versions_json(versions : Array[String]) -> Json {
  let values : Array[Json] = []
  for version in versions {
    values.push(Json::string(version))
  }
  Json::array(values)
}

///|
fn sections_json(sections : Array[ReportSection]) -> Json {
  let values : Array[Json] = []
  for section in sections {
    values.push(
      Json::object({
        "section_id": Json::string(section.section_id),
        "expected_minor": Json::number(
          section.expected.minor.to_double(),
          repr=section.expected.minor.to_string(),
        ),
        "actual_minor": Json::number(
          section.actual.minor.to_double(),
          repr=section.actual.minor.to_string(),
        ),
        "currency": Json::string(section.expected.currency),
        "balanced": Json::boolean(section.balanced),
      }),
    )
  }
  Json::array(values)
}

///|
fn report_payload(report : ConsolidatedReport) -> String {
  Json::object({
    "report_id": Json::string(report.report_id),
    "period_id": Json::string(report.period_id),
    "principal_id": Json::string(report.principal_id),
    "scope": Json::string(report.scope),
    "source_snapshot_id": Json::string(report.source_snapshot_id),
    "mapping_versions": mapping_versions_json(report.mapping_versions),
    "sections": sections_json(report.sections),
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
    "state": Json::string(report_state_name(report.state)),
    "cash_released": Json::boolean(false),
    "period_posted": Json::boolean(false),
    "tax_filed": Json::boolean(false),
  }).stringify()
}

///|
pub fn ConsolidatedReport::append_projection(
  self : ConsolidatedReport,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise ReportingError {
  if projection.aggregate_type != "consolidated_report" ||
    projection.aggregate_id != self.report_id {
    raise ReportingError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=report_payload(self),
    source_event_id="company:consolidated-report:" +
      self.report_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise ReportingError::Projection(error)
  }
}
