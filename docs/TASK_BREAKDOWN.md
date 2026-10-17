# Break down a project-plan task

In **Projects → current project draft → Task order**, expand **Break down a task**.
Choose the broad task you want to refine. Enter names and costs for two sequential
steps; **Add step** allows up to ten and **Remove step** keeps at least two.
The allocation line shows the total entered and remaining amount in the plan's
currency. Split the original amount exactly, including cents. Zero-cost steps are
allowed. Names and individual cost strings are preserved as entered.

Choose **Preview breakdown**. The preview shows:

- The original task ID that will be removed and every replacement's new ID
- Each step's name, cost, owner, milestone and prerequisite
- Each following task whose dependency will change to the final step
- Each risk that will now refer to every replacement step

The first step inherits the original prerequisites. Each later step depends on the
previous step. The replacement stays at the original position in draft order, and
all steps initially inherit its owner and milestone. Other task fields, milestone
criteria, scope, currency, budget and contingency stay unchanged. Existing links
to other tasks are retained. This is a sequential breakdown, not parallel branching;
use the ordinary task forms to edit assignments or dependencies afterward.

**Apply breakdown** replaces the original task and saves the complete changed draft
in this browser. It gives the draft a new request identity and clears the old
prepared result. Repeated Apply does nothing. The task finder returns to all forms
so the new steps are visible. Use ordinary task editing, task CSV export, or full
plan-template export with the resulting draft. **Native prepare and save plan**
remains the separate operation that validates and saves the whole plan.

Preview and step editing do not save, change the current draft or contact the
company service. **Cancel breakdown**, changing the chosen task, ordinary draft
edits, switching project/actor, refreshing projects, template replacement, opening
a saved plan or reloading clears the pending breakdown. Applied work reloads from
normal local draft storage. If browser storage is unavailable, the existing warning
says the edited draft remains only on the page.

## Limits and recovery

- The resulting draft must have at most 100 tasks. Existing task IDs must be
  unique and nonempty. The chosen task cannot depend on itself.
- Step IDs are freshly generated. The API rejects collisions with existing task
  IDs and even unresolved dependency/risk references, so decomposition cannot
  silently attach unrelated broken references to a new step.
- Costs must be nonnegative with at most two decimal places, and add up exactly
  to the original amount. Invalid names or costs leave the draft untouched.
- Unrelated draft gaps, such as missing owner or prerequisite references, stay
  visible for ordinary editing and native validation; decomposition does not
  certify the plan.
- There is no automatic undo of Apply. Download a complete plan template first
  if you want a portable draft backup. Existing saved native versions are not
  rewritten and can be reopened through history.
- No formal tasks, external notifications, execution, customer acceptance,
  financial authorization or payments are created by this local editing workflow.

## Verification scope

Six pure tests cover sequence construction, fan-out dependencies, risk expansion,
exact cents, Unicode, copied collections, reference collisions and row limits.
Four compiled production UI tests cover preview/apply, linked form labels, escaped
HTML, local storage/reload, CSV round trip, full prepare payload, repeated actions,
validation, cancellation and context changes. Browser APIs and saved responses use
synthetic Node adapters. These results do not establish graphical-browser,
keyboard/screen-reader ergonomics, native gateway or live PostgreSQL acceptance.

After saving the native plan, [Delegate a deliverable](DELEGATE_DELIVERABLE.md)
can turn its owned tasks and prerequisites into a reviewed Flow execution graph.
Breakdown itself still edits only the plan and starts no work.
