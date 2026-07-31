# MoonFlow project-plan adapter port

The native command is:

```sh
moon run --target native cmd/moonflow_project_plan_adapter -- capability
moon run --target native cmd/moonflow_project_plan_adapter -- execute \
  --workspace <workspace> --request <request-ref> --result <result-ref>
moon run --target native cmd/moonflow_project_plan_adapter -- reconcile \
  --workspace <workspace> --request <request-ref> --result <result-ref>
moon run --target native cmd/moonflow_project_plan_adapter -- health \
  --workspace <workspace> --checked-at <UTC> --valid-until <UTC> \
  --attestation <workspace-relative-ref>
```

The port accepts only:

- `moonproj/project.plan.prepare@0.1.0`;
- `moonproj/project-plan-request@1.0.0`;
- `moonproj/project-plan-artifact@1.0.0`;
- `workspace-mutation`;
- a `digital-artifact` claim.

The adapter also requires MoonFlow's complete generic request envelope,
including non-empty `book_id`, work `declaration_id`, and
`acceptance_criteria`. Those values are retained in immutable intent and
idempotency evidence. The work declaration is not confused with the adapter
ID; the catalog's canonical operation binding selects the adapter.

Execute writes durable intent before plan construction. Reconcile may
deterministically resume an intent-only attempt because the operation has no
external or company-business effect. Result, plan, idempotency and health
evidence are immutable and digest-bound.
