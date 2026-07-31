# Project-plan adapter conformance

The release slice is conformant only when focused validation proves:

1. the manifest, adapter declaration and native constants publish the same
   operation, schema, authority and claim identities;
2. domain `ProjectPlan` rejects invalid dependency order;
3. planned cost plus contingency cannot exceed the declared envelope;
4. every owner, milestone, gate, risk and source-evidence reference resolves;
5. execution is idempotent and reconciliation resumes from durable intent;
6. stored source evidence still matches its declared SHA-256 digest;
7. the output remains `pending_review` with all business-effect flags false;
8. health evidence is content-addressed and expires within one hour.
