///|
pub(all) enum AttentionSeverity {
  Informational
  Normal
  Urgent
  Critical
} derive(Debug, Eq)

///|
pub(all) enum AttentionStatus {
  Open
  Acknowledged
  Resolved
} derive(Debug, Eq)

///|
pub(all) struct AttentionItem {
  attention_id : String
  dedupe_key : String
  principal_id : String
  source_kind : String
  source_id : String
  work_item_id : String
  title : String
  reason : String
  requested_action : String
  severity : AttentionSeverity
  amount_at_risk_minor : Int64
  reversible : Bool
  evidence : Array[String]
  status : AttentionStatus
  created_at_epoch : Int64
  updated_at_epoch : Int64
} derive(Debug, Eq)

///|
pub(all) struct AttentionInbox {
  revision : Int
  items : Array[AttentionItem]
} derive(Debug, Eq)

///|
pub(all) suberror AttentionError {
  Invalid(String)
  NotFound(String)
  AlreadyResolved
} derive(Debug, Eq)

///|
pub fn AttentionInbox::new() -> AttentionInbox {
  { revision: 0, items: [] }
}

///|
fn AttentionItem::validate(self : AttentionItem) -> Unit raise AttentionError {
  if self.attention_id.trim().is_empty() ||
    self.dedupe_key.trim().is_empty() ||
    self.principal_id.trim().is_empty() ||
    self.source_kind.trim().is_empty() ||
    self.source_id.trim().is_empty() ||
    self.title.trim().is_empty() ||
    self.reason.trim().is_empty() ||
    self.requested_action.trim().is_empty() ||
    self.amount_at_risk_minor < 0 ||
    self.created_at_epoch < 0 ||
    self.updated_at_epoch < self.created_at_epoch {
    raise Invalid("attention item identity, action, risk, or time is invalid")
  }
}

///|
pub fn AttentionInbox::upsert(
  self : AttentionInbox,
  item : AttentionItem,
) -> AttentionInbox raise AttentionError {
  item.validate()
  let items = self.items.copy()
  for index, current in items {
    if current.dedupe_key == item.dedupe_key && current.status != Resolved {
      items[index] = {
        ..item,
        attention_id: current.attention_id,
        created_at_epoch: current.created_at_epoch,
      }
      return { revision: self.revision + 1, items }
    }
  }
  items.push(item)
  { revision: self.revision + 1, items }
}

///|
pub fn AttentionInbox::acknowledge(
  self : AttentionInbox,
  attention_id~ : String,
  at_epoch~ : Int64,
) -> AttentionInbox raise AttentionError {
  let items = self.items.copy()
  for index, item in items {
    if item.attention_id == attention_id {
      if item.status is Resolved {
        raise AlreadyResolved
      }
      items[index] = {
        ..item,
        status: Acknowledged,
        updated_at_epoch: at_epoch,
      }
      return { revision: self.revision + 1, items }
    }
  }
  raise NotFound(attention_id)
}

///|
pub fn AttentionInbox::resolve(
  self : AttentionInbox,
  attention_id~ : String,
  resolution_evidence~ : Array[String],
  at_epoch~ : Int64,
) -> AttentionInbox raise AttentionError {
  if resolution_evidence.is_empty() {
    raise Invalid("resolution evidence is required")
  }
  let items = self.items.copy()
  for index, item in items {
    if item.attention_id == attention_id {
      if item.status is Resolved {
        raise AlreadyResolved
      }
      let evidence = item.evidence.copy()
      for reference in resolution_evidence {
        if reference.trim().is_empty() || evidence.contains(reference) {
          raise Invalid("resolution evidence must be non-empty and unique")
        }
        evidence.push(reference)
      }
      items[index] = {
        ..item,
        status: Resolved,
        evidence,
        updated_at_epoch: at_epoch,
      }
      return { revision: self.revision + 1, items }
    }
  }
  raise NotFound(attention_id)
}

///|
pub fn AttentionInbox::open_items(
  self : AttentionInbox,
) -> Array[AttentionItem] {
  self.items.filter(item => item.status != Resolved)
}
