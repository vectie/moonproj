///|
fn fixture() -> @work_inventory.Inventory {
  {
    schema: "moonsuite.product-work-inventory.v1",
    product_id: "moonbook",
    as_of: "2026-10-04",
    origin: "packaged_prd_assessment",
    source_scope: "Source fixture only",
    current_gap: "Host journey unverified",
    vision_scope: "Additional vision requires acceptance decomposition",
    full_target_estimate: "Unknown; scoped group estimate only",
    next_milestone: {
      title: "Qualify Book lifecycle",
      estimate_low_days: Some(2),
      estimate_high_days: Some(5),
      unit: "engineer-days",
      confidence: "low",
      scope: "One scoped fixture journey",
      linked_group_id: Some("book-lifecycle"),
    },
    prd_source: "MoonBook_PRD.docx",
    prd_sha256: "fixture",
    philosophy: ["Keep reviewed memory"],
    non_goals: ["No invented acceptance"],
    requirements: [
      {
        id: "MOONBOOK-B01",
        title: "Book lifecycle",
        track: "baseline",
        priority: "P0",
        statement: "Retain exact Book identity",
        acceptance: ["Reopen the same Book"],
        dependencies: ["Host"],
        historical_status: "Source documented",
        historical_evidence: ["PRD"],
        status: "partial",
        reason: "Contract present; host not qualified",
        evidence: ["source/file.mbt"],
      },
    ],
    groups: [
      {
        id: "book-lifecycle",
        title: "Qualify Book lifecycle",
        requirement_ids: ["MOONBOOK-B01"],
        status: "partial",
        next_action: "Reopen a reviewed fixture",
        acceptance: ["Identity survives restart"],
        dependencies: ["Configured host"],
        estimate_low_days: Some(2),
        estimate_high_days: Some(5),
        estimate_scope: "Verification only; not full implementation",
        confidence: "low",
        assumptions: ["One engineer and a prepared host"],
        evidence: ["source/file.mbt"],
      },
    ],
  }
}

///|
fn rejected(value : @work_inventory.Inventory) -> Bool {
  try {
    ignore(@work_inventory.parse(value.to_json(), "moonbook"))
    false
  } catch {
    _ => true
  }
}

///|
test "dated work scope round trips without completion arithmetic" {
  let value = @work_inventory.parse(fixture().to_json(), "moonbook")
  assert_eq(value, fixture())
  assert_eq(value.count("partial"), 1)
  assert_eq(value.count("verified"), 0)
  let unknown = {
    ..value,
    next_milestone: {
      ..value.next_milestone,
      estimate_low_days: None,
      estimate_high_days: None,
      linked_group_id: None,
    },
    groups: [
      { ..value.groups[0], estimate_low_days: None, estimate_high_days: None, },
    ],
  }
  assert_eq(@work_inventory.parse(unknown.projection(), "moonbook"), unknown)
  let wire = unknown.projection()
  assert_true(
    wire
    is {
      "groups": Array(
        [{ "estimate_low_days": Null, "estimate_high_days": Null, .. }]
      ),
      ..
    },
  )
  assert_eq(@work_inventory.parse(wire, "moonbook"), unknown)
}

///|
test "next milestone cannot omit its estimate or misstate its linked work group" {
  let value = fixture()
  for
    milestone in [
      { ..value.next_milestone, title: "Different scope", },
      { ..value.next_milestone, linked_group_id: Some("unknown"), },
      { ..value.next_milestone, estimate_low_days: Some(1), },
      { ..value.next_milestone, estimate_high_days: None, },
      { ..value.next_milestone, estimate_low_days: Some(0), },
    ] {
    assert_true(rejected({ ..value, next_milestone: milestone, }))
  }
  let wire = value.projection()
  guard wire is { "next_milestone": Object(fields), .. } else {
    fail("Milestone fixture")
  }
  fields.remove("estimate_low_days")
  let failed = try {
    ignore(@work_inventory.parse(wire, "moonbook"))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
test "inventory rejects identity loss unsupported evidence and incomplete scope" {
  let value = fixture()
  for
    invalid in [
      { ..value, schema: "future", },
      { ..value, product_id: "moonfish", },
      { ..value, origin: "live_company_database", },
      { ..value, requirements: [value.requirements[0], value.requirements[0]], },
      {
        ..value,
        requirements: [{ ..value.requirements[0], status: "complete", }],
      },
      {
        ..value,
        requirements: [
          { ..value.requirements[0], status: "verified", evidence: [], },
        ],
      },
      { ..value, requirements: [{ ..value.requirements[0], acceptance: [], }], },
      { ..value, groups: [], },
      {
        ..value,
        groups: [{ ..value.groups[0], requirement_ids: ["MOONBOOK-B02"], }],
      },
      {
        ..value,
        groups: [value.groups[0], { ..value.groups[0], id: "other", }],
      },
      { ..value, groups: [{ ..value.groups[0], estimate_high_days: None, }], },
      { ..value, groups: [{ ..value.groups[0], estimate_low_days: Some(8), }], },
      { ..value, groups: [{ ..value.groups[0], estimate_low_days: Some(0), }], },
    ] {
    assert_true(rejected(invalid))
  }
}

///|
test "portfolio matches exact catalog membership and does not invent missing products" {
  let value : Json = {
    "schema": "moonsuite.work-inventory.v1",
    "products": [fixture().to_json()],
  }
  assert_eq(@work_inventory.parse_portfolio(value, ["moonbook"]).length(), 1)
  for ids in [["moonbook", "moonfish"], ["moonfish"], []] {
    let failed = try {
      ignore(@work_inventory.parse_portfolio(value, ids))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}
