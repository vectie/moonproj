# Hand off a delegated task to another owner

A plan can be correct while its intended owner is unavailable. On an unimported
Deliverable task board, open **Hand off a task to another owner**. Enter the task
ID, a different owner ID from the original native plan, and the reason. Preview
the old/new named assignment, the complete task scope, and its exact new digest.
Choose **Save review-pending owner handoff** to keep a separate durable child.

The original board and native plan bytes remain available. Each child retains
its immediate parent ID/digest and all prior handoff reasons (up to 32). Acceptance
criteria, required evidence, assigned source-file bytes and task dependencies do
not change. The original source plan is historical; current task accountability
is in the new reviewed deliverable scope and the generated Claw request.

Changing any handoff input invalidates the preview. Repeating an identical save
returns the same child after an interrupted response or host restart. Cancelling
an in-flight preview prevents its late response from restoring stale form data.
A save already in flight cannot be cancelled as if it had never happened.

## Planning order and authority

Reassign before capacity, specialist or rework planning. Imported boards are
rejected even when no provider call is known to have occurred. Existing capacity
lanes are derived from their old owners and cannot silently survive reassignment.
Capacity planning on the new owner-handoff child computes lanes from its current
owners. Existing specialist integration and rework scopes also remain unchanged;
this feature does not migrate running tasks or inherited reviewed outputs.

Every child requires its own exact operator review before import. The parent's
review and provider approval do not authorize the new digest. Owner labels are
accountability labels, not authenticated company assignments. No native plan
costs, estimates, company state, financial authority, acceptance or provider
permissions are changed by saving a proposal.

## Product scope and verification

This is bounded usability support for MOONPROJ-UC07/B07: versioned review-pending
plan handoff with changed scope requiring new review. It does not complete the
signed execution roadmap or establish customer acceptance or payment.

Focused tests cover the real Node host, mounted panel handlers, real loopback
HTTP routes, restart/retry, stale/cancelled preview, original byte preservation,
corrupt evidence, capacity composition and rejection of imported/scoped boards.
Flow/Claw regression adapters are explicitly synthetic. Native MoonBit
check/test/info/fmt, native installed execution, frontend packaging, graphical
browser/accessibility and signed company/PostgreSQL gates remain unrun and
release-blocking. The Node event DOM is not a graphical-browser qualification.
