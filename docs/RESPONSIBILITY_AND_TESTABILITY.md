# MoonProj responsibility and testability

MoonProj owns one-person-company records and controls. Its second-iteration
primary slice is a formal task that moves through create, start, evidence
submission and named acceptance using backend event and audit receipts.

## Responsibility boundary

| Concern | Owner | MoonProj seam |
| --- | --- | --- |
| Project, task, acceptance and company records | MoonProj | Owns state rules and persistent commands. |
| Orchestration and agent work | MoonFlow / MoonClaw | May schedule or propose; cannot advance company truth. |
| Authority/provider access | MoonGate and company policy | MoonProj rejects missing identity or scope. |
| Accounting, payment, filing and contracting effects | MoonProj + named human | Require product-owned controls and receipts. |

The established `frontend/` location remains a reviewed migration exception.
`frontend/opc/goal_flow.mbt` is a cohesive Rabbita workflow component;
`frontend/opc/redesign_command.mbt` owns the formal task screen. Reference
projection cards are folded and explicitly remain non-PostgreSQL facts.

## Test seams

- `frontend/opc/main_wbtest.mbt` asserts durable stage mapping, denial copy and
  the receipt boundary.
- Backend command tests own authorization, duplicate effects and audit/event
  persistence.
- `docs/qualification/UI_TO_UI_USE_CASES.md` owns the rendered create → start →
  submit → accept record and its common denied/retry path.

Browser-local preview state is never evidence of accounting, payment,
contract, tax or accepted delivery effects.
