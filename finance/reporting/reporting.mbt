///|
pub(all) enum ConsolidatedReportState {
  Reconciled
} derive(Debug, Eq)

///|
pub(all) struct ReportSection {
  section_id : String
  expected : @finance.Money
  actual : @finance.Money
  balanced : Bool
} derive(Debug, Eq)

///|
/// A non-posting, source-snapshot-bound control-total report. It combines
/// already reconciled subreports without becoming a ledger or cash command.
pub(all) struct ConsolidatedReport {
  report_id : String
  period_id : String
  principal_id : String
  scope : String
  source_snapshot_id : String
  mapping_versions : Array[String]
  sections : Array[ReportSection]
  expected_total : @finance.Money
  actual_total : @finance.Money
  difference_minor : Int64
  accounting_link_count : Int
  reconciled_link_count : Int
  state : ConsolidatedReportState
} derive(Debug, Eq)

///|
pub(all) suberror ReportingError {
  EmptyIdentifier
  NoMappingVersions
  DuplicateMappingVersion
  NoSections
  DuplicateSection
  InvalidLinkCount
  CurrencyMismatch
  UnbalancedSection(Int64)
  Reconciliation(@reconciliation.ReconciliationError)
  NotAuthorized(@foundation.AuthorityError)
  ProjectionIdentity
  Projection(@store.ProjectionError)
} derive(Debug, Eq)

///|
pub fn ConsolidatedReport::new(
  report_id~ : String,
  period_id~ : String,
  principal_id~ : String,
  scope~ : String,
  source_snapshot_id~ : String,
  mapping_versions~ : Array[String],
  reports~ : Array[@reconciliation.ReconciliationReport],
  accounting_link_count~ : Int,
  reconciled_link_count~ : Int,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ConsolidatedReport raise ReportingError {
  if report_id.trim() == "" ||
    period_id.trim() == "" ||
    principal_id.trim() == "" ||
    scope.trim() == "" ||
    source_snapshot_id.trim() == "" {
    raise ReportingError::EmptyIdentifier
  }
  if mapping_versions.length() == 0 {
    raise ReportingError::NoMappingVersions
  }
  for i in 0..<mapping_versions.length() {
    if mapping_versions[i].trim() == "" {
      raise ReportingError::NoMappingVersions
    }
    for j in (i + 1)..<mapping_versions.length() {
      if mapping_versions[i] == mapping_versions[j] {
        raise ReportingError::DuplicateMappingVersion
      }
    }
  }
  if reports.length() == 0 {
    raise ReportingError::NoSections
  }
  if accounting_link_count < 0 ||
    reconciled_link_count < 0 ||
    reconciled_link_count > accounting_link_count {
    raise ReportingError::InvalidLinkCount
  }
  let first = reports[0]
  first.require_balanced() catch {
    error => raise ReportingError::Reconciliation(error)
  }
  let currency = first.expected_total.currency
  let sections : Array[ReportSection] = []
  let seen_sections : Array[String] = []
  let mut expected_minor = 0L
  let mut actual_minor = 0L
  for report in reports {
    for seen in seen_sections {
      if seen == report.scope {
        raise ReportingError::DuplicateSection
      }
    }
    if report.expected_total.currency != currency ||
      report.actual_total.currency != currency {
      raise ReportingError::CurrencyMismatch
    }
    report.require_balanced() catch {
      _ => raise ReportingError::UnbalancedSection(report.difference_minor)
    }
    seen_sections.push(report.scope)
    sections.push({
      section_id: report.scope,
      expected: report.expected_total,
      actual: report.actual_total,
      balanced: report.balanced,
    })
    expected_minor += report.expected_total.minor
    actual_minor += report.actual_total.minor
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="report:consolidate",
    scope~,
    amount_minor=0,
  ) catch {
    error => raise ReportingError::NotAuthorized(error)
  }
  let expected_total = try! @finance.Money::new(minor=expected_minor, currency~)
  let actual_total = try! @finance.Money::new(minor=actual_minor, currency~)
  {
    report_id,
    period_id,
    principal_id,
    scope,
    source_snapshot_id,
    mapping_versions: mapping_versions.copy(),
    sections,
    expected_total,
    actual_total,
    difference_minor: actual_minor - expected_minor,
    accounting_link_count,
    reconciled_link_count,
    state: ConsolidatedReportState::Reconciled,
  }
}
