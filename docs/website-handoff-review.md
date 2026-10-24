# Website handoff review

Reviewed 2026-10-24. This review adds the existing product's behavior to FinTrack's
planning baseline. It does not import financial data, port website code, or change
the native implementation.

## Source and verification

The user supplied `HouseholdFinance_Codex_Handoff.zip` in Downloads and authorized
extraction there. Extracted to:

`C:\Users\rproi\Downloads\HouseholdFinance_Codex_Handoff`

All 61 files listed in the enclosed SHA256SUMS.txt matched their supplied hashes.
The ZIP contains 62 files including that manifest. Its metadata identifies website
saved version 16, package 0.8.2, and source commit
`917c0ae48120bf62b625ff9f0e1d13b81b1006e2`. This verifies the extracted files against
the supplied manifest, not independently against a remote repository.

Read the handoff instructions and all five handoff documents, the website README,
protocol and ledger mapping, architecture sections, the core review/validation and
status modules, reimbursement helpers, key overview and ledger-adapter logic,
and representative approval/discussion, adapter, overview, and form tests.

The historical website remains unchanged outside this repository. Do not copy
its hosting configuration, original account/spreadsheet identifiers, private
benefit settings, real queues, or processing journals into source control. The
handoff states that live financial data and credentials were not exported.
No financial services, existing Site, Sheet, or connected account were accessed.

The handoff reports 127 Node tests: 126 passed and one date-dependent form test
failed. Inspection confirms that test seeds the current date but asserts a fixed
review-period label. Its later assertions did not run in the reported baseline.
The check script also uses URL.pathname for child-process paths, which needs a
Windows portability review. These historical tests were not rerun here, and no
browser/iPad visual behavior was verified. Existing FinTrackCore verification
is now 22 passing Windows tests, including subsequent treatment/review and draft
compatibility work. This documentation review added no native
build or domain-test coverage.

## What the existing website actually does

The website is a review interface, not the authoritative transaction database.
An external ChatGPT workflow publishes a Drive review queue from a Sheet. The
browser records immutable feedback events; a separate processing pass validates
them, writes targeted Sheet fields, verifies readback, and publishes receipts.
It does not invoke an LLM or update the Sheet directly from the browser.

Browser tokens and financial queue snapshots live in memory. IndexedDB retains
unsent feedback, and the service worker caches the app shell rather than a full
financial ledger. This helps explain why reconnecting and offline record access
were poor fits for the desired native app. Replacing the browser UI alone would
not resolve those ownership and authorization constraints.

FinTrack's newer confirmed direction remains one user on one iPad, with a durable
app-owned local ledger and Apple cloud backup. The Sheet and Drive architecture
is historical context and possible migration input, not the selected native
storage architecture. Do not reintroduce it automatically.

## Behavior to preserve

The gap column below records the initial scaffold at handoff review time.
Subsequent implementations of treatment, review, notes, tags, and event flags are
described in [review-workflow.md](review-workflow.md); full website parity remains
incomplete.

| Area | Evidence and inherited rule | Native scaffold gap |
| --- | --- | --- |
| Approval | `dist/core.mjs` and core/discussion tests: each transaction requires explicit approval; suggestions, comments, confidence, and merchant rules cannot approve it | Only a two-state review picker exists; full approval rules are absent |
| Review actions | Approve, Discuss, Skip, and Reopen are distinct. Discuss saves context and requests follow-up; it does not itself confirm or revoke a classification | No discussion or action history model |
| Reopening | Classification, tags, or Exceptional Event changes reopen approval. Notes alone preserve prior approval. Explicit approval clears discussion | No classification change/reapproval machinery |
| Eligibility | Pending transactions can be annotated/discussed but cannot be approved. Payments, statement credits, unresolved categories, and conflicts have explicit restrictions | No posted/pending state or accounting treatment field |
| Comments | User notes, assistant questions/reasons, user answers, and read-only legacy ledger notes have separate ownership | Only one user note field exists; future AI output must not be placed there |
| Money | Exact integer cents and balanced allocations; legacy convention is positive spending, negative merchant refunds | User confirmed matching this convention; examples/guidance now align. Old unmarked native stores need explicit migration; other imports need sign mapping |
| Source identity | Original transaction IDs, account/source references, posted/activity dates, raw descriptions, related-record links, and source revisions survive edits/import | Local UUID and one date do not replace these fields |
| Splits | Allocation amounts must balance; category shares must not duplicate the whole purchase in reports | No allocation model yet |
| Tags/events | Tags belong to individual transactions. Exceptional Events are included until explicitly filtered out; overlapping exclusions count once | No tags/event flags or overview engine |
| Reimbursements | Expected is context, not received cash or reduced spending. Received needs actual repayment evidence/linkage | No reimbursement model; legacy flags alone are not full accounting |
| History | Multiweek review plus longer spending history, category drilldown, comparable periods, explicit available coverage, and unavailable detail labels | Basic date browsing/search only; no coverage or spending analytics |
| Processing | Local save, queued, uploaded/unprocessed, applied, rejected, failed, and conflicting are different outcomes | Only local save/draft state exists |
| Conflict/replay | Stable operation IDs, explicit base revisions, preserved competing edits, replay checks, processing journal and receipts | Integer revision guards and UUID duplicate checks are only a starting point |

