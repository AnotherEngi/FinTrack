# FinTrack project guidance

## Purpose and context

FinTrack is a new native iPad household finance app built with Swift and SwiftUI.
The personal Windows PC with VS Code and Codex is the main workspace. A work Mac
is available for Xcode builds, debugging, signing, and installation. The iPad is
the main testing and usage device: model MHQU3LL/A, reported OS 27.0. The user
reported macOS 26.5.2 (25F84), Xcode 26.6 (17F113), and Swift 6.3.3
(swiftlang-6.3.3.1.3, clang-2100.1.1.101). Recommend macOS 26.6 or later with
stable Xcode 27.x for the iPadOS 27 SDK; an update has not yet been confirmed.
The user later reported a successful app build and physical-iPad refund edit/
reopen persistence check; exact updated tool versions remain unconfirmed. Version 1 is for
one user on one iPad. The user requires cloud-backed storage and prefers their
Apple iCloud storage; actual iCloud settings and backup availability are unverified.

An earlier web app and the current Google Sheet finance-review workflow have
been frustrating because of Google Drive reconnects and sync conflicts. FinTrack
must manage transaction records directly. ChatGPT provides analysis and proposed
changes; the user must also be able to add and edit records independently.
The user has ChatGPT Plus. See [requirements](docs/requirements.md) for details,
verified integration sources, unresolved decisions, and the implementation plan.
The existing website handoff has now been reviewed; see
[website handoff review](docs/website-handoff-review.md). Its extracted historical
source remains in Downloads, unchanged and outside this repo. Use its behavior
and synthetic tests as reference, not its browser auth/Sheet storage architecture.
Current transaction/review behavior and migration limits are documented in
[review workflow](docs/review-workflow.md).
The user approved and locked the refined transaction table design on 2026-10-24,
captured in
[transaction design](docs/design/transactions.md). Preserve its sorting, optional
approved/non-approved split, category/tag status pills, detailed editor, and
independent session/discussion indicators. The HTML preview remains design-only;
the native table, local source aliases, per-field provenance, process-session
markers, and explicitly user-tracked discussion progress are now implemented in
source. The newer review/backup batch below adds a narrow weekly source-ID intake
contract and manually imported processing receipts; arbitrary bank adapters and
automatic ChatGPT transport remain future work.
The user corrected pill placement after the first iPad review: **only category
and tags are colored; merchant text is always plain, including approved rows**.
This correction supersedes the earlier merchant-pill interpretation.
Use the approved preview defaults as the implementation baseline: category/tag
status pills, comfortable rows, and a detailed edit sheet. Earlier preview
alternatives are exploratory, not the approved layout. This approval records the
design decision. The user has now shown the native table running on iPad; its
color/width/gutter/export-discovery refinements still need a new device check;
see docs/ipad-acceptance.md for the combined table/export/ChatGPT test session.
Standing UI decision: protect screen space. Do not put a FinTrack branding/header
bar on working screens or repeat an active tab name as a page heading. The
transaction workspace omits permanent color legends, record/approval counts,
and the known USD label. Use a thin leading activity column with an icon heading,
equal icon action buttons, top search/date presets, and an **Amalgamate** switch
(on combines tables; off separates approved rows below non-approved rows).
Keep accessible labels and usable touch targets. Currency remains explicit in
the data model/exports. See the design notes before adding interface chrome.
The user explicitly requested public source visibility for anonymous pulls on
the work Mac. `AnotherEngi/FinTrack` was made public on 2026-10-24; GitHub access
checks showed only the owner with write access, no collaborators/invitations or
deploy keys. Keep the work Mac free of GitHub write credentials. Public source
does not change the requirement to keep financial data and credentials private.

## Required behavior

- Browse multiple weeks of history.
- Add and edit transactions, categories, subcategories, splits, and tags.
- Track notes, review status, and reimbursements.
- Persist valid edits immediately and operate offline.
- Automatic iCloud backup of the latest complete authoritative app state is
  critical. Device-backup eligibility alone is insufficient. Automatic retention
  of older versions is not required; manual full export/import is a proposed
  supplementary recovery feature. Choose and validate the backup mechanism.
