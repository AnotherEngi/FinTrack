# Transaction treatments and review workflow

Implemented in source on 2026-10-24. All 50 portable Swift tests pass on Windows.
The user now reports a successful native build and physical-iPad refund edit/
reopen pass, plus both Mac package suites passing. The four focused iPad checks
provisionally passed based on the user's report. Those reports predate the new
tabs and export. Backup/restore and device validation of this batch remain
outstanding. See [device-verification.md](device-verification.md);
syntax parsing on Windows alone does not establish Apple SDK compatibility.

## Transaction meaning

Posting status is Posted, Pending, or Needs posting review. Treatment is Spending,
Merchant refund, Income, Payment, Statement credit, Transfer, or Needs treatment
review. These fields are independent of the amount sign and approval state.

Amounts follow the confirmed positive-outflow convention: spending must be
nonnegative; merchant refunds and income nonpositive. Payments, credits, and
transfers permit either direction because the account perspective matters. Zero
is permitted. Changing treatment never automatically flips the amount sign.

`SpendingTotals` sums only Spending and Merchant refund, separating Posted from
Pending. Income, payments, statement credits, transfers, unresolved treatment,
and unresolved posting are excluded. It rejects Int64 overflow rather than
wrapping or rounding. An Exceptional Event remains included by default.
The UI labels these as spending for the shown transactions, not complete
household coverage. Complete source coverage/overview analytics remain future work.

## Approval and discussion

Approval is Unreviewed, Approved, or Not applicable. Discussion is a separate flag.
The old two-state review picker has been removed. Only an explicit Approve action
confirms a classification. A known, resolved, non-excluded category, Posted status,
and Spending or Merchant refund treatment are required.

Income, payments, statement credits, and transfers are Not applicable for spending
review. They can be edited and skipped, but cannot be approved or discussed in
this workflow. Pending or unresolved-posting purchases can receive notes and be
discussed; they cannot be approved until their posting status is resolved.

| Action/change | Effect |
| --- | --- |
| Approve | Confirms this transaction, clears discussion, appends a review decision |
| Discuss | Requires the user's own nonblank note or answer; requests discussion and preserves the current approval |
| Reopen | Makes the transaction Unreviewed and clears discussion |
| Skip | Saves valid pending input, advances without approval or a review-decision event |
| Mark reviewing in ChatGPT | Explicitly records the user's workflow state on a requested discussion; preserves approval and creates a review decision, without contacting ChatGPT |
| Note/answer edit | Preserves approval and discussion |
| Category, tags, Exceptional Event, amount, payee, dates, posting, or treatment change | Reopens approval; retains discussion while the transaction remains reviewable |
| Change to an excluded treatment | Makes approval Not applicable and clears discussion |
| Identical edit | Does not create a revision; tag ordering alone does not revoke approval |

Approve, Discuss, and Skip advance to the next ordinary outstanding item in the
current visible range/filter, or close the editor if none remains. Reopen stays
on the record. Failed/invalid edits remain recoverable drafts and block review
actions. Saved input precedes the explicit review action; an action failure does
not erase the user's separately saved note/classification edits.

Actions use a request UUID, transaction UUID, expected record revision, and action
kind. The per-record decision history preserves requests and applied revisions.
An exact retry returns the existing/latest record without repeating the action;
reusing that ID for different content on the same record fails. A stale new
action cannot overwrite newer edits. Replaying an old approval after a later
classification edit does not reapprove the record. Global exchange-level
deduplication and cross-record operation reconciliation remain future work.

These are local review actions. Discuss does not contact ChatGPT, and a local
decision is not an upload or remote processing receipt. Selected-record manual
packet export is implemented; returned suggestion import is not. See
[chatgpt-export.md](chatgpt-export.md).

Existing discussion flags decode as awaiting export. The user can explicitly
mark a discussion as reviewing in ChatGPT; neither exporting nor app backgrounding
does so automatically. Approve/Reopen clear discussion progress. Requesting a
new discussion returns to awaiting export. Table details stay on the selected
record after an action; the older drilldown/question review flow can still advance.

