///|
fn profile_fixture() -> ProductProfile raise {
  ProductProfile::new(profile_id="moonproj", name="MoonProj", capabilities=[
    {
      id: "company-governance",
      label: "Company governance",
      circuit: Governance,
      system: Principal,
    },
  ])
}

///|
fn extension_fixture() -> ExtensionPack raise {
  ExtensionPack::new(
    extension_id="professional-services-plus",
    name="Professional Services Plus",
    base_profile_id="moonproj",
    source_system="moonproj-packs",
    mount_path="/packs/professional-services-plus",
    capabilities=[
      {
        id: "professional-services-advanced",
        label: "Advanced professional service workflow",
        circuit: Operating,
        system: Delivery,
      },
    ],
    route_prefixes=["/services/advanced"],
  )
}

///|
fn adoption_fixture() -> WorkflowAdoptionEvidence {
  {
    principal_id: "opc-001",
    product_id: "moonproj",
    workflow_id: "professional-service-shadow-001",
    decision: Pass,
    product_in_gate_receipt: "receipt/product-in-gate-pass-001",
    accepted_customer_evidence: ["receipt/customer-acceptance-001"],
    owner_id: "owner-001",
    adoption_count: 1,
    successful_completions: 1,
    reviewed_at_epoch: 100L,
  }
}

///|
test "transactional pack activates only after the first adopted workflow" {
  let transactional : TransactionalPack = {
    pack: extension_fixture(),
    price_currency: "CNY",
    price_minor: 9900L,
    transaction_provider: "verified-pack-store",
  }
  let (profile, receipt) = profile_fixture().activate_transactional(
    transactional,
    adoption_fixture(),
    payment_receipt="payment/pack-001",
    activated_by="owner-001",
    activated_at_epoch=200L,
  )
  assert_true(profile.has_extension("professional-services-plus"))
  assert_eq(receipt.workflow_id, "professional-service-shadow-001")
  let not_adopted = { ..adoption_fixture(), adoption_count: 0 }
  let second_profile = profile_fixture()
  try
    second_profile.activate_transactional(
      transactional,
      not_adopted,
      payment_receipt="payment/pack-002",
      activated_by="owner-001",
      activated_at_epoch=200L,
    )
  catch {
    FirstWorkflowAdoptionRequired => ()
    _ => fail("expected first-workflow gate")
  } noraise {
    _ => fail("expected pack activation to fail")
  }
}

///|
test "staffing and marketplace remain behind Product In-Gate and independent review" {
  let review : AutonomousExpansionReview = {
    review_id: "review-autonomy-001",
    principal_id: "opc-001",
    product_id: "moonproj",
    feature: AutonomousStaffing,
    requested_by: "owner-001",
    reviewed_by: "reviewer-002",
    scope: "professional-service-shadow",
    risk_evidence: ["evidence/autonomy-risk-001"],
    approved: true,
    reviewed_at_epoch: 200L,
  }
  let receipt = authorize_autonomous_expansion(adoption_fixture(), review)
  assert_true(receipt.enabled)
  assert_true(!receipt.company_authority_granted)
  try
    authorize_autonomous_expansion(adoption_fixture(), {
      ..review,
      reviewed_by: "owner-001",
    })
  catch {
    IndependentReviewRequired => ()
    _ => fail("expected independent review gate")
  } noraise {
    _ => fail("expected self-reviewed staffing to fail")
  }
  try
    authorize_autonomous_expansion(
      { ..adoption_fixture(), decision: Experiment },
      review,
    )
  catch {
    ProductInGatePassRequired => ()
    _ => fail("expected Product In-Gate pass")
  } noraise {
    _ => fail("expected experiment-stage marketplace/staffing to fail")
  }
}
