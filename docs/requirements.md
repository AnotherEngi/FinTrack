# FinTrack requirements and implementation plan

Status: initial synthetic prototype source created; native compilation/device validation
pending. No cloud sync. Updated 2026-10-24.
Confirmed constraints below come from the user. Proposed designs remain open until
selected; documentation verification does not establish account or device access.

## Context and goal

Build a new native household finance app called **FinTrack**, using Swift and
SwiftUI, with the iPad as the primary device. The personal Windows PC with VS Code
and Codex is the main development workspace. A work Mac is available for Xcode
builds, debugging, signing, and installation.

The previous web app used Google Drive for transaction review. Frequent reconnects
and sync conflicts made it frustrating. The current review workflow uses a Google
Sheet and needs a better solution. FinTrack will manage records directly; ChatGPT
will analyze explicitly supplied information and propose changes. Manual entry
and editing must work independently of ChatGPT.

Confirmed usage scope: one user, exclusively on their iPad. Multi-user editing and
editable replicas on other devices are outside version 1. The user requires data
to be backed up to a cloud and prefers their available Apple iCloud storage.
Account settings, capacity, and actual backup/restore behavior remain unverified.

## Existing website reference now available

The user supplied `HouseholdFinance_Codex_Handoff.zip`, extracted in Downloads
outside this repo. The handoff and relevant source/tests have been reviewed;
all 61 enclosed manifest hashes matched. See
[website-handoff-review.md](website-handoff-review.md) for provenance, source
evidence, model gaps, and the revised sequence. The historical website remains
unchanged; its live ledger, queues, account state, and private configuration were
not exported or accessed.

The handoff recorded an earlier preference to avoid routine manual file transfer.
The user has now explicitly confirmed **manual file exchange is acceptable
initially**. Keep it as the initial ChatGPT workflow and prove a synthetic round
trip early. The app-owned local ledger and Apple backup direction from this
conversation supersede the old Sheet-authoritative browser architecture.

Inherited product rules to retain:

- Explicit per-transaction approvals; separate Approve, Discuss, Skip, and Reopen
  intent. AI suggestions, comments, confidence, and merchant rules never approve.
  Classification/tag/Exceptional Event changes reopen approval; note edits and
  discussion alone preserve prior approval. Pending charges cannot be approved.
- Separate posted spending, pending authorizations, merchant refunds, payments,
  statement credits, and transfers. Payments/statement credits and transfers are
  excluded from spending; pending totals stay separate. Preserve posted/activity
  dates and source/account identity, descriptions, revisions, and related IDs.
- User notes, assistant questions/reasons, user answers, and historical ledger
  notes have distinct ownership. Never prefill user notes with assistant text.
- Balanced category allocations, per-charge tags, and explicit Exceptional Event
  exclusions. Overlapping category/tag/event filters count excluded amounts once.
  Flagged expenses remain included by default. Routine repairs remain ordinary.
- Distinct electricity/natural-gas/water tracking; separate travel subcategories;
  requested medical subcategories and Holiday Overhead. The reference is not a
  complete current taxonomy export; user-specific benefit settings stay private.
- Expected reimbursement neither reduces spending nor records repayment. Received
  requires actual repayment evidence; partial matching remains to be designed.
- Multiweek review plus historical overview and category expense drilldown with
  explicit coverage. Missing sources/details/prior periods are unavailable, not
  zero spending. Aggregates/projections cannot substitute for migration of actual
  historical transaction records.
- Distinct local-save, queued, uploaded/unprocessed, applied, failed, rejected, and
  conflict outcomes. Preserve both in-app feedback and direct-chat corrections,
  with idempotent operation IDs, revision checks, and processing receipts.

