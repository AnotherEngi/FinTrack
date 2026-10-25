# Lifecycle implementation and verification

2026-10-25. Implements the recommended first safety batch plus the user's
approval/retention decision. Initially prepared without execution under the prior
command preference; the user subsequently authorized all available local checks.
On Windows Swift 6.4.1, **all 108 portable tests passed**, including the 14 new
lifecycle cases and the synthetic archive larger than 50 MiB. All **18** Apple
app/persistence source/test files passed syntax parsing. Scheme XML, app source
references, conflict-marker search, and `git diff --check` also passed. No Mac
build/native suite, device/cloud verification, commit, or push was performed.
An additional Apple-target parser pass covered those 18 files plus BackupArchive
(19 total), including its Apple replacement branch. Windows sysroot warnings
confirm that this was syntax parsing without an Apple SDK, not native typechecking.
See the complete
[data inventory and retention policy](data-retention.md).

## Mac regression follow-up

The user supplied a Mac run of 41 persistence tests reporting four issues in
three tests. This confirms native test compilation/execution for that revision,
not an overall pass. Corrections in this follow-up:

- The atomic-add/rollback fixture previously supplied identical merchant/date/
  amount facts under two IDs. The stricter duplicate guard correctly stopped
  before the simulated save failure. Two distinct fictional merchants now let
  this test reach the save boundary; ambiguous purchases still have dedicated
  rejection/rollback coverage.
- The reopen test now requires approval to clear assistant questions/reasons
  while preserving earlier ledger notes, user notes, review history and approval.
