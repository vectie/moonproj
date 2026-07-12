///|
/// An append-only revision of a domain aggregate. The payload is an opaque
/// domain snapshot; `source_event_id` makes replay and migration idempotency
/// explicit at the persistence boundary.
pub(all) struct AggregateRevision {
  aggregate_type : String
  aggregate_id : String
  revision : Int
  schema_version : Int
  payload : String
  source_event_id : String
} derive(Debug, Eq)

///|
pub(all) struct AggregateProjection {
  aggregate_type : String
  aggregate_id : String
  revision : Int
  store : RecordStore
} derive(Debug, Eq)

///|
pub(all) suberror ProjectionError {
  EmptyAggregateType
  EmptyAggregateId
  EmptySourceEventId
  InvalidRevision
  RevisionConflict
  InvalidHistory
  Store(StoreError)
} derive(Debug, Eq)

///|
fn projection_record_type(aggregate_type : String) -> String {
  "projection/" + aggregate_type
}

///|
fn projection_record_id(aggregate_id : String, revision : Int) -> String {
  aggregate_id + "@r" + revision.to_string()
}

///|
fn projection_count(
  store : RecordStore,
  aggregate_type : String,
  aggregate_id : String,
) -> Int {
  let record_type = projection_record_type(aggregate_type)
  let prefix = aggregate_id + "@r"
  let mut count = 0
  for record in store.records {
    if record.record_type == record_type && record.record_id.has_prefix(prefix) {
      count += 1
    }
  }
  count
}

///|
pub fn AggregateProjection::new(
  store : RecordStore,
  aggregate_type~ : String,
  aggregate_id~ : String,
) -> AggregateProjection raise ProjectionError {
  if aggregate_type.trim() == "" {
    raise ProjectionError::EmptyAggregateType
  }
  if aggregate_id.trim() == "" {
    raise ProjectionError::EmptyAggregateId
  }
  let revision = projection_count(store, aggregate_type, aggregate_id)
  if revision > 0 {
    let latest_id = projection_record_id(aggregate_id, revision)
    if store.get(
        record_type=projection_record_type(aggregate_type),
        record_id=latest_id,
      )
      is None {
      raise ProjectionError::InvalidHistory
    }
  }
  { aggregate_type, aggregate_id, revision, store }
}

///|
pub fn AggregateProjection::append(
  self : AggregateProjection,
  expected_revision~ : Int,
  payload~ : String,
  source_event_id~ : String,
) -> AggregateProjection raise ProjectionError {
  if expected_revision != self.revision + 1 {
    raise ProjectionError::RevisionConflict
  }
  if payload.trim() == "" || expected_revision <= 0 {
    raise ProjectionError::InvalidRevision
  }
  if source_event_id.trim() == "" {
    raise ProjectionError::EmptySourceEventId
  }
  let record = StoredRecord::new(
    record_type=projection_record_type(self.aggregate_type),
    record_id=projection_record_id(self.aggregate_id, expected_revision),
    schema_version=self.store.schema.version,
    payload~,
    source_id=source_event_id,
  ) catch {
    error => raise ProjectionError::Store(error)
  }
  let store = self.store.append(record) catch {
    error => raise ProjectionError::Store(error)
  }
  { ..self, revision: expected_revision, store }
}

///|
pub fn AggregateProjection::latest(
  self : AggregateProjection,
) -> AggregateRevision? {
  if self.revision == 0 {
    return None
  }
  let record_id = projection_record_id(self.aggregate_id, self.revision)
  match
    self.store.get(
      record_type=projection_record_type(self.aggregate_type),
      record_id~,
    ) {
    Some(record) =>
      Some({
        aggregate_type: self.aggregate_type,
        aggregate_id: self.aggregate_id,
        revision: self.revision,
        schema_version: record.schema_version,
        payload: record.payload,
        source_event_id: record.source_id,
      })
    None => None
  }
}

///|
pub fn AggregateProjection::into_store(
  self : AggregateProjection,
) -> RecordStore {
  self.store
}
