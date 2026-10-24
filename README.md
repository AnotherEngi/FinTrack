# FinTrack

Native SwiftUI iPad household finance app for one user. This is the first
**synthetic-data prototype**, not yet a verified iPad build. No cloud sync or
LLM API requests are implemented.

## Layout

- `Apps/FinTrack/FinTrack.xcodeproj`: iPad app and shared FinTrack scheme.
- `Packages/FinTrackCore`: portable Swift 6 finance models, exact USD amounts,
  calendar dates, stable IDs/revisions, synthetic examples, and rule tests.
- `Packages/FinTrackPersistence`: Apple-only local SwiftData adapter and storage
  tests, with CloudKit explicitly disabled.
- `scripts`: optional Windows toolchain setup and portable test runner.
- `docs`: [requirements](docs/requirements.md), [model decisions](docs/data-model.md),
  [review workflow](docs/review-workflow.md), [website handoff review](docs/website-handoff-review.md), and
  [build/verification instructions](docs/development.md).

## First prototype

The source provides transaction browsing/search, date ranges, add/edit, explicit
posting and accounting treatment, category selection, tags, Exceptional Event,
and Approve/Discuss/Skip/Reopen actions with per-record history. User notes and
answers are separate from read-only assistant questions/reasons and ledger notes.
A visible button loads 24 invented records spanning eight
weeks into an empty store. Valid editor changes explicitly save as input changes;
incomplete input and failed saves retain a separate recoverable draft. The active
ledger stays in the iPad app's Application Support directory, eligible for device
backup. Device/cloud backup has not been verified or enabled by the app.

Amounts now follow the confirmed positive-outflow convention: expenses are
positive, refunds and income negative. The prototype supports USD and dot-decimal
input. Category selection uses an invented catalog; full category/subcategory
management, splits, reimbursements, bank imports, backup archive export/restore, and ChatGPT
exchange are **not implemented yet**. Do not use real records until save/recovery,
migrations, and backup/restore have been tested on Apple devices.

The earlier website's approval/discussion, note-ownership, and treatment rules now
have portable implementations and tests. Source identity, full allocation rules,
and reimbursement accounting still need implementation. Manual file exchange
with ChatGPT is explicitly acceptable for the initial version, but is not built.
Historical source stays outside the repo; no live ledger has been migrated.
Older unmarked prototype stores/drafts are preserved and blocked from opening
until an explicit sign-convention migration is available. New stores include a
convention marker; existing amounts are never flipped automatically.
An authored schema v1-to-v2 migration retains old native review flags as history
without guessing posting/treatment/category or inferring approval. It still needs
Mac verification. See [review-workflow.md](docs/review-workflow.md).

## Run

On a configured machine:

```sh
swift test --package-path Packages/FinTrackCore
```

On Mac:

```sh
swift test --package-path Packages/FinTrackPersistence
open Apps/FinTrack/FinTrack.xcodeproj
```

Choose the FinTrack scheme and an iPad simulator. For a physical iPad, select your
personal signing team and replace `com.example.FinTrack` with a unique bundle ID.
No iCloud/CloudKit capability is needed for this prototype. Follow the complete
[development instructions](docs/development.md) before testing.

## Current verification

FinTrackCore compiled on Windows using Swift 6.4.1 and **all 22 tests passed**
on 2026-10-24. The Apple persistence tests and native app build have **not run**.
The Mac update and first build remain pending. Full verification details are in
`docs/development.md`.

Keep all real financial files and credentials outside this repository. No source
changes have been committed or pushed by the agent.
