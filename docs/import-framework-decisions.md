# Import framework decisions and implementation sequence

Confirmed by the user on 2026-10-25 following review of
[the supplied requirements](import-framework-requirements.md). Those framework
requirements are prerequisites for the real migration. This document records the
user's exceptions/clarifications and takes precedence where they differ.

## Confirmed decisions

1. **Require the full framework before real import.** Read-only preservation of
   splits/subcategories/reimbursements is insufficient. Do not use the prototype
   v1 history format for the real migration. Publish the revised complete contract
   and capability/acceptance evidence first. The app's initial-history action is
   blocked while this gate is unmet; the old decoder remains for synthetic tests.
2. **Defer merchant refunds to a separate import.** The next ChatGPT request must
   separate refund rows from the proposed initial history, preserving them for a
   later dedicated contract. This is an explicit exception to the previous single
   complete-history-file plan, not permission for arbitrary partial history files.
   Weekly intake and full backups remain separate protocols.
3. **Use gross purchases until linked refunds arrive.** The later refund import
   reduces the original purchase dates/categories. Identify any purchases already
   netted down in the Sheet before export, to prevent double subtraction. Do not
   guess gross amounts or purchase links. No legacy refund-date reporting mode is
   requested by this decision. Preserve actual receipt dates and reconcile the
   temporary difference caused by deferring refunds explicitly.
4. **An unresolved question means currently unapproved.** Earlier approval
   evidence remains historical evidence; it does not approve a record with an
   unresolved question. Historical approval by itself must not delete that
   question. A new explicit Approve action still closes the current discussion.
   Do not confuse a retained, already-resolved historical question with a current
   unresolved one; retain uncertainty rather than fabricating a resolution.
5. **Six months means the current partial calendar month plus five preceding
   full calendar months.** Through 2026-10-25, that is 2026-05-01–2026-10-25,
   inclusive. Other preset meanings have not been changed by this clarification.
6. **Reporting timezone: America/New_York. Week start: Monday.** Reporting today
   and custom date pickers use these defaults independently of the device zone.
   Date-only ledger values are not shifted as if they were UTC instants. Source
   timestamps/zones and conflicting source report definitions need explicit
   representation in the revised framework.
7. **Do not manage the original workbook/export.** The user retains it separately.
   Do not add workbook copying, attachments, bookmarks, fingerprints, source-file
   references or backup management. This overrides the optional artifact feature
   in section 7 of the supplied document. Normal typed records, archival financial
   fields, migration audits and import-payload replay fingerprints remain app data;
   the original workbook is not a FinTrack-managed artifact.
8. **The pre-release framework rebuild does not preserve obsolete development
   formats.** Use one current financial model/store schema and one current
   contract for each operation. Replace prototype decoders, schemas and
   compatibility-only fixtures rather than carry them forward. Backup/restore
   tests cover the current format; old-development-backup reading and schema
   migration chains are not deliverables. Format identifiers can still reject
   incompatible files clearly. No existing data is silently deleted or reset.
9. **Ask before choosing preservation for a breaking architecture change.**
   Explain the affected data/objects and ask what needs to survive before adding
   multiple revisions, compatibility branches, adapters or migrations. A prior
   answer for the same change is sufficient. The current pre-release decision
   does not authorize silently choosing compatibility or reset for future changes.
10. **Primary category and proportional refund choices.** Never create a Mixed
    category. An unsplit purchase uses its primary category; the user chooses
    additional categories and their dollar amounts. A proportional refund
    allocation may be offered for explicit confirmation; no proposal is applied
    automatically. The proposed calculation basis is remaining refundable
    allocation balances with exact-cent rounding, to be specified in the contract.

## Next ChatGPT request

Use [the audit and refund-partition request](chatgpt-import-audit-request.md),
not the old real-migration generation instructions. It requests an audit before
any revised import JSON exists. No source financial files were read in this
workspace. Private audit/export results stay outside this public checkout.

The future import audit must account for every source row as an initial active
record, retained historical/superseded record, deferred refund, or explicitly
excluded row. Deferred refunds are not silently dropped or presented as if the
entire source history were already incorporated. Preserve stable purchase IDs
for the later refund references. The refund supplement must be atomic, replay
safe, revision checked and independently reconciled against the initial import.

## Implementation sequence (planned, not complete)

1. Define one coherent current financial model and draft contracts using the
   requirements handoff and independently invented fixtures. Include categories/
   subcategories/definitions, balanced allocations, financial lifecycle versions,
   historical decisions, current discussions, typed relationships, reporting
   settings and explicit unknowns. Separate permanent financial facts from
   transient assistant content. The developer does not need private audits or
   real records; actual source decisions stay with the user/finance workflow.
2. Implement and test the accounting rules in FinTrackCore: primary-category
   purchases and explicit splits, active/superseded eligibility, benefits and
   partial/combined reimbursement receipts, refunds, and independent controls.
   Preserve unknown periods/eligibility and require confirmation of proportional
   refund proposals. Never fabricate received funds, source links or allocations.
3. Persist the current model directly with one current store schema, current
   drafts and one current backup/archive layout. Reuse useful operational code
   for exact money, atomic saves, recovery and iCloud upload confirmation. Replace
   obsolete prototype structures/readers instead of wrapping or migrating them.
   Verify save failure, restart, rollback and current-format backup/restore. Any
   actual reset of test state must be explicit, not a silent startup side effect.
4. Connect editing, filters, reports and ChatGPT context to the current model.
   Count parents once; keep gross spending, reimbursements and net cost distinct.
   Preserve source evidence, note ownership, review state and source comparison
   baselines. Retain the approved table/two-chart UI and New York/calendar rules.
5. Finish one current contract for each distinct operation: initial non-refund
   history, dedicated deferred refunds, weekly intake, ChatGPT review and backup.
   Do not support multiple revisions of any contract without asking the user.
   Include complete partition/column accounting, independent debit/credit/net/
   spending/source/tab/treatment controls, concrete previews, atomic commitment,
   exact replay checks and explicit reconciliation of changed facts. Update
   producer instructions and synthetic fixtures together with the current schema.
6. Trace every acceptance case in the requirements/developer handoffs to actual
   tests. Run all available Windows checks, Mac persistence/build checks and one
   combined iPad/current-format iCloud backup/download/restore session. Publish
   the complete current contracts, capability matrix and validation evidence.
   Keep real import blocked until all agreed financial behavior is implemented
   and validated. Prototype compatibility is not part of this completion gate.

Implemented in this follow-up: calendar-month six-month bounds, explicit New York
reporting-date defaults/Monday grouping, initial-migration pause, and these
decision/audit documents. The full financial framework is **not implemented yet**.

## Verification

The preservation-policy/plan revision changes documentation only. Existing
runtime compatibility code has not been removed in this planning update; its
replacement belongs to the framework implementation. Earlier test evidence below
remains historical. No new runtime tests were needed for this documentation edit.

All **121 portable tests passed** on Windows Swift 6.4.1, including the new
six-calendar-month boundary checks and New York winter/summer midnight checks.
All **19** native source/test files passed syntax parsing. The date-picker/table
UI and migration block still need the Mac build/device checks; parsing does not
typecheck Apple frameworks. No real financial data was read or imported, and no
commit/push was performed by the agent. The financial framework acceptance cases
are future work, not covered by the calendar tests.
