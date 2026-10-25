# Exchange and backup hardening pass

## Latest iPad-feedback follow-up

All **77** portable tests pass; **14** Apple source/test files parse. There are
**25** authored Apple persistence tests awaiting Mac execution. Twelve portable
and four Apple tests are new for this follow-up. Prior counts below are historical.

- Colored all populated classification values while preserving unknown legacy
  authorship; new synthetic fixtures identify their simulated assistant origin.
- Separated discussion answers from actual category/tag edits, preserving older
  response files/canonical bytes and matching acknowledgements without financial
  edits. Incoming IDs/revisions/text and backup discussion references validate.
- Added durable reply drafts/messages and explicit resolution without approval;
  drafts remain discoverable after relaunch yet never enter review files. Frozen
  revision guards preserve stale reply text. Failed commits retain drafts and do
  not save half a conversation. Later messages reopen resolved discussions; new
  unrelated classification proposals do not. Late older replies do not replace
  a newer question's direction. Cache decoded threads once on ledger reload.
- Prepared exports lock their choices and identify mode; imported replies and
  backup tools use separate pages. Manual backup export opens the Files dialog
  immediately, independent of iCloud setup. Cancel is not shown as an error.
- Exact signed spending charts reuse tested finance totals, separate pending,
  preserve negative refunds, break missing-month lines, and provide drilldowns.
  Opt-in multi-year fixtures append by stable IDs without replacing edits.

SwiftUI/Charts/FileDocument and SwiftData **semantic compilation and actual device
behavior remain unverified here**. See [current flow](review-flow.md) and the
[combined test](ipad-acceptance.md); syntax parsing is not a Mac build substitute.

## Earlier exchange/backup hardening

2026-10-24. Source review and Windows verification completed after implementing
the new review/intake/backup flows. This is not an Apple build or cloud test.

## Findings addressed

- **First Mac compilation failure after push:** a nested `guard` in the guidance
  freshness check allowed its outer `else` block to fall through. Windows syntax
  parsing did not catch this semantic error. Move the check into the portable
  core with one throwing guard, add a Windows regression for same-response versus
  intervening-edit cases, and expand the existing Apple integration test to accept
  two proposals before rejecting a third after a manual edit. Mac rerun remains
  required; syntax-only parsing is not a substitute for semantic compilation.

- **Lost feedback after restart:** process-session markers were not durable.
  Schema V3 persists feedback, manifests, drafts, and journals. Record mutations
  and feedback/draft changes share one explicit SwiftData transaction/rollback.
- **Autosave noise and packet growth:** consecutive unsent edits to the same
  record coalesce to net prior/saved values. Never merge across a prepared packet
  or assistant/review revision gap. Later edits survive an older receipt.
- **Unresolved discussion dropped after receipt:** open discussion/unanswered
  questions remain eligible even if their earlier operations were acknowledged.
- **Stale/replayed assistant output:** bind proposals and receipts to stored
  packet/operation IDs, record revisions, and guidance versions. Reject unknown
  fields/out-of-scope IDs, repeated proposal IDs, or changed content under a file
  ID. Accepting is explicit, does not approve, and cannot write user notes/amounts.
- **Stale rule proposals after manual edits:** preserve response lineage for
  sequential decisions, clearing it on manual guidance changes/other responses.
- **Bank duplicates and source changes:** use scoped genuine provider IDs;
  retain original/latest evidence. New-row batches commit atomically; ambiguous
  manual matches require reconciliation or an explicit separate-purchase choice.
  Existing updates require a captured current revision and preserve annotations.
- **Imported tags changed during unrelated editing:** raw editor input now
  remembers original tags, preserving delimiters/whitespace until tags are edited.
  Optional metadata decodes old drafts without changing their earlier behavior.
- **Unsafe restore of existing UUIDs:** reconcile existing SwiftData objects
  rather than delete/reinsert matching unique IDs. Validate, confirm, retain one
  local pre-restore archive, and atomically replace records/workspace/raw drafts.
- **False cloud success / lost previous backup:** journal a unique immutable
  candidate before file I/O; verify its local bytes and uploaded metadata/size
  before confirmation. Confirm durably before deleting the prior good cloud file.
  A confirmation for one generation never covers later edits.
- **Interrupted upload / expired permission:** persist candidate bytes and folder
  bookmark locally, retry on foreground/relaunch/while active, and report failures.
  Folder selection requires an iCloud ubiquitous directory; no local/provider
  folder is mislabeled cloud backup. Corrupt settings are reported and preserved
  before explicit folder reconfiguration. Missing confirmed files queue replacement.
- **UI error visibility:** result/reconciliation editors show errors inside their
  own presentation, rather than depending on an alert behind an existing sheet.
- **Untrusted/large files and shared-file lifetime:** coordinated security-scoped
  reads with file-size/bounded-read limits; schema/relationship validation;
  generated-only output names. Share files remain available after sheet dismissal;
  startup cleans only older generated files and cannot block ledger startup on
  cleanup failure. No runtime data or credentials are added to Git.

## Verification executed

- `scripts/Test-Core.ps1`: Swift 6.4.1, **65 Swift Testing tests passed**, exit 0.
  Fifteen tests are new for this batch. The separate XCTest runner's zero tests
  is expected; the Swift Testing summary is the actual result.
- Windows `swiftc -frontend -parse`: all **12** Apple app/persistence source/test
  files pass syntax parsing. This does not expand SwiftData macros, resolve Apple
  SDK types, or establish concurrency/API availability on the target SDK.
- Xcode project object references/unique IDs and all eight app source references
  checked; shared scheme XML parsed. Mac `plutil` and `xcodebuild` still required.
- Synthetic weekly fixture JSON parsed, all diffs checked for whitespace errors.
  No staging/commit/push, tool installation, real account access, or real imports.

## Remaining validation and limits

- **21 Apple persistence tests await Mac execution**, including nine new tests
  for V2-to-V3 migration, draft/feedback rollback, receipts/replays, source intake,
  atomic batch additions, guidance conflicts, and full restore rollback.
- SwiftUI/SwiftData typechecking, existing-store migration, bookmarked external
  folder behavior, metadata upload notification, permission renewal, interruption,
  independent cloud-file inspection, and restoring an automatic backup need the
  physical iPad. Use [one combined checklist](ipad-acceptance.md). Do not use real
  financial data before these pass. Agent has no direct Mac/iPad session.
- Automatic backup depends on app execution, network, account, and storage.
  No fixed background timing, instantaneous offline protection, or app-enabled
  OS device backup is claimed. A crash/cleanup failure can leave an extra backup;
  there is no automatic historical archive/retention product feature.
- Files are capped at 50 MB, with explicit failure and no silent truncation.
  Large-history partitioning and exchange-journal pruning are not implemented.
  This prototype serializes workspace state; high-volume performance is untested.
- Restore handles a readable current store transactionally. An unreadable/corrupt
  live store is preserved on startup failure; creating a separate recovery store
  through an in-app startup-recovery screen is future work, not a verified path.
- Review rules are inspectable text supplied to ChatGPT, not an automatic local
  classifier. Actual weekly bank connector output/source completeness, private
  history migration, full taxonomy/splits/reimbursements remain unverified or
  unimplemented. No cloud record sync or automatic ChatGPT task connection.
- Backup files have no app-level password/encryption feature; use private storage.
  Source financial records and credentials remain outside the public checkout.
