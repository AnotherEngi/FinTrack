# Development and verification

Updated 2026-10-25. Use synthetic data throughout development.

## Current unverified batch: 2026-10-25

Overview/Visibility/refund changes are documented in [the current design](design/overview.md).
No terminal commands, Swift tests, Apple parsing, commits, or pushes were executed
for this batch. The user's human-run-command preference remains active. Run:

```powershell
Set-Location 'C:\Users\rproi\source\repos\FinTrack'
swift test --package-path Packages/FinTrackCore
```

On Mac, from the checkout root:

```sh
swift test --package-path Packages/FinTrackCore
swift test --package-path Packages/FinTrackPersistence
xcodebuild -project Apps/FinTrack/FinTrack.xcodeproj -scheme FinTrack -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

These are instructions for the user, not verification results. Earlier counts
below are for previous source revisions. Rebuild/install through Xcode for the
physical iPad; do not delete the app/store or reset signing changes to update it.

## Previous review/intake/backup batch

Previous-revision verification: **83 portable tests passed** on Windows Swift 6.4.1; all 14
Apple source/test files pass syntax-only parsing. There are **27** authored Apple
persistence tests, two added by the final hardening pass. Windows has not typechecked SwiftUI/Charts/SwiftData or
validated iCloud folder permission, migration, upload confirmation, or restore.
See [hardening](hardening.md), [current guide](chatgpt-export.md), and the
[combined acceptance session](ipad-acceptance.md). Historical counts below refer
to earlier iterations, not this batch.

After the final authorized hardening push, the user runs terminal/Git commands.
Do not execute them on the user's behalf without an explicit additional exception.

See [discussion and chart changes](review-flow.md). Xcode now references ten app
source files. Swift Charts is an Apple framework dependency, not an installed
third-party package. No signing/capability changes are added. Workspace metadata
is additive/optional; the new resolveDiscussion action requires the new app binary.

Schema V3 reuses the frozen V2 transaction model and adds one persistent workspace
for pending feedback, packets/results, source links, guidance, and raw drafts.
Existing draft files migrate once and remain preserved. The live database stays
local with CloudKit disabled. Automatic backup uses a user-selected iCloud Drive
folder, remembered via a local security-scoped bookmark; no entitlement/team or
bundle-ID change is required by this source change. Reuse existing signing.

Run on Mac after transferring the new source:

```sh
swift test --package-path Packages/FinTrackCore
swift test --package-path Packages/FinTrackPersistence
plutil -lint Apps/FinTrack/FinTrack.xcodeproj/project.pbxproj
open Apps/FinTrack/FinTrack.xcodeproj
```

Keep the installed store and bundle ID. Do not delete/uninstall/reset data to get
past a failed migration; preserve error output. Enable the automatic backup folder
once on iPad, inspect the uploaded file independently, and test restoration from
that file before real-data use. OS device backup remains an additional layer.

## Windows setup

`Setup-WindowsSwift.ps1` prepares a stable Swift installation through WinGet.
With `-Install`, it installs VS 2022 x64 C++ Build Tools and the Windows 11 SDK
if no supported C++ toolset is found, then installs Swift and its declared WinGet
dependencies (Python 3.10 and the Microsoft VC runtime). It does not install a
full Visual Studio IDE, enable Developer Mode, or permanently change execution
policy. Existing C++ installations still need a supported Windows SDK.

Sources: [Swift Windows setup](https://www.swift.org/install/windows/),
[Swift prerequisite details](https://www.swift.org/install/windows/manual/),
[Microsoft installer parameters](https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=vs-2022).

Setup history and current state on this PC:

- WinGet 1.29.380 works outside the restricted agent shell.
- Initial discovery found no Swift executable or supported VS x64 C++ installation.
- The first prerequisite install attempt returned MSI cancellation code 1602
  (WinGet failure -1978335226), before the Swift step. The user then continued
  setup separately. Do not automatically retry a canceled installer.
- Subsequent verification found Swift 6.4.1 targeting x86_64-unknown-windows-msvc
  and VS 2022 Developer PowerShell 17.14.42. FinTrackCore now builds and all 22
  tests passed initially; the current table/export batch passes all 50 tests.
  No further installer run is currently necessary.
- The agent's inherited PATH was stale. Refreshing it from current Machine/User
  environment settings made Swift available. The restricted shell also denied
  access to the installation directory, so the successful test run used approved
  execution outside that restriction.

From the repository in a normal PowerShell terminal, inspect the plan:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Setup-WindowsSwift.ps1
```

When ready to install, run the same command with `-Install`. The execution policy
override applies only to that process; omit it if your policy already permits
local scripts. Installation may need elevation and a terminal restart.

