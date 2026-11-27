///|
#derive(Debug, Eq)
struct RetainerSmoke {
  retainer_id : String
  cycle_price_minor : Int64
  completed_cycles : Int32
  collected_minor : Int64
  active : Bool
}

///|
fn RetainerSmoke::new(
  retainer_id : String,
  cycle_price_minor : Int64,
) -> RetainerSmoke raise SmokeError {
  if retainer_id.trim().is_empty() || cycle_price_minor <= 0 {
    raise InvalidRetainerState
  }
  {
    retainer_id,
    cycle_price_minor,
    completed_cycles: 0,
    collected_minor: 0L,
    active: true,
  }
}

///|
fn RetainerSmoke::complete_paid_cycle(
  self : RetainerSmoke,
  payment : SandboxProviderReceipt,
) -> RetainerSmoke raise SmokeError {
  if !self.active ||
    !payment.sandbox ||
    payment.status != "sandbox-confirmed" ||
    payment.amount_minor != self.cycle_price_minor {
    raise InvalidRetainerState
  }
  {
    ..self,
    completed_cycles: self.completed_cycles + 1,
    collected_minor: self.collected_minor + payment.amount_minor,
  }
}

///|
fn RetainerSmoke::cancel(
  self : RetainerSmoke,
) -> RetainerSmoke raise SmokeError {
  if !self.active {
    raise InvalidRetainerState
  }
  { ..self, active: false, }
}

///|
fn require_quote_gate(
  price_minor~ : Int64,
  modeled_cost_minor~ : Int64,
  founder_minutes~ : Int32,
  capacity_minutes~ : Int32,
  minimum_margin_bps~ : Int64,
) -> Int64 raise SmokeError {
  if founder_minutes > capacity_minutes {
    raise CapacityExceeded
  }
  let contribution = price_minor - modeled_cost_minor
  if price_minor <= 0 || contribution <= 0 {
    raise MarginBelowFloor
  }
  let margin_bps = contribution * 10000L / price_minor
  if margin_bps < minimum_margin_bps {
    raise MarginBelowFloor
  }
  margin_bps
}

///|
test "retainer adapter runs three paid cycles behind margin and capacity gate" {
  let margin_bps = require_quote_gate(
    price_minor=750000L,
    modeled_cost_minor=144000L,
    founder_minutes=480,
    capacity_minutes=600,
    minimum_margin_bps=7000L,
  )
  assert_eq(margin_bps, 8080L)
  let mut retainer = RetainerSmoke::new("retainer-market-monitoring", 250000L)
  for cycle in 1..<=3 {
    retainer = retainer.complete_paid_cycle(
      sandbox_receipt(
        "sandbox-retainer-payment-" + cycle.to_string(),
        "sandbox-payment-provider",
        "retainer-cycle-" + cycle.to_string(),
        250000L,
      ),
    )
  }
  retainer = retainer.cancel()
  assert_eq(retainer.completed_cycles, 3)
  assert_eq(retainer.collected_minor, 750000L)
  assert_true(!retainer.active)
  try
    retainer.complete_paid_cycle(
      sandbox_receipt(
        "sandbox-retainer-payment-4", "sandbox-payment-provider", "retainer-cycle-4",
        250000L,
      ),
    )
  catch {
    InvalidRetainerState => ()
    _ => fail("expected cancelled retainer to reject another cycle")
  } noraise {
    _ => fail("cancelled retainer must not bill")
  }
}

///|
test "quote gate rejects low margin and founder over-capacity" {
  try
    require_quote_gate(
      price_minor=250000L,
      modeled_cost_minor=100000L,
      founder_minutes=300,
      capacity_minutes=600,
      minimum_margin_bps=7000L,
    )
  catch {
    MarginBelowFloor => ()
    _ => fail("expected low-margin quote to be rejected")
  } noraise {
    _ => fail("low-margin quote must not pass")
  }
  try
    require_quote_gate(
      price_minor=250000L,
      modeled_cost_minor=44000L,
      founder_minutes=601,
      capacity_minutes=600,
      minimum_margin_bps=7000L,
    )
  catch {
    CapacityExceeded => ()
    _ => fail("expected founder over-capacity quote to be rejected")
  } noraise {
    _ => fail("over-capacity quote must not pass")
  }
}
