///|
pub extend Inventory with Debug::{to_repr}

///|
pub extend InventoryError with Debug::{to_repr}

///|
pub extend Inventory with Eq::{equal, not_equal}

///|
pub extend Inventory with ToJson::{to_json}

///|
pub extend Inventory with @json.FromJson::{from_json}

///|
pub extend Requirement with Debug::{to_repr}

///|
pub extend Requirement with Eq::{equal, not_equal}

///|
pub extend Requirement with ToJson::{to_json}

///|
pub extend Requirement with @json.FromJson::{from_json}

///|
pub extend WorkGroup with Debug::{to_repr}

///|
pub extend WorkGroup with Eq::{equal, not_equal}

///|
pub extend WorkGroup with ToJson::{to_json}

///|
pub extend WorkGroup with @json.FromJson::{from_json}

///|
pub extend Milestone with Debug::{to_repr}

///|
pub extend Milestone with Eq::{equal, not_equal}

///|
pub extend Milestone with ToJson::{to_json}

///|
pub extend Milestone with @json.FromJson::{from_json}
