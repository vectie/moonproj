# Continuing a research-backed decision

The existing MoonFind decision JSON import accepts the same v1 envelope and
worksheet. Optional continuation fields preserve up to 20 historical worksheet
versions and per-option historical source/claim receipts. Old exports without
these fields continue to import unchanged. Unknown metadata is still discarded.

After reviewing the import, **准备可编辑草稿** makes one local planning draft.
The complete typed research history survives browser draft save/restore and is
included in the founder packet export. The existing research details preview
and draft context show it through the same packet renderer.

Historical versions and source receipts are explicitly labeled historical and
are never inserted into current evidence. A cleared active citation remains
Unknown even if its historical ID matches a current source with different
content. Carried user assessments, reasoning, chosen option and next action are
not newly validated findings. No formal task, company decision, runtime action,
evidence acceptance, customer demand or payment is created by importing them.

The consumer rejects repeated/out-of-order/future or cross-run history revision
IDs, more than 20 versions, and malformed bounded historical worksheet shapes.
The existing two-million-character import limit applies to the complete
decision JSON. Historical unresolved references remain explicit text for
inspection; they do not resolve against current sources.

Qualification uses exact bytes emitted by MoonFind's actual `choice_export_json`
for current, changed-source and removed-source cases, then exercises preview,
prepare, local draft serialization/restoration and founder packet export.
The tests are fixture-backed; no provider run, browser session or Mac workflow
is claimed by this qualification.