- Preserve user changes during future exchange/sync and handle duplicate imports.
- Exchange selected data and suggested changes with the existing ChatGPT workflow.
- Keep core record management usable without ChatGPT or a network connection.

## Boundaries

- Use synthetic transactions throughout development, fixtures, screenshots, and tests.
- Keep real financial data, bank exports, personal notes, account identifiers,
  credentials, tokens, signing identities, and private keys out of source control.
  Prefer storing private material outside this checkout. Ignore rules are a backup,
  not proof that a file is safe to commit. Inspect the actual staged diff.
- Do not assume access to existing ChatGPT conversations, memories, connected
  accounts, Google Sheets, or financial files. Ask for necessary context explicitly.
- Do not implement cloud sync, Google Drive integration, CloudKit capabilities,
  or a hosted bridge until the integration approach has been settled with the user.
  Cloud backup is distinct from record sync: OS-managed device backup and explicit
  backup-file export fit the proposed local-first design. Keep the live database
  local; do not place it in iCloud Drive. Do not promise every saved edit is
  already backed up or that an exported file has finished uploading.
  The user subsequently authorized automatic **backup** through a user-selected
  iCloud Drive folder. This is implemented in source with remembered folder
  permission and upload-metadata confirmation; it does not authorize record sync,
  a live cloud database, CloudKit, or a hosted bridge.
- The user explicitly confirmed after reviewing the handoff that manual file
  exchange with ChatGPT is acceptable initially. Prove a synthetic round trip
  early; do not assume that Apple cloud backup gives ChatGPT access to records.
- Preserve per-transaction explicit approvals and separate Discuss/Skip/Reopen
  intent. Comments, suggestions, or merchant rules must not imply approval.
  Pending charges cannot be approved; preserve treatment/exclusion semantics.
- Keep user-authored notes separate from assistant questions/reasons and legacy
  note history. Expected reimbursements do not reduce spending or prove repayment.
- Do not introduce separately billed LLM API usage or an automatic paid fallback.
  Recheck official subscription integration documentation before implementation.
  ChatGPT Plus eligibility alone does not establish native iPad support.
- Treat AI output and imported files as untrusted input. Validate proposed changes
  and let the user review and accept them before modifying authoritative records.
- Preserve unrelated work. Do not commit, push, install tools, or create accounts
  unless requested or otherwise authorized. Ask when a missing tool is needed.

## Implementation guidance

- Latest iPad feedback: all populated category/tag values have colored review
  pills, including older unknown provenance (orange needs review; keep stored
  origin unknown). Blue is user-edited and green approved. The earlier neutral
  fallback is superseded. Never rewrite old example records to repair their UI.
- The user confirmed separating discussion answers from category/tag proposals.
  Answers are readable with Reply/Mark Resolved; only actual record changes use
  Apply changes/Keep current. Import records matching acknowledgements, never
  approvals or automatic financial edits. Preserve legacy response compatibility.
  Discussions replaces Questions, with a thin question column beside activity.
  Reply drafts/messages/closure are optional V3 workspace fields, backed up.
- Send, Import, and Backup are separate review pages. Lock preparation choices
  after creating a file; label its mode and require Start Another Review to
  prepare another. Manual full backup export opens a Files save dialog and does
  not depend on automatic cloud-backup configuration.
- Overview must lead with category spending, monthly trends, and year comparisons,
  as explicitly selected by the user. Use exact amounts, separate pending, leave
  missing periods unknown, and provide transaction drilldowns. See
  [current flow](docs/review-flow.md); the old HTML preview is historical for these
  additions. Native chart/file-provider UI still needs Mac/iPad validation.

- The user clarified the four data flows on 2026-10-24: their existing ChatGPT
  task retrieves card transactions weekly; FinTrack needs intake, durable app
  feedback, and recoverable classification knowledge around the accepted ledger.
  These private connections were reported, not accessed or verified. The user
  accepts manual attachment initially with automatically prepared contents.
  Routine review must gather pending marked/added/modified work without repeated
  record/context selection. See [data-flow proposal](docs/data-flow-proposal.md)
  for the proposed architecture, current implementation gaps, and open choices.
  The user subsequently requested implementation. Manual file transport and a
  one-time user-selected iCloud Drive backup folder are implemented in source;
  Mac/iPad validation remains. Cloud record sync and automatic ChatGPT transport
  remain excluded.
  Snapshot export and process-session markers are not a durable feedback queue.
