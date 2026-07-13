# Rabbita expense browser acceptance

Recorded: 2026-07-13
Scope: local development gateway only

This is a repeatable acceptance record for the first connected Rabbita
workflow. It does not authorize production deployment or claim full ERP UI
parity.

## Environment

- Browser bundle: `warren build frontend/main --dist <dist>`
- Authenticated service: `scripts/company_postgres_service.py`
- Same-origin gateway: `scripts/company_postgres_dev_gateway.py`
- Database: local PostgreSQL `moonproj`
- Probe identity: `EXP-RABBITA-LOCAL`

The service token stayed in the gateway environment. The browser sent only
same-origin JSON; the gateway supplied bearer authentication, forwarded HTTPS,
and translated each JSON `idempotency_key` into `Idempotency-Key`. The
browser login established an in-memory HttpOnly session, and the gateway
signed `rabbita-user` before forwarding command requests.

## Scenario

| Step | Browser action | Visible state |
|---|---|---|
| 1 | Open 财务管理 → 费用预算 → 我的报销 → 新建报销 | `未创建` |
| 2 | Click 保存草稿 | `草稿` |
| 3 | Click 提交审批 | `已提交` |
| 4 | Click 退回补充 | `已驳回` |
| 5 | Click 重新提交 | `已提交` |
| 6 | Click 批准报销 | `已批准` |

The service log recorded HTTP 201 for create and HTTP 200 for submit, reject,
resubmit, and approve. PostgreSQL inspection showed the final `approved`
projection plus five `company_command` receipts and five
`company_audit_event` records. The probe rows were deleted after verification.

## Remaining gate

This acceptance covers only the local development probe. The expense form
still uses a fixed demo ID and idempotency keys, the session store is
in-memory, and the production identity/session/token issuer, persistence,
rotation, and owner acceptance are not accepted. Other ERP route families
remain fixture-backed or read-only.
