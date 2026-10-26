# Current financial framework contracts

2026-10-25. One current model and one contract per purpose. `schemaVersion` is
**2**. Retired development JSON, drafts and SwiftData schemas have no reader or
migration chain. A version number rejects incompatible data; it does not promise
compatibility. Ask the user what must survive before a future breaking change.

Normal history/refund import actions are enabled for current-contract files, with
preview and explicit user confirmation. The 2026-10-26 product fix removes the
unconditional application gate so synthetic end-to-end validation can run. Actual
real-data intake should follow successful iPad/backup checks and private source
reconciliation. No schema revision, fixture allowlist or validation bypass is added.
The examples are invented fixtures, not a template containing private values.
The importer validates a received payload; it cannot prove that every source cell
was inspected. Private independent source controls are still required.

## Operations and examples

| Purpose | Producer / receiver | Current example |
| --- | --- | --- |
| `fintrack-history-import` | Finance workflow → initial separate ledger | [history.synthetic.json](examples/history.synthetic.json) |
| `fintrack-refund-import` | Finance workflow → the same committed migration | [refunds.synthetic.json](examples/refunds.synthetic.json) |
| `fintrack-weekly-intake` | Collector/finance workflow → add/reconcile preview | [weekly.synthetic.json](examples/weekly.synthetic.json) |
| `fintrack-review-request` | FinTrack → ChatGPT; pending or full history | [review-request.synthetic.json](examples/review-request.synthetic.json) |
| `fintrack-review-response` | ChatGPT → answer display and optional proposed edits | [review-response.synthetic.json](examples/review-response.synthetic.json) |
| `fintrack-full-backup` | FinTrack → current framed `.fintrack` archive → FinTrack | Tested by `BackupArchive` / `NativeBackupArchive`; never use AI exchange as backup |

The example files are serialized from the actual Swift types and decoded by
`publishedCurrentContractExamplesPassTheActualDecoders`. Optional fields may be
omitted or null; required arrays/objects are supplied even when empty. Unknown
fields are rejected recursively, except intentional dictionary keys. Do not add
a field hoping it will be preserved. Put unsupported essential behavior in
`audit.blockers`; it blocks commitment. Unmodeled evidence belongs in a qualified
typed archival field, with its transformation explained in the column audit.

## Shared representations

- IDs: UUID strings for app records/allocations/programs/claims; stable string IDs
  for categories/subcategories. Generate app purchase UUIDs once. Row locators,
  provider transaction IDs, app UUIDs and account aliases have different meanings.
- Money: `{ "minorUnits": "1234", "currency": "USD" }`. USD only; exact canonical
  signed Int64 decimal strings. Outflows positive; merchant refunds, income and
  actual reimbursement receipts nonpositive. Never convert through floating point.
  Weekly rows and refund links use `amountMinorUnits` strings as shown in examples.
- Revisions: positive Int64 strings, including full record `revision`, local action
  `expectedRevision` and `appliedRevision`. No leading zeroes, fractional cents or
  scientific notation for money/revisions. Zero or missing never means unknown money.
- Calendar dates: `YYYY-MM-DD` strings, without timestamp/timezone conversion.
  App `createdAt`/`updatedAt` and local action times use Foundation seconds since
  2001-01-01 UTC. These are app observation/action metadata, **not** evidence of a
  source classification decision. Imported historical decision times use
  `TimestampEvidence {original, timeZone?, precision?}` or remain absent.
- `SourceValue`: `{kind, text?, boolean?}`. Kinds: `absent`, `unknown`, `null`,
  `text`, `number`, `boolean`. Empty text, numeric `"0"` and boolean `false` are
  distinct. Number text retains its original valid JSON-number spelling.
- Ownership: `userNote`, `userAnswer`, `assistantQuestion`, `assistantReason`,
  `ledgerFact`, `mixed`, `unknown`. Classification origin: `user`, `assistant`,
  `unknown`. Never assign all text in a mixed source column to one author.

## Authoritative record and catalog

Each `LedgerTransaction` holds id/revision, app timestamps, `draft`, current
`approval`, discussion intent/progress, assistant context, local review actions,
and classification provenance. Copy the complete object shape from the example.

`draft` contains date/activity date/source report date, payee, money, current
posting state and accounting treatment; primary category/subcategory; tags,
user notes/answers; `allocations`; refund links; `sourceVersions`;
`historicalDecisions`; owned `sourceNotes`; qualified `archivalFields`;
`reportedVisibility`, `reportedExceptional`, nullable current `exceptionalEvent`,
and explicit `questionState` (`none`, `open`, `unknown`, `resolved`). Original
source flags remain evidence when the user later changes display settings.

