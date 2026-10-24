# Development and verification

Updated 2026-10-24. Use synthetic data throughout development.

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
  tests pass. No further installer run is currently necessary.
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
The initial source/project was authored on Windows and still needs Xcode compiler
and project validation. Fix any compiler/project issues before device testing.

In Xcode, select FinTrack and an installed iPad simulator, then Run. For the
physical iPad, select a personal signing team and unique bundle ID under Signing
& Capabilities, pair the device, and enable device Developer Mode if prompted.
Keep the resulting private signing material out of Git. Do not add CloudKit or
iCloud Drive capabilities to make the local store work. OS-level iCloud Backup
inclusion is separate from those capabilities.

## Tests and device checklist

The 22 portable tests cover the confirmed positive-outflow convention, exact
money/date handling, posting/treatment and spending exclusions, explicit
approval/discussion, classification reopening, comment ownership, Skip/Reopen,
revision/retry protections, old raw-draft decoding, and serialization/history.
See [review-workflow.md](review-workflow.md) for exact behavior and limitations.
Eight Apple persistence tests are authored: sample loading, duplicates/revisions,
store reopen, write/action rollback and retry, amount-convention guards, and
v1-to-v2 migration preservation. They have not executed on Mac yet.
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

Apple persistence tests, native UI, backup/restore, and migration behavior remain
**not verified** because no Mac session is available. Earlier static checks
covered PowerShell syntax, scheme XML, project reference paths, cloud-disabled
configuration, and whitespace. Windows core-test success does not establish that
the SwiftData package or iPad app compiles or runs.
