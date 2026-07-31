# Project-plan authority boundary

`moonproj/project.plan.prepare@0.1.0` has exactly one authority class:
`workspace-mutation`.

That authority permits MoonProj to validate evidence and write an immutable,
review-pending planning artifact. It does not authorize project execution,
spending, budget reservation, procurement, contract signature, payment,
accounting, tax, investment, publication, external communication, or a
physical effect.

The internal `Project` and `ProjectPlan` grants used while constructing the
artifact are ephemeral proposal-validation grants. They exercise the native
identity, dependency, currency and cost invariants but are never persisted as
company authority.

A named human must accept a later, separately versioned plan revision before
any business workflow may request its own authority.