Category and individual-tag origins are now stored separately from approval.
Manual classification edits mark only affected origins as user; retained tags
keep their origins. Approval/reopen does not rewrite provenance. Older missing
origin/source metadata stays unknown. Source changes reopen approval, while
note/answer-only changes preserve it. Session markers track successful distinct
commits/actions for this process, including review decisions, not merely opening
a record. Table actions cannot bypass an unfinished raw draft.

## Note ownership and classification controls

User notes and user answers are editable. Assistant question, assistant reason,
and earlier ledger notes are distinct immutable context in the domain model and
read-only UI sections. Assistant text cannot satisfy the requirement for the
user's own discussion context and is never copied into the user-note field.

The prototype offers a small invented category catalog with stable IDs, including
unresolved and excluded choices to exercise approval restrictions. The catalog
is injected into the repository and is not an export of the user's taxonomy.
Category CRUD, subcategories, and split allocations are not implemented yet.
Transaction tags and Exceptional Event can now be edited; tags use semicolons in
the prototype UI, with 20 distinct values of at most 80 characters each.

## Storage evolution and old drafts

SwiftData schema 1's persistent fields are frozen. Schema 2 adds an optional
payload containing the validated domain record, including review state, history,
classification, raw-note ownership, and treatment. The original columns remain
as queryable mirrors and legacy history; reads verify that the payload matches
them. An inconsistent/corrupted record is rejected, never reset.

The explicit v1-to-v2 lightweight migration preserves original fields. Rows
without a v2 payload retain their amount, UUID, revision, timestamps, date, payee,
notes, and old review flag. Because v1 stored no treatment/category/posting state,
those migrate as unresolved and Unreviewed, with the earlier flag displayed as
legacy history. It is not promoted to a new category approval. This applies to
the early native prototype's flag; future migration of the website's actual
Confirmed classifications must retain its known taxonomy and genuine approvals.

Raw editor input moved into the portable `TransactionInput` value so old draft
decoding is tested on Windows. Incomplete text is retained verbatim; an old
`reviewStatus` becomes legacy metadata and cannot approve a transaction. Valid
edits retain this metadata as part of the saved domain record.

The separate positive-outflow marker guard remains in place. Unmarked earlier
negative-expense stores/drafts are blocked and preserved; schema migration does
not guess or convert their signs. Full sign-conversion and backup/restore flows
are still future work.

Apple references for the staged schema design:
[VersionedSchema and migration walkthrough](https://developer.apple.com/videos/play/wwdc2023/10195/),
[MigrationStage](https://developer.apple.com/documentation/swiftdata/migrationstage).

## Verification and next work

Portable tests cover explicit approval, pending/unresolved restrictions, note and
assistant ownership, classification reopening, discussion, Skip/Reopen, stale and
repeated actions, sign/tag/catalog validation, spending exclusions and overflow,
history serialization, and old-record/raw-draft decoding. Existing money/date,
stable-fixture, and revision tests continue to pass. Twelve additional tests cover
display selection, totals/exclusions, questions/history, and export privacy,
precision, escaping, determinism, and invalid selections. Sixteen further tests
cover the table's source/provenance, legacy payloads/drafts, session markers,
discussion progress, date ranges, and all-column sorting (50 tests total).

Twelve Apple persistence tests are authored, including v1 migration preservation,
review/comment history after reopening, and action write-failure rollback/retry.
The four new tests cover source/provenance/progress reopening, old v2 payload
compatibility, idempotent example append, and append rollback/retry. The user
reports earlier FinTrackCore and FinTrackPersistence suites passed on Mac;
test logs/counts were not supplied. Before real data, verify the full iPad
workflow, backup/restore, and migration readiness using synthetic records.

Next model work: original bank source/account IDs and raw provenance, full taxonomy and
subcategories/splits, reimbursement accounting, source coverage, and the first
versioned manual ChatGPT suggestion import following device validation of the
export. No cloud sync or LLM API billing has
been added.
