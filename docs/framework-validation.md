# Financial framework validation and release gate

2026-10-25. Current contracts: [financial-framework.md](contracts/financial-framework.md).
Implementation uses one current store/model/format; no prototype readers or
schema migrations. No private source/audit data was used. No commit or push was run.

## Evidence and limits

### 2026-10-26 normal import actions enabled

The user reports that corrected Mac tests and the app build pass. They explicitly
authorized removing the unconditional application gate before validating the next
build, so the required synthetic history/refund trial can actually finish. The
normal current-contract import flow is enabled; this is not a fixture allowance
or a test mode. No one-off test script is being added to the repository.

Initial history still requires its audit acknowledgement and explicit Import
Into Separate Ledger confirmation. The current format and financial graph are
validated before isolated restore; existing migration receipts prevent overwrite
or duplicate import. Refunds still require explicit Import Reviewed Refunds and
pass the existing migration-ID, exact deferred-set, purchase-revision, currency,
allocation-cap, replay and atomic-write checks. The audit view's excluded-row
count now uses current row dispositions rather than a removed property.

The remaining rollout sequence is: recheck/build this change on Mac, install on
iPad, verify editing/exchange/iCloud recovery, run synthetic initial/refund/weekly
intake through the normal UI, and reconcile the actual source privately before
real intake. The older reports and gate descriptions below are historical.

Agent verification of the enabled flow's source: **139 portable tests passed**
on Windows Swift 6.4.1 (exit **0**, 21.931 seconds execution), **19 native Swift
files passed syntax parsing**, and `git diff --check` passed. No additional test
mode, resource bundle, fixture-specific code or schema change was introduced.
The native package suite, SwiftUI typecheck/build and iPad confirmation/file flows
must still run on Mac/iPad for this update. Windows syntax parsing is not an
Apple build. No real financial files were inspected and no commit/push was run.

### 2026-10-26 Mac test report and follow-up

The user's screenshots show **137 core tests passed on Mac** and the native
persistence package built successfully. The native run completed **47 tests**
with **three assertion issues in two tests**:

- The refund rollback test compared the committed normalized import against its
  pre-import fixture. Initial history intentionally changes a completed
  discussion's question state from `none` to `resolved`. The corrected test
  captures the actual committed baseline and compares all records and workspace
  data after injected failure, both in the existing context and a reopened store.
  It still checks successful retry, duplicate prevention, unchanged replay
  generation and preservation of the purchase.
- The discussion test still expected approval after replying and resolving.
  The agreed behavior is unapproved after a new discussion, remaining unapproved
  on resolution until an explicit Approve. The corrected test checks earlier
  approval evidence, user answer and reopen persistence, then explicit reapproval.

The unused mutable `workspace` local in restore was removed to fix the compiler
warning. No financial behavior, schema, contract or import gate changed. Two
portable regressions exercise the underlying normalization and review semantics.
Agent verification after correction: **139 portable tests passed** on Windows
Swift 6.4.1 with process exit **0** (27.344 seconds execution), **19 native Swift
source/test files parsed**, and `git diff --check` passed. Windows cannot run
SwiftData, so these are not corrected-native-suite results.
The corrected **native suite still needs a Mac rerun**; a successful Windows
regression run cannot establish native rollback/reopen results. Real migration
remains blocked.

### Earlier Windows framework baseline

Windows Swift 6.4.1: the final complete portable suite passed **137 tests** with
exit code **0** after the hardening pass (21.763 seconds for test execution).
All **19** native app/persistence source and test files passed syntax parsing.
`git diff --check` passed. The toolchain's `.build/debug` symbolic-link warning
did not prevent a successful test run. Windows cannot typecheck SwiftUI/SwiftData
or build an iPad app. There are **47 native test declarations**, not executed
here; parameterized cases may produce a larger runtime count. Four new native
framework tests cover settings rollback/reopen,
complete source-version reconciliation, native archive financial context, and
atomic refund-stage retry. Retired schema-migration tests were replaced, not kept
as compatibility obligations.

The user reported earlier Mac package suites and an actual iCloud backup/download/
restore passed. Those reports are **for the previous model**. The new store,
archive, editor, financial context and regression tests need a new Mac/device run.
The initial-history/refund actions remain blocked until that evidence is supplied.
This is a validation gate; it is not permission to import the old development format.

