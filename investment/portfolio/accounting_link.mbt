///|
/// Build a balanced mark-to-market source-to-journal link. The quote snapshot
/// is supplied explicitly; valuation recording does not move cash or post a
/// period to the accounting book.
pub fn Portfolio::to_valuation_event(
  self : Portfolio,
  valuation_id~ : String,
  event_id~ : String,
  event_type~ : String,
  quotes~ : Array[MarketQuote],
  investment_account~ : String,
  gain_account~ : String,
  loss_account~ : String,
  actor_id~ : String,
  grant~ : @foundation.AuthorityGrant,
) -> @accounting.AccountingEvent raise PortfolioError {
  if valuation_id.trim() == "" {
    raise PortfolioError::EmptyIdentifier
  }
  let valuation = self.value(quotes)
  let mut cost_minor : Int64 = 0
  for position in self.positions {
    cost_minor += position.cost_basis.minor
  }
  let delta_minor = valuation.total_market_value.minor - cost_minor
  if delta_minor == 0L {
    raise PortfolioError::InvalidAmount
  }
  let amount_minor = if delta_minor < 0L {
    0L - delta_minor
  } else {
    delta_minor
  }
  let amount = @finance.Money::new(minor=amount_minor, currency=self.currency) catch {
    error => raise PortfolioError::Money(error)
  }
  @foundation.require_authority(
    grant,
    principal_id=self.principal_id,
    actor_id~,
    capability="investment:valuation:record",
    scope=self.project_scope,
    amount_minor~,
  ) catch {
    error => raise PortfolioError::NotAuthorized(error)
  }
  let journal : @finance.JournalEntry = if delta_minor > 0L {
    {
      entry_id: "investment/" + valuation_id + "/gain",
      description: "Mark investment portfolio gain " + self.portfolio_id,
      postings: [
        {
          account: investment_account,
          side: @finance.PostingSide::Debit,
          amount,
        },
        { account: gain_account, side: @finance.PostingSide::Credit, amount },
      ],
    }
  } else {
    {
      entry_id: "investment/" + valuation_id + "/loss",
      description: "Mark investment portfolio loss " + self.portfolio_id,
      postings: [
        { account: loss_account, side: @finance.PostingSide::Debit, amount },
        {
          account: investment_account,
          side: @finance.PostingSide::Credit,
          amount,
        },
      ],
    }
  }
  @accounting.AccountingEvent::new(
    event_id~,
    principal_id=self.principal_id,
    source_type="investment_valuation",
    source_id=valuation_id,
    event_type~,
    journal~,
  ) catch {
    error => raise PortfolioError::AccountingEvent(error)
  }
}
