///|
/// A durable link between an operational source event and its validated journal
/// projection. The journal remains immutable; the link makes reconciliation and
/// replay visible without making source aggregates depend on the ledger.
pub(all) struct AccountingEvent {
  event_id : String
  principal_id : String
  source_type : String
  source_id : String
  event_type : String
  journal : @finance.JournalEntry
} derive(Debug, Eq)

///|
pub(all) struct AccountingEventLog {
  events : Array[AccountingEvent]
} derive(Debug, Eq)

///|
pub(all) suberror AccountingEventError {
  EmptyIdentifier
  DuplicateEvent
  DuplicateSource
  Journal(@finance.LedgerError)
  Store(@store.StoreError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn AccountingEvent::new(
  event_id~ : String,
  principal_id~ : String,
  source_type~ : String,
  source_id~ : String,
  event_type~ : String,
  journal~ : @finance.JournalEntry,
) -> AccountingEvent raise AccountingEventError {
  if event_id.trim() == "" ||
    principal_id.trim() == "" ||
    source_type.trim() == "" ||
    source_id.trim() == "" ||
    event_type.trim() == "" {
    raise AccountingEventError::EmptyIdentifier
  }
  @finance.validate_journal(journal) catch {
    error => raise AccountingEventError::Journal(error)
  }
  { event_id, principal_id, source_type, source_id, event_type, journal }
}

///|
pub fn AccountingEventLog::empty() -> AccountingEventLog {
  { events: [] }
}

///|
pub fn AccountingEventLog::append(
  self : AccountingEventLog,
  event : AccountingEvent,
  scope~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> AccountingEventLog raise AccountingEventError {
  for existing in self.events {
    if existing.event_id == event.event_id {
      raise AccountingEventError::DuplicateEvent
    }
    if existing.source_type == event.source_type &&
      existing.source_id == event.source_id {
      raise AccountingEventError::DuplicateSource
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=event.principal_id,
    actor_id~,
    capability="accounting:event:append",
    scope~,
    amount_minor=event.journal.postings[0].amount.minor,
  ) catch {
    error => raise AccountingEventError::NotAuthorized(error)
  }
  let events = self.events.copy()
  events.push(event)
  { events, }
}