## Capability and acceptance matrix

`FinancialFrameworkTests` refers to the portable test file; other test families
remain in the complete suite. Native runtime results are pending for every row.

| Requirement | Implemented path | Synthetic evidence / remaining native check |
| --- | --- | --- |
| Split categories/subcategories | Exact allocation graph, primary-remainder editor, category table pills, category search/selection/chart totals | `splitEditsRequireExactBalanceAndPrimaryCategory`, `splitsAndActualReceiptsReportOnceWithoutExpectedDoubleCounting`; edit/reopen on iPad |
| Accepted unsplit purchase | Primary category, no invented allocations/Mixed category | `acceptedUnsplitPrimaryPurchaseDoesNotInventAMixedCategory` |
| Unused catalog/definitions/stored labels | Persistent catalog, category/subcategory form and full export/archive | Current-framework import/archive tests; native `currentNativeArchiveRetainsProgramsClaimsAllocationsAndUnusedDefinitions` |
| Expected reimbursement | Structured optional expected and source-reported money; no fabricated cash | Combined repayment/report tests; inspect header metrics and claims form |
| Partial/combined repayments | Actual receipt-to-claim/component links and cumulative receipt cap | `combinedRepaymentsAllocateActualCashAcrossClaimsWithoutInventingEligibility`; link one receipt to two claims on device |
| Unknown benefit settings | Explicit unknown period/eligibility, optional limit/expected, SourceValues | `currentFrameworkMigrationPreservesFinancialMeaningAndUnknownEvidence`; settings reopen |
| Pending → posted changed facts | One logical UUID, full predecessor versions, explicit revision-checked reconciliation | Same-provider-ID version test; native `weeklyReconciliationRetainsCompletePendingVersionAndUserEdits` |
| Ambiguous duplicate | Candidate review; atomic batch abort, explicit separate/reconcile choice | Intake/core and existing native batch/duplicate tests |
| Historical approval + current question | Historical decision evidence separate; current unapproved | Framework migration/approval tests; inspect Discussions |
| Pending/superseded earlier approval | Historical decisions do not make source version active | Source lifecycle/evidence tests; verify source evidence UI |
| Mixed/unknown ownership | Typed source notes/archival ownership and source presence | Unknown-value/approval cleanup/export tests |
| Known resolved assistant text | Cleared before history commitment and explicit close; no immutable assistant copies | `sourceNotesDoNotBecomePermanentCopiesOfKnownResolvedAssistantText`, lifecycle tests |
| Partial/multiple/multi-purchase refunds | Positive exact purchase/component allocations; purchase-date reporting; retained receipt date | `SummaryReportTests` plus dedicated-stage/proportional tests; confirmation UI |
| Unlinked/uncertain credit | Explicit unresolved links/type; no inferred negative pie slice | Full/unlinked refund and treatment tests |
| Payment/statement credit/income/transfer/repayment | Separate accounting types and typed payment relationships | Financial graph and existing spending-treatment tests |
| Deferred initial refunds | Complete deferred partition with original amount/future UUID; initial gross purchases | `deferredRefundStageUsesConfirmedExactAllocationAndPurchaseDate` |
| Stable staged UUIDs | Initial receipt plus same migration/purchase IDs and exact target revisions | Native `dedicatedRefundImportRollsBackAndRetriesWithoutDuplicateOrGenerationChange` |
| Invalid refund graph | Reject wrong stage/type/targets/currency/status/caps/revisions before writes | Invalid graph/cap/stale tests; native rollback injection |
| Date-only/timestamp separation | Date strings, original timestamp metadata, source report date separate | Date/timezone tests plus current import fixture |
| Monday and calendar six months | Central reporting calendar/presets and complete timeline buckets | Workspace/SummaryReport boundary tests |
| Source reporting basis changes | Immutable source baselines; behavioral posted-unreviewed switch | `sourceReportingBaselineRemainsEvidenceWhenApprovalFilterChanges`; source UI comparison |
| Unknown flags | Nullable current exceptional flag plus original exceptional/visibility SourceValues | Unknown/null/empty/zero/false tests; UI unknown picker |
| Missing coverage | Structured source coverage and explicit limitation text; no claim of verified zero | Framework report/coverage tests; long-warning layout on iPad |
| Complete rows/columns/partitions | Unique disposition/locator, qualified columns, preserved cells, all independent controls | Framework migration and omitted-essential/missing-cell tests |
| Offsetting debit/credit omissions | Exact positive/negative/net/spending counts across every grouping | `sourceControlOffsetsCannotHideMissingDebitAndCreditRows` |
| Replay/changed facts/failure | Payload fingerprints, current revisions, isolated initial restore, atomic commits | Core replay tests; native history/settings/refund rollback tests |
| Full archive and ChatGPT context | Current archive includes all structures; connected context and full history; text ownership filtering | Current archive/review/published-decoder tests; native compressed round trip |
| Unsupported essential/oversized data | Audit blockers/essential omissions/unknown fields reject; complete clipboard/file fallback | Essential/nested-key/capacity/clipboard tests; iPad large-file practicality unmeasured |

