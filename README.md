# FinTrack

Native SwiftUI iPad household finance app for one user. Use **synthetic data only**
until the current Mac/iPad migration, exchange, and backup checks pass. The earlier
app runs on the physical iPad; the current exchange/backup batch is not device-verified.
No cloud record sync, bank login, LLM API request, or subscription sign-in is added.

## Layout

- `Apps/FinTrack/FinTrack.xcodeproj`: iPad app and shared scheme.
- `Packages/FinTrackCore`: portable finance rules, review/weekly/backup contracts,
  classification guidance, exact money, and synthetic tests.
- `Packages/FinTrackPersistence`: local SwiftData adapter; CloudKit explicitly off.
- `scripts`: Windows Swift setup and portable test runner.
- `docs`: [requirements](docs/requirements.md), [data flows](docs/data-flow-proposal.md),
  [review and backup guide](docs/chatgpt-export.md), [combined iPad test](docs/ipad-acceptance.md),
  [design](docs/design/transactions.md), and [development](docs/development.md).

## Current source

Transactions provides sorting, search/date ranges, source aliases, category/tag
status pills, Amalgamate, detailed editing, notes, tags, and explicit review actions.
Valid edits persist locally; invalid input is retained as a recoverable draft.
Optional fictional samples never replace existing edits. Overview, Questions, and
Review history remain available. Merchant text is always plain.

**Review & backup** replaces the old selected-record exporter:

- Review with ChatGPT automatically prepares one JSON file with pending additions,
  edits, decisions, open questions, relevant context, and classification guidance.
- Full History Review includes all accepted records. No date/search filter hides work.
- Import ChatGPT results, explicitly record receipts, and accept/reject individual
  classification or guidance proposals. Stale proposals cannot replace newer edits.
- Import structured weekly batches with genuine source IDs, add new rows atomically,
  and explicitly reconcile source changes or ambiguous purchases.
- Enable automatic backup by selecting a dedicated **iCloud Drive** folder once.
  Complete logical snapshots upload there; metadata confirmation is separate from
  local saves. Pending uploads survive restart. Keep the previous good backup until
  the new one uploads; automatic older-version history is not required.
- Full backup export/restore is supplementary. Restore validates and confirms the
  replacement and preserves a local pre-restore recovery copy.

The live database stays in Application Support. Schema V3 adds the durable
workspace without changing V2 transaction fields. Existing draft files migrate
into the transactional workspace and remain preserved as migration evidence.
Backups include ledger, drafts, feedback, incoming/results journals, source links,
and guidance; permission bookmarks stay local. iOS execution/network/storage
limits can delay backup. No claim of fixed background timing or immediate offline
cloud protection is made. See the guide for current limits and test steps.

Amounts use positive outflows and negative refunds/income, exact USD minor units,
and dot-decimal entry. Full taxonomy management, splits, reimbursements, arbitrary
bank-export adapters, and real-history migration remain future work. Existing
private bank connections have not been accessed or verified. ChatGPT receives
only files you attach; its separate weekly task does not automatically see them.

## Run on Mac

After transferring source through your normal Git workflow:

```sh
swift test --package-path Packages/FinTrackCore
swift test --package-path Packages/FinTrackPersistence
open Apps/FinTrack/FinTrack.xcodeproj
```

Keep the existing personal signing team and bundle ID. Build/run on the physical
iPad; do not uninstall or delete its store to resolve a migration failure. No
CloudKit capability is required for the user-selected iCloud Drive folder.

Windows can run `scripts/Test-Core.ps1` with the installed Swift/VS tools. Windows
verification for this batch: all **64** portable tests pass; all 12 Apple source/
test files pass syntax parsing.
Windows
cannot typecheck SwiftUI/SwiftData or verify iCloud behavior. The Apple persistence
suite has 21 tests, including nine new exchange/migration/recovery cases, awaiting
this batch's Mac run. See [verification](docs/device-verification.md).

Keep financial records and credentials out of this public repository. The agent
has not committed or pushed these changes.
