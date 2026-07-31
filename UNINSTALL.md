# MoonProj pack uninstall contract

Removing the optional MoonFlow adapter must not delete company records,
accepted project plans, review receipts, or source evidence.

The following workspace-owned data is preserved:

```text
.moonsuite/products/moonproj/adapter-attempts/
.moonsuite/products/moonproj/idempotency/
.moonsuite/products/moonproj/health/
```

An operator may archive those records under the workspace retention policy
after confirming that no active MoonFlow run or review receipt references
them. Uninstall never changes MoonProj accounting, authority or project state.
