# Synthetic source assignment walkthrough

These portable files contain invented demonstration material, not customer
evidence, market demand, authenticated company facts or executable instructions.

1. Use the existing [delivery plan template](../delivery-plan-template.json)
   through the [Projects template workflow](../../PLAN_TEMPLATES.md). Review all
   dates, cost assumptions and owners, then save the native review-pending plan
   using the existing configured native operation. If that service is unavailable,
   use an already saved native plan; do not treat the template JSON as a native
   plan artifact.
2. Load that saved native plan in **Delegate a deliverable**. Choose an approved
   local workspace and model selector. Select `interview-notes.md` and
   `alternatives.csv` from this directory. Inspect each and assign them to the
   current **Draft brief** task ID shown on your board. Adapt inherited acceptance
   gates to explicit task criteria and required evidence, then preview and save.
3. Create two specialist contributions on **Draft brief**. Give each a current
   board owner:
   - **Check source claims**: criterion “Separate the two observed problems from
     untested demand claims”; required evidence “Claim-by-claim source notes”.
   - **Compare alternatives**: criterion “Compare both options using the supplied
     assumptions and state what remains untested”; required evidence “Comparison
     with explicit assumptions”.
4. On the new specialist board, choose **Assign source evidence to a task**.
   Select **Check source claims**, check only `interview-notes.md`, and use the
   reason “Give the specialist the interview observations used by the integrator”.
   Preview and save the separate child.
5. On that child, assign only `alternatives.csv` to **Compare alternatives**,
   explain the assignment, preview and save again. The original **Draft brief**
   keeps both files and its integration gate. Inspect the complete current graph:
   each specialist receives only its chosen source reference, and **Draft brief**
   still waits for both specialists' named acceptance.
6. Prepare the current owners' briefs. Reference-only output excludes source
   contents; opt in separately if you want the full synthetic text included.
   Reload and confirm the same mapping and history. Stop here unless existing
   operator review, native Flow/Claw and provider configuration are authorized.

No supplied file contains an absolute filesystem path, account ID, credential,
provider endpoint or pre-granted review. IDs are read from the actual saved board,
not guessed from the template. Preview/save alone remains useful without execution
configuration. Nothing sends the brief or records delivery/acceptance/payment.
