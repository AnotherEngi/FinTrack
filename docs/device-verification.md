# Device verification record

Updated 2026-10-24. All device checks use synthetic transactions.

## Current review/intake/backup batch

This section supersedes implementation status/counts in the earlier table below.
The previous three-file export was never tested on iPad and has been replaced.

| Check | Result | Evidence / required next step |
| --- | --- | --- |
| Portable rules and regression suite | Pass, agent executed | All 64 Swift Testing tests pass on Windows Swift 6.4.1, including 14 new exchange/backup/editor cases |
| Apple source syntax | Pass, agent executed | All 12 app/persistence source/test files parse; no Apple SDK types/macros checked |
| Xcode project references / scheme | Pass, static only | Unique/defined object IDs, all eight app sources referenced, scheme XML valid; Mac plutil/build still needed |
| Synthetic weekly fixture / whitespace | Pass, agent executed | JSON parsed, diff check clean; no financial accounts/files used |
| Mac persistence suite / schema V3 | Pending | 21 authored tests, nine new; existing-store and raw-draft migration need Mac execution |
| Automatic packet / ChatGPT round trip | Implemented in source, pending device check | One file, pending/open context, full history, returned receipt/proposals, explicit acceptance and stale/replay protection |
| Weekly source intake / guidance | Implemented in source, pending native check | Atomic new-row batches, genuine scoped IDs, explicit reconciliation, guidance edits and version conflicts |
| Automatic iCloud backup | Implemented in source, unverified on device | One-time folder permission, durable candidate/retries, uploaded metadata confirmation; independently inspect cloud contents |
| Full backup restore | Implemented in source, pending native check | Validate/confirm/atomic replace, keep a local pre-restore copy, include drafts and exchange state |

Follow [one combined Mac/iPad checklist](ipad-acceptance.md). See
[hardening report](hardening.md) for fixes and limits. No current-batch native
build, cloud upload, restore, or real-data safety pass is claimed.

## Earlier table batch (historical)

Earlier test passes cover the earlier prototype. The user has now provided an
iPad screenshot of the native transaction table and reported color/width/gutter
issues. The category/tag and layout refinements are prepared locally; export
handoff and broader checks remain unreported. See the
[single combined acceptance session](ipad-acceptance.md).

| Check | Result | Evidence / limits |
| --- | --- | --- |
| Native app builds and runs on physical iPad | Pass, user reported | User reported a successful build and confirmed the test was on the physical iPad; exact current Mac/Xcode versions and build logs were not supplied |
| Edited sample grocery refund survives closing/reopening | Pass, user reported | Modified dollar amount remained after reopening. Exact amount is not recorded. Full process termination and offline mode were not specified |
| Portable finance/table/export tests | Pass, agent executed | All 50 tests passed with Windows Swift 6.4.1, including 16 new table/model tests |
| FinTrackCore tests on Mac | Pass, user reported | User reports the suite passed; test output and counts were not supplied |
| FinTrackPersistence tests on Mac | Pass, user reported | User reports the suite passed; authored coverage includes migration preservation, reopen, rollback, and retry. Test output and counts were not supplied |
| Current Mac package compilation | Earlier failure corrected in source; suite rerun not reported | Shared history/overview chains were split into typed loops/separate sorts; all 50 Windows tests passed again. The new native app now runs on iPad; standalone suite results remain unreported |
| Explicit approval/discussion behavior in UI | Provisional pass, user reported | User said all four focused checks appeared to work; no individual observations/logs supplied |
| Invalid draft after process termination | Provisional pass, user reported | Included in the user's report that the focused checks appeared to work; no individual observations/logs supplied |
| Offline physical-device save/relaunch | Provisional pass, user reported | Included in the user's report that the focused checks appeared to work; no individual observations/logs supplied |
| Backup/restore and real-data migration | Pending / not implemented in full | A successful local reopen does not establish cloud backup, schema upgrade, or restore correctness |
| New tab navigation, totals, exclusions, drilldowns | Pending on Mac/iPad | Portable rules pass; new SwiftUI controls still need native validation |
| New native source syntax | Pass, agent executed | All ten app/persistence source/test files parsed on Windows; this does not check Apple SDK types |
| Current Apple persistence suite | Pending on Mac | Twelve tests, including four new source/provenance/progress/legacy-payload and append tests |
| Native transaction table on iPad | Runs, user screenshot/report | Screenshot shows search/presets/Amalgamate, status, source/category/tag columns and icon actions. User corrected highlights to category/tags and reported short row backgrounds and amount/merchant crowding |
| Category/tag colors, row width/gutters, Export discovery refinement | Prepared; device recheck pending | Merchants now plain; only category/tags use provenance/approval pills. Column minima sum to 924pt, with extra width distributed explicitly; shared insets and full-width frames align headers/rows. Export now has a visible text label and workflow guidance |
| ChatGPT export sharing and manual analysis | Implemented in source; device check pending | JSON/CSV/prompt export, privacy switches, preview, multi-file/individual sharing |
| Returned ChatGPT suggestion import | Not implemented | No automatic apply, acceptance receipts, or exchange replay/conflict handling yet |

## Focused checks reported complete

Both Mac package test suites passed according to the user for the earlier
prototype. Repeat appropriate checks after relevant code changes.

The user said, "I think those all worked," referring to the four checks below.
Record these as provisional passes rather than independent verification. Keep
this list for regression checks after relevant code changes, using only invented
records on the physical iPad:

1. Approve a posted purchase with a resolved sample category. Reopen the same
   transaction and edit only its note: approval must remain. Change its category
   or tags: it must become Unreviewed.
2. Add your own note, choose Discuss, and find the record under Needs discussion.
   Discuss must not approve it. Reopen must clear the discussion flag. A Pending
   purchase must not allow Approve.
3. Leave an unfinished amount such as `12.` on a sample purchase. Wait for the
   draft-saved message, fully stop the app, and relaunch. Resume Unsaved Drafts;
   exact unfinished text must remain, and the ledger's last valid amount must be
   unchanged. Discarding that draft must preserve the committed record.
4. With the iPad offline, add a new synthetic transaction with a positive expense
   amount and Spending treatment. Fully stop/relaunch and confirm the saved
   values remain. This independently checks creation and the offline path.

## Next development milestone

Complete the [combined table/export/ChatGPT checklist](ipad-acceptance.md).
Then implement returned-proposal preview and explicit accept/reject, with
repeated-import deduplication and a stale-response conflict case.
Full backup/restore and migration verification still precede any real-data use.