- Foundation replacement failed with Cocoa permission error 513 on a mode-000
  pointer. Recovery now prepares the new pointer under its future PreviousStore
  filename and swaps it with ActiveStore.json in one Darwin `RENAME_SWAP` call.
  The unreadable original bytes and permissions remain at the PreviousStore name;
  no contents are read and no original pointer is removed first. Unsupported
  filesystem swaps fail visibly while leaving the old pointer in place. See
  [Apple's swap-support documentation](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumesupportsswaprenaming).
- The existing recovery regression now covers mode 000 and read-only mode 400,
  checks preserved permissions/bytes, and reopens the activated ledger. Another
  regression rejects a directory at the pointer path without deleting evidence.

Verification after these corrections: all 108 portable tests passed again on
Windows Swift 6.4.1 and all 18 Apple source/test files passed syntax parsing.
The native corrections require a new Mac run. Windows cannot execute SwiftData
or Darwin filesystem behavior; parser success does not validate those operations.

## Implemented source changes

- Approve and Mark Resolved close the current discussion; saved notes/last user
  answer and unacknowledged feedback remain. Nonempty unfinished replies block
  closure. An approval retry remains idempotent even after a later draft exists.
- Parsed open answers live independently of raw responses. Completed files become
  compact SHA-256/ID receipts. Closed answer/reply history is removed once no
  unsent reply needs it. Old closure snapshots migrate to revision cursors before
  their underlying responses disappear. Ordinary approval does not invent a
  discussion. Newer questions about later unapproved revisions can open a thread.
- Accepted/kept classifications queue record-scoped feedback and current context;
  opaque proposal IDs alone would be insufficient after deleting the raw response.
- Approval settles older classification proposals, not guidance. Unfinished
  proposals/files remain until handled or explicitly dismissed. Dismissal does
  not acknowledge user feedback. Manifests retire on completion or at 90 days
  when no active staged response needs them; pending feedback is never aged out.
- Index discussion projections by record and compare source identities through
  dictionaries, avoiding repeated whole-history scans inside each record's
  projection. The persistent workspace remains a JSON row; this is not the final
  indexed-entity storage refactor or a measured performance result.
- Backup archive v2 frames records/workspace items individually, bounds expansion,
  binds counts/order/generation and per-entry SHA-256, and uses Apple Compression
  deflate in the native adapter. Legacy bounded JSON backups still read. See
  [Apple's buffer API](https://developer.apple.com/documentation/compression/compression_encode_buffer%28_%3A_%3A_%3A_%3A_%3A_%3A%29).
- Backup limits are independent of AI exchange. Conservative precommit capacity
  checks cover every workspace-backed mutation and preserve the old state on
  failure. Format ceilings: 250,000 records, 1 GiB logical payload, 80 MiB per
  entry, one million entries, 2 GiB physical file. Device support still needs
  measurement. Logical snapshots, not SwiftData contexts, cross worker boundaries.
- Automatic candidates are immutable archive files with hash/size metadata in the
  journal. Legacy embedded candidates migrate once. Copy/read validation precedes
  provider upload confirmation; the previous file remains until confirmation is
  persisted. Failed deletions remain queued for retry. Offline edits remain local.
  Cloud copies use an unpublished staging name and acquire the monitored final
  name only after byte verification, so an interrupted copy cannot strand a
  partially written final backup. Existing JSON confirmation upgrades to v2.
- Recovery is available from the startup error screen and does not encode/open
  the damaged database. It builds a separate store, reopens/verifies it, then
  atomically changes the active pointer. Prior stores remain user-deletable
  recovery copies. Missing selected stores/legacy store files are not silently
  recreated. Explicit Create Separate Empty Ledger is a recovery choice.
  Pointer replacement now uses Darwin's atomic swap (see the Mac follow-up
  above), preserving the original inode without reading its contents or copying
  damaged permissions onto the new pointer.
- Both intake addition paths examine linked/unlinked rows and same-batch candidates.
  Merchant/date evidence flags tip/date/ID variants for explicit reconciliation;
  it never automatically merges equal purchases. Batch failures save no additions.
  Known superseded facts/identities cannot regress a posted record. Weekly v1
  still cannot reliably order an unknown previously unseen source version.
- Guidance additions use the same 1,000-rule bound for assistant and manual paths.
  Backup source graphs, receipts, closure cursors and resource sizes validate.

## Windows

The agent runs available local tests. Only remote-writing Git commands remain
human-run; provide those automatically when publication is next. The current
Windows shell needed approved execution outside the restricted shell to access
the installed toolchain. The helper ran with a process PATH refreshed from the
machine/user environment and session-only script execution-policy bypass:

```powershell
Set-Location 'C:\Users\rproi\source\repos\FinTrack'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Core.ps1
```

```powershell
swift test --package-path Packages/FinTrackCore
```

The first run found three outdated assertions: approval retaining resolved
assistant questions, restored unfinished replies appearing resolved, and an
export prompt claiming import was unimplemented. Expectations now verify the
approved retention behavior and the working reply contract. Compilation also
warned that Foundation file replacement is unimplemented on Windows; the portable
archive now uses a same-directory Windows replacement, with an exercised
successful overwrite check as well as the failed-write preservation check.
SwiftPM emitted a nonfatal `.build/debug` symlink warning; the suite exited zero.

Run one route, not both repeatedly without a reason. The archive suite includes a
synthetic uncompressed archive larger than 50 MiB; this is an intentional boundary
test and may take longer than earlier tiny fixtures. Windows does not compile
SwiftUI, SwiftData, CryptoKit/Compression adapters, or physical iCloud behavior.

## Mac

After the user reviews/commits/transfers the source, from the checkout root:

```sh
swift test --package-path Packages/FinTrackCore
swift test --package-path Packages/FinTrackPersistence
plutil -lint Apps/FinTrack/FinTrack.xcodeproj/project.pbxproj
xcodebuild -project Apps/FinTrack/FinTrack.xcodeproj -scheme FinTrack -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
open Apps/FinTrack/FinTrack.xcodeproj
```

Keep the installed app identity/store. Build/install normally through Xcode;
do not uninstall or reset data to bypass a failed migration. New Swift files are
in Swift packages, so no app project source/signing/capability edits are required.

Authored regressions cover standard SHA vectors, response compaction/replay,
pending feedback, new discussions and legacy closures, >50 MiB and legacy archive
round trips, corruption/truncation, capacity rejection, atomic duplicate blocking,
guidance bounds, native compression, startup recovery, and missing-store protection.
Existing persistence assertions were updated where retaining raw response files
or active proposal-ID sets is now explicitly superseded by compact receipts.
There are 14 new portable cases, included in the 108-test Windows pass, and 11
new native cases awaiting Mac execution. Windows parsing does not typecheck
SwiftUI/Charts/SwiftData, native Compression/CryptoKit, or Apple SDK behavior.

## One combined physical-iPad session

1. Add synthetic data; prepare/send a review, import a response containing an
   answer and a category/tag change, then apply the change. Confirm the next
   pending packet includes that record/current values even after raw-file cleanup.
2. Approve: current questions disappear, notes/classification stay, old answers
   cannot return through file replay. Start a new discussion and verify it works.
   An unfinished reply must survive relaunch and block closure until handled.
3. Import another valid file with an undecided guidance proposal. Approval must
   not accept that rule. Dismiss remaining items and verify user feedback remains.
4. Import fictional pending/posted variants with different IDs, dates, and tips.
   Both Add and Add All must stop for reconciliation. Verify a same-batch pair
   saves neither row on failure. Explicit Separate Purchase must still work.
5. Export .fintrack with no automatic backup folder configured: Files must open
   and the saved file must restore. Try an old JSON backup and a corrupt archive.
6. Enable iCloud, edit offline, relaunch/reconnect, and wait for the newest
   generation's upload confirmation. Independently download the confirmed file
   and restore into an isolated test store. Compare records, exact money, source
   relationships, notes, drafts, pending feedback, guidance and visibility.
7. Interrupt restore before/after preparation and pointer activation using a
   disposable synthetic store. Original or verified replacement must remain
   usable. A deliberately unreadable/missing current store must expose recovery;
   do not damage the only copy of any personal data to run this check.
8. Verify preserved stores cannot delete the active store and are removed only
   through explicit confirmation. Check candidate cleanup after upload/retry.
9. Repeat the existing landscape/trackpad/chart/visibility checks. Measure launch,
   editing, peak memory and backup/restore at 10k/50k/100k realistic synthetic rows,
   including retained open work. Adjust the supported device envelope from those
   measurements; format limits alone are not a performance qualification.

Still separate work: real taxonomy/splits/reimbursements and deterministic legacy
migration, stable collector/account IDs and true source chronology, structured
coverage, indexed workspace entities, bounded baseline/full-history review jobs,
guidance revision history, share redaction, and archive encryption/key recovery.
None of those is claimed complete by this batch.
