# ChatGPT review, weekly intake, and automatic iCloud backup

Current source batch: 2026-10-24. Synthetic development data only. Mac build,
SwiftData migration tests, and physical-iPad handoff/upload/restore need validation.
This guide replaces the former selected-range JSON/CSV/three-file export steps.

## Normal review

1. Open **Review & backup**, or the **Review with ChatGPT** action in Transactions.
2. Tap **Review with ChatGPT**. FinTrack automatically gathers pending additions,
   edits (including prior/saved values), review decisions, open discussions and
   unanswered questions, relevant committed records, and classification guidance.
   Notes and answers are included; unfinished raw drafts are excluded. The first
   packet establishes existing records as a baseline. Table filters do not limit it.
3. Optionally inspect the preview. Use **Share or Save File** and attach the one
   JSON file in your chosen ChatGPT finance conversation. Instructions and a return
   template are embedded; there are no routine date/record/context choices.
4. Ask ChatGPT to follow the embedded instructions and return one JSON file. Save
   that result and use **Import ChatGPT or Weekly File** in FinTrack.
5. Open the incoming response. **Record Processing Receipt** removes only the
   acknowledged operation IDs; newer edits remain pending. Accept/reject individual
   suggestions separately. Newer records/guidance block stale acceptance.

Preparing/sharing a file is not receipt or approval. Open discussions remain
eligible for the next review even after their operations were acknowledged.
Resolve discussion using the existing explicit review actions and answer fields.
Assistant suggestions never populate user-authored notes/answers or approve records.
Accepted classification changes reopen approval and retain assistant provenance.
Replays have no additional effect; reused file/proposal IDs with changed scope or
content are rejected. Rejections/acceptances return as decisions, not manual edits.

## Full-history review and guidance

**Full History Review** creates one file containing all accepted records, current
pending work, and the guidance library. Use it periodically to refine decisions.
No source/date completeness is inferred. The 50 MB limit rejects oversized files
visibly rather than silently truncating history; partitioned analysis is future
work. The inline preview alone is capped at 100 KB, with an explicit message.

Add guidance under **Classification guidance**, or open an existing rule to edit/
delete it. ChatGPT can suggest additions/replacements; accept them explicitly.
Changing guidance manually invalidates older outstanding rule proposals. Multiple
proposals from an unchanged response can be accepted sequentially. Rules are scoped
text, not an automatic merchant-rule execution engine. Each review carries their
version and the actual guidance, so a new conversation can use them.

Manual attachment uses the existing ChatGPT subscription session. No LLM API or
paid fallback is used. FinTrack cannot access existing chats, memories, bank
connections, or scheduled tasks. Your separate weekly task needs its current
instructions/context explicitly; this app does not schedule or configure it.
[Official OpenAI file guidance](https://learn.chatgpt.com/docs/use-chatgpt).

## Weekly intake

Import a `fintrack-weekly-intake` JSON file, inspect coverage and the rows, then
choose **Add All New Transactions**. New identities are added in one transaction;
existing identities are skipped. Any ambiguous match stops the batch without
partial additions. Individual rows can be added or reconciled separately.

Provider transaction IDs must be genuine, scoped to source aliases. Never invent
IDs if the weekly collector cannot supply them. For a manual duplicate candidate,
pending-to-posted identity change, or source correction, choose **Reconcile /
Separate Purchase** or **Review Source Update**. Select the existing record and
inspect the before/after facts before applying. User notes/category/tags remain;
financial/source changes reopen approval. **Add as a Separate Purchase** explicitly
allows two legitimate purchases with the same date/merchant/amount. Original and
latest source evidence remain recorded. Guess changes on already imported rows
should return through classification proposals, not overwrite annotations.

[Weekly synthetic fixture](../fixtures/exchange/weekly-synthetic.json) demonstrates
the supported shape. This is an adapter contract, not support for arbitrary bank
CSV files or proof of the user's actual weekly connector's output/completeness.

## Automatic iCloud backup

1. Tap **Enable Automatic iCloud Backup**. Create/select a dedicated folder inside
   **iCloud Drive** using Files. On My iPad and other providers are rejected.
2. This one-time folder permission is remembered. After changes, FinTrack prepares
   complete logical snapshots and attempts upload automatically while it can run.
3. Status distinguishes local/pending/error from **Backed up to iCloud**. Only
   Apple's uploaded-file metadata confirms cloud completion. A last-confirmed
   snapshot date does not imply that newer local edits reached the cloud.
4. Offline/interrupted work and the candidate upload survive relaunch. Returning
   to the app or **Retry Backup Now** retries. Expired permissions require choosing
   the folder again. Insufficient storage or inaccessible iCloud stays visible.

The previous complete backup remains until the replacement uploads. Normally
there is one confirmed file and at most one pending replacement; old files are
removed after confirmation. Cleanup failures can leave an extra file and are
reported. A crash during cleanup can also leave an extra file; there is no
user-visible automatic historical retention policy. Do not manually edit these
files or use this folder from a second editable replica.

The live database is local, CloudKit is disabled, and no extra signing capability
is added. User-selected-folder backup uses security-scoped bookmarks, coordinated
file I/O, and NSMetadataQuery upload notifications. It does not rely solely on
periodic device backup. Apple backup eligibility is retained as another layer.
No guarantee of uploads while force-quit or of a fixed background schedule is made.
[Apple directory access](https://developer.apple.com/documentation/uikit/providing-access-to-directories),
[upload confirmation](https://developer.apple.com/documentation/foundation/urlresourcekey/ubiquitousitemisuploadedkey).

## Supplementary full export/restore

**Export Full Backup** creates a private full snapshot; share/save that file.
**Restore Full Backup** opens either an automatic cloud backup file or a manual
export, validates it, and asks before replacing current state. One local
`Application Support/FinTrack/BeforeRestore.json` preserves the pre-restore state;
this is not an automatic version history. The restore transaction preserves the
current store on failure and updates backup work for the restored state.

Full backups include raw drafts, ledger IDs/revisions/provenance, pending feedback,
packet manifests, incoming files, decisions/receipts, source mappings, and guidance.
They omit folder permission bookmarks and credentials. A review packet is not a
backup and cannot be imported as one. Files are ordinary private JSON snapshots;
there is no app-level archive password/encryption feature. Keep them outside Git.
Prepared share files use app temporary storage and are not a backup destination.

Complete the [combined checklist](ipad-acceptance.md) before real-data use.
