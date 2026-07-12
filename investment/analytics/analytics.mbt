///|
pub(all) enum Trend {
  Rising
  Falling
  Flat
} derive(Debug, Eq)

///|
pub(all) struct AnalysisReport {
  instrument : String
  sample_size : Int
  first_close_minor : Int64
  last_close_minor : Int64
  trend : Trend
  moving_average_minor : Int64
} derive(Debug, Eq)

///|
pub(all) suberror AnalysisError {
  EmptyInstrument
  EmptySeries
  InvalidWindow
} derive(Debug, Eq)

///|
pub fn moving_average(
  closes : Array[Int64],
  window : Int,
) -> Int64 raise AnalysisError {
  if closes.length() == 0 {
    raise AnalysisError::EmptySeries
  }
  if window <= 0 || window > closes.length() {
    raise AnalysisError::InvalidWindow
  }
  let mut total : Int64 = 0
  let start = closes.length() - window
  for i in start..<closes.length() {
    total += closes[i]
  }
  total / window.to_int64()
}

///|
pub fn analyze_closes(
  instrument~ : String,
  closes~ : Array[Int64],
) -> AnalysisReport raise AnalysisError {
  if instrument.trim() == "" {
    raise AnalysisError::EmptyInstrument
  }
  if closes.length() == 0 {
    raise AnalysisError::EmptySeries
  }
  let first = closes[0]
  let last = closes[closes.length() - 1]
  let trend = if last > first {
    Trend::Rising
  } else if last < first {
    Trend::Falling
  } else {
    Trend::Flat
  }
  let window = if closes.length() < 3 { closes.length() } else { 3 }
  {
    instrument,
    sample_size: closes.length(),
    first_close_minor: first,
    last_close_minor: last,
    trend,
    moving_average_minor: try! moving_average(closes, window),
  }
}