- The user also requires periodic full-history ChatGPT review and ongoing cloud
  backup, beyond routine pending feedback and manual backup export. Design for
  full-history snapshots and automatic latest-state backup/retry with visible pending,
  failed, and cloud-confirmed status. Source now implements these with manual
  full-history review and user-selected iCloud Drive folder backup. Actual upload,
  permission renewal, migration, and recovery need Mac/iPad validation; offline
  edits cannot have immediate cloud protection. Automatic history-review cadence
  is not implemented; do not implement cloud record sync on this basis.
  The user clarified that automatic historical backup retention is not required.
  Preserve the last good cloud backup until its replacement is complete; this is
  safe replacement, not a requirement for a user-visible version archive.

- The user approved proceeding with the local-first prototype. It now uses
  local-only SwiftData. The user reports both Mac package test suites passed;
  the four focused iPad checks provisionally passed based on the user's report.
  Backup/restore validation remains before real-data use.
  Latest source adds schema V3 durable feedback/manifests, incoming response and
  weekly staging, source-ID reconciliation, explicit proposal decisions/receipts,
  editable guidance, automatic iCloud folder backup, and full backup export/restore.
  Drafts migrate from old files into the workspace atomically; original files are
  preserved as evidence. Ledger changes and feedback/draft updates commit together.
  Direct subscription sign-in remains future work. See docs/chatgpt-export.md.
- Favor a small Swift package for portable finance rules and exchange contracts,
  with SwiftUI and the selected Apple persistence adapter outside that package.
- Use stable record IDs, exact monetary arithmetic (never binary floating point
  for amounts), explicit currency, schema versions, and revision checks.
- Confirmed amount convention: positive outflows/expenses, negative refunds and
  other inflows (including income), matching the legacy ledger. Sign alone does
  not determine accounting treatment. Fresh stores carry an outflow-positive-v1
  marker; unmarked older stores/drafts require explicit migration and remain
  preserved. Never silently flip existing amounts or reset a store.
- Re-imports and stale AI suggestions must not overwrite newer manual edits.
  Preserve source identity/provenance; ambiguous duplicate matches need review.
- Commit related changes atomically; a split must balance to its parent. Report
  persistence failures visibly and retain the user's editable draft.
- Record decisions and update requirements when scope or constraints change.
- Carry forward the reviewed website's domain rules before expanding the UI.
  The native sign convention now matches its positive-outflow convention; other
  import formats still need explicit source-specific sign mapping. Preserve source
  IDs/revisions alongside local UUIDs; do not treat duplicate-UUID checks as full
  bank import deduplication. Missing history coverage must not become zero spend.

## Validation and environment

- Current review/backup/discussion/chart batch: all **77** portable tests pass on Windows Swift
  6.4.1. Hardening results are recorded
  in docs/device-verification.md. Fourteen Apple source/test files pass Windows
  syntax parsing only. There are 25 Apple persistence tests (four new in this UX follow-up); run them
  and the Xcode build on Mac. Verify iCloud permission, metadata confirmation,
  retries, and full restore on iPad before real data. The older test counts below
  are historical evidence, not validation of schema V3 or cloud backup.

- Always set the shell working directory explicitly to this repository. This
  environment's default shell directory did not match the supplied workspace.
- Git works at `C:\Program Files\Git\cmd\git.exe`, but is absent from this shell's
  PATH. Swift, xcodebuild, and xcrun were unavailable during the initial inspection.
- Windows can review/edit Swift and validate fixtures/contracts. After installing
  a supported Windows Swift toolchain, it can build/test portable Swift packages.
  Do not claim Windows has validated SwiftUI, SwiftData, or an iPadOS build.
- Use the Mac for Xcode project creation, SwiftUI previews, Apple persistence and
  migration tests, simulator/UI tests, signing, and device installation/debugging.
  Verify actual usage, offline saves, lifecycle behavior, and file handoff on iPad.
- Run checks appropriate to each change and state what ran, what could not run,
  and why. See docs/development.md for build commands and outstanding validation.
