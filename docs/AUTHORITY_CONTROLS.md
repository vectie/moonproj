# Authority Controls

Recorded: 2026-07-13

The company product keeps workflow assignment, RBAC, delegation, and business
authority separate:

- workflow assignments identify who is configured for a process step;
- role assignments authorize capabilities at exact scopes;
- separation rules prevent one actor from holding incompatible capabilities;
- delegations issue bounded grants only inside an explicit time window;
- domain operations still validate represented principal, actor, capability,
  scope, amount, and local state.

`foundation/access` implements effective-dated delegation records with
`not_before_epoch`, optional exclusive `expires_at_epoch`, revocation, actor
matching, and amount ceilings. It also evaluates separation rules both when a
new role assignment is created and when a rule is added after assignments exist.

Workflow assignment enforcement is opt-in: attaching a validated assignment to
a process definition makes new instances reject actors not assigned to a
configured step. An assignment never grants the capability needed to decide;
the ordinary `AuthorityGrant` check remains mandatory.

The migration cohorts preserve this boundary. `wf_step_assignee` rows require
explicit target actor mappings, process scopes, and step capabilities; they do
not import legacy super-user bits or create role permissions.
