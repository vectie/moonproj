///|
/// The kind of principal that may own records or receive authority.
pub(all) enum PrincipalKind {
  Entity
  Person
  Service
} derive(Debug, Eq)

///|
/// A stable institutional or acting identity.
pub(all) struct Principal {
  id : String
  kind : PrincipalKind
} derive(Debug, Eq)

///|
/// A legal entity that owns resources, obligations, and accounting books.
pub(all) struct LegalEntity {
  entity_id : String
  legal_name : String
  functional_currency : String
} derive(Debug, Eq)

///|
/// A credential-free company user identity. Authentication secrets and
/// privilege grants deliberately live outside this migration-safe record.
pub(all) enum UserAccountState {
  Active
  Disabled
} derive(Debug, Eq)

///|
pub(all) struct UserAccount {
  user_id : String
  user_code : String
  display_name : String
  principal_id : String
  business_unit_id : String
  department_id : String?
  state : UserAccountState
} derive(Debug, Eq)

///|
pub(all) struct UserDirectory {
  users : Array[UserAccount]
} derive(Debug, Eq)

///|
/// Authority granted by an institutional principal to an actor.
pub(all) struct AuthorityGrant {
  grant_id : String
  principal_id : String
  actor_id : String
  capability : String
  scope : String
  max_amount_minor : Int64
  active : Bool
} derive(Debug, Eq)

///|
pub(all) suberror IdentityError {
  EmptyIdentifier(String)
  EmptyName
  InvalidCurrency(String)
  DuplicateUser
  NotAuthorized(AuthorityError)
} derive(Debug, Eq)

///|
pub(all) suberror AuthorityError {
  InactiveGrant
  WrongActor
  WrongPrincipal
  WrongCapability
  ScopeMismatch
  AmountExceeded
} derive(Debug, Eq)

///|
pub fn Principal::new(
  id~ : String,
  kind~ : PrincipalKind,
) -> Principal raise IdentityError {
  if id.trim() == "" {
    raise IdentityError::EmptyIdentifier(id)
  }
  { id, kind }
}

///|
pub fn LegalEntity::new(
  entity_id~ : String,
  legal_name~ : String,
  functional_currency~ : String,
) -> LegalEntity raise IdentityError {
  if entity_id.trim() == "" {
    raise IdentityError::EmptyIdentifier(entity_id)
  }
  if legal_name.trim() == "" {
    raise IdentityError::EmptyName
  }
  if functional_currency.length() != 3 {
    raise IdentityError::InvalidCurrency(functional_currency)
  }
  { entity_id, legal_name, functional_currency }
}

///|
pub fn UserAccount::new(
  user_id~ : String,
  user_code~ : String,
  display_name~ : String,
  principal_id~ : String,
  business_unit_id~ : String,
  department_id~ : String?,
  enabled~ : Bool,
  actor_id~ : String,
  grant~ : AuthorityGrant,
) -> UserAccount raise IdentityError {
  if user_id.trim() == "" {
    raise IdentityError::EmptyIdentifier(user_id)
  }
  if user_code.trim() == "" {
    raise IdentityError::EmptyIdentifier(user_code)
  }
  if display_name.trim() == "" || principal_id.trim() == "" {
    raise IdentityError::EmptyName
  }
  if business_unit_id.trim() == "" {
    raise IdentityError::EmptyIdentifier(business_unit_id)
  }
  require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="identity:user:create",
    scope="organization:" + business_unit_id,
    amount_minor=0,
  ) catch {
    error => raise IdentityError::NotAuthorized(error)
  }
  {
    user_id,
    user_code,
    display_name,
    principal_id,
    business_unit_id,
    department_id,
    state: if enabled {
      UserAccountState::Active
    } else {
      UserAccountState::Disabled
    },
  }
}

///|
pub fn UserDirectory::empty() -> UserDirectory {
  { users: [] }
}

///|
pub fn UserDirectory::append(
  self : UserDirectory,
  user : UserAccount,
) -> UserDirectory raise IdentityError {
  for existing in self.users {
    if existing.user_id == user.user_id || existing.user_code == user.user_code {
      raise IdentityError::DuplicateUser
    }
  }
  let users = self.users.copy()
  users.push(user)
  { users, }
}

///|
pub fn AuthorityGrant::allows(
  self : AuthorityGrant,
  principal_id~ : String,
  actor_id~ : String,
  capability~ : String,
  scope~ : String,
  amount_minor~ : Int64,
) -> Bool {
  self.active &&
  self.principal_id == principal_id &&
  self.actor_id == actor_id &&
  self.capability == capability &&
  self.scope == scope &&
  amount_minor >= 0 &&
  amount_minor <= self.max_amount_minor
}

///|
pub fn require_authority(
  grant : AuthorityGrant,
  principal_id~ : String,
  actor_id~ : String,
  capability~ : String,
  scope~ : String,
  amount_minor~ : Int64,
) -> Unit raise AuthorityError {
  if !grant.active {
    raise AuthorityError::InactiveGrant
  }
  if grant.principal_id != principal_id {
    raise AuthorityError::WrongPrincipal
  }
  if grant.actor_id != actor_id {
    raise AuthorityError::WrongActor
  }
  if grant.capability != capability {
    raise AuthorityError::WrongCapability
  }
  if grant.scope != scope {
    raise AuthorityError::ScopeMismatch
  }
  if amount_minor < 0 || amount_minor > grant.max_amount_minor {
    raise AuthorityError::AmountExceeded
  }
}
