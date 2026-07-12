///|
/// A governed configuration option. The value is intentionally opaque: a
/// parameter dictionary is not allowed to smuggle accounting or CBS meaning
/// into the company model without a later, explicit mapping.
pub(all) struct ParameterOption {
  parameter_id : String
  code : String
  value : String
  display_order : Int
  enabled : Bool
} derive(Debug, Eq)

///|
pub(all) struct ParameterDictionary {
  parameter_name : String
  principal_id : String
  scope : String
  options : Array[ParameterOption]
} derive(Debug, Eq)

///|
pub(all) suberror ParameterError {
  EmptyIdentifier
  DuplicateOption
  InvalidOrder
  NotAuthorized(AuthorityError)
} derive(Debug, Eq)

///|
pub fn ParameterDictionary::new(
  parameter_name~ : String,
  principal_id~ : String,
  scope~ : String,
  actor_id~ : String,
  grant~ : AuthorityGrant,
) -> ParameterDictionary raise ParameterError {
  if parameter_name.trim() == "" ||
    principal_id.trim() == "" ||
    scope.trim() == "" {
    raise ParameterError::EmptyIdentifier
  }
  require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="parameter:create",
    scope~,
    amount_minor=0,
  ) catch {
    error => raise ParameterError::NotAuthorized(error)
  }
  { parameter_name, principal_id, scope, options: [] }
}

///|
pub fn ParameterDictionary::add_option(
  self : ParameterDictionary,
  option : ParameterOption,
  actor_id~ : String,
  grant~ : AuthorityGrant,
) -> ParameterDictionary raise ParameterError {
  if option.parameter_id.trim() == "" || option.code.trim() == "" {
    raise ParameterError::EmptyIdentifier
  }
  if option.display_order < 0 {
    raise ParameterError::InvalidOrder
  }
  for existing in self.options {
    if existing.parameter_id == option.parameter_id ||
      existing.code == option.code {
      raise ParameterError::DuplicateOption
    }
  }
  require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="parameter:edit",
    scope=self.scope,
    amount_minor=0,
  ) catch {
    error => raise ParameterError::NotAuthorized(error)
  }
  let options = self.options.copy()
  options.push(option)
  { ..self, options, }
}