Posting is `posted`, `pending`, `unresolved`, or `superseded`. Treatment is
`spending`, `refund`, `reimbursementReceipt`, `income`, `payment`,
`statementCredit`, `transfer`, or `unresolved`. A negative sign never chooses a
treatment. Only active eligible posted purchases contribute to spending. Current
unapproved purchases are included when `reporting.includePostedUnreviewed` is true.

Categories and subcategories retain stable IDs, display label, stored source
label, definition `SourceValue`, unresolved/excluded flags and origin. Retain
unused entries. Never create a Mixed category. An unsplit purchase uses its
primary category. A split is one parent plus positive, exact same-currency
`ExpenseAllocation` values `{id,categoryID,subcategoryID?,amount,origin}` whose sum
equals the parent. No duplicate parent purchases. The editor asks for secondary
dollar amounts and calculates the primary remainder. Changing a referenced
allocation requires fixing any existing refund/repayment links first.

Source versions retain original amount, merchant, all separate dates/timestamp,
observed posting state, original treatment/classification/allocations/tags, safe
owned notes and historical decisions. `successorID` links versions **inside one
logical transaction**. Preserve full predecessors; never overwrite them with a
new posted observation. Supersession chains cannot fork, cycle or dangle. A
standalone superseded record may retain historical evidence without inventing an
unknown successor. Genuine bank identities are optional and must not be fabricated
from rows/hashes/UUIDs. Repeated observations under one provider ID remain versions
of that same identity; separate pending/posted provider IDs can still share one
logical app purchase.

Current approval is `unreviewed`, `confirmed`, or `notApplicable`. Any current
unresolved/unknown question requires `unreviewed`, including pending/excluded
records. Earlier approvals go in `historicalDecisions`, with known actor/origin
and decision time or explicit uncertainty. Pending/superseded approval evidence
never makes a version eligible posted spending. An explicit new Approve closes
the current discussion. Known resolved assistant questions/reasons are cleared,
including known-role archival fields; mixed/unknown/user/factual text survives.
Never bury cleared assistant text in immutable versions or source-link copies.

## Reimbursements, relationships and reporting

`accounts` retain app UUID, alias, provider and provider account identity as
SourceValues. They contain no credentials. Typed `relationships` are
`paymentCounterpart` or `duplicateCandidate`; neither creates a refund or deletes
a row. Duplicate candidates require explicit user reconciliation.

`programs`: UUID, label/currency, optional recorded money limit, `period`
(`unknown`, `calendarYear`, `fixedRange`, `rolling`, optional bounds/description),
eligibility `SourceValue`, recorded default SourceValues, origin. Missing periods,
eligibility, limits or balances remain unknown; defaults never create claims/cash.

`claims`: UUID, purchase UUID, optional program UUID, eligibility
(`unknown/eligible/ineligible`), optional expected money, status
(`unknown/notClaimed/submitted/partial/paid/denied`), optional
`sourceReportedReceived`, notes. A source-reported received value is evidence,
not a fabricated receipt. `repayments` link positive amounts from actual posted
`reimbursementReceipt` transactions to claims, optionally to an expense allocation.
One receipt can cover multiple claims and a claim can receive multiple receipts.
Total assigned from any receipt cannot exceed its magnitude. Overpayment relative
to an expected claim is visible as a negative outstanding balance, never clamped.

Overview distinguishes original gross purchases, spending after merchant refunds,
pending spending, actual receipt-date cash, and purchase net cost after assigned
repayments. Expected reimbursement changes none of these cash/spending totals.
Net cost uses repayments linked to selected purchases regardless of receipt date.
Unattributed repayments on a partially category-filtered purchase are omitted
from that filtered net-cost result with a visible limitation; assign a component
to resolve attribution. Category charts remain spending charts, not cash-flow pies.

`reporting`: New York timezone, Monday first weekday (2), optional source as-of date,
include-posted-unreviewed setting, original `sourceRules` evidence and structured
coverage per source/date interval (`complete/partial/unknown`, limitations).
Calendar presets use New York today. Six months starts at the first of the current
month minus five months and ends today. Source as-of/period/formula definitions
remain separate evidence, not a replacement for current app today. Source rules
are comparison context; unsupported essential behavior must be a blocker.
`sourceBaselines` retain original basis SourceValues and exact independent
controls; changing app settings never rewrites them as if they were new reports.

## Initial history audit and commitment

Top level: schemaVersion/purpose/id/amountSignConvention/sourceName; complete
non-refund `records`, `categories`, `accounts`, `programs`, `claims`, `repayments`,
`relationships`, `reporting`, `sourceBaselines`, global `knowledge`, and `audit`.
No workbook copy, URL, reference, bookmark or workbook fingerprint is managed.

Every source candidate row has a qualified unique `locator`, `kind`
(`financial/header/summary/helper/blank`), source/tab, and one disposition:

