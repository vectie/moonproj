///|
test "performed commitment produces recognition journal" {
  let grant : @foundation.AuthorityGrant = {
    grant_id: "recognition-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability: "commitment:create",
    scope: "project:p-001",
    max_amount_minor: 100000,
    active: true,
  }
  let draft = Commitment::new(
    commitment_id="commit-recognition-001",
    principal_id="co-001",
    project_scope="project:p-001",
    counterparty_id="supplier-001",
    amount=@finance.Money::new(minor=50000, currency="CNY"),
    actor_id="alice",
    grant~,
  )
  let submitted = draft.transition(
    CommitmentState::Submitted,
    actor_id="alice",
    grant={ ..grant, capability: "commitment:submit" },
  )
  let approved = submitted.transition(
    CommitmentState::Approved,
    actor_id="alice",
    grant={ ..grant, capability: "commitment:approve" },
  )
  let performed = approved.transition(
    CommitmentState::Performed,
    actor_id="alice",
    grant={ ..grant, capability: "commitment:perform" },
  )
  let journal = recognition_journal(
    performed,
    expense_account="6101",
    payable_account="2202",
  )
  assert_eq(journal.postings.length(), 2)
  @finance.validate_journal(journal)
}

///|
test "performed commitment creates a source accounting event" {
  let grant : @foundation.AuthorityGrant = {
    grant_id: "recognition-event-grant",
    principal_id: "co-001",
    actor_id: "alice",
    capability: "commitment:create",
    scope: "project:p-001",
    max_amount_minor: 100000,
    active: true,
  }
  let performed = Commitment::new(
      commitment_id="commit-event-001",
      principal_id="co-001",
      project_scope="project:p-001",
      counterparty_id="supplier-001",
      amount=@finance.Money::new(minor=50000, currency="CNY"),
      actor_id="alice",
      grant~,
    )
    .transition(CommitmentState::Submitted, actor_id="alice", grant={
      ..grant,
      capability: "commitment:submit",
    })
    .transition(CommitmentState::Approved, actor_id="alice", grant={
      ..grant,
      capability: "commitment:approve",
    })
    .transition(CommitmentState::Performed, actor_id="alice", grant={
      ..grant,
      capability: "commitment:perform",
    })
  let event = recognition_event(
    performed,
    event_id="event-commitment-001",
    event_type="commitment.performed",
    expense_account="6101",
    payable_account="2202",
  )
  assert_eq(event.source_type, "commitment")
  assert_eq(event.journal.postings.length(), 2)
}
