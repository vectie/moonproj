///|
fn approve_with_actor_separation(
  commitment : @commitment.Commitment,
  submitted_by : String,
  approved_by : String,
  grant : @foundation.AuthorityGrant,
) -> @commitment.Commitment raise {
  if submitted_by == approved_by {
    raise SmokeError::SelfApproval
  }
  commitment.transition(Approved, actor_id=approved_by, grant~)
}

///|
#derive(Debug, Eq)
enum CollectionSmokeState {
  Due
  Overdue
  Disputed
  WrittenOff
  Recovered
}

///|
#derive(Debug, Eq)
struct CollectionSmoke {
  receivable_id : String
  amount_minor : Int64
  recovered_minor : Int64
  state : CollectionSmokeState
}

///|
fn CollectionSmoke::new(
  receivable_id : String,
  amount_minor : Int64,
) -> CollectionSmoke raise SmokeError {
  if receivable_id.trim().is_empty() || amount_minor <= 0 {
    raise InvalidCollectionState
  }
  { receivable_id, amount_minor, recovered_minor: 0L, state: Due, }
}

///|
fn CollectionSmoke::mark_overdue(
  self : CollectionSmoke,
) -> CollectionSmoke raise SmokeError {
  if self.state != Due {
    raise InvalidCollectionState
  }
  { ..self, state: Overdue, }
}

///|
fn CollectionSmoke::dispute(
  self : CollectionSmoke,
) -> CollectionSmoke raise SmokeError {
  if self.state != Overdue {
    raise InvalidCollectionState
  }
  { ..self, state: Disputed, }
}

///|
fn CollectionSmoke::write_off(
  self : CollectionSmoke,
) -> CollectionSmoke raise SmokeError {
  if self.state != Disputed {
    raise InvalidCollectionState
  }
  { ..self, state: WrittenOff, }
}

///|
fn CollectionSmoke::recover(
  self : CollectionSmoke,
  amount_minor : Int64,
) -> CollectionSmoke raise SmokeError {
  if self.state != WrittenOff ||
    amount_minor <= 0 ||
    amount_minor > self.amount_minor {
    raise InvalidCollectionState
  }
  { ..self, recovered_minor: amount_minor, state: Recovered, }
}

///|
test "smoke policy blocks founder self-approval before core transition" {
  let scope = "project:smoke-sod"
  let draft = @commitment.Commitment::new(
    commitment_id="commitment-smoke-sod",
    principal_id="opc-market-studio",
    project_scope=scope,
    counterparty_id="supplier-smoke",
    amount=smoke_cny(100000L),
    actor_id="founder",
    grant=smoke_authority(
      "grant-smoke-sod-create", "founder", "commitment:create", scope, 100000L,
    ),
  )
  let submitted = draft.transition(
    Submitted,
    actor_id="founder",
    grant=smoke_authority(
      "grant-smoke-sod-submit", "founder", "commitment:submit", scope, 100000L,
    ),
  )
  try
    approve_with_actor_separation(
      submitted,
      "founder",
      "founder",
      smoke_authority(
        "grant-smoke-sod-self-approve", "founder", "commitment:approve", scope, 100000L,
      ),
    )
  catch {
    SelfApproval => ()
    _ => fail("expected smoke policy to reject self-approval")
  } noraise {
    _ => fail("self-approval must not reach the core transition")
  }
  let approved = approve_with_actor_separation(
    submitted,
    "founder",
    "commercial-reviewer",
    smoke_authority(
      "grant-smoke-sod-independent-approve", "commercial-reviewer", "commitment:approve",
      scope, 100000L,
    ),
  )
  assert_eq(approved.state, Approved)
}

///|
test "collection adapter exercises overdue dispute write-off and recovery" {
  let recovered = CollectionSmoke::new("receivable-smoke-bad-debt", 250000L)
    .mark_overdue()
    .dispute()
    .write_off()
    .recover(100000L)
  assert_eq(recovered.state, Recovered)
  assert_eq(recovered.recovered_minor, 100000L)
  assert_eq(recovered.amount_minor - recovered.recovered_minor, 150000L)
}
