# FinTrack project guidance

## Context and current state

FinTrack is a native Swift/SwiftUI household finance app for one user on one iPad.
Windows/VS Code/Codex is the main workspace. The work Mac provides Xcode,
SwiftData/SwiftUI compilation, signing and installation. The physical iPad is the
main usage/test device (MHQU3LL/A; reported OS 27.0). Previously reported Mac
versions were macOS 26.5.2, Xcode 26.6, Swift 6.3.3; updated versions are unconfirmed.
The user will update before Mac work. Do not assume SDK/device compatibility
without checking actual installed versions when that becomes relevant.

An earlier website/Google Sheet workflow suffered reconnects/conflicts. FinTrack
owns the accepted financial records; ChatGPT provides analysis and suggestions.
The user has ChatGPT Plus and reports a weekly collector connected to their card
companies. This coding session has not inspected that connection, private source
files, conversations, memories or financial records. Manual file exchange was
accepted initially; explicit clipboard copy/paste is now the preferred transport.
No separately billed LLM API or automatic paid fallback is authorized.

The current source implements the financial framework described in
[current contracts](docs/contracts/financial-framework.md) and
[framework decisions](docs/import-framework-decisions.md). It replaces retired
development formats with one current domain model, one SwiftData schema, current
drafts, and one contract per purpose. Format version 2 does not imply a v1 reader.
The user authorized enabling the normal history/refund import actions on
2026-10-26 so physical-iPad synthetic import validation can be completed. The
unconditional application gate has been removed; preview, audit acknowledgement,
explicit confirmation, validation, isolated history restore, atomic writes,
revision checks and replay protection remain. This is the normal product flow,
without a fixture allowlist or test mode. Keep actual real-data intake until
device/backup checks and private source reconciliation pass; that is the rollout
sequence, not a software gate that prevents its own prerequisite tests. Do not
reinstate that circular dependency.
See [framework validation](docs/framework-validation.md) for exact current evidence
and remaining checks, and [retention](docs/data-retention.md) for the data inventory.

The user reports earlier native suites and an iCloud backup/download/restore
passed. Those results predate this framework rewrite. Record user reports
separately from checks actually run by the agent.
Latest agent-run verification: **137 portable tests passed** on Windows Swift
6.4.1, **19 native source/test files parsed**, and `git diff --check` passed.
The **47 native test declarations** and app/device/iCloud runtime checks remain
unrun here because Apple frameworks/Xcode are unavailable. No commit/push performed.
2026-10-26 follow-up supersedes those counts/status: the user supplied Mac output
with **137 core tests passing** and the native persistence package building, then
**47 persistence tests completing with three assertion issues in two tests**.
Corrected the stale pre-import rollback baseline and discussion approval
expectations, strengthened saved-state/reopen checks, and removed the unused
mutable restore local. No financial behavior/schema/contract changed. **139 core
tests now pass on Windows**, **19 native files parse**, and `git diff --check`
passes. The corrected native tests, app build and device checks still need their
Mac/iPad run; keep real migration gated. No commit/push for this follow-up.

Subsequent 2026-10-26 user report: the corrected Mac tests and app build pass.
The user then explicitly approved removing the import gate before validating the
resulting build. That current decision supersedes historical gate instructions
above/below. The earlier one-off checklist/fixture-only code was undone; do not
recreate it. Give manual test walkthroughs in the conversation when requested.
Recheck the current product change on Mac and iPad; the preceding report does not
validate later edits. No schema, contract, migration reader or signing change is
part of enabling these existing actions.
Validation for this product change: all **139 portable tests passed** on Windows
Swift 6.4.1, **19 native files parsed**, and `git diff --check` passed. Mac/native
UI validation of this update remains pending. No commit or push performed.

## Required behavior and financial decisions

- Browse and edit history offline; valid transaction edits save immediately.
  Retain invalid/incomplete drafts; display save failures and rollback partial work.
- Categories/subcategories/definitions, exact balanced expense allocations, tags,
  notes/answers, current review, historical decisions and source lifecycle are
  distinct structured data. Never simulate a split with duplicate purchases or
  introduce a Mixed category. Unsplit purchases use their primary category;
  the user supplies secondary categories/dollar amounts.
- Keep stable app UUIDs distinct from genuine provider/account IDs, aliases and
  audit locators. Do not invent provider IDs from rows/hashes/UUIDs. Replays or
  stale suggestions cannot overwrite newer manual edits. Ambiguous duplicates
  require explicit reconciliation. Preserve complete predecessor observations.
- Exact money and revisions use integer strings in exchange contracts; use no
  binary floating point for monetary calculations. USD is currently supported.
  Expenses are positive; merchant refunds/income/actual reimbursement receipts
  are negative. Sign alone never determines treatment.
- Any unresolved/unknown current question makes the record unapproved. Earlier
  approval evidence and unknown decision times remain separate. Explicit new
  approval closes discussion. Known resolved assistant questions/reasons are
  removed, including known-role archival duplicates; user/factual/mixed/unknown
  text and unsent corrections survive. Do not retain assistant text in immutable
  financial versions/source caches to evade cleanup.
- Expected/source-reported reimbursements are not cash. Only assigned actual
  receipts reduce purchase net cost. Keep gross purchases, spending after merchant
  refunds, receipt-date cash and purchase net cost distinguishable.
