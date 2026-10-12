# Explore current draft budget allocation

In Projects, open a project draft and scroll to **草稿成本分配 / Budget breakdown**.
The read-only report groups every task once by its owner and once by its
milestone, showing task IDs, exact known cost subtotal and count of invalid or
blank cost entries. Unassigned, missing and ambiguous references remain visible.
Groups appear in first task appearance order; zero-task groups are omitted.

Edit a task cost, owner or milestone with the ordinary editor, or bring in CSV
updates/templates/phases. The report recalculates from the current draft on
render. Choose **下载成本分配 (.txt)** to download that exact current context.
After a local reload, the same restored draft generates the same report.
Repeated exports reflect intervening edits. Downloading does not mutate the
draft, prepared result or browser storage, and makes no network request.

The summary includes authored currency, budget limit, contingency, known task
subtotal and remaining budget after tasks and contingency. Amount parsing uses
the workbench's existing two-decimal nonnegative amount syntax; minor units are
100 per entered unit, regardless of currency label. No FX conversion or currency
exponent inference occurs. Contingency is deducted once in the summary and is
not assigned to owner/milestone groups. The two group views contain the SAME
costs: adding them together would double count.

Blank/malformed/negative task costs are excluded from the known subtotal and
counted explicitly, never treated as zero. Remaining is unavailable until all
task costs, limit and contingency parse. Arithmetic is exact Int64, including
beyond JavaScript safe integers; a subtotal or cost-plus-contingency overflow is
unavailable, never wrapped. A negative remaining value identifies an over-budget
proposal. Missing owner/milestone references do not prevent arithmetic, but they
remain clearly labeled and may block the separate native prepare operation.

Task source amounts are listed unchanged to support correction. Review free
text before sharing. This is a local planning aid, not accounting, budget
approval, spending, payment evidence, task dispatch or a saved native result.
The native prepare action still performs complete proposal validation. An empty
plan shows a zero task subtotal, which does not imply the plan is ready.

Focused checks:

- `product/plan_workbench/budget_breakdown_test.mbt`: exact partitioning,
  incomplete amounts, over-budget proposals, overflow, large integers, empty
  and ambiguous references, unchanged inputs and recalculation.
- `frontend/opc/project_plan_budget_wbtest.mbt`: actual compiled UI rendering,
  edit/storage reload, repeated export, prepared-state preservation, no network
  effects and actor/project scope checks, with synthetic browser APIs.