- `active`: one current retained logical record; amount/type must match exactly.
  This does not assert posted/spending eligibility.
- `historical`: retained source version UUID and logical record UUID; superseded
  evidence never additional spending.
- `deferredRefund`: future stable refund UUID, original negative money/type and
  locator; no refund is included in the initial records.
- `excluded`: non-record with explicit reason. Financial excluded rows retain
  amount/type for the complete source controls. Nonfinancial rows have no money/type.

Every qualified column has `name`, `handling` (`mapped/preserved/omitted`),
supported `target` or null for omission, explanation, `essential` boolean and
`tabs` array (empty applies to all). Essential columns cannot be omitted. Each
applicable preserved cell must exist in the record's qualified archival map,
including explicit absent/null/empty evidence. Mapping financial splits to
archival text does not implement them. `audit.blockers` must be empty before import.

Controls contain group/count/currency, positive debit magnitude, credit magnitude,
signed net, gross active posted spending, and exact basis
`all-source-rows-active-gross-posted`. Supply all groups: `all`, each `source:`,
`tab:`, `treatment:` and `partition:`. Include source excluded/historical/deferred
rows in debit/credit/net controls; count a current parent once for spending. The
app computes the same bases and requires all independent supplied values to match.
The finance workflow must obtain the supplied controls independently from the
complete private source, not copy totals calculated from its proposed JSON.

The initial import creates and reopens an isolated local database before switching
the active pointer. Replaying an identical committed migration preserves later
edits; changed same-ID input or another initial migration is rejected. A receipt
keeps payload digest, IDs and audit, not a workbook artifact or full raw JSON.

## Dedicated deferred refunds

`migrationID` must equal the committed initial import ID. Supply the complete
deferred locator/record-ID set **once**, refund records, and `purchaseRevisions`
mapping each referenced purchase UUID to its exact current revision. Amounts must
match deferred controls. This operation never replaces purchases or imports a
second history subset. Wrong stage, reused changed ID, missing/colliding IDs,
stale revisions, broken references, wrong type/currency and cumulative over-refunds
fail atomically. Identical replay is a no-op.

Refund links are `{purchaseID, allocationID?, amountMinorUnits, currency}`. Keep
actual refund receipt dates. Charts reduce the linked original purchase activity
date, falling back to posted date. A link without component attribution on a
split remains unresolved and visibly unallocated; never guess the category.
The optional proportional proposal uses remaining refundable component balances,
exact full-width integer products and deterministic largest-remainder cents
(ties by allocation UUID). It needs explicit confirmation before saving. Previous
unresolved category attribution blocks another proportional proposal. Unlinked
amounts remain flagged. Initial gross purchases and later purchase-date refunds
can legitimately differ from a source's refund-receipt-date reports; retain and
explain the comparison gap. Flag already-netted source purchase amounts first.

## Weekly intake and review

Weekly genuine `(sourceAlias, transactionID)` identities provide idempotence.
Changed facts need explicit reconciliation against a current record/revision;
similar date/amount/merchant is only a candidate. New-batch additions are atomic
and stop for ambiguous matches, including linked pending charges and earlier
rows in the same incoming batch. Reconciliation appends source versions and
preserves user category/tags/notes, while invalidating affected approval.

Review requests automatically include pending user changes/open discussions, or
full history on request; they include the full catalog, owned per-row evidence
and `financialContext` (accounts/programs/claims/repayments/relationships/reporting/
baselines/migration audit/refund receipts). Context never grants write permission.
Replies go in `answers`, requiring no acceptance. Actual classification proposals
may replace category/subcategory/tags/expense allocations only, with exact current
revision checks and explicit Apply Changes. They cannot alter money, user text,
approval, provider facts, refund links or program cash. Plain replies disguised
as proposals are rejected. Global guidance proposals have their separate review.

## Transport and limits

Explicit Copy defaults to local-only text expiring after one hour, with explicit
Paste for returned JSON. Clipboard cap: 256 KiB including instructions. JSON-file
fallback: 50 MiB. Never truncate or split a complete history into independent
partial imports. One optional JSON fence is accepted; prose/links/multiple objects
are rejected. No automatic clipboard reading, hosted bridge or LLM API billing.

Full backups use only current `FINTRACK-FINANCIAL-ARCHIVE` framed files with per-item
integrity checks and bounded optional native compression. Limits: 250,000 records,
1 GiB logical data, 2 GiB file, 80 MiB per item. These are format bounds, **not**
measured device capacity. Per record: at most 100 expense/refund allocations,
1,000 source versions/owned notes/archival fields and 10,000 historical decisions;
50 MiB exchange and memory/performance bounds can constrain practical history first.
Oversized complete history needs a designed transport revision, after asking the
user about preservation; it is not permission to silently drop fields.