The user confirmed adopting USD's legacy **positive-outflow** convention:
positive expenses and negative refunds/other inflows. Native examples and editor
guidance now match it. Preserve legacy IDs beside UUIDs. Older unmarked native
prototype stores/drafts require explicit conversion and remain untouched; a
convention marker prevents silent reinterpretation. Other source formats still
need explicit sign mapping. The legacy Sheet's two-allocation/one-shared-subcategory limits
are adapter constraints, not settled native requirements. The current scaffold
now implements treatment/posting, explicit review actions, and comment ownership.
The remaining source/provenance, split, reimbursement, coverage, and exchange work
is not complete; 22 passing core tests do not establish website feature parity.
See [review-workflow.md](review-workflow.md) for implemented rules and limits.

User-reported setup:

- iPad model identifier: MHQU3LL/A; reported as running "iOS 27.0" (iPadOS version
  to confirm on device). No model-name lookup or device inspection was performed.
- Mac terminal output supplied by the user: macOS 26.5.2 (25F84), Xcode 26.6
  (17F113), and Swift 6.3.3 (swiftlang-6.3.3.1.3, clang-2100.1.1.101).
  These are user-reported results; this agent has not accessed the Mac directly.
  The user reports a macOS update is available, but its target version is unknown.
- ChatGPT plan: Plus. The current Sheet's columns, rules, and return format have
  not been inspected. Do not assume access to that Sheet or prior conversations.

