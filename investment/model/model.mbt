///|
/// A versioned investment model imported from an operational source. The
/// model stores index values as source representations so percentages,
/// currency amounts, dates, and formulas are not silently conflated.
pub(all) struct ModelVersion {
  version_id : String
  project_id : String
  principal_id : String
  name : String
  version_no : Int
  current : Bool
  created_by : String
  created_at : String
  remark : String?
} derive(Debug, Eq)

///|
pub(all) struct ModelIndex {
  index_id : String
  version_id : String
  project_id : String
  dimension : String
  full_code : String
  name : String
  parent_code : String?
  unit : String?
  value_repr : String?
  remark : String?
  sort_order : Int
} derive(Debug, Eq)

///|
pub(all) struct InvestmentModel {
  version : ModelVersion
  indexes : Array[ModelIndex]
} derive(Debug, Eq)

///|
pub(all) suberror ModelError {
  EmptyIdentifier
  InvalidVersion
  InvalidOrder
  DuplicateIndex
  VersionMismatch
  InvalidIndex
  ProjectionIdentity
  Projection(@store.ProjectionError)
  NotAuthorized(@foundation.AuthorityError)
} derive(Debug, Eq)

///|
pub fn ModelVersion::new(
  version_id~ : String,
  project_id~ : String,
  principal_id~ : String,
  name~ : String,
  version_no~ : Int,
  current~ : Bool,
  created_by~ : String,
  created_at~ : String,
  remark~ : String?,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> ModelVersion raise ModelError {
  if version_id.trim() == "" ||
    project_id.trim() == "" ||
    principal_id.trim() == "" ||
    name.trim() == "" ||
    created_by.trim() == "" ||
    created_at.trim() == "" {
    raise ModelError::EmptyIdentifier
  }
  if version_no <= 0 {
    raise ModelError::InvalidVersion
  }
  @foundation.require_authority(
    grant,
    principal_id~,
    actor_id~,
    capability="investment:model:version:create",
    scope="project:" + project_id,
    amount_minor=0,
  ) catch {
    error => raise ModelError::NotAuthorized(error)
  }
  {
    version_id,
    project_id,
    principal_id,
    name,
    version_no,
    current,
    created_by,
    created_at,
    remark,
  }
}

///|
pub fn ModelIndex::new(
  index_id~ : String,
  version_id~ : String,
  project_id~ : String,
  dimension~ : String,
  full_code~ : String,
  name~ : String,
  parent_code~ : String?,
  unit~ : String?,
  value_repr~ : String?,
  remark~ : String?,
  sort_order~ : Int,
) -> ModelIndex raise ModelError {
  if index_id.trim() == "" ||
    version_id.trim() == "" ||
    project_id.trim() == "" ||
    dimension.trim() == "" ||
    full_code.trim() == "" ||
    name.trim() == "" {
    raise ModelError::EmptyIdentifier
  }
  if sort_order < 0 {
    raise ModelError::InvalidOrder
  }
  {
    index_id,
    version_id,
    project_id,
    dimension,
    full_code,
    name,
    parent_code,
    unit,
    value_repr,
    remark,
    sort_order,
  }
}

///|
pub fn InvestmentModel::new(version : ModelVersion) -> InvestmentModel {
  { version, indexes: [] }
}

///|
pub fn InvestmentModel::add_index(
  self : InvestmentModel,
  index : ModelIndex,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> InvestmentModel raise ModelError {
  if index.version_id != self.version.version_id ||
    index.project_id != self.version.project_id {
    raise ModelError::VersionMismatch
  }
  for existing in self.indexes {
    if existing.index_id == index.index_id ||
      existing.full_code == index.full_code {
      raise ModelError::DuplicateIndex
    }
  }
  @foundation.require_authority(
    grant,
    principal_id=self.version.principal_id,
    actor_id~,
    capability="investment:model:index:add",
    scope="project:" + self.version.project_id,
    amount_minor=0,
  ) catch {
    error => raise ModelError::NotAuthorized(error)
  }
  let indexes = self.indexes.copy()
  indexes.push(index)
  { ..self, indexes, }
}

///|
fn optional_json(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
fn int_json(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn index_json(index : ModelIndex) -> Json {
  Json::object({
    "index_id": Json::string(index.index_id),
    "version_id": Json::string(index.version_id),
    "project_id": Json::string(index.project_id),
    "dimension": Json::string(index.dimension),
    "full_code": Json::string(index.full_code),
    "name": Json::string(index.name),
    "parent_code": optional_json(index.parent_code),
    "unit": optional_json(index.unit),
    "value_repr": optional_json(index.value_repr),
    "remark": optional_json(index.remark),
    "sort_order": int_json(index.sort_order),
  })
}

///|
pub fn InvestmentModel::append_projection(
  self : InvestmentModel,
  projection : @store.AggregateProjection,
) -> @store.AggregateProjection raise ModelError {
  if projection.aggregate_type != "investment_model" ||
    projection.aggregate_id != self.version.version_id {
    raise ModelError::ProjectionIdentity
  }
  let values : Array[Json] = []
  for index in self.indexes {
    values.push(index_json(index))
  }
  let payload = Json::object({
    "version_id": Json::string(self.version.version_id),
    "project_id": Json::string(self.version.project_id),
    "principal_id": Json::string(self.version.principal_id),
    "name": Json::string(self.version.name),
    "version_no": int_json(self.version.version_no),
    "current": Json::boolean(self.version.current),
    "created_by": Json::string(self.version.created_by),
    "created_at": Json::string(self.version.created_at),
    "remark": optional_json(self.version.remark),
    "indexes": Json::array(values),
  }).stringify()
  let revision = projection.revision + 1
  projection.append(
    expected_revision=revision,
    payload~,
    source_event_id="company:investment-model:" +
      self.version.version_id +
      ":r" +
      revision.to_string(),
  ) catch {
    error => raise ModelError::Projection(error)
  }
}
