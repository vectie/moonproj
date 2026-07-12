///|
/// Convert a validated legacy row into the target's opaque record envelope.
/// Domain import functions remain responsible for authority and state-machine
/// checks; this layer makes the source identity and payload durable for a
/// repeatable migration run.
fn legacy_record(
  record_type~ : String,
  record_id~ : String,
  source_id~ : String,
  schema_version~ : Int,
  payload~ : String,
) -> @store.StoredRecord raise ErpImportError {
  @store.StoredRecord::new(
    record_type~,
    record_id~,
    schema_version~,
    payload~,
    source_id~,
  ) catch {
    error => raise ErpImportError::Store(error)
  }
}

///|
fn json_number(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
/// A raw source row used when a table has not yet earned a domain translator.
/// The payload is preserved as supplied by the read-only extractor and is
/// never treated as an approved company aggregate.
pub(all) struct LegacyRawRow {
  table_name : String
  record_id : String
  payload : String
} derive(Debug, Eq)

///|
pub fn raw_record(
  row : LegacyRawRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  if row.table_name.trim() == "" || row.record_id.trim() == "" {
    raise ErpImportError::MissingIdentifier
  }
  legacy_record(
    record_type="legacy/raw/" + row.table_name,
    record_id=row.record_id,
    source_id="erp:" + row.table_name + ":" + row.record_id,
    schema_version~,
    payload=row.payload,
  )
}

///|
/// Stage a raw table batch before it enters a migration manifest. The batch
/// keeps source rows opaque, but still enforces stable table/primary-key
/// identity so duplicate exports cannot be mistaken for independent evidence.
pub fn raw_records(
  rows : Array[LegacyRawRow],
  schema_version~ : Int,
) -> Array[@store.StoredRecord] raise ErpImportError {
  let records : Array[@store.StoredRecord] = []
  let seen_records : Array[String] = []
  let seen_sources : Array[String] = []
  for row in rows {
    let record_key = row.table_name + "\u{1f}" + row.record_id
    let source_key = "erp:" + row.table_name + ":" + row.record_id
    for existing in seen_records {
      if existing == record_key {
        raise ErpImportError::DuplicateRecord
      }
    }
    for existing in seen_sources {
      if existing == source_key {
        raise ErpImportError::DuplicateSource
      }
    }
    let record = raw_record(row, schema_version~)
    seen_records.push(record_key)
    seen_sources.push(source_key)
    records.push(record)
  }
  records
}

///|
pub fn business_unit_record(
  row : LegacyBusinessUnitRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  let parent : Json = match row.parent_guid {
    Some(value) => Json::string(value)
    None => Json::null()
  }
  legacy_record(
    record_type="legacy/business_unit",
    record_id=row.bu_guid,
    source_id="erp:mu_business_unit:" + row.bu_guid,
    schema_version~,
    payload=Json::object({
      "bu_guid": Json::string(row.bu_guid),
      "parent_guid": parent,
      "bu_code": Json::string(row.bu_code),
      "bu_name": Json::string(row.bu_name),
      "bu_type": Json::string(row.bu_type),
    }).stringify(),
  )
}

///|
pub fn project_record(
  row : LegacyProjectRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  legacy_record(
    record_type="legacy/project",
    record_id=row.proj_guid,
    source_id="erp:ep_project:" + row.proj_guid,
    schema_version~,
    payload=Json::object({
      "proj_guid": Json::string(row.proj_guid),
      "bu_guid": Json::string(row.bu_guid),
      "proj_code": Json::string(row.proj_code),
      "proj_name": Json::string(row.proj_name),
    }).stringify(),
  )
}

///|
pub fn contract_record(
  row : LegacyContractRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  legacy_record(
    record_type="legacy/contract",
    record_id=row.contract_guid,
    source_id="erp:cb_contract:" + row.contract_guid,
    schema_version~,
    payload=Json::object({
      "contract_guid": Json::string(row.contract_guid),
      "bu_guid": Json::string(row.bu_guid),
      "proj_guid": Json::string(row.proj_guid),
      "provider_guid": Json::string(row.provider_guid),
      "ht_amount_minor": json_number(row.ht_amount_minor),
      "currency": Json::string(row.currency),
    }).stringify(),
  )
}

///|
pub fn cost_record(
  row : LegacyCostRow,
  cost_id~ : String,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  legacy_record(
    record_type="legacy/cost",
    record_id=cost_id,
    source_id="erp:cb_cost:" + cost_id,
    schema_version~,
    payload=Json::object({
      "currency": Json::string(row.currency),
      "direct_minor": json_number(row.direct_minor),
      "indirect_minor": json_number(row.indirect_minor),
      "contingency_minor": json_number(row.contingency_minor),
      "other_minor": json_number(row.other_minor),
    }).stringify(),
  )
}

///|
pub fn supplier_record(
  row : LegacySupplierRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  legacy_record(
    record_type="legacy/supplier",
    record_id=row.provider_guid,
    source_id="erp:srm_provider:" + row.provider_guid,
    schema_version~,
    payload=Json::object({
      "provider_guid": Json::string(row.provider_guid),
      "bu_guid": Json::string(row.bu_guid),
      "provider_code": Json::string(row.provider_code),
      "provider_name": Json::string(row.provider_name),
      "category_code": Json::string(row.category_code),
    }).stringify(),
  )
}

///|
pub fn tender_record(
  row : LegacyTenderRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  legacy_record(
    record_type="legacy/tender",
    record_id=row.tender_guid,
    source_id="erp:tender_plan:" + row.tender_guid,
    schema_version~,
    payload=Json::object({
      "tender_guid": Json::string(row.tender_guid),
      "bu_guid": Json::string(row.bu_guid),
      "proj_guid": Json::string(row.proj_guid),
      "tender_name": Json::string(row.tender_name),
      "category": Json::string(row.category),
      "estimated_amount_minor": json_number(row.estimated_amount_minor),
      "currency": Json::string(row.currency),
    }).stringify(),
  )
}

///|
pub fn milestone_record(
  row : LegacyMilestoneRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  legacy_record(
    record_type="legacy/milestone",
    record_id=row.milestone_guid,
    source_id="erp:cb_contract_milestone:" + row.milestone_guid,
    schema_version~,
    payload=Json::object({
      "milestone_guid": Json::string(row.milestone_guid),
      "contract_guid": Json::string(row.contract_guid),
      "sequence": Json::number(
        row.sequence.to_double(),
        repr=row.sequence.to_string(),
      ),
      "node_name": Json::string(row.node_name),
      "trigger_type": Json::string(row.trigger_type),
      "plan_amount_minor": json_number(row.plan_amount_minor),
      "plan_pct_bps": json_number(row.plan_pct_bps),
    }).stringify(),
  )
}

///|
pub fn invoice_record(
  row : LegacyInvoiceRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  legacy_record(
    record_type="legacy/invoice",
    record_id=row.invoice_guid,
    source_id=row.source_id,
    schema_version~,
    payload=Json::object({
      "invoice_guid": Json::string(row.invoice_guid),
      "bu_guid": Json::string(row.bu_guid),
      "customer_guid": Json::string(row.customer_guid),
      "amount_minor": json_number(row.amount_minor),
      "currency": Json::string(row.currency),
    }).stringify(),
  )
}

///|
pub fn expense_record(
  row : LegacyExpenseRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  legacy_record(
    record_type="legacy/expense",
    record_id=row.expense_guid,
    source_id="erp:vcb_expense:" + row.expense_guid,
    schema_version~,
    payload=Json::object({
      "expense_guid": Json::string(row.expense_guid),
      "bu_guid": Json::string(row.bu_guid),
      "employee_guid": Json::string(row.employee_guid),
      "proj_guid": Json::string(row.proj_guid),
      "cost_subject": Json::string(row.cost_subject),
      "amount_minor": json_number(row.amount_minor),
      "currency": Json::string(row.currency),
    }).stringify(),
  )
}

///|
pub fn advance_record(
  row : LegacyAdvanceRow,
  schema_version~ : Int,
) -> @store.StoredRecord raise ErpImportError {
  legacy_record(
    record_type="legacy/advance",
    record_id=row.loan_guid,
    source_id="erp:vcb_loan_simple:" + row.loan_guid,
    schema_version~,
    payload=Json::object({
      "loan_guid": Json::string(row.loan_guid),
      "bu_guid": Json::string(row.bu_guid),
      "employee_guid": Json::string(row.employee_guid),
      "amount_minor": json_number(row.amount_minor),
      "currency": Json::string(row.currency),
    }).stringify(),
  )
}