Setup recommendation checked against Apple documentation on 2026-10-24: the
reported macOS/Xcode combination is supported. Xcode 26.6 includes the iPadOS 26.5
SDK; stable Xcode 27.x provides the iPadOS 27 SDK and requires macOS 26.6 or later.
Update macOS to a supported stable version, then install stable Xcode 27.x and
its platform support. A major upgrade to macOS 27 is not required solely for this
toolchain. Use Xcode's bundled Swift; no standalone Swift update is needed on Mac.
An older SDK alone does not prove that an app cannot run on a newer device OS;
actual pairing, signing, installation, and debugging still need a device test.
The user will complete the updates before Mac work is needed. The updates and
that test remain pending; do not record the recommended versions as installed.
[Apple Xcode compatibility table](https://developer.apple.com/xcode/system-requirements/).

## Repository and tool inspection

Observed in `C:\Users\rproi\source\repos\FinTrack` on 2026-10-24:

| Item | Finding |
| --- | --- |
| Repository | `main` tracking `origin/main`; initial empty commit `6325623`; no tracked files before this task |
| Existing local files | Untracked `.vscode/settings.json` and `Microsoft/Windows/PowerShell/ModuleAnalysisCache`; left in place |
| Prior guidance | No existing repository AGENTS.md or guidance found at the checked ancestor paths |
| Git | 2.56.0.windows.3 at `C:\Program Files\Git\cmd\git.exe`; not on this tool shell's PATH |
| VS Code | 1.143.1, x64; Codex extension reported; no Swift extension reported |
| PowerShell | 5.1.26100.9711 |
| Swift | Not found on PATH or in the common installation locations checked; no compiler/test execution verified |
| Xcode tools | `xcodebuild` and `xcrun` unavailable on Windows; Mac not connected or inspected |
| Other runtimes | Python and Node not on PATH; .NET host found but no .NET SDK reported; none required for this planning task |

At initial inspection no Xcode project, Swift package, dependency manifests, app
code, fixtures, or test suite existed. The first scaffold now exists (see below).
Set an explicit working directory for shell calls: the shell initially started
outside this workspace.
VS Code extension listing produced a log-directory permission warning but returned
an extension list; this was not a full IDE health check.

Subsequent cleanup: removed the generated PowerShell cache and its empty parent
directories. Kept `.vscode/settings.json` (Peacock workspace colors) locally and
excluded `.vscode/` from Git. The cache ignore rule remains in case it regenerates.

## Current implementation progress

The user approved proceeding after the local-first storage/backup proposal.
The first source scaffold is now in `Apps/FinTrack` with portable `FinTrackCore`
and Apple-only `FinTrackPersistence` packages. SwiftData is selected for this
prototype, with production use gated on Mac/iPad save, migration, and recovery
validation. Project setup and test commands are in [development.md](development.md).

- Implemented in source: browse/search/date/review filters, manual add/edit,
  posting/treatment, invented-category selection, tags/Exceptional Event,
  Approve/Discuss/Skip/Reopen with per-record history, separated user/assistant
  fields, recoverable drafts, local saves, exact spending/pending totals, stable
  IDs/revisions, duplicate-UUID checks, and 24 opt-in synthetic records.
- Tests authored: money/date/review/treatment rules, old draft decoding,
  serialization, revisions/retries, deterministic examples, storage reopen,
  write/action failure rollback, and v1-to-v2 migration preservation. Native
  storage/migration tests are not executed yet.
- Not implemented: full category/subcategory management, split allocations,
  source/account provenance, reimbursements, bank imports, coverage/overview,
  backup export/restore, ChatGPT exchange, or cloud record sync.
- Confirmed amount convention: positive expenses, negative refunds/income. The
  prototype uses USD, dot-decimal input, Gregorian dates, explicit approval and
  independent discussion. Additional currency/source-date needs remain open.
  See [data-model.md](data-model.md).
- Windows Swift setup is now usable: after an initial canceled installation and
  the user's subsequent setup, FinTrackCore compiled with Swift 6.4.1 and all 22
  tests passed on 2026-10-24. Apple persistence tests and the native app build have
  not run. The Mac update and first device build remain pending.

## Functional requirements

| ID | Requirement | Acceptance example using synthetic data |
| --- | --- | --- |
| F1 | Browse multiple weeks of history with date navigation/filtering | Load at least eight synthetic weeks, move between ranges, and open/edit old records without losing newer ones |
| F2 | Add and edit transactions manually | Create a record offline, edit its date/description/amount, relaunch, and see the saved result |
| F3 | Manage categories and subcategories | Add, rename, and assign them; handle in-use category removal without orphaned records |
| F4 | Add and edit splits | Allocate a transaction across categories; reject an unbalanced committed split while preserving the draft |
| F5 | Add, edit, and assign tags | Assign multiple tags and retain them after relaunch and exchange |
| F6 | Track notes and explicit approval/discussion state | Notes preserve approval; classification changes reopen it; Discuss requests follow-up without implying approval; pending charges cannot be approved |
| F7 | Track reimbursements | Record an expected reimbursement, partial receipt, and settlement without double-counting the expense or receipt |
| F8 | Save valid edits immediately and work offline | A saved edit survives termination/relaunch in airplane mode; a failed write is visible and retains the draft |
| F9 | Import safely and recognize duplicates | Import the same file twice without adding duplicates or replacing manual annotations; surface ambiguous matches |
| F10 | Exchange records and review suggestions with ChatGPT | Initially use manual selected-range packets; preserve app/chat feedback, preview returned proposals, and apply only explicitly accepted changes |
| F11 | Preserve changes during future sync/exchange | A proposal based on an older revision raises a conflict and preserves a later manual edit |
| F12 | Support Apple cloud backup of authoritative data | On iPad, verify the local store is eligible for device backup, FinTrack is included in the user's iCloud Backup settings, and a test backup completes |
| F13 | Export and restore an independent full backup | Export a dated synthetic archive to iCloud Drive, validate its contents, restore into an isolated test store, and confirm all records and relationships match |
| F14 | Preserve source identity and accounting treatment | Reimport/migrate without replacing source IDs or metadata; keep posted/pending, spending/refunds, payments/credits/transfers distinct |
| F15 | Preserve comment ownership | Assistant questions never appear as user-authored notes; old ledger notes remain readable without being overwritten |
| F16 | Report historical source coverage | An unavailable account/month/detail is labeled unavailable; category shares and totals reconcile without double counting |
| F17 | Filter spending without changing the ledger | Tag/category/Exceptional Event exclusions overlap without double subtraction; flags alone do not exclude expenses |
| F18 | Track review-processing outcomes honestly | Uploaded feedback remains unprocessed until an explicit processing result; failed/conflicting operations remain recoverable |

Proposed browsing additions: text search and filters for category, tag, review
status, and outstanding reimbursements. Their exact layout is not yet specified.

## Data integrity and privacy requirements

- The on-device store is authoritative for the first version. An export or AI
  response is not a replacement database. ChatGPT is never required to save edits.
- Persist each valid edit through an explicit successful write before showing it
  as saved. Define a field editing boundary (for example, accepted value or focus
  change); invalid/incomplete input remains a recoverable draft. Related split
  changes and accepted proposal batches must be atomic.
- Represent money exactly with an explicit currency and rounding policy. Choose
  integer minor units or decimal arithmetic; do not use binary floating point.
- Use stable IDs and per-record revisions. Preserve import provenance, source
  IDs, and user annotations. Define schema migrations and backup/restore before
  any use with real records; never reset a store as a migration fallback.
- Prefer source/account/external transaction IDs for duplicate detection. Without
  source IDs, use candidate fingerprints and review ambiguous matches: two equal
  purchases on one date can be legitimate. Reimports must be idempotent. Pending
  to posted transitions and changed bank descriptions need explicit policies.
- Future sync must detect stale writes and preserve competing edits, including
  deletion intent. Avoid silently replacing records or a shared database file.
  Cloud sync is deferred; conflict tests can use simulated revision changes.
- Use synthetic data for development, tests, demonstrations, logs, and screenshots.
  Do not commit real transactions, source exports, financial files, credentials,
  tokens, provisioning profiles, or signing keys. Prefer private storage outside
  the repo; `.gitignore` only adds protection for known paths and file types.
- Any later credentials belong in platform credential storage (Keychain on iPad),
  never source code or exchange files. Do not copy Codex login tokens into the app.
- Export only selected records/fields after a clear preview. Include notes only
  when selected. Do not fetch conversations, memories, accounts, or financial
  files implicitly. AI proposals must pass schema, ID, revision, amount, and
  relationship validation before the user can accept them.

## Storage direction and Apple cloud backup

Selected for the first single-user/single-iPad prototype: local-only SwiftData
behind a small repository interface. The design includes iCloud device-backup
eligibility and future full backup archives exportable to iCloud Drive. Keep
finance rules and exchange models in a portable Swift package. Production
adoption remains provisional until Mac/iPad tests verify saving, migrations, and
recovery; alternatives remain available if a material limitation appears.

| Candidate | Why consider it | What the spike must establish |
| --- | --- | --- |
| SwiftData, local only | Natural candidate for a small SwiftUI app | Explicit saves/failures, atomic splits, uniqueness/dedup strategy, migrations, backup/restore, and supported OS range; Apple-specific tests require Mac |
| SQLite with a maintained Swift adapter | Explicit schema/transactions and potential portability | Dependency/platform support, migrations and concurrency cost; Windows testability is conditional on the chosen adapter |
| Core Data, local only | Alternative if mature Apple persistence features justify extra setup | Implementation cost and migration/test needs compared with the other candidates |

Do not select storage solely because it offers automatic cloud sync. If SwiftData
is selected, configure CloudKit off explicitly and omit cloud capabilities during
this phase. Apple documents opting out with `cloudKitDatabase: .none`.
[Apple: SwiftData synchronization](https://developer.apple.com/documentation/SwiftData/Syncing-model-data-across-a-persons-devices).

A shared JSON/CSV file is a proposed exchange format, not the live database.
Multi-person access and editable replicas are outside the confirmed v1 scope.

### Backup design and limits

Apple documents `Library/Application Support` as a backed-up location for internal
app data. Store the authoritative database there, avoid cache/temporary locations,
and do not exclude irreplaceable records from backup.
[Apple file storage guidance](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html).

iCloud Backup includes local app data that is not already synced to iCloud. It
takes periodic device snapshots, rather than uploading every transaction edit.
Its use depends on the user's settings and available storage; FinTrack must not
claim it has enabled or verified device backup on the user's behalf.
[What iCloud backs up](https://support.apple.com/en-us/108770).
Apple describes automatic daily backup when the iPad is locked, on power, and
connected to Wi-Fi; setup and actual completion must be checked on the device.
[Back up iPad](https://support.apple.com/guide/ipad/back-up-ipad-ipad9a74df05xx/ipados).

Proposed app-level recovery feature: a user-initiated **Create Backup** action
that exports a dated, versioned full archive through the system file picker to a
user-selected folder such as `iCloud Drive/FinTrack/Backups`. iCloud Drive is
available through Files and stores files in the user's iCloud storage.
[iCloud Drive on iPad](https://support.apple.com/guide/ipad/set-up-iclouddrive-ipad847732d1/27/ipados/27).
This is an independent snapshot, not a second editable ledger. Keep the working
database local and never use Drive to synchronize a live database file.

The full archive must cover records, categories/subcategories, splits, tags,
notes, review/reimbursement state, IDs/revisions, and import/proposal provenance,
with a manifest and schema version. Export a consistent logical snapshot rather
than copying open database files. Keep older snapshots; do not overwrite a single
file on every edit. Backup archives differ from selected/redacted ChatGPT review
packets and must not include credentials.

**Restore Backup** must validate the archive, preview its contents, protect the
current store with a recoverable snapshot, and require confirmation before
replacing current data. Test restores using an isolated store and synthetic data
before real usage. A corrupt or unsupported archive must leave current data intact.
Device backup supports device recovery; this separate archive provides FinTrack
with a direct app-level restore path.

Record completed export time separately from any cloud-upload status the system
actually exposes. A successful local save or file export does not prove a remote
copy exists. Offline edits must remain usable if iCloud is disabled, unavailable,
or full. Automatic archive scheduling, retention, and archive encryption are still
open decisions; do not promise background uploads on a fixed schedule.
No CloudKit record sync or custom cloud service is required by this recommendation,
and no cloud access or backup implementation has been performed in this task.

## ChatGPT integration: verified options and remaining gaps

Official documentation checked on 2026-10-24. The user has Plus, but no account
authorization, feature availability, or end-to-end integration was tested.

| Route | Verified support | FinTrack recommendation / open issue |
| --- | --- | --- |
| User-mediated files or pasted text in ChatGPT | Official guidance supports supplying CSV/spreadsheets, requesting output files, and reviewing results [1] | User explicitly accepted this initially after handoff review; prove an early synthetic round trip, including direct-chat feedback and stale-edit protection. FinTrack makes no billed LLM request |
| Sign in with ChatGPT with plan usage | Eligible Plus/Pro subscribers can authorize plan usage; documentation covers open-source/local projects and selected private clients [2][3] | Candidate for later in-app analysis. Confirm project eligibility and a supported native iPad authorization flow before choosing it |
| ChatGPT plugin/custom MCP tools | ChatGPT supports custom MCP read/write tools via server URL or a secure tunnel; access and workspace controls apply [6] | Possible later exchange bridge. Requires an available authenticated service/host and reconciliation design; do not build it now |
| Standard API-key inference | API pricing is separate from subscription usage [7] | Excluded by the requirement to avoid separately billed LLM API usage; no API key setup or paid fallback |

Sign-in and plan usage are separate permissions. Plan usage shares the subscriber's
existing allowance, can involve available credits, and does not grant access to
conversations or memories [3]. FinTrack must stop or defer analysis at limits;
do not assume unlimited use or enable extra paid usage automatically.

The documented open-source sign-in flow uses PKCE and an HTTP loopback callback
at `127.0.0.1` [4]. **Inference:** these desktop-style instructions do not establish
a supported native iPad flow. Validate mobile callback/lifecycle support and any
required approval; do not assume a custom URL scheme can replace it. Open-source
versus private distribution is also unresolved. No need to make the repo public
as part of this task.

The plan-usage preview requires streaming, `store: false`, and explicit request
context. Persistent conversation reuse and several hosted tools, including file
search and Code Interpreter, are unavailable on that route [5]. In-app analysis
must therefore be evaluated separately from the current interactive Sheet review.

Sources:

1. [ChatGPT: clean and prepare data](https://learn.chatgpt.com/use-cases/clean-messy-data).
2. [Sign in with ChatGPT quickstart](https://developers.openai.com/siwc/quickstart).
3. [ChatGPT plan usage and permissions](https://learn.chatgpt.com/docs/sign-in-with-chatgpt).
4. [Registration and sign-in contract](https://developers.openai.com/siwc/token-sharing-open-source/sign-in).
5. [Plan-usage preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).
6. [Custom MCP server connection](https://developers.openai.com/api/docs/guides/custom-mcp-server).
7. [Subscription and API pricing distinction](https://learn.chatgpt.com/docs/pricing).

### Initial exchange direction accepted; packet contract still proposed

Export a user-selected range as a versioned review packet: readable CSV plus a
structured JSON representation for splits, tags, and reimbursements, with a short
review prompt. Include only explicitly provided categorization rules and context
needed for the task. The user supplies it to the chosen ChatGPT conversation and
returns a structured proposal file or pasted proposal text to FinTrack.
This manual transfer is now explicitly acceptable initially. Prove the round trip
before broad feature expansion; do not reuse the old Sheet feedback contract
without reconciling its different authoritative owner, IDs, signs, and revisions.

Proposed packet fields: schema version, packet ID, export time/range, stable
record IDs, base revisions, currency/amount conventions, and relevant category/tag
definitions. Proposed return fields: packet ID, proposal ID, record ID, expected
revision, allowed field changes, and rationale. Exact schema and CSV columns are
still open; an end-to-end synthetic experiment should settle them.

FinTrack validates and previews proposals against current records. Accepting an
unchanged record applies an atomic edit; rejecting a suggestion changes nothing.
Stale revisions require explicit resolution and never overwrite a newer edit.
Unknown IDs/fields, invalid splits, and repeated proposal IDs are rejected or
flagged. Keep an application history so accepted changes can be inspected and
undone safely without erasing intervening edits. A returned full ledger must not
silently replace the store. This exchange works without Google Drive sync.

## Unresolved decisions

| Decision | Proposed next step |
| --- | --- |
| Local persistence engine and minimum iPadOS | SwiftData selected for prototype, provisional deployment minimum iPadOS 17; verify saves, migrations, and recovery on Mac/iPad before real-data use |
| ChatGPT exchange route | Manual file exchange explicitly acceptable initially; settle packet fields/receipts and prove app/chat feedback round trip early. Direct plan sign-in remains a separate feasibility question |
| Existing review rules and fields | Handoff/source now reviewed; carry documented behavior into synthetic Swift tests. Actual private taxonomy/current ledger state still needs a separately authorized migration export |
| Currency, amounts, and dates | Positive-outflow convention confirmed and adopted; test source-specific import mappings and explicit migration of old native stores. Settle posted/activity dates, timezone, and additional currency needs |
| Categories, splits, review, reimbursements | Explicit approval/discussion rules are implemented; replace prototype catalog with full taxonomy management, decide native allocation/subcategory limits, and design partial repayment matching |
| Import sources | Choose one initial file format; define source identity, duplicates, pending/posted updates, refunds, and transfers |
| Household access and future sync | Single user on one iPad confirmed; no multi-device or household sharing in v1. Record sync remains deferred |
| Recovery and privacy | Apple cloud backup preferred; verify iCloud Backup on device, trial archive export/restore via iCloud Drive, and settle archive format, retention, encryption, redaction, and app lock |
| Mac/device provisioning | Confirm personal Apple account, developer membership, work Mac constraints, and intended installation method |
| Distribution / sign-in eligibility | Decide personal/private versus open-source distribution; confirm mobile support before embedding plan usage |

## Small implementation plan

1. **Continue model alignment with the reviewed website.** Treatment/posting,
   activity dates, explicit review actions, and separated notes/questions now
   have portable tests. Add source/account identity, full taxonomy/allocations,
   and source import mappings; settle native-only schema choices.
2. **Validate the existing native slice.** The project and portable package now
   exist. Verify Mac updates/signing, run persistence tests and the app, add/edit
   a category, and verify offline save/reopen plus draft recovery on iPad. Keep
   the local store eligible for device backup; no CloudKit or hosted bridge.
3. **Prove the first ChatGPT file round trip early.** Export selected synthetic
   records, capture app and chat feedback, return proposals/results, and explicitly
   accept/reject them. Test stale revisions, repeated imports, and offline
   recovery before broad UI expansion. No separately billed model API calls.
4. **Complete recovery and expand features.** Implement full backup/restore and
   verify iCloud backup before real data. Then expand splits, tags, reimbursements,
   historical overview, and one migration/import adapter with source/approval
   preservation. Actual ledger/feedback/journal exports need separate authorization.
   Cloud sync still requires a settled design before implementation.

## Windows, Mac, and iPad validation

| Environment | Can validate | Cannot establish |
| --- | --- | --- |
| Windows now | Documentation, source review, Git diffs, and synthetic JSON/CSV shape checks with available tools | Swift compilation/tests: no toolchain currently available; no native iPad build or UI run |
| Windows after optional Swift setup | Portable `FinTrackCore` builds/tests: money/splits, import identity, proposal validation, revision conflicts | SwiftUI/SwiftData integration, Apple SDKs, signing, simulator behavior |
| Mac with Xcode | Full app build, previews, simulator/UI tests, Apple store/migration/backup tests, signing, install/debug | Actual device behavior and performance from simulator results alone |
| Physical iPad | Offline edits and relaunch, interruption/draft recovery, file export/import and ChatGPT handoff, iCloud Backup inclusion, full archive export/restore through iCloud Drive, touch/keyboard/layout/accessibility, reimbursement workflow | Actual cloud copy existence from local-save/export success alone; future multi-device cloud conflict behavior until a sync design exists |

Swift.org documents Windows installation and its tool prerequisites. Installing
Swift and a VS Code Swift extension is optional for this first task; nothing was
installed. Keep the portable package free of SwiftUI, SwiftData, and other
Apple-only dependencies. [Swift for Windows](https://www.swift.org/install/windows/).

After package creation, run `swift test --package-path Packages/FinTrackCore` on
both configured machines. Add exact Xcode project/scheme commands once they exist;
do not treat an unwritten project or a Windows package test as an iPad build.

Mac setup checks to run when access is available:

```sh
sw_vers
xcodebuild -version
swift --version
xcrun simctl list devices available
```

Confirm the installed Xcode supports the iPad OS and download matching platform
support if needed. Sign in to the intended Apple account, select the team, pair
the iPad, and configure Developer Mode as required. Apple documents Mac-based
simulator/device runs and provisioning. A free Personal Team requires periodic
reprovisioning; Apple currently documents seven-day provisioning expiration.
Decide whether that is acceptable for everyday use.
[Device testing](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices),
[Personal Team limitations](https://developer.apple.com/help/account/basics/about-your-developer-account).

Use Git to transfer source between Windows and Mac. Keep runtime stores, private
exports, signing credentials, and personal tool state outside tracked source.
Access to the work Mac and its policies is unverified; use synthetic data there.

Initial planning validation covered documentation and ignore rules. FinTrackCore
now builds on Windows and all 22 tests pass with Swift 6.4.1. No Mac session
was available for Apple persistence or native app verification. See development.md
for current checks and limitations.