After installation, reopen your terminal/VS Code and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Core.ps1
```

That test runner loads the VS x64 developer environment when available, then
runs `swift test --package-path Packages/FinTrackCore`. It does not attempt to
compile SwiftUI or SwiftData on Windows. Developer Mode may be needed for the
full Windows debugging workflow described in Swift's installation guide; it is
not enabled automatically.

## Mac first build

The user will update the Mac before it is needed. Confirm the actual versions;
recommended setup is supported macOS 26.6 or later and stable Xcode 27.x.

The user requested public source access. `AnotherEngi/FinTrack` is now public,
with owner-only write access verified on 2026-10-24. No GitHub login is required
to clone/pull it on the work Mac. For a new checkout:

```sh
git clone https://github.com/AnotherEngi/FinTrack.git
cd FinTrack
```

For an existing checkout, run `git pull --ff-only origin main` from that folder.
Keep GitHub write credentials on the personal Windows PC; the Mac can build a
public checkout without them. Xcode's Apple-account signing setup is separate.
Anonymous Git read access was verified against the published main commit.

From the repository root:

```sh
sw_vers
xcodebuild -version
swift --version
swift test --package-path Packages/FinTrackCore
swift test --package-path Packages/FinTrackPersistence
xcodebuild -list -project Apps/FinTrack/FinTrack.xcodeproj
xcodebuild -project Apps/FinTrack/FinTrack.xcodeproj -scheme FinTrack -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
open Apps/FinTrack/FinTrack.xcodeproj
```

The project has local package dependencies and a shared scheme; no project
generator or third-party packages are required. It is iPad-only with a provisional
iPadOS 17 deployment minimum, Swift 6 language mode, and no cloud entitlements.
The initial source/project was authored on Windows. The user now reports a
successful native build and a physical-iPad refund edit/reopen check. Exact current
tool versions and automated Apple test output have not been supplied. The user
reports both package test suites passed on Mac; continue
with the targeted checks in [device-verification.md](device-verification.md).

In Xcode, select FinTrack and an installed iPad simulator, then Run. For the
physical iPad, select a personal signing team and unique bundle ID under Signing
& Capabilities, pair the device, and enable device Developer Mode if prompted.
Keep the resulting private signing material out of Git. Do not add CloudKit or
iCloud Drive capabilities to make the local store work. OS-level iCloud Backup
inclusion is separate from those capabilities.

## Tests and device checklist

For the latest table/export batch, use the single combined Mac/iPad/ChatGPT session
in [ipad-acceptance.md](ipad-acceptance.md). All 50 portable tests pass on Windows.
Ten native app/persistence source/test files pass syntax parsing; Apple SDK
typechecking, navigation, sharing, and the 12 persistence tests need this batch's
Mac/iPad run. The adapter adds atomic, opt-in example append, and the domain
payload gains source/provenance/progress fields. SwiftData schema v2 is unchanged.
Earlier Mac/device reports below cover the preceding prototype.

The original 22 portable tests cover the confirmed positive-outflow convention, exact
money/date handling, posting/treatment and spending exclusions, explicit
approval/discussion, classification reopening, comment ownership, Skip/Reopen,
revision/retry protections, old raw-draft decoding, and serialization/history.
Twelve export/display and sixteen table/model tests bring the total to 50. See
[review-workflow.md](review-workflow.md) for exact behavior and limitations.
Twelve Apple persistence tests are authored: sample loading, duplicates/revisions,
store reopen, write/action rollback and retry, amount-convention guards, and
v1-to-v2 migration preservation, old v2 payload compatibility, source/provenance/
progress reopen, and idempotent/failed example appends. The user reports both
earlier Mac suites passed; the four new storage tests still need execution.
Additional native tests cover refusing unmarked earlier stores, unknown amount
conventions, and orphaned drafts while preserving the original bytes. New stores
write a positive-outflow convention marker alongside the store. Existing unmarked
prototype files cannot open until an explicit migration is implemented; do not
delete them or add a marker manually to bypass that check.

On an iPad simulator, then on the physical iPad:

1. Start with an empty store; confirm examples appear only after tapping Load
   Synthetic Examples, and that relaunch does not duplicate them. Check sample
   pending/posted, income/refund, assistant-question, and approval-history fields.
2. Browse All History, Last 8 Weeks, and a custom range. The fixed examples are
   dated August/September 2026, so some can fall outside a current rolling range.
3. Edit payee, amount, dates, posting, treatment, category, tags, event flag, and
   notes. Confirm Saved on this iPad, relaunch offline, and verify exact values.
   Approve a resolved posted purchase, then edit its note: approval must remain.
   Change category/tag: approval must reopen. Discuss must preserve current
   approval and show in Needs discussion; Reopen clears that flag. Pending and
   unresolved records cannot be approved; excluded treatments are Not applicable.
   Skip advances without an approval/history event. Check actions in filtered
   views and confirm read-only assistant text never populates the user note.
4. Leave an invalid amount/date or blank payee. Close/relaunch and resume the
   input under Unsaved Drafts; current saved values must remain valid.
5. Exercise Retry Save and the persistence failure test. The old ledger record
   must survive failure. Discarding unsaved input must leave saved edits intact.
6. Check landscape/portrait, keyboard access, VoiceOver labels, and large text.
7. Inspect iCloud Backup settings and confirm FinTrack data is included. Verify
   actual device backup/restore before real use; local save success is not proof
   of cloud backup. Full app-level backup export/restore is still future work.

## Verification record

On 2026-10-24, `scripts/Test-Core.ps1` loaded the VS x64 developer environment,
compiled FinTrackCore with Swift 6.4.1, and ran **22 Swift Testing tests: all
passed**, exit code 0. The separate XCTest runner reports zero tests because
this package uses Swift Testing; its 22-test summary is the relevant result.
A `.build/debug` symbolic-link warning appeared but did not fail the build/tests.
All eight SwiftData/app source and test files also passed syntax-only
parsing with Windows swiftc; Apple imports, macros, and types were not checked.

On 2026-10-24 the user reported that the app builds, and confirmed on the physical
iPad that an edited sample grocery-refund amount persisted after closing and
reopening. This verifies that specific user-tested path, not every native feature;
offline mode and full process termination were not specified. See
[device-verification.md](device-verification.md).

The user also reports both Mac package suites passed, including the persistence
suite's migration coverage. The user subsequently said all four focused iPad
checks appeared to work, covering approval/classification edits, discussion and
pending restrictions, draft recovery, and offline creation/relaunch. These are
provisional user-reported passes. Backup/restore remains unverified; the agent
has no direct Mac session. Earlier static checks
covered PowerShell syntax, scheme XML, project reference paths, cloud-disabled
configuration, and whitespace. Windows core-test success does not establish that
the SwiftData package or iPad app compiles or runs.

