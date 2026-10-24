# Initial data model

Status: first synthetic prototype, 2026-10-24. This document records provisional
implementation conventions; it does not finalize bank import or ChatGPT formats.

## Implemented values

| Value | Representation and invariant |
| --- | --- |
| Money | Signed `Int64` minor units plus currency; USD only in this prototype. Confirmed positive outflows/expenses and negative inflows (refunds/income); zero permitted. No Double conversion or silent rounding |
| Amount entry | ASCII digits with optional sign and one/two decimal places; dot separator, no grouping or scientific notation. Reject excessive precision and overflow |
| TransactionDate | Valid Gregorian calendar date, serialized as `YYYY-MM-DD`, with no timezone or time of day |
| PostingStatus | Posted, Pending, or Unresolved; unknown older state is never inferred from amount sign |
| TransactionTreatment | Spending, Refund, Income, Payment, Statement credit, Transfer, or Unresolved; controls spending/review eligibility separately from sign |
| ApprovalStatus | Unreviewed, Confirmed, or Not applicable; independent discussion flag and explicit Approve/Discuss/Reopen actions |
| TransactionDraft | Date/optional activity date, payee, money, user notes/answer, posting/treatment, category ID, tags, Exceptional Event, and preserved legacy flag |
| LedgerTransaction | UUID, positive revision, timestamps, validated draft, approval/discussion, immutable assistant context, and review history. Stale edits/actions fail; identical edits are no-ops |
| TransactionInput / EditorDraft | Portable raw incomplete text plus app wrapper UUID/expected revision/creation time. Stored separately so invalid input does not corrupt ledger records |

`TransactionDraft` is a domain edit value. `EditorDraft` additionally retains raw
input such as an unfinished date or minus sign, which is not a valid transaction.
`TransactionInput` lives in the portable package and is tested with old draft
formats; the EditorDraft wrapper lives in the app layer. Neither is a ChatGPT
exchange contract. See [review-workflow.md](review-workflow.md) for exact rules.

## Website reference alignment required

The subsequently supplied website handoff establishes richer behavior than this
initial model. See [website-handoff-review.md](website-handoff-review.md).

- The user confirmed the legacy positive-outflow convention. New examples and
  editor guidance use positive expenses and negative refunds/income. Amount sign
  does not identify treatment; income, refunds, transfers, and payments must still
  have separate semantics. Other source formats need deliberate sign mapping.
- Preserve original source transaction/account IDs, revisions/fingerprints,
  posted/activity dates, descriptions, related records, and provider provenance
  alongside local UUIDs. Source IDs are not necessarily UUID strings.
- Explicit approval, independent discussion, eligibility checks, and separate
  comment ownership are now implemented. Processing/upload receipts are still
  future work; local decisions do not imply ChatGPT processing.
- Expected reimbursement is not received cash. Reimbursement accounting and
  source coverage remain future work; missing history must not become zero spend.
- Design balanced allocations with subcategories/tags without inheriting the
  Sheet's two-slot/one-subcategory limitation by accident.

The remaining gaps need synthetic tests before real import or broad native UI
expansion. Manual review packet exchange is allowed initially; its native schema
has not been finalized. Category selection currently uses an invented catalog;
full taxonomy management and balanced splits are not yet implemented.

Eight synthetic weeks contain three records per week (24 total), covering
2026-08-01 through 2026-09-21. IDs are deterministic; payees, amounts, and notes
are invented. Loading them is explicit and only permitted with an empty ledger.
The sample includes positive grocery/transit purchases, negative paycheck inflows,
and a negative grocery refund. Entry and JSON round-trip tests preserve these
signs exactly.
Some invented transactions have explicit fictional approval history; a pending
purchase and separated assistant context exercise the review UI. Demo loading
does not create approval from a merchant/category rule.

## Persistence prototype

`FinTrackPersistence` now uses SwiftData schema 2.0.0. Frozen v1 fields remain as
queryable mirrors and legacy metadata; an optional payload stores the richer
validated domain record. Reads check payload/column agreement and catalog-based
approval validity. Existing v1 rows without payload preserve original fields and
their earlier review flag, with unknown posting/treatment/category unresolved and
current approval Unreviewed. Do not confuse that prototype flag with an actual
website classification approval. No store is reset after read/migration failure.
An explicit lightweight v1-to-v2 migration and preservation test are authored but
have not run on Mac. Full details are in review-workflow.md.

The agreed amount convention is recorded separately in
`FinTrack.store.amount-sign` as `outflow-positive-v1`. Schema evolution does not
change signs or bypass the guard. Before
opening a database, the repository checks its marker. Unmarked existing stores,
SQLite sidecars, or orphaned draft files are preserved and require an explicit
migration. Unknown markers are rejected. Only a fresh store/draft location gets
a new marker. This prevents pre-decision negative-expense prototype values from
being silently reinterpreted; conversion of those files is not implemented yet.
Backups/restores will need to preserve and validate the marker. Native tests cover
unmarked-store and orphaned-draft preservation and unknown-marker rejection;
they still require execution on Mac.

The repository uses a private main-actor context with autosave disabled. It
checks duplicate IDs before insertion, checks expected revisions for edits and
review actions, explicitly saves changed records, and rolls back on write failure.
Per-record review request IDs support exact retries and reject content reuse;
Skip and identical edits do not create revisions or decisions.
All in-app windows share one repository. Cross-process/multi-device writes and
bank duplicate matching are outside this prototype's guarantees.

Valid editor changes save immediately as the SwiftUI input changes. This can
commit intermediate valid values while typing (for example, `1` before `12.34`).
Invalid intermediate values stay in a separate draft. Every changed input is
written as a recoverable draft before a ledger commit is attempted. On success,
that draft is removed; on failure, it remains available under Unsaved Drafts.
If even the draft write fails, the editor shows an error and disables ordinary
dismissal until a retry succeeds or the user explicitly discards unsaved input.
Saved edits are not undone by discarding a remaining draft.

A crash between a ledger save and draft cleanup can leave an older draft behind.
Its old expected revision prevents silent overwrite; the user can inspect it
and discard the unsaved draft to reopen the current record. Automatic merging
is deliberately absent. Verify these lifecycle behaviors on iPad.

## Deferred model decisions

The positive-outflow sign convention and inherited review semantics are settled.
Confirm additional currency needs and source-date mappings before real-data
entry. Add source/account provenance, full category/subcategory management, and
balanced split lines. Tags/Exceptional Event are editable now, with full reporting
filters still future work.
Define reimbursements and links to receipts without double-counting. Define bank
source IDs/provenance separately from local UUIDs before adding imports.

These additions will need new versioned schemas, migration fixtures, and tests
that preserve existing data. Full backup archives must cover all such records
and relationships. Neither backup nor AI proposal file schemas are implemented
by the current JSON Codable conformance.
