///|
fn extension_capability(
  id : String,
  label : String,
  circuit : @product.OperatingCircuit,
  system : @product.CompanySystem,
) -> @product.Capability {
  { id, label, circuit, system }
}

///|
/// The working erp_new real-estate deployment, retained as a first-class
/// extension and as the broad migration acceptance source.
pub fn real_estate_erp() -> @product.ExtensionPack {
  @product.ExtensionPack::new(
    extension_id="real-estate-erp",
    name="Real Estate Development ERP",
    base_profile_id="opc-basic",
    source_system="erp_new",
    mount_path="/extensions/real-estate",
    capabilities=[
      extension_capability(
        "real_estate.development",
        "Development project lifecycle",
        Operating,
        Delivery,
      ),
      extension_capability(
        "real_estate.cbs",
        "Development cost breakdown structure",
        Economic,
        Control,
      ),
      extension_capability(
        "real_estate.target_cost",
        "Target and dynamic development cost",
        Economic,
        Control,
      ),
      extension_capability(
        "real_estate.tender",
        "Construction tender planning and award",
        Economic,
        Market,
      ),
      extension_capability(
        "real_estate.property_inventory",
        "Property and saleable inventory",
        Economic,
        Market,
      ),
      extension_capability(
        "real_estate.subscription",
        "Property subscription and reservation",
        Economic,
        Market,
      ),
      extension_capability(
        "real_estate.mortgage",
        "Mortgage processing",
        Economic,
        Control,
      ),
      extension_capability(
        "real_estate.engineering",
        "Engineering progress and output",
        Operating,
        Delivery,
      ),
    ],
    route_prefixes=[
      "/projects", "/project-plan", "/project/progress", "/investment", "/dynamic-cost",
      "/cost-dashboard-v3", "/cbs", "/tender", "/sales/subscriptions", "/sales/mortgages",
    ],
  ) catch {
    _ => abort("the built-in real-estate extension must be valid")
  }
}