The final hardening regressions also cover autosave retaining the user's raw
decimal text/source UUID, duplicate deferred-refund UUID rejection, historical-only
superseded records, secondary/subcategory display-label search, connected review
context, and a genuinely new assistant question after closure without reviving
old replies. Financial settings retain invalid raw input in the open form even
when a disclosure is collapsed, and block Save until it is corrected/discarded.
The native UI behavior still requires the device checks below.

Source controls are supplied by the producer independently from the complete
private source. Tests validate invariants, not actual private source completeness.
Workbook layout/formulas themselves are not imported. Any essential financial
behavior the producer cannot map must remain a blocker, not an archival workaround.

## Combined Mac/iPad check

From the Mac checkout root after publishing/pulling this batch:

```sh
git status --short
git pull --ff-only
swift test --package-path Packages/FinTrackCore
swift test --package-path Packages/FinTrackPersistence
xcodebuild -project Apps/FinTrack/FinTrack.xcodeproj -scheme FinTrack -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
open Apps/FinTrack/FinTrack.xcodeproj
```

Keep local signing changes; resolve any pull blocker explicitly instead of force
resetting/deleting local work. Select the actual iPad in Xcode and Run. Existing
prototype data may produce the expected incompatible-format message. Use the
explicit **Create a Separate Empty Ledger** action for synthetic testing; old
files remain untouched. Re-select the iCloud folder for the new backup-journal
format if requested. Old development archives are deliberately rejected.

1. In Financial Settings add categories/subcategories/definitions (including an
   unused one), a benefit program with unknown settings, and inspect Advanced
   Financial Settings. Broken references/invalid amounts must visibly reject
   Save and retain the open editing work.
2. Add a synthetic purchase; create secondary dollar allocations. Change amount,
   category/subcategory and tag; check balanced remainder, table pills, category
   graph totals/selection/search and save/reopen. No duplicate parent spending.
3. Add a negative synthetic **Reimbursement receipt**. Create claims and actual
   receipt allocations, including partial/combined claims. Verify gross purchases,
   adjusted spending, receipt-date cash and purchase net cost separately. Expected
   reimbursement alone changes no spending/cash. Over-assigned receipt fails.
4. Link a later refund to an earlier split purchase. Confirm proportional preview
   before saving. Test manual component selection, cumulative caps, unlinked and
   partially linked amounts. March purchase/June refund must adjust March only.
5. Send pending feedback and full history via clipboard/file. Confirm structured
   allocations/global financial context/source evidence, separate answers and
   explicit actual-edit acceptance, stale edit rejection and closure cleanup.
6. Use the enabled normal import actions to complete the published synthetic
   initial/refund pair end to end, including replays and weekly intake. Review
   the real producer audit privately before actual real-data intake. Do not
   reintroduce an application gate that blocks this prerequisite synthetic trial.
7. With the new structures saved, confirm iCloud upload, export/download a current
   `.fintrack` archive, make another edit, restore the downloaded checkpoint and
   verify all financial objects, pending drafts/feedback and source evidence.
   Confirm backup resumes for the new restored generation. Test offline edit and
   later retry. Do not treat a local candidate as confirmed cloud backup.

Real-data acceptance remains paused until these checks and the complete source
audit are satisfactory. Device capacity/performance, keyboard/trackpad layout,
compression/file-provider behavior and native macro typechecking are material
remaining validation, not results that Windows can establish.
