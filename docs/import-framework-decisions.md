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

1. Define the versioned financial structures and source mapping: category and
   subcategory definitions, signed balanced allocations, complete lifecycle
   versions, historical decisions, text ownership including unknown authorship,
   typed relationships, reporting settings and explicit unknowns. Keep raw source
   facts distinct from edits and current eligibility. Obtain the source audit to
   expose differences; do not invent settings from its absence.
2. Implement splits/subcategories throughout editing, filtering, review exchange
   and allocation-based reporting. Count each parent once. Exclude superseded
   versions from active totals while preserving their original facts and evidence.
3. Implement benefit/program configuration and reimbursement/repayment allocation
   accounting, including partial/combined receipts and cumulative bounds. Expected
   reimbursement must not reduce spending. Keep gross spending, receipts and any
   net-cost presentation distinguishable; do not invent eligibility or resets.
4. Carry every supported field through persistence, migrations, archived source
   fields, offline drafts, backup/restore, export and ChatGPT context. Version
   incompatible contracts consistently; retain deliberate legacy read support.
   Preserve user edits and validate entire relationship graphs before commit.
5. Publish the revised main-history contract and dedicated deferred-refund
   contract. Add complete per-row/column disposition, independent debit/credit/
   spending/net/source/tab/treatment controls and explicit reporting differences.
   Provide concrete previews and atomic/recoverable import paths, including
   source-ID uncertainty, replay and stale-version handling.
6. Demonstrate all eleven acceptance cases from the supplied framework with
   synthetic fixtures, run all available portable/native checks, then validate a
   complete backup/download/restore on iPad for that revision. Return the final
   contract, supported-capability checklist and remaining limitations before the
   user generates or imports real data.

Implemented in this follow-up: calendar-month six-month bounds, explicit New York
reporting-date defaults/Monday grouping, initial-migration pause, and these
decision/audit documents. The full financial framework is **not implemented yet**.

## Verification

All **121 portable tests passed** on Windows Swift 6.4.1, including the new
six-calendar-month boundary checks and New York winter/summer midnight checks.
All **19** native source/test files passed syntax parsing. The date-picker/table
UI and migration block still need the Mac build/device checks; parsing does not
typecheck Apple frameworks. No real financial data was read or imported, and no
commit/push was performed by the agent. The financial framework acceptance cases
are future work, not covered by the calendar tests.
