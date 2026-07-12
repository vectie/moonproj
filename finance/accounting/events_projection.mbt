///|
fn posting_side_name(side : @finance.PostingSide) -> String {
  match side {
    @finance.PostingSide::Debit => "debit"
    @finance.PostingSide::Credit => "credit"
  }
}

///|
fn accounting_event_payload(event : AccountingEvent) -> String {
  let postings : Array[Json] = []
  for posting in event.journal.postings {
    postings.push(
      Json::object({
        "account": Json::string(posting.account),
        "side": Json::string(posting_side_name(posting.side)),
        "amount_minor": Json::number(
          posting.amount.minor.to_double(),
          repr=posting.amount.minor.to_string(),
        ),
        "currency": Json::string(posting.amount.currency),
      }),
    )
  }
  Json::object({
    "event_id": Json::string(event.event_id),
    "principal_id": Json::string(event.principal_id),
    "source_type": Json::string(event.source_type),
    "source_id": Json::string(event.source_id),
    "event_type": Json::string(event.event_type),
    "journal_entry_id": Json::string(event.journal.entry_id),
    "journal_description": Json::string(event.journal.description),
    "postings": Json::array(postings),
  }).stringify()
}

///|
/// Persist a validated source-to-journal link as an immutable record. The
/// event log remains the authority for replay checks; this is its durable
/// envelope for migration and reconciliation queries.
pub fn AccountingEvent::to_record(
  self : AccountingEvent,
  schema_version~ : Int,
) -> @store.StoredRecord raise AccountingEventError {
  @store.StoredRecord::new(
    record_type="accounting_event",
    record_id=self.event_id,
    schema_version~,
    payload=accounting_event_payload(self),
    source_id="company:accounting-event:" + self.event_id,
  ) catch {
    error => raise AccountingEventError::Store(error)
  }
}

///|
pub fn AccountingEventLog::to_records(
  self : AccountingEventLog,
  schema_version~ : Int,
) -> Array[@store.StoredRecord] raise AccountingEventError {
  let records : Array[@store.StoredRecord] = []
  for event in self.events {
    records.push(event.to_record(schema_version~))
  }
  records
}
