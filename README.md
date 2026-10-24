# FinTrack

Native SwiftUI iPad household finance app for one user. This is a
**synthetic-data prototype** with a user-reported successful physical-iPad build
and refund edit/reopen check. No cloud sync or
LLM API requests are implemented.

## Layout

- `Apps/FinTrack/FinTrack.xcodeproj`: iPad app and shared FinTrack scheme.
- `Packages/FinTrackCore`: portable Swift 6 finance models, exact USD amounts,
  calendar dates, stable IDs/revisions, synthetic examples, and rule tests.
- `Packages/FinTrackPersistence`: Apple-only local SwiftData adapter and storage
  tests, with CloudKit explicitly disabled.
- `scripts`: optional Windows toolchain setup and portable test runner.
- `docs`: [requirements](docs/requirements.md), [model decisions](docs/data-model.md),
  [review workflow](docs/review-workflow.md), [export and display tabs](docs/chatgpt-export.md),
  [approved table design](docs/design/transactions.md), [combined iPad test](docs/ipad-acceptance.md),
  [website handoff review](docs/website-handoff-review.md), and
  [build/verification instructions](docs/development.md).

## First prototype

The source provides transaction browsing/search, date ranges, add/edit, explicit
posting and accounting treatment, category selection, tags, Exceptional Event,
and Approve/Discuss/Skip/Reopen actions with per-record history. User notes and
answers are separate from read-only assistant questions/reasons and ledger notes.
An opt-in action appends twelve current-date table examples without replacing
existing edits. Earlier stores may still contain the original 24 eight-week
examples. Valid editor changes explicitly save as input changes;
incomplete input and failed saves retain a separate recoverable draft. The active
ledger stays in the iPad app's Application Support directory, eligible for device
backup. Device/cloud backup has not been verified or enabled by the app.

Five native tabs now provide Overview, Transactions, Questions, Review history,
and ChatGPT export. Transactions implements the approved sortable table, source
labels, classification/tag origins, icon actions, search/date presets,
Amalgamate, and session/discussion indicators. Overview includes category/month drilldowns and display-only
tag/event exclusions. To export, open **ChatGPT export** (or the export icon in
Transactions), select records/context, choose **Prepare Export**, then **Save or
Share All 3 Files**. See the [export guide and combined device checklist](docs/chatgpt-export.md).
These new SwiftUI screens still require a Mac build and physical-iPad validation.

Amounts now follow the confirmed positive-outflow convention: expenses are
positive, refunds and income negative. The prototype supports USD and dot-decimal
input. Category selection uses an invented catalog; full category/subcategory
management, splits, reimbursements, bank imports, backup archive export/restore,
and ChatGPT suggestion import are **not implemented yet**. Do not use real records until save/recovery,
migrations, and backup/restore have been tested on Apple devices.

The earlier website's approval/discussion, note-ownership, and treatment rules now
have portable implementations and tests. Original bank source identity, full allocation rules,
and reimbursement accounting still need implementation. Manual file exchange
with ChatGPT is implemented as JSON/CSV/prompt export; returned suggestions must
currently be reviewed and entered manually.
Historical source stays outside the repo; no live ledger has been migrated.
Older unmarked prototype stores/drafts are preserved and blocked from opening
until an explicit sign-convention migration is available. New stores include a
convention marker; existing amounts are never flipped automatically.
An authored schema v1-to-v2 migration retains old native review flags as history
without guessing posting/treatment/category or inferring approval. The user reports
the Mac persistence suite passed. See [review-workflow.md](docs/review-workflow.md).

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

FinTrackCore compiled on Windows using Swift 6.4.1 and **all 50 tests passed**
on 2026-10-24. The user reports a successful app build and an edited synthetic
refund amount persisting after closing/reopening on the physical iPad. The user
also reports both FinTrackCore and FinTrackPersistence tests passed on Mac.
The four focused iPad checks provisionally passed based on the user's report;
those reports predate the new table/tabs/export. Ten native app/persistence files
passed syntax parsing on Windows; Apple SDK typechecking, the twelve-test
persistence suite, sharing, and screen checks remain for this batch on Mac/iPad.
Use the [combined checklist](docs/ipad-acceptance.md). Backup/restore remains outstanding.
See [device-verification.md](docs/device-verification.md) for evidence and next checks.

Keep all real financial files and credentials outside this repository. No source
changes have been committed or pushed by the agent.
