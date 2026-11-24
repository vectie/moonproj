# GitHub issue export to an editable plan

In Projects, select a project and open the plan template panel. Paste a saved
JSON issue export and choose **预览 GitHub Issues JSON**. Choose the planning
preparer and use the existing template replacement or phase-append controls.
Then edit task owners, dependencies, milestones and budgets and save through
the existing project plan workflow.

A standard export can be prepared separately with:

```sh
gh issue list --state all --limit 100 --json number,title,body,url,state,assignees,milestone,labels > issues.json
```

The importer itself is offline and does not invoke this command or contact
GitHub. An array of these issue objects also works for GitHub Enterprise issue
URLs and combined exports from several repositories. The URL's issue number
must match `number`. Open issues become tasks in input order. Closed issues
are counted and excluded. Between one and 100 open issues can be imported.

Title is the editable task name. Issue URL, body, assignees, labels and source
milestone are retained in plan notes, including when appending a phase. Task
IDs in the preview distinguish repository and host; the existing apply/append
workflow remaps task IDs. Source assignees and milestones are context only:
assign real plan owners and milestones using existing controls. No completion,
acceptance, execution or engineering release state is inferred from GitHub.
Comments, attachments, reactions and other export fields are not imported.
Keep the original export if those fields are needed.

## Focused verification

```sh
node --test scripts/test_github_plan.mjs scripts/test_trello_plan.mjs
```

These tests execute the production JS converter and check the UI wiring. They
cover multiline/Unicode issue bodies, distinct repository identities, closed
issue exclusion, deterministic conversion and repairable malformed input.
They are not a browser session or signed gateway persistence qualification.

Current cloud validation also executed the actual MoonBit converter/template
reader and replacement/phase-append against a USD plan (1/1 passed). Unpriced
source imports adopt the destination currency on append without introducing
costs or changing the existing budget. The production batch task-table importer
ran separately (1/1 passed), retaining an editable Draft, not service tasks.

With moonc 0.10.16 the restored source contained removed `try?` syntax. Three
existing product files received equivalent `try Ok(...) catch { e => Err(e) }`
replacements. A separate private Rabbita 0.12.4 overlay makes the same single
syntax substitution; original bytes, hashes and patches are in evidence/R795.
Frontend check passed with pre-existing warnings. Browser interaction, signed
service persistence and release gates were not exercised.
