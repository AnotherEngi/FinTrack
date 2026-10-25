# Overview, visibility, and purchase-date refunds

User decisions, 2026-10-25. This supersedes the earlier three-chart Overview.
Implemented in source; this batch has not been compiled or run on Windows,
Mac, or iPad. The user requires human-run terminal commands after the previous
authorized push. No new Git commit or push has been performed.

## Layout and interaction

Landscape iPad is the target, with keyboard/trackpad and touch equally supported.
Two charts sit side by side, with independently scrolling panels below them:

| Left | Right |
| --- | --- |
| Category-colored stacked bars over time | Pie for the entire selected date range |
| Category legend and temporary inclusion toggles | Contextual purchases, initially empty |

An explicit bar click/tap selects the **whole time period**, including all its
enabled categories. A pie click/tap selects that category across the selected
date range. Purchases appear inline, never in a chart-triggered modal. Hover has
no selection action. Select period and category-name buttons provide keyboard
and accessibility alternatives. Opening a purchase is a separate explicit action.
Its net amount is displayed along with links to any applied refunds.

Automatic grouping uses Monday-based calendar weeks for spans up to 93 days,
months up to 1,096 days, and years for longer spans. Presets/custom dates determine
the span; All history uses the full saved purchase span, independent of filters.
Only observed periods are drawn; missing history does not mean zero spending.
The same category colors are used in both charts and the legend. Totals are exact
integer minor units; floating point is confined to native chart/pointer geometry.
Pending charges are shown separately and do not enter posted-spending charts.
Income, transfers, payments, and statement credits remain outside these charts.

Legend switches filter both charts. They are not saved or exported, and reset on
date-range changes, app backgrounding/closing, or a new app process. Selection
clears with those changes and when visibility changes. Show hidden is also a
temporary Overview control; it does not bypass disabled legend categories.

## Persistent visibility

The global Visibility tab lets the user hide individual transaction IDs, category
IDs (including No category), or exact tags. Rules combine with OR: any matching
rule hides the record from Overview. Category/tag rules also cover future matches.
Turning off an individual switch does not override an active category/tag rule;
the row explains when another rule still hides it.

Visibility is optional app-owned `ReviewWorkspace.summaryVisibility` metadata,
persisted in the existing SwiftData V3 workspace payload. Saving it changes the
backup generation and schedules the existing automatic iCloud backup path. It
does not change financial records, revisions, approval, or pending AI feedback.
Full manual/automatic backups include it; restoring a backup restores the rules.
Older payloads without this field mean no visibility rules. No SwiftData entity
migration, new cloud capability, or record sync is introduced.

Hidden records still appear in Transactions, Discussions, history, exports, and
ChatGPT packets. Hiding a purchase omits its net spending; hiding a refund omits
that refund's adjustment until Show hidden is enabled. Visibility never deletes
data and is separate from accounting treatment and Exceptional Event flags.

## Refund allocations

The user clarified that refunds must reduce the original purchase dates, rather
than appear as negative spending on the receipt date. Example: a purchase on
March 1 for 100.00 and a refund received June 12 for 25.00 produce 75.00 at March 1
and no new June spending from that refund. The refund keeps its actual bank date
and -25.00 ledger amount. A March-only summary still sees the linked June refund.

The refund editor links one or more original posted spending records, with a
positive amount allocated to each. Partial allocation is allowed. Allocations
must not exceed the refund or, across all refunds, any original purchase amount.
Self-links, repeated purchases within a refund, missing/future purchases, pending
purchases, and currency/treatment mismatches are rejected. Changing a linked
purchase or reconciled source fact must preserve those invariants. Invalid raw
editor input remains a durable draft; it does not replace valid saved records.

Overview uses each purchase's activity date when supplied, otherwise its posted
date, and its current category. Fully refunded purchases remain available in the
period panel at zero net. Pie slices contain only positive net category totals.
Unallocated refunds, including older synthetic examples, are flagged as **Link
refunds** and listed for editing. They are never guessed, silently allocated, or
subtracted on the wrong date. The flag's amount is the unallocated remainder,
while opening its record shows the original full refund amount.

Links are optional `TransactionDraft.refundAllocations` fields. The SwiftData
transaction payload already supports additive JSON fields. Backups preserve
links and validate the complete graph. Review JSON/CSV includes read-only links;
pending feedback captures link edits, and relevant linked purchases/refunds are
added as packet context. ChatGPT may discuss missing links, but the incoming
response contract cannot write them or approve records. Amounts in exported
allocations use exact integer strings: purchaseID, amountMinorUnits, currency.
Old records/input/backups without links remain readable. Existing sample UUIDs
and user edits are not rewritten to manufacture refund matches.

## Transfer screens

Send, Import, and Backup now have dedicated screen types/presentations. There is
no shared segmented picker and no route from Send into Import inside its sheet.
Transaction/discussion toolbar actions open their corresponding screen directly.
Review & backup is a launcher for these independent screens; the status strip
opens Backup. Existing prepared-file locking and immediate Files backup export
remain in place.

## Validation to run

Eleven new portable tests cover purchase-date refunds, splits/remainders, graph
validation, exact large values, extreme legacy amounts, visibility/filter union,
date grouping, overflow, older payloads, backup round trips, and review context.
Three new Apple persistence tests cover reopen/restore, rollback, and rejection
of edits that invalidate refund links. None has run for this batch. Previous
83-test results and Apple syntax parsing describe the previous revision only.

On Windows, run `swift test --package-path Packages/FinTrackCore`. On Mac, run
both package suites and build the iPad app. On the physical iPad verify:

1. Landscape layout fits, both lower panels scroll, and trackpad hover opens nothing.
2. A bar click lists its whole period; a pie click lists its category. Initially
   the purchases panel is empty. Keyboard alternatives work.
3. Category toggles update both graphs and reset on date changes/backgrounding.
4. Hide by ID/category/tag, relaunch, and toggle Show hidden. Check Transactions
   and review packets still contain hidden records. Verify visibility after restore.
5. Add synthetic March purchase/June refund. Link a partial amount, reopen, then
   view March and June separately. Split a refund across two purchases. Try an
   excessive allocation and confirm the saved record is intact and draft retained.
6. Send/Import have no segmented navigation between them. Backup remains separate.
7. Configure the iCloud folder, edit visibility/refund links, wait for confirmed
   upload, and restore the complete synthetic backup on a disposable test store.
   A local save or prepared file alone does not prove upload completed.

Native Charts hit testing, keyboard behavior, SwiftData semantics, file-provider
UI, and actual iCloud confirmation require the Mac/iPad checks above.
