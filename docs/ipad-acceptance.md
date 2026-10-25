# Combined Mac/iPad acceptance: review, intake, and iCloud backup

## Latest UI follow-up (supersedes earlier control names below)

Follow [current review/discussion flow](review-flow.md). Current source adds:

1. Check that older non-approved category/tag values are now orange, user edits
   blue, approved values green, and merchants plain. Existing saved values and
   unknown provenance must remain unchanged. Check the thin question column,
   sorting, and direct discussion navigation alongside session activity.
2. Transactions has distinct up-arrow sending and down-arrow import controls.
   Review & backup separates Send to ChatGPT, Import reply, and Backup pages.
3. Prepare Full History Review: its section must name that mode and both top
   choices gray out. Start Another Review enables them; then prepare pending
   feedback and verify the new mode label/file. Never silently swap a shared file.
4. Import a response with answers plus one real category/tag change. Answers show
   as discussion replies with no accept/reject. Only actual changes show Apply
   changes/Keep current with before/after values. Matching acknowledgements record
   on import; newer edits remain pending. Older response files still open.
5. Open Discussions. Distinguish who asked and who needs to respond. Write a reply,
   force-quit/relaunch to recover its draft, Save Reply for ChatGPT, and verify it
   joins the next prepared packet. Read an imported answer, Mark Resolved, and
   confirm approval is unchanged. A fresh question reopens it; unrelated new
   classification proposals do not. Also open the discussion from the editor.
6. Export Full Backup on the Backup page **without** choosing an automatic backup
   folder: a Files save dialog must appear immediately. Cancel must leave state
   intact. Save and restore one archive with discussion messages/drafts/closures.
7. Overview shows category bars, monthly spending, and year comparisons. Use Add
   Synthetic Chart Examples in its secondary toolbar actions for prior/current
   years; repeat without duplicating or overwriting edits. Check dates, exclusions,
   drilldowns, negative refunds, and gaps rather than zero-filled missing months.

Automatic iCloud upload/restore checks below still apply unchanged. Current Apple
suite has 27 tests; its discussion/draft/receipt/example and final hardening cases plus the new
SwiftUI/Charts/Files save controls need Mac/iPad validation. Keep the same bundle ID.

Source batch: 2026-10-24. **Synthetic data only.** This replaces the old three-file
export checklist; those export controls have been superseded, not device-tested.
Keep the installed app/store and its existing bundle ID. An earlier native build
and local edit/reopen pass do not validate schema V3, file exchange, or cloud upload.

## Build once on Mac

After transferring the source using the normal Git workflow, from the checkout:

```sh
git pull --ff-only
swift test --package-path Packages/FinTrackCore
swift test --package-path Packages/FinTrackPersistence
plutil -lint Apps/FinTrack/FinTrack.xcodeproj/project.pbxproj
open Apps/FinTrack/FinTrack.xcodeproj
```

Keep personal signing changes, the existing team, and installed bundle ID. Run
FinTrack on the physical iPad. If migration/build fails, preserve the files and
error output; do not delete the store, uninstall, or bypass the amount marker.
The Apple suite now has 21 tests including V2-to-V3 migration, atomic feedback,
receipts, duplicate source intake, knowledge conflicts, and restore rollback.

## Existing data, table, and drafts

- Confirm the previously edited sample refund persists. Use Custom dates for
  older August/September records. Existing unknown origins retain their metadata and now show orange needs-review pills.
- Check corrected category/tag pills (orange assistant, blue user, green approved),
  plain merchants, full-width row backgrounds, and the amount/merchant gutter.
  Sort/search/date presets and Amalgamate must still work in both orientations.
- Optionally append the current-date synthetic table examples twice. No duplicate
  records or overwritten edits should appear. Do not reset existing examples.
- Edit a valid amount/note/category, relaunch offline, and confirm exact persistence.
  Notes preserve approval; financial/classification changes reopen it. Pending
  charges cannot be approved. User and assistant text remain separately owned.
- Leave invalid input such as `12.`; force-quit/relaunch and resume the exact draft.
  Existing draft files migrate into the workspace and remain preserved as evidence.
- Verify Overview, Questions, and Review history still open and show correct records.

## One-file review and a real ChatGPT handoff

1. Add a fictional transaction, edit another, and mark a question for discussion.
2. Filter the table so some edited/question records are hidden. Open **Review with
   ChatGPT** / **Review & backup**, then tap **Review with ChatGPT**. Pending work
   and open questions must still be included. No date/record/context selection.
3. Preview and **Share Prepared Review**. Attach this ONE JSON in your chosen ChatGPT
   finance conversation. It contains instructions, context, and a return template.
4. Before importing its response, edit one exported record again. Keep another
   exported record unchanged. Ask ChatGPT to return classification suggestions
   for both and a scoped guidance suggestion using its embedded contract.
