# Device verification record

Updated 2026-10-24. All device checks use synthetic transactions.

The user-reported native passes below cover the earlier prototype. The approved
transaction table, current payload fields, export, and other new tabs have not
yet been built or exercised on Mac/iPad; see the
[single combined acceptance session](ipad-acceptance.md).

| Check | Result | Evidence / limits |
| --- | --- | --- |
| Native app builds and runs on physical iPad | Pass, user reported | User reported a successful build and confirmed the test was on the physical iPad; exact current Mac/Xcode versions and build logs were not supplied |
| Edited sample grocery refund survives closing/reopening | Pass, user reported | Modified dollar amount remained after reopening. Exact amount is not recorded. Full process termination and offline mode were not specified |
| Portable finance/table/export tests | Pass, agent executed | All 50 tests passed with Windows Swift 6.4.1, including 16 new table/model tests |
| FinTrackCore tests on Mac | Pass, user reported | User reports the suite passed; test output and counts were not supplied |
| FinTrackPersistence tests on Mac | Pass, user reported | User reports the suite passed; authored coverage includes migration preservation, reopen, rollback, and retry. Test output and counts were not supplied |
| Current Mac package compilation | Failed, user reported; source fix prepared | Both suites stopped at the shared Core history expression in LedgerDisplay.swift. History/overview chains were split into typed loops and separate sorts; all 50 Windows tests passed again. Mac rerun is pending |
| Explicit approval/discussion behavior in UI | Provisional pass, user reported | User said all four focused checks appeared to work; no individual observations/logs supplied |
| Invalid draft after process termination | Provisional pass, user reported | Included in the user's report that the focused checks appeared to work; no individual observations/logs supplied |
| Offline physical-device save/relaunch | Provisional pass, user reported | Included in the user's report that the focused checks appeared to work; no individual observations/logs supplied |
| Backup/restore and real-data migration | Pending / not implemented in full | A successful local reopen does not establish cloud backup, schema upgrade, or restore correctness |
| New tab navigation, totals, exclusions, drilldowns | Pending on Mac/iPad | Portable rules pass; new SwiftUI controls still need native validation |
| New native source syntax | Pass, agent executed | All ten app/persistence source/test files parsed on Windows; this does not check Apple SDK types |
| Current Apple persistence suite | Pending on Mac | Twelve tests, including four new source/provenance/progress/legacy-payload and append tests |
| Approved native table and lifecycle | Implemented in source; device check pending | Search/presets/sort/Amalgamate, source/origin pills, icon actions, session/draft and discussion states |
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
