///|
fn cbs_state_name(state : CbsVersionState) -> String {
  match state {
    CbsVersionState::Draft => "draft"
    CbsVersionState::Active => "active"
    CbsVersionState::Frozen => "frozen"
  }
}

///|
fn cbs_subjects_json(subjects : Array[CostSubject]) -> Json {
  let encoded : Array[Json] = []
  for subject in subjects {
    encoded.push(
      Json::object({
        "subject_id": Json::string(subject.subject_id),
        "code": Json::string(subject.code),
        "name": Json::string(subject.name),
        "parent_code": Json::string(subject.parent_code),
        "target_minor": Json::number(
          subject.target_minor.to_double(),
          repr=subject.target_minor.to_string(),
        ),
      }),
    )
  }
  Json::array(encoded)
}

///|
fn cbs_projection_payload(version : CbsVersion) -> String {
  Json::object({
    "version_id": Json::string(version.version_id),
    "project_scope": Json::string(version.project_scope),
    "state": Json::string(cbs_state_name(version.state)),
    "target_total_minor": Json::number(
      version.target_total_minor().to_double(),
      repr=version.target_total_minor().to_string(),
    ),
    "subjects": cbs_subjects_json(version.subjects),
  }).stringify()
}

///|
pub fn CbsVersion::append_projection(
  self : CbsVersion,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise CbsError {
  if projection.aggregate_type != "cbs_version" ||
    projection.aggregate_id != self.version_id {
    raise CbsError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=cbs_projection_payload(self),
    source_event_id="company:cbs-version:" +
      self.version_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise CbsError::Projection(error)
  }
}

///|
fn cbs_budget_state_name(state : CbsBudgetReservationState) -> String {
  match state {
    CbsBudgetReservationState::Reserved => "reserved"
    CbsBudgetReservationState::Consumed => "consumed"
    CbsBudgetReservationState::Released => "released"
  }
}

///|
fn cbs_budget_reservations_json(
  reservations : Array[CbsBudgetReservation],
) -> Json {
  let encoded : Array[Json] = []
  for reservation in reservations {
    encoded.push(
      Json::object({
        "reservation_id": Json::string(reservation.reservation_id),
        "source_id": Json::string(reservation.source_id),
        "version_id": Json::string(reservation.version_id),
        "project_scope": Json::string(reservation.project_scope),
        "subject_code": Json::string(reservation.subject_code),
        "principal_id": Json::string(reservation.principal_id),
        "amount_minor": Json::number(
          reservation.amount.minor.to_double(),
          repr=reservation.amount.minor.to_string(),
        ),
        "currency": Json::string(reservation.amount.currency),
        "state": Json::string(cbs_budget_state_name(reservation.state)),
      }),
    )
  }
  Json::array(encoded)
}

///|
pub fn CbsBudgetLedger::append_projection(
  self : CbsBudgetLedger,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise CbsError {
  if projection.aggregate_type != "cbs_budget_ledger" ||
    projection.aggregate_id != self.version_id {
    raise CbsError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  let payload = Json::object({
    "version_id": Json::string(self.version_id),
    "project_scope": Json::string(self.project_scope),
    "principal_id": Json::string(self.principal_id),
    "currency": Json::string(self.currency),
    "reserved_minor": Json::number(
      self.reserved_minor().to_double(),
      repr=self.reserved_minor().to_string(),
    ),
    "consumed_minor": Json::number(
      self.consumed_minor().to_double(),
      repr=self.consumed_minor().to_string(),
    ),
    "reservations": cbs_budget_reservations_json(self.reservations),
    "accounting_posted": Json::boolean(false),
    "cash_released": Json::boolean(false),
  }).stringify()
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:cbs-budget-ledger:" +
      self.version_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise CbsError::Projection(error)
  }
}

///|
fn cost_subject_link_projection_payload(link : CostSubjectLink) -> String {
  Json::object({
    "link_id": Json::string(link.link_id),
    "source_id": Json::string(link.source_id),
    "version_id": Json::string(link.version_id),
    "project_scope": Json::string(link.project_scope),
    "subject_code": Json::string(link.subject_code),
    "principal_id": Json::string(link.principal_id),
    "amount_minor": Json::number(
      link.amount.minor.to_double(),
      repr=link.amount.minor.to_string(),
    ),
    "currency": Json::string(link.amount.currency),
  }).stringify()
}

///|
pub fn CostSubjectLink::append_projection(
  self : CostSubjectLink,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise CbsError {
  if projection.aggregate_type != "cbs_cost_link" ||
    projection.aggregate_id != self.link_id {
    raise CbsError::ProjectionIdentity
  }
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload=cost_subject_link_projection_payload(self),
    source_event_id="company:cbs-cost-link:" +
      self.link_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise CbsError::Projection(error)
  }
}