5. Save the returned JSON; **Import ChatGPT Reply or Weekly File**. Importing alone must
   change neither ledger nor approvals. Open the staged result and its summary.
6. On import, only included/acknowledged operation IDs clear;
   your later edit stays pending. Open discussions remain available for follow-up.
7. Apply the unchanged record's category/tag suggestion: its classification changes,
   assistant provenance remains, and any financial/classification change reopens
   approval. Your notes, answers, amount, and source facts remain intact. Reject
   another suggestion. The stale record's Apply changes action is disabled/rejected.
8. Import the same response again and repeat its receipt/decision. No duplicate
   events, altered record, or repeated application should result.
9. Accept a guidance suggestion. Edit guidance manually, then try an older remaining
   rule proposal: it must be stale. A new review contains the updated guidance.
10. Tap **Full History Review** while using a narrow table filter. Its snapshot
    must contain all accepted records, not only pending/visible rows. No truncation
    is claimed if file limits are reached. ChatGPT reports any analysis limitations.

The first packet may include an explicit existing-record baseline. Shared is not
processed; processed is not approved. Raw unfinished drafts are excluded from
review files but included in full backups. The separate weekly ChatGPT task has
not been configured by this app and does not automatically see this conversation.

## Weekly intake / duplicate and source-update checks

Copy `fixtures/exchange/weekly-synthetic.json` to a private test location available
on iPad. Import it through **Import ChatGPT Reply or Weekly File**.

- Check coverage and two fictional records. **Add All New Transactions** adds
  both atomically; importing/accepting again adds none. Pending remains pending.
- Edit an imported record's notes/tags. Reimporting must preserve those edits.
- For source-update testing, make a private synthetic copy with a NEW batch UUID,
  the SAME source identity, and changed amount/posting/date. Review it explicitly;
  no silent update occurs. Apply facts to the existing record, keeping manual
  notes/category/tags and reopening approval as appropriate.
- For a pending charge receiving a new provider ID, explicitly reconcile the new
  source identity to its existing record. Verify one record with both source links.
- For a matching manual purchase, batch addition stops without partial writes.
  Reconcile the matching row or explicitly choose **Add as a Separate Purchase**.
- Invalid amounts, duplicate source IDs, unknown fields, reused file IDs with
  changed contents, malformed JSON, or wrong packet/revision must fail visibly.
  Never invent IDs to make a real connector fit this fixture.

## Automatic iCloud backup (required)

1. Under **Review & backup**, **Enable Automatic iCloud Backup**. Select a dedicated
   folder inside iCloud Drive. Test rejection of On My iPad/a non-iCloud provider.
2. Wait for **Backed up to iCloud**, not just successful file creation. Confirm the
   uploaded JSON exists from a separate iCloud client, such as Files on your Mac.
   Check the generation/content against the current synthetic data. Never infer
   remote completion from the local folder listing alone.
3. Edit a fictional record, then leave the app open. Without Export/Share, a new
   complete backup uploads; its confirmation supersedes the previous snapshot.
   Normally one confirmed file remains; a second exists while replacement uploads.
4. Enable airplane mode. Edit a record and leave an unfinished draft. Local saves
   continue; the app must not claim the new state is cloud-backed. Force-quit and
   relaunch offline, reconnect, and return to FinTrack. Pending work retries and
   eventually confirms, including the draft and latest edits.
5. Rapid edits during an upload must remain pending until the newest generation
   confirms. Background/foreground and reselecting the folder must preserve data.
6. Check expired/revoked folder access, unavailable iCloud, and full storage when
   feasible without disrupting other data. Failure stays visible; retry/reselect
   recovers. Never delete unrelated iCloud files to manufacture a failure.
7. An old complete backup must remain usable while replacement fails. Upload
   metadata must correspond to the verified pending file before cleanup occurs.

iOS may suspend or force-quit the app; no fixed background schedule or instant
cloud protection offline is promised. Backup is automatic once the folder is
configured. OS device backup remains a separate extra layer.

## Restore and final verification

- Export a full synthetic backup. Save it privately, make a distinctive later
  synthetic edit, and use **Restore Full Backup** to restore the exported file.
  Confirm the replacement dialog, then verify records/IDs, notes/origins, raw
  drafts, pending feedback, guidance, source links, and receipt/decision history.
- Repeat restore from an automatic iCloud backup file. The restored state should
  queue a fresh automatic backup. Do not rely only on the manual export test.
- Cancel restore and try a corrupt/unsupported archive: existing state must survive.
- Restore retains one private local `BeforeRestore.json` for emergency recovery;
  no automatic historical cloud archive is required.

Record each Mac/iPad result in docs/device-verification.md. Real-history migration,
backup correctness, and native file-provider behavior remain unverified until
these checks are complete. Report any failure with the exact error and step.
