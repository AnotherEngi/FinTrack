# Clipboard, summary refinement and private history trial

2026-10-25. The user reports the previous Mac tests and an actual iCloud
backup/download/restore passed. That report predates this batch. No real
financial records, Sheet, collector connection or credentials were accessed here.

## Current changes

- Overview has four separate cards: bar chart, pie chart, category switches,
  and contextual purchases. The bottom cards scroll independently.
- Timeline domains include empty calendar periods. Empty means no recorded
  purchases in this view, not verified zero bank spending. Rolling date presets
  retain their existing inclusive bounds: six rolling months can touch seven
  calendar months when both end months are partial. The date window is not
  silently shortened to match a bar count. Weeks use the first Monday date,
  then `wk 2`, `wk 3`, etc.; full dates remain in selection menus/context.
- Visibility lists only hidden categories/tags/transactions. Add Category/Add
  Tag opens a complete searchable picker. Individual hiding is in the transaction
  editor, saved independently of financial edits. A category/tag rule can still
  hide a transaction after its individual flag is removed; the editor explains it.
- Preparing either review copies the complete JSON plus instructions to the
  local iPad clipboard by default. It expires after one hour. Larger packets
  remain available as complete shareable JSON files; they are never truncated.
  Paste in Import reply accepts actual JSON message text (optionally one JSON
  code fence), not attachment names/URLs. It preserves all existing validation,
  proposal review, revision and replay rules. Copying never acknowledges feedback.
- Clipboard limit is an app-selected 256 KiB, not a claim about ChatGPT's context
  capacity. File exchange remains bounded at 50 MiB. The app uses Apple's
  [PasteButton](https://developer.apple.com/documentation/swiftui/pastebutton)
  and [pasteboard options](https://developer.apple.com/documentation/uikit/uipasteboard/optionskey)
  for explicit paste and expiring device-local copy. No background clipboard read,
  native ChatGPT API bridge, separately billed API, cloud record sync or new tool
  installation is involved.

## Initial history migration

Use [the Markdown handoff](chatgpt-history-migration.md) in the finance ChatGPT
conversation with the actual Sheet/export access. It asks for a full source audit,
then the dedicated `fintrack-history-import` JSON. The published synthetic example
is checked against the actual decoder in the portable suite.

The importer verifies source row accounting, unique IDs/locators, declared column
handling, exact net control total, known categories, explicit prior approval
evidence, preserved-detail keys, source mappings and the refund graph. Unknown
JSON fields fail instead of being silently ignored. Missing genuine bank IDs are
flagged, not synthesized. It cannot prove that ChatGPT examined every source cell;
compare the audit with the original before confirming.

The preview requires acknowledgement of source counts/totals and limitations.
It creates/verifies an isolated store using the existing recovery path and retains
the previous ledger. Replaying the same history import preserves later app edits;
a different second history migration is refused in an established history ledger.
Weekly additions are a separate intake flow. Cancel/validation failure does not
change the current ledger.

Actual category IDs/labels are persisted with the workspace, loaded on reopen,
and used by editing/review, weekly intake, and archive validation. Approved rows
need explicit source approval evidence; no new historical action timestamps are
fabricated. Closed assistant questions/reasons follow the existing retention rule.
Accepted source guidance can migrate through the optional knowledge array.

Preserved unsupported details (including subcategory/split/reimbursement fields)
are read-only in the editor and included for corresponding review records through
`historyContext`. They are not new booked transactions or implemented accounting
features. The audit flags their effect; do not assume category-split or received
reimbursement calculations are live. Global unsupported settings/inaccessible
learnings must be flagged for follow-up by the exporter. Archive encryption is
unchanged: user-managed private storage is required; `.fintrack` is not app-encrypted.

## Combined Mac and iPad session

After reviewing/committing/pushing on Windows, from the Mac checkout root:

```sh
git pull --ff-only origin main
swift test --package-path Packages/FinTrackCore
swift test --package-path Packages/FinTrackPersistence
xcodebuild -project Apps/FinTrack/FinTrack.xcodeproj -scheme FinTrack -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
open Apps/FinTrack/FinTrack.xcodeproj
```

Install with the existing app identity through Xcode (select the iPad, Command-R).
Do not uninstall the app or discard local signing changes to update it.

1. Check the four cards, empty-month spacing and short weekly labels in landscape
   with trackpad. Verify category/tag pickers and hiding in the editor. Visibility
   must leave transactions/export/history intact and survive relaunch/backup.
2. Obtain the complete private migration JSON using the Markdown handoff. In
   Import reply use Paste or Import File. Check source counts, net control total,
   missing bank IDs, exclusions, preserved unsupported fields and all warnings.
   Compare with the original Sheet. If a key detail is omitted, correct the
   export/mapping before confirming the initial import.
3. Confirm migration into a separate ledger. Check actual categories, user notes,
   prior approval evidence, pending rows, positive/negative amounts and refund
   links. The imported net control total includes excluded treatments; Overview
   spending intentionally excludes them and uses linked purchase-date refunds.
   Reopen and verify persistence; test restoring a newly confirmed cloud backup.
4. Prepare routine or full-history review; paste into ChatGPT. Copy the returned
   JSON message and use Paste in Import reply. Read answers separately from
   Apply changes/Keep current. A later manual edit must prevent a stale overwrite.
5. Ask ChatGPT for a small real weekly batch using the handoff's weekly schema,
   actual stable source aliases and genuine provider IDs. Preview and accept new
   rows. Reconcile plausible duplicates/changed source facts explicitly. Paste
   that identical file again; records/notes must not duplicate or regress.

## Verification record

All **119 portable tests passed** on Windows Swift 6.4.1. This includes eleven
new cases covering timeline gaps, compact week labels, clipboard boundaries and
replay, history audit/approval/source-ID checks, preserved details, actual taxonomy,
guidance, archive round trips, and the exact Markdown JSON examples above.
All **19** Apple app/persistence source/test files passed syntax parsing only.
Four new native cases cover taxonomy reopen/weekly intake, save-failure rollback,
isolated history activation, and legacy restore after an imported taxonomy.
Those require the Mac; Windows has not typechecked SwiftUI/Charts/SwiftData or
exercised the new clipboard UI, file pickers, restore, or cloud behavior.

Hardening reviewed duplicate intake, replay after manual edits, explicit source
approval evidence, unknown/unmapped JSON fields, exact control totals, backup
framing of every new workspace field, and restoration of the appropriate catalog.
Recovery now also compares restored migration audit/catalog/details before
activation. Clipboard failure retains the complete file and does not acknowledge
pending operations. No source/signing/capability changes were needed in the Xcode
project. No commit or push was performed by the agent for this batch.