- Initial history is one complete **non-refund** import. Merchant refunds are a
  separate complete deferred stage referencing the same stable purchase UUIDs.
  Purchases stay gross until linked refunds arrive. Preserve refund receipt dates
  while reporting adjustments on purchase dates/categories. Never double-subtract
  source-netted amounts. Proportional split-refund amounts are proposals requiring
  explicit confirmation, based on remaining refundable balances and exact cents.
- Reporting: America/New_York, Monday weeks. Six months means current partial
  calendar month plus five prior full months, through report today. Keep source
  report/as-of dates and original timestamps separate; never shift date-only values.
- Keep source baselines, coverage uncertainty, all row/column dispositions and
  separate debit/credit/net/spending controls. Unsupported essential meaning blocks
  migration. The app cannot prove the producer inspected every source cell.
- No workbook attachment/reference/fingerprint/bookmark management. The user keeps
  the original independently. Import-payload replay hashes and audit locators are
  allowed app data and are different from retaining a workbook artifact.

## Backup and integration boundaries

- The live SwiftData database stays local, eligible for OS backup. Automatic latest
  full backup to a user-selected iCloud Drive folder is critical and implemented
  separately from record sync. Folder permissions and cloud progress stay local.
  Local writes do not prove upload; confirm cloud metadata and show failures/retry.
- Current logical archive export/restore includes all recoverable financial and
  working data. Manual exports/imports are supported; automatic historical-version
  retention is not required. Preserve the last confirmed backup until replacement
  is confirmed. Explicitly report any practical limits not measured on the iPad.
- Do not implement CloudKit, cloud record sync, Drive integration or a hosted bridge
  without settling that integration with the user. Do not put the live DB in iCloud.
- Treat AI/imports as untrusted. Reject unknown writable fields, invalid graphs,
  unsafe IDs, unbalanced amounts, wrong currencies and stale revisions before
  authoritative writes. Answers require no acceptance; actual classification or
  guidance edits require user review. Never infer approval from AI confidence.
- Subscription sign-in eligibility does not establish native iPad integration.
  Verify official OpenAI documentation before any new subscription integration.

## Architecture-breaking changes: ask first

Before an architecture-breaking change, **ask the user what existing data,
formats, schemas, models or other objects must be preserved**. Do not decide to
support multiple revisions, adapters, migrations or compatibility readers first.
Explain affected state and preservation/reset options. A recorded answer for the
same change suffices; it is not blanket approval for future changes.

For this pre-release financial-framework rebuild, the user explicitly said old
development structures have no value. Replace them; do not maintain legacy-backup
reading, frozen prototype schemas or migration chains. Incompatible files/stores
fail clearly and remain untouched. Creating a separate empty ledger is an explicit
user recovery action, never an automatic reset. Leaving old files untouched is
not support for their formats.

## Privacy and workspace

- Use invented synthetic fixtures, screenshots and tests only. Keep actual bank
  exports, transactions, personal notes, account identities, credentials, tokens,
  signing identities and keys outside this public checkout. Ignore rules are only
  a fallback. Inspect actual diffs/staged content before recommending publication.
- Public repo: `AnotherEngi/FinTrack`; the user wants anonymous pulls on the work Mac
  with no GitHub write credentials. Public visibility does not authorize private data.
- Preserve unrelated work. Do not install tools/create accounts without permission.
  The user authorized Windows Swift setup earlier; Swift 6.4.1 now works.
- Always set shell cwd to `C:\Users\rproi\source\repos\FinTrack`.
  Git is `C:\Program Files\Git\cmd\git.exe` when absent from PATH. Use rg first.

## Validation and Git operations

- **Run all applicable local tests and checks yourself.** Do not ask the user to
  run checks this environment can execute. `scripts/Test-Core.ps1` loads the
  installed Windows Swift/VS C++ environment; default runs all core tests.
  `-Action build` builds the portable package. Windows can also parse Apple Swift
  syntax; it cannot validate SwiftUI, SwiftData macros, Apple SDKs or iPad builds.
- Run native persistence tests, Xcode build, signing and UI/device/iCloud checks on
  Mac/iPad. State what ran, what could not, and why. Provide Mac commands without
  waiting for the user to ask. Old successful runs do not validate new source.
- Shell/local Git operations are allowed within the task; do not commit unless
  requested. **Git operations writing to a remote are human-run**, including push
  and remote branch/tag deletion, unless the user grants a new explicit exception.
- Whenever publication is the next step, **automatically provide exact review,
  add/commit/push commands** for the work, even if the user did not ask again.
  Do not run remote-writing commands under standing authorization from an older batch.

## Approved UI

Preserve the table design in [transactions](docs/design/transactions.md), the
four-card [Overview](docs/design/overview.md), and clipboard-first separate Send,
Import and Backup screens. Avoid wasting screen space with branding, repeated tab
headings, known-currency labels, saved/approved counts or a permanent color legend.
Only categories/tags have review pills: orange suggested/unknown, blue user,
green approved. Merchant text is always plain. Activity/question columns are thin;
equal-width icon actions and Amalgamate switch remain. Support keyboard/trackpad
and touch; hover must not trigger modal chart selections. Visibility lists only
hidden rules/records, with add pickers; individual visibility is in the editor.
