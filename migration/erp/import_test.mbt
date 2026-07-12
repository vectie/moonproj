///|
fn import_grant(
  capability : String,
  scope : String,
) -> @foundation.AuthorityGrant {
  {
    grant_id: "erp-import-grant",
    principal_id: "bu-001",
    actor_id: "migration",
    capability,
    scope,
    max_amount_minor: 1000000,
    active: true,
  }
}

///|
test "ERP fixtures map project, contract, and cost rows" {
  let business_unit = import_business_unit(
    {
      bu_guid: "bu-001",
      parent_guid: None,
      bu_code: "BU-001",
      bu_name: "Legacy Company",
      bu_type: "company",
    },
    actor_id="migration",
    grant=import_grant("organization:create", "organization:bu-001"),
  )
  assert_true(business_unit.kind == @organization.OrganizationKind::Company)

  let project = import_project(
    {
      proj_guid: "p-legacy-001",
      bu_guid: "bu-001",
      proj_code: "P-001",
      proj_name: "Legacy Project",
    },
    actor_id="migration",
    grant=import_grant("project:create", "project:p-legacy-001"),
  )
  assert_eq(project.project_id, "p-legacy-001")

  let contract = import_contract(
    {
      contract_guid: "ct-legacy-001",
      bu_guid: "bu-001",
      proj_guid: "p-legacy-001",
      provider_guid: "provider-001",
      ht_amount_minor: 500000,
      currency: "CNY",
    },
    actor_id="migration",
    grant=import_grant("commitment:create", "project:p-legacy-001"),
  )
  assert_eq(contract.commitment_id, "ct-legacy-001")

  let cost = import_cost({
    currency: "CNY",
    direct_minor: 100000,
    indirect_minor: 20000,
    contingency_minor: 5000,
    other_minor: 3000,
  })
  assert_eq(cost.total_minor, 128000)
}

///|
test "ERP importer preserves invalid cost rows as errors" {
  try
    import_cost({
      currency: "CNY",
      direct_minor: -1,
      indirect_minor: 0,
      contingency_minor: 0,
      other_minor: 0,
    })
  catch {
    ErpImportError::Cost(_) => ()
    _ => fail("wrong import error")
  } noraise {
    _ => fail("expected import error")
  }
}

///|
test "ERP rows become schema-bound durable migration envelopes" {
  let schema = @schema.SchemaState::initial()
  let migration = @schema.MigrationStep::new(
    version=1,
    migration_id="V1__foundation",
    checksum="sha256:one",
    description="Create foundation tables",
  )
  let project_row : LegacyProjectRow = {
    proj_guid: "p-envelope-001",
    bu_guid: "bu-001",
    proj_code: "P-ENV-001",
    proj_name: "Envelope Project",
  }
  let contract_row : LegacyContractRow = {
    contract_guid: "ct-envelope-001",
    bu_guid: "bu-001",
    proj_guid: "p-envelope-001",
    provider_guid: "provider-001",
    ht_amount_minor: 500000,
    currency: "CNY",
  }
  let store = @store.RecordStore::new(schema)
    .migrate(migration)
    .append_batch([
      project_record(project_row, schema_version=1),
      contract_record(contract_row, schema_version=1),
      cost_record(
        {
          currency: "CNY",
          direct_minor: 100000,
          indirect_minor: 20000,
          contingency_minor: 5000,
          other_minor: 3000,
        },
        cost_id="cost-envelope-001",
        schema_version=1,
      ),
    ])
  assert_eq(store.count_type(record_type="legacy/project"), 1)
  assert_eq(store.count_type(record_type="legacy/contract"), 1)
  let snapshot = store.to_snapshot()
  let restored = @store.RecordStore::from_snapshot(snapshot)
  assert_eq(restored.records.length(), 3)
  assert_true(snapshot.contains("erp:ep_project:p-envelope-001"))
}

///|
test "ERP fixtures translate supplier, tender, milestone, invoice, expense, and loan rows" {
  let supplier_grant = import_grant("supplier:create", "company:bu-001")
  let supplier = import_supplier(
    {
      provider_guid: "provider-001",
      bu_guid: "bu-001",
      provider_code: "SUP-001",
      provider_name: "Legacy Supplier",
      category_code: "construction",
    },
    actor_id="migration",
    grant=supplier_grant,
  )
  assert_eq(supplier.supplier_id, "provider-001")

  let tender = import_tender(
    {
      tender_guid: "tender-001",
      bu_guid: "bu-001",
      proj_guid: "p-legacy-001",
      tender_name: "Legacy Tender",
      category: "construction",
      estimated_amount_minor: 300000,
      currency: "CNY",
    },
    actor_id="migration",
    grant=import_grant("tender:create", "project:p-legacy-001"),
  )
  assert_eq(tender.tender_id, "tender-001")

  let commitment = import_contract(
    {
      contract_guid: "ct-legacy-002",
      bu_guid: "bu-001",
      proj_guid: "p-legacy-001",
      provider_guid: "provider-001",
      ht_amount_minor: 500000,
      currency: "CNY",
    },
    actor_id="migration",
    grant=import_grant("commitment:create", "project:p-legacy-001"),
  )
  let milestone = import_milestone(
    {
      milestone_guid: "milestone-001",
      contract_guid: "ct-legacy-002",
      sequence: 1,
      node_name: "Legacy completion",
      trigger_type: "progress",
      plan_amount_minor: 200000,
      plan_pct_bps: 4000L,
    },
    commitment,
    actor_id="migration",
    grant=import_grant("milestone:create", "project:p-legacy-001"),
  )
  assert_eq(milestone.commitment_id, "ct-legacy-002")

  let invoice = import_invoice(
    {
      invoice_guid: "invoice-001",
      bu_guid: "bu-001",
      customer_guid: "customer-001",
      source_id: "erp:invoice_out:invoice-001",
      amount_minor: 120000,
      currency: "CNY",
    },
    actor_id="migration",
    grant=import_grant("invoice:create", "customer:customer-001"),
  )
  assert_eq(invoice.invoice_id, "invoice-001")

  let expense = import_expense(
    {
      expense_guid: "expense-001",
      bu_guid: "bu-001",
      employee_guid: "employee-001",
      proj_guid: "p-legacy-001",
      cost_subject: "R0-01",
      amount_minor: 8000,
      currency: "CNY",
    },
    actor_id="migration",
    grant=import_grant("expense:create", "employee:employee-001"),
  )
  assert_eq(expense.expense_id, "expense-001")

  let advance = import_advance(
    {
      loan_guid: "loan-001",
      bu_guid: "bu-001",
      employee_guid: "employee-001",
      amount_minor: 20000,
      currency: "CNY",
    },
    actor_id="migration",
    grant=import_grant("advance:create", "employee:employee-001"),
  )
  assert_eq(advance.advance_id, "loan-001")
}
