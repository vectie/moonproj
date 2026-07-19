///|
/// The three circuits that must remain healthy for a viable OPC.
pub(all) enum OperatingCircuit {
  Economic
  Operating
  Governance
} derive(Debug, Eq)

///|
/// The minimum organizational systems that exist even when one person holds
/// several roles.
pub(all) enum CompanySystem {
  Principal
  Market
  Delivery
  Control
  Learning
  Continuity
} derive(Debug, Eq)

///|
/// A stable product capability. IDs are the compatibility contract used by
/// profiles and extension packs; labels may evolve without changing the ID.
pub(all) struct Capability {
  id : String
  label : String
  circuit : OperatingCircuit
  system : CompanySystem
} derive(Debug, Eq)

///|
/// A standalone product profile. The base OPC profile has no active extension.
pub(all) struct ProductProfile {
  profile_id : String
  name : String
  capabilities : Array[Capability]
  active_extensions : Array[String]
} derive(Debug, Eq)

///|
/// A domain pack that adds capability without becoming a dependency of the
/// generic OPC core.
pub(all) struct ExtensionPack {
  extension_id : String
  name : String
  base_profile_id : String
  source_system : String
  mount_path : String
  capabilities : Array[Capability]
  route_prefixes : Array[String]
} derive(Debug, Eq)

///|
pub(all) suberror ProductCatalogError {
  EmptyIdentifier
  DuplicateCapability(String)
  IncompatibleBase(expected~ : String, actual~ : String)
  ExtensionAlreadyActive(String)
} derive(Debug, Eq)

///|
fn validate_capabilities(
  capabilities : Array[Capability],
) -> Unit raise ProductCatalogError {
  for index, capability in capabilities {
    if capability.id.trim().is_empty() || capability.label.trim().is_empty() {
      raise EmptyIdentifier
    }
    for previous in 0..<index {
      if capabilities[previous].id == capability.id {
        raise DuplicateCapability(capability.id)
      }
    }
  }
}

///|
pub fn ProductProfile::new(
  profile_id~ : String,
  name~ : String,
  capabilities~ : Array[Capability],
) -> ProductProfile raise ProductCatalogError {
  if profile_id.trim().is_empty() || name.trim().is_empty() {
    raise EmptyIdentifier
  }
  validate_capabilities(capabilities)
  { profile_id, name, capabilities, active_extensions: [] }
}

///|
pub fn ExtensionPack::new(
  extension_id~ : String,
  name~ : String,
  base_profile_id~ : String,
  source_system~ : String,
  mount_path~ : String,
  capabilities~ : Array[Capability],
  route_prefixes~ : Array[String],
) -> ExtensionPack raise ProductCatalogError {
  if extension_id.trim().is_empty() ||
    name.trim().is_empty() ||
    base_profile_id.trim().is_empty() ||
    source_system.trim().is_empty() ||
    mount_path.trim().is_empty() {
    raise EmptyIdentifier
  }
  validate_capabilities(capabilities)
  {
    extension_id,
    name,
    base_profile_id,
    source_system,
    mount_path,
    capabilities,
    route_prefixes,
  }
}

///|
pub fn ProductProfile::includes(
  self : ProductProfile,
  capability_id : String,
) -> Bool {
  for capability in self.capabilities {
    if capability.id == capability_id {
      return true
    }
  }
  false
}

///|
pub fn ProductProfile::has_extension(
  self : ProductProfile,
  extension_id : String,
) -> Bool {
  for active in self.active_extensions {
    if active == extension_id {
      return true
    }
  }
  false
}

///|
/// Activate a pack without allowing it to overwrite a core capability or a
/// previously activated pack.
pub fn ProductProfile::activate(
  self : ProductProfile,
  extension : ExtensionPack,
) -> ProductProfile raise ProductCatalogError {
  if extension.base_profile_id != self.profile_id {
    raise IncompatibleBase(
      expected=extension.base_profile_id,
      actual=self.profile_id,
    )
  }
  if self.has_extension(extension.extension_id) {
    raise ExtensionAlreadyActive(extension.extension_id)
  }
  let capabilities = self.capabilities.copy()
  for capability in extension.capabilities {
    if self.includes(capability.id) {
      raise DuplicateCapability(capability.id)
    }
    capabilities.push(capability)
  }
  let active_extensions = self.active_extensions.copy()
  active_extensions.push(extension.extension_id)
  { ..self, capabilities, active_extensions }
}
