///|
fn capability(
  id : String,
  label : String,
  circuit : @product.OperatingCircuit,
  system : @product.CompanySystem,
) -> @product.Capability {
  { id, label, circuit, system }
}

///|
/// The general OPC product. It is deliberately industry-neutral and remains
/// operable without any MoonSuite sibling or vertical extension.
pub fn basic_opc() -> @product.ProductProfile {
  @product.ProductProfile::new(
    profile_id="opc-basic",
    name="MoonProj Basic OPC",
    capabilities=[
      capability("company.identity", "Legal identity", Governance, Principal),
      capability(
        "company.constitution",
        "Charter and reserved matters",
        Governance,
        Principal,
      ),
      capability(
        "company.organization",
        "Organization and accountable roles",
        Governance,
        Principal,
      ),
      capability(
        "company.authority",
        "Delegated and revocable authority",
        Governance,
        Control,
      ),
      capability(
        "resource.registry",
        "Owned and controlled resources",
        Economic,
        Control,
      ),
      capability(
        "party.counterparty",
        "Customers, suppliers, and professionals",
        Economic,
        Market,
      ),
      capability(
        "market.customer",
        "Customer and buyer records",
        Economic,
        Market,
      ),
      capability(
        "market.offer",
        "Offers, pricing, and value measures",
        Economic,
        Market,
      ),
      capability(
        "market.pipeline",
        "Acquisition, pipeline, and renewal",
        Economic,
        Market,
      ),
      capability(
        "work.portfolio",
        "Goals, work, and portfolio decisions",
        Operating,
        Delivery,
      ),
      capability(
        "work.workflow",
        "Workflow, approvals, and exceptions",
        Operating,
        Delivery,
      ),
      capability(
        "delivery.acceptance",
        "Delivery, quality, and acceptance",
        Operating,
        Delivery,
      ),
      capability(
        "commerce.commitment",
        "Commitments and obligations",
        Economic,
        Control,
      ),
      capability(
        "commerce.contract",
        "Contracts and change control",
        Economic,
        Control,
      ),
      capability(
        "commerce.procurement",
        "Sourcing and procurement",
        Economic,
        Market,
      ),
      capability(
        "commerce.exchange",
        "Orders, invoices, payment, and collection",
        Economic,
        Control,
      ),
      capability(
        "finance.budget",
        "Budget and approval limits",
        Governance,
        Control,
      ),
      capability(
        "finance.accounting",
        "Ledger, close, and statements",
        Governance,
        Control,
      ),
      capability(
        "finance.receivable",
        "Receivables and collection",
        Economic,
        Control,
      ),
      capability(
        "finance.payable",
        "Payables and settlement",
        Economic,
        Control,
      ),
      capability(
        "finance.treasury",
        "Cash, banking, and reconciliation",
        Governance,
        Control,
      ),
      capability(
        "finance.financing",
        "Financing and capital structure",
        Economic,
        Control,
      ),
      capability(
        "finance.tax",
        "Tax evidence, filing, and payment",
        Governance,
        Control,
      ),
      capability(
        "investment.portfolio",
        "Mandates, proposals, positions, and performance",
        Economic,
        Control,
      ),
      capability(
        "assurance.evidence",
        "Evidence provenance and audit trail",
        Governance,
        Learning,
      ),
      capability(
        "assurance.risk",
        "Risk, incidents, and independent review",
        Governance,
        Control,
      ),
      capability(
        "learning.procedure",
        "Procedures, experiments, and invalidation",
        Operating,
        Learning,
      ),
      capability(
        "continuity.record",
        "Durable company operating record",
        Governance,
        Continuity,
      ),
      capability(
        "continuity.restore",
        "Backup, restore, and safe degraded mode",
        Operating,
        Continuity,
      ),
      capability(
        "continuity.trustee",
        "Founder-unavailability trustee mode",
        Governance,
        Continuity,
      ),
      capability(
        "intelligence.agent",
        "Bounded agent proposals and execution",
        Operating,
        Delivery,
      ),
      capability(
        "reporting.scorecard",
        "Customer, cash, control, and attention scorecards",
        Governance,
        Learning,
      ),
    ],
  ) catch {
    _ => abort("the built-in OPC profile must be valid")
  }
}
