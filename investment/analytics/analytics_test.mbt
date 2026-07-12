///|
test "investment analytics is deterministic" {
  let report = analyze_closes(instrument="DEMO", closes=[100L, 110L, 120L, 130L])
  assert_eq(report.sample_size, 4)
  assert_eq(report.moving_average_minor, 120L)
  assert_true(report.trend == Trend::Rising)
}

///|
test "investment analytics rejects empty evidence" {
  try analyze_closes(instrument="DEMO", closes=[]) catch {
    AnalysisError::EmptySeries => ()
    _ => fail("wrong analysis error")
  } noraise {
    _ => fail("expected analysis error")
  }
}
