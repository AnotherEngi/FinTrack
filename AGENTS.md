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
approved/non-approved split, merchant/tag status pills, detailed editor, and
independent session/discussion indicators. The HTML preview remains design-only;
the native table, local source aliases, per-field provenance, process-session
markers, and explicitly user-tracked discussion progress are now implemented in
source. Full bank provenance/import and automatic processing receipts remain future work.
Use the approved preview defaults as the implementation baseline: merchant/tag
status pills, comfortable rows, and a detailed edit sheet. Earlier preview
alternatives are exploratory, not the approved layout. This approval records the
design decision. The native implementation still requires Mac/iPad validation;
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
- Keep authoritative app data eligible for iCloud device backup and plan a
  separate app-level backup/restore archive exportable to iCloud Drive.
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

- The user approved proceeding with the local-first prototype. It now uses
  local-only SwiftData. The user reports both Mac package test suites passed;
  the four focused iPad checks provisionally passed based on the user's report.
  Backup/restore validation remains before real-data use.
  Cloud backup requirements remain; backup archive export/restore
  is not implemented. Manual ChatGPT export is implemented; suggestion import
  and direct subscription sign-in remain future work. See docs/chatgpt-export.md.
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
- The latest batch implements the approved native Transactions table alongside
  Overview, Questions, Review history, and ChatGPT export. SwiftData schema v2 is
  unchanged; its domain payload gains backward-compatible optional source,
  classification-provenance, and discussion-progress fields. Old fields default
  to unknown source/origin and awaiting-export for an existing discussion request.
  All 50 core tests pass on Windows. All ten native app/persistence source/test
  files passed syntax parsing only; 12 Apple persistence tests await this batch's
  Mac run. Earlier user-reported Mac/iPad passes predate this batch.
  Follow docs/ipad-acceptance.md for one combined Mac/iPad/ChatGPT session.
  Exports include only selected committed records; notes and assistant context
  require explicit opt-in. Keep Int64 amounts/revisions as strings in the exchange
  contract. Exporting or receiving analysis cannot approve or edit records.
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
  imports, backup archives, and AI suggestion import remain future work.
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
  origins remain neutral. Session markers register successful distinct writes,
  survive backgrounding/reload, and clear on a new app process. Discussion progress
  is explicitly user-marked; never infer it from export or foreground changes.
- Opt-in table examples use a separate stable UUID namespace and append only
  missing rows atomically. Never rewrite existing records, including examples
  the user edited. Existing older samples remain preserved and may need Custom
  dates because the approved table defaults to one month.