- Run `swift test --package-path Packages/FinTrackCore` on Windows or Mac with a
  working Swift toolchain. Run the FinTrackPersistence package tests and app build
  on Mac. FinTrackCore compiled with Windows Swift 6.4.1 and all 50 tests passed
  on 2026-10-24. The user reported that the app builds and an edited synthetic
  refund amount persists after closing/reopening on the physical iPad. The user
  also reports both FinTrackCore and FinTrackPersistence tests passed on Mac;
  test logs/counts were not supplied. The user says all four focused iPad checks
  appeared to work: approval/classification edits, discussion/pending restrictions,
  force-quit draft recovery, and offline creation/relaunch. Treat these as
  provisional passes. See docs/device-verification.md; keep user reports
  distinct from agent-executed test results.
- The earlier table batch implements the approved native Transactions table alongside
  Overview, Questions, Review history, and ChatGPT export. SwiftData schema v2 is
  unchanged; its domain payload gains backward-compatible optional source,
  classification-provenance, and discussion-progress fields. Old fields default
  to unknown source/origin and awaiting-export for an existing discussion request.
  All 50 core tests pass on Windows. All ten native app/persistence source/test
  files passed syntax parsing only; 12 Apple persistence tests await this batch's
  Mac run. Earlier user-reported Mac/iPad passes predate this batch.
  The first current-batch Mac attempt stopped in LedgerDisplay.swift with a
  compiler typechecking timeout, blocking both packages. History and overview
  expressions have been split into typed loops/separate sorts; all 50 Windows
  tests passed again. The user subsequently showed the native app running on iPad;
  the current standalone package-test results are not explicitly reported.
  Prefer small typed steps over
  nested flatMap/map/sorted expressions when evolving these shared projections.
  Follow docs/ipad-acceptance.md for one combined Mac/iPad/ChatGPT session.
  The newer routine review supersedes selected-range export: include pending
  feedback/open questions and their committed context automatically, including
  relevant notes/answers and prior/saved values. Explain this before the user
  shares. Full-history mode includes every accepted record. Keep Int64 amounts/
  revisions as strings in review/source contracts. Sharing is not receipt;
  importing analysis cannot approve or edit records without explicit acceptance.
- Windows setup scripts are in scripts/. The initial prerequisite installation
  was canceled, but Swift 6.4.1 and VS 2022 Developer PowerShell 17.14.42 are now
  available. Refresh the process PATH or reopen terminals after tool installation.
  The restricted shell may deny access to installed tools; use approved escalation
  for execution when needed. Do not automatically retry a canceled installer.
- Positive expenses/negative inflows are now confirmed. USD matches the reference;
  dot-decimal entry remains a prototype convention. Explicit treatment/posting,
  approval/discussion, separate assistant context, tags, and Exceptional Event are
  implemented in source. Category selection currently uses an invented catalog;
  full taxonomy/subcategories, splits, original bank provenance, reimbursements, bank
  arbitrary bank adapters and real-data migration remain future work. Narrow
  source-ID weekly intake, backup archives, and AI classification/guidance import
  are now implemented in source, pending Mac/iPad checks.
- Schema v2 adds a validated domain payload alongside frozen v1 fields. A staged
  migration preserves old native review flags as history and marks missing
  treatment/posting/classification unresolved. Do not infer approval from those
  flags or weaken the amount-convention marker guard. The actual website's known
  approvals require a separate deliberate migration, not this prototype mapping.
- Review requests are distinct from draft edits. Preserve per-record action IDs,
  expected revisions, explicit intent, and idempotency. Skip creates no decision.
  Local discussion requests do not imply ChatGPT was contacted or processed them.
- Source labels are local aliases with UUIDs, not bank account numbers or a bank
  import identity system. Category/tag provenance is retained through approval;
  manual classification changes update only the affected origins. Older unknown
  origins retain unknown metadata but use orange needs-review pills. Session markers register successful distinct writes,
  survive backgrounding/reload, and clear on a new app process. Discussion progress
  is explicitly user-marked; never infer it from export or foreground changes.
- Opt-in table examples use a separate stable UUID namespace and append only
  missing rows atomically. Never rewrite existing records, including examples
  the user edited. Existing older samples remain preserved and may need Custom
  dates because the approved table defaults to one month.
