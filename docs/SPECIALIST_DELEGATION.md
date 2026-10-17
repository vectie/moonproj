# Delegate parallel specialist contributions (R583)

In **Delegate a deliverable**, choose an original saved, unimported task board.
Expand **Delegate specialist contributions** and choose the task that will integrate
the contributions. Its original owner, acceptance criteria and required evidence
remain the final internal integration gate. Fill the two initial contribution rows:

- A short contribution name, such as “Verify source claims”
- An accountable owner selected from the existing board owners
- Acceptance criteria, one per line, such as “Every material claim has a checked source”
- Required evidence, one per line, such as “Checked source notes”

Use **Add contribution** for up to ten rows; **Remove contribution** keeps at least
two. Stable contribution IDs are generated without colliding with existing board
tasks. Switching saved boards clears the form so an old scope cannot accidentally
be submitted to the new board. Empty required fields show a repairable error.
Choose **Create specialist delegation**. The new board shows the contributions,
original integration task, original board link identity and a new execution digest.
It is an execution proposal; the native source plan and authored costs, dates,
statuses, estimates, budget and risk records are unchanged.

Each contribution inherits the integration task's original prerequisites and can
run in parallel with the other contributions after those prerequisites are accepted.
A delegated board can be capacity-planned before import (see
[capacity-plan delegated contributions](DELEGATE_DELIVERABLE.md#capacity-plan-delegated-contributions-r592)).
Owner lanes may serialize contributions; parallel readiness alone is not staffing
capacity. The original integration task retains those prerequisites and additionally waits
for every contribution's named acceptance. Its goal explicitly asks it to integrate
the reviewed outputs. Existing downstream tasks still wait on that original task,
not merely on a specialist returning output. Normal Flow preparation carries direct
prerequisite evidence into the integration request. Work completion without review
does not release it.

Review the new exact scope with the existing operator review configuration, then
use **Import / prepare ready tasks**, dispatch, independent native review, and
assembly normally. Original approval is intentionally invalid for the child scope.
Provider approval remains separately required. Neither proposal creation nor
assembly records customer acceptance, delivery, cash or authenticated assignments.

This differs from the project draft's sequential task breakdown: that editor
replaces an authored row and allocates its cost; specialist delegation preserves
the original task as a convergence gate and builds a separate executable proposal.
No cost estimates are assigned to the added contributions. Review the extra work
and any provider budget outside this scope before authorizing execution.

If the original board includes local source evidence, new contributions start
without source assignments. Use [Assign source evidence to a task](SOURCE_ASSIGNMENT.md)
before import to choose each contribution's files explicitly, preview the exact
inputs and save a separately reviewed child. Existing integration/source mappings
remain available; there is no implicit inheritance or provider approval.

## Limits and recovery

- Only original unimported boards can be split into specialists. An unimported
  specialist board may receive one explicit capacity-planning proposal, preserving
  its integration gate and requiring a new review. Imported, capacity-scoped, rework,
  or previously split boards cannot receive another specialist split.
- Two to ten contributions and at most 100 total tasks. Contribution IDs are unique
  across the whole scope. Unknown owners, missing criteria/evidence, and extra
  fields (including arbitrary dependencies or authority settings) reject.
- The same request returns the same child even after host restart. A different
  contribution scope produces a separate review-pending proposal.
- Invalid input leaves the original intact. Source-plan byte corruption blocks
  creation; no source bytes or original board files are rewritten.
- Owner names are accountability labels, not authenticated actors or staffing
  assignments. Parallel readiness is not a resource reservation or quota.

## Verification

`../run-focused.sh` in the round evidence package runs production Node helper,
host, mounted-controller and loopback HTTP tests plus existing dispatch regressions.
Specialist tests cover fan-out/fan-in, retained acceptance, untouched source,
invalid input, form add/remove and selection reset, repeated-click serialization,
dismissed-panel late responses, exact review rejection, independent contribution acceptance,
integration prerequisite references, assembly, restart/idempotency, cross-origin
refusal, HTML escaping and the mounted input/click path.

Native Flow/Claw responses and reviewer receipts are explicitly synthetic test
adapters. Native builds, mounted graphical browser, actual provider execution,
PostgreSQL company state and release qualification remain unrun. Passing these
checks is not evidence of autonomous RSI, customer delivery or commercial success.