The requested taxonomy includes separate electricity, natural gas, and water;
distinct Travel Airfare, Travel Hotel, Travel dining, and Other travel; medical
subcategories including Fertility and Dental; and Holiday Overhead separate from
Gifts & donations. The handoff reports that Dental and Holiday Overhead were
requested but not found as literals in exported source. Private queue taxonomy
was not inspected, so do not claim those are already configured. Personal benefit
limits and trip-specific values remain private migration configuration; use
invented values in tests.
Do not infer benefit eligibility or an annual reset from a configured limit.

The legacy Sheet has two allocation slots and one shared subcategory cell.
Those are adapter limitations, not native product requirements. The sample web
protocol allows more allocations. Native split count and per-allocation
subcategory design still need a deliberate decision.

The old review patch cannot change source amount, identity, or account; it changes
classification/context fields. That restriction must not block the user's native
manual add/edit flow. Separate user record editing from AI review proposals, and
define exactly which fields AI suggestions may propose.

## ChatGPT exchange clarification

The handoff recorded a preference to avoid routine manual file downloads/uploads.
After this discrepancy was raised, the user explicitly confirmed on 2026-10-24:
**manual file exchange is acceptable initially**. Therefore the first native
exchange can use user-selected review packets and returned proposals. A less
manual bridge remains a later option, not a prerequisite for the initial version.

Preserve both in-app feedback and feedback given directly in chat. The old
"feedback is ready" processing trigger is useful workflow context; it grants no
automatic access to previous conversations, files, or connected accounts. Every
review packet must contain the explicitly chosen records and necessary rules.
Return explicit operation IDs, base revisions, proposed changes, and outcomes.
Do not equate a returned file, upload, or acknowledgement with an applied result.

The existing feedback protocol is valuable behavioral evidence, not a drop-in
native import contract: its authoritative owner is the Sheet, source revisions
are fingerprints, record IDs may be arbitrary strings, and its patch fields are
limited. Design a versioned native packet deliberately. Local UUIDs and integer
revisions should coexist with preserved source IDs/revisions. Compatibility with
the old JavaScript protocol also needs its safe-integer range checked.

Apple cloud backup and ChatGPT exchange remain separate: iCloud Backup/Drive
availability does not establish ChatGPT access to the iPad store or backup files.
No cloud sync or hosted bridge was implemented during this review.

## Revised next steps

1. Refine the native domain before adding more screens: source identity/accounts,
   posted/activity dates, transaction treatment, explicit approval/discussion,
   separate comment ownership, categories/allocations, and exact sign mapping.
   Port behavioral examples as synthetic Swift tests rather than guessing rules.
2. Validate the current SwiftData save/reopen/draft slice on Mac/iPad; add category
   editing to that small slice. Introduce new versioned schemas with migration
   fixtures as fields grow; preserve existing stores on failure.
3. Prove an early synthetic app-to-ChatGPT-to-app file round trip before broad
   UI expansion: classification suggestion, app comment, chat correction,
   explicit accept/reject, stale revision, repeated import, and offline recovery.
4. Build full app-level backup/restore and test actual iCloud device backup before
   any real-data migration. Then expand splits, reimbursements, and overview
   reporting using inherited acceptance examples.
5. Obtain a separately authorized private migration export only when ready. The
   ZIP is not the live ledger: original records/taxonomy, approvals, outstanding
   feedback, receipts/journals, and coverage must be reconciled independently.

The user subsequently confirmed matching the legacy positive-outflow convention.
Native examples now use positive expenses and negative refunds/income, and
unmarked earlier stores are preserved behind an explicit migration requirement.

Still open: exact first import/export schema, source-specific sign conversion and
old native store migration, split model limits, partial reimbursement matching,
source-coverage representation, archive protection/retention, and installation
lifecycle. Core USD support matches the exported reference; additional currencies
are not established. Current live data/configuration remains unknown.
