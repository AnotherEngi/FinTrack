# Transaction table and ChatGPT handoff: one iPad session

Source batch prepared 2026-10-24. Use only synthetic records. The approved table
is implemented in SwiftUI source; it has not yet been built or tested on Mac/iPad.

Windows validation: all **50 FinTrackCore tests passed**, and all ten app/
persistence source/test files passed syntax parsing. Windows cannot typecheck
SwiftUI/SwiftData. The persistence suite now has twelve tests; the four new ones
cover the current payload fields and opt-in example append. Their Mac results
are pending. Earlier user-reported Mac/device passes cover the earlier app.

## Transfer and build once

Transfer this source batch through the usual commit/push workflow first. These
changes have not been committed or pushed by the agent. Then, on the Mac, from
its FinTrack checkout:

```sh
git pull --ff-only
swift test --package-path Packages/FinTrackCore
swift test --package-path Packages/FinTrackPersistence
open Apps/FinTrack/FinTrack.xcodeproj
```

Run both suites for this batch because the domain payload and persistence
behavior changed. Build/run the FinTrack scheme on the physical iPad using the
existing personal signing settings. Keep its installed store; do not uninstall,
delete a store, or alter the amount-sign marker to make a failed open succeed.
If a command/build fails, retain the error output so it can be diagnosed.

## Prepare the synthetic records

1. Confirm the earlier modified grocery-refund value still exists. Older August/
   September examples may be outside the default one-month range: choose Custom
   and those dates to view them. Unknown source/origin on these earlier records
   is expected; they must not be labeled as AI or manual by guessing.
2. Use **Add Synthetic Table Examples** in the toolbar's secondary actions (or
   the button on an empty/mismatched view). This explicitly appends twelve
   current-date examples with stable IDs, invented sources, mixed classification
   origins, pending/approved rows, tags, and discussion states. It preserves
   existing records and skips any of these examples already present.
3. Return to **1 month**. Eight of the new examples are in that range. Load the
   examples again: there should be no duplicates and no overwritten edits.

These source labels and AI origins are fictional demonstration values. The app
has no bank connection, model call, ChatGPT login, or automatic processing service.

## Table, editing, and persistence

- Check portrait and landscape, and light/dark appearance. There is no branding
  bar, repeated Transactions heading, standing legend, record/approval count, or
  USD label in the workspace. Status is the thin leading column. The three row
  actions have equal 44-point targets. Scroll horizontally when space is narrow.
- Sort each column both ways. Search a merchant, source label, category, and tag.
  Search should combine with date filtering and work across both groups.
- Try 1/3/6-month, YTD, past-year, and Custom. Custom includes both endpoint dates
  and rejects a reversed range. Older examples explain why broader ranges contain
  additional records; missing history is not a complete-source claim.
- Toggle **Amalgamate**: on combines rows; off puts non-approved rows above
  approved rows. Search, dates, and sort should remain in effect.
- Approve an orange fictional purchase. Its merchant and tags become green and
  it moves below. Reopen returns it to the upper group with its retained origins.
  Edit a category: the merchant pill becomes blue. An unchanged older tag retains
  its own origin, while a newly added tag is blue. Reapprove: all are green.
- On an approved purchase, change only the note/answer: approval remains. Change
  amount, category, tags, source, or another classification/financial field:
  approval reopens. A pending charge and a payment outside spending review cannot
  be approved. An unsaved draft blocks a table review action.
- A successful edit/action adds the session pencil. Simply opening a record or
  making an identical edit does not. Backgrounding or returning from Files keeps
  it; fully terminating/relaunching clears session markers. Saved records,
  provenance, approvals, and discussion state remain on disk.
- Leave an unfinished amount such as `12.`; close/terminate/reopen and resume it
  from the unsaved-drafts toolbar menu. The exact unfinished input survives while
  the ledger retains its last valid value. Use invented notes only.
- Repeat a new manual transaction save and table/export browsing offline. Source
  labels are local aliases; do not enter account numbers or credentials.
- Visit Overview, Questions, and Review history in the same session. Category/
  month drilldowns should open the corresponding records; overlapping tag/event
  exclusions should hide a record only once. An answered question disappears
  unless discussion remains requested, and saved review actions appear in history.

## ChatGPT handoff on the physical iPad

1. On a synthetic row, tap the conversation icon. Add your own note or answer
   and choose Discuss in the detail sheet. It stays separate from assistant text,
   preserves approval, and gets a waiting-discussion marker. It is not sent yet.
2. Search/date-filter to a few rows including that discussion. Tap the export
   icon above the table. Confirm it starts with just those shown record IDs; you
   can deselect individual rows.
3. First leave context switches off and prepare an export. Inspect JSON: notes,
   answers, and assistant context should be omitted, while local source aliases,
   classification origins, saved review state, and exact string revisions remain.
   Close and prepare again with your notes/answers included; optionally include
   the synthetic assistant context too.
4. Use **Save or Share All 3 Files → Save to Files**, choosing a folder in iCloud
   Drive if available. Open the saved JSON, CSV, and prompt text in Files. Also
   try an individual-file share. Close the export preview: your saved copies must
   still open. A local save/export is not proof the cloud upload finished.
5. In the ChatGPT conversation you choose, attach the JSON and prompt text files.
   CSV is an optional readable companion. Ask ChatGPT to follow the prompt. It
   should cite the selected transaction IDs/base revisions, keep pending spending
   separate, and ask for missing context instead of claiming full account coverage.
6. While reviewing it in ChatGPT, you may explicitly choose **Mark Reviewing in
   ChatGPT** in the transaction's detail sheet. This persists your own workflow
   status and changes the activity symbol. Exporting or app switching alone must
   not mark it in progress. This is not a server receipt or live processing signal.
7. Give ChatGPT invented feedback in the conversation. Ask it to incorporate the
   feedback into its recommendations while keeping your words separate from
   assistant reasoning. Review a proposed classification/tag change and enter it
   manually in FinTrack. It should show blue and remain unapproved until you
   explicitly approve it. Relaunch and confirm the chosen edit and source remain.
8. Export the chosen rows again: the updated revision, values, and discussion
   state should be visible. FinTrack does not import a returned suggestion file
   yet; no chat response can silently apply a change or approve a record.

Manual file attachments were rechecked against
[official ChatGPT documentation](https://learn.chatgpt.com/docs/use-chatgpt) on
2026-10-24. This uses the user's existing session and its upload/usage limits;
FinTrack introduces no separately billed model API request.

Report any build/test failure first, then any table or handoff step that differed
from the expected behavior. Record completed results in
[device-verification.md](device-verification.md). Backup/restore remains required
before using real financial records.
