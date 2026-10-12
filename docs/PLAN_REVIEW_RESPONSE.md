# Return preparer replies to one reviewer

The existing offline plan-review worksheet now completes a reviewer/preparer/
reviewer loop. A preparer can hand one review's answers back without including
other reviewers' observations or responses. The reviewer resumes the original
submitted notes, reads the replies beside the exact source rows, and returns a
revised review through the existing notes format. This is feedback on an unchanged
snapshot, never acceptance of a plan or evidence that proposed edits were applied.

## Use and recovery

1. In Projects, download a new **offline plan-review worksheet (.html)** from
   the current draft. Existing HTML files contain the program at export time;
   older exports do not acquire these controls automatically. Retain the exact
   original template snapshot and returned review files.
2. In that worksheet's **Preparer feedback inbox**, import the returned reviews,
   enter the preparer label, and record explanations as usual. The overview now
   has **Download response packet for review N** beside each numbered review.
   Numbers distinguish separate submissions even when labels match.
3. Select the intended numbered review's button. Non-open dispositions in that
   review need a nonblank explanation; other reviews may remain unfinished.
   Verify `plan-review-response-N.json` was saved. It contains the complete plan,
   that original review, and only its preparer responses. It excludes other
   reviews, responses and imported filenames. Inspect it before manually sharing
   it with the reviewer along with the original compatible worksheet HTML.
   No communication or upload is performed by the worksheet.
4. The reviewer opens the HTML and uses **Load preparer response packet and
   resume original review**. Loading restores the original reviewer label,
   states and notes, and shows original observations plus preparer replies under
   their source rows. Replacement of unsaved review edits requires confirmation.
   The separate preparer inbox is untouched.
5. Edit review states/notes above the replies. Replies remain historical context
   tied to the original submitted observations, even after editing the current
   notes. **Download review notes JSON** saves the revised notes using the
   unchanged `moonproj.plan-review-notes.v1` format. Verify the download, then
   manually return it to the preparer. Keep the response packet to retain replies;
   the revised notes file does not embed preparer replies.
6. The preparer imports the revised notes through the existing inbox. Changed
   content is a separate submission with fresh open responses; the older review
   and its replies remain intact. Identical returned notes are deduplicated.
   There is no inferred identity, superseding policy, agreement or approval.

To resume later, reopen the HTML, load the response packet to inspect its original
context, and save any new review edits separately. Loading an ordinary saved-notes
file clears the old reply display, so replies cannot look attached to a different
review. To inspect replies alongside a later saved revision, keep two worksheet
tabs, one with the packet and one with the saved notes. There is no automatic
storage or combined reviewer-session save. Never close before verifying saved files.

## Compatibility and limits

`moonproj.plan-review-response.v1` contains exactly `schema`, `preparer`, `review`
and `responses`. The complete original review includes the exact source-template
string. Responses retain their annotation indexes and use review index zero in
this one-review packet. All required feedback items must be represented in source
row order. The existing inbox validation supplies the label/note limits,
response-association checks and non-open explanation requirement.

Loading requires the exact unchanged template string, including whitespace.
Changed plans need a new review; neither loading nor exporting migrates feedback
onto changed task descriptions, dependencies or budgets. A response file is limited
to 40 MB and supports the same source row bounds as the worksheet. Unfinished open
responses and zero-feedback reviews are supported and do not manufacture coverage.
Read/validation failure or a cancelled replacement preserves the current review
and replies. A newer review edit or file load supersedes any older pending read.

Both reviewer and preparer labels are self-declared. The packet is not signed,
authenticated or proof of delivery. Plain text rendering and the worksheet's
network-disabled content policy remain. The complete plan may contain private
information even though unrelated reviews are excluded. Download requests cannot
confirm a file save; the existing unsaved-edit warning remains best effort.

## Qualification and product rationale

Run from the repository root:

```sh
node --test scripts/test_plan_review_response.mjs scripts/test_plan_review_inbox.mjs scripts/test_plan_review.mjs scripts/test_trello_plan.mjs scripts/test_import_csv.mjs
```

Eight focused response tests plus 64 existing tests pass. The new tests execute
the production JavaScript extern renderer and generated worksheet handlers using
Node and a synthetic DOM. The full journey writes HTML/response/revised-review
files, reopens them, and imports the revised notes into the existing inbox.
No Moon invocation, dependency installation, browser, accessibility session,
PostgreSQL, native plan application or full-product acceptance was performed.
MoonBit function signatures and generated interfaces are unchanged. R50 remains
last fully verified cumulative; R51–55 remain separate.

MOONPROJ-UC07/B07 require review-pending plans bound to their inputs; N01 separates
drafts from company and financial authority. This closes the existing worksheet's
manual reply/resume gap without changing those authority boundaries. It does not
complete orchestration, signed approval, commercial closure or measured product
adoption, and does not upgrade any PRD requirement's qualification status.
