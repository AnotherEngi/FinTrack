# FinTrack data inventory and retention

Updated 2026-10-25. This describes the current source after the lifecycle fixes,
not a claim of successful execution of the new Mac/iPad flows. All 119 portable
tests passed on Windows; 19 Apple files passed syntax parsing. The user reports
earlier native/iCloud checks passed; the clipboard/history batch needs its own
validation. See [the current trial guide](real-data-trial.md).
Only synthetic development data was used. No commit/push was performed.

FinTrack owns the accepted financial ledger. ChatGPT supplies temporary analysis;
its full responses are not a permanent financial history. Approval closes the
current discussion. A later explicit discussion, or a newer question about a
subsequent unapproved revision, can open a new one. Approval never deletes unsent
corrections, user notes, accepted guidance, or unfinished input.

## Storage locations

`Application Support/FinTrack` is private app storage on the iPad. The initial
database is `FinTrack.store` with its SQLite sidecars and `.amount-sign` marker.
After restore, `ActiveStore.json` selects `Stores/<UUID>/FinTrack.store`.
The live database remains local; it is never placed in iCloud Drive.

Transactions have separate SwiftData rows with indexed fields and a JSON domain
payload. Growing exchange state still uses the SwiftData workspace JSON row.
This batch adds compaction and capacity checks; splitting that row into indexed
entities and measuring large-history performance remain separate work.

The selected iCloud Drive folder receives **logical full backups**, including
records and all recoverable workspace state. Local folder permissions, upload
progress, and retired database files are not embedded in those archives.

## Financial and working data

| Data | Storage | Purpose | Retention / removal |
| --- | --- | --- | --- |
| Transaction IDs, dates, merchant, exact amount/currency, posting/treatment, optional activity date | Transaction SwiftData row and domain payload; full backups | Authoritative financial history | No automatic expiry. Edits replace current values. Full restore can replace the ledger. Individual transaction deletion is not implemented. |
| Current category and tags, exceptional-event flag | Transaction payload; full backups | Classification and reporting | No automatic expiry; kept until edited or replaced by restore. Tags remain even when their discussion is removed. |
| Imported actual category catalog | Workspace `importedCategories`; full backups | Keep real category IDs/labels and flags consistent across restart, editing, weekly intake and ChatGPT | No automatic expiry; retained with the ledger and restored with it. Synthetic defaults apply only before migration. |
| Initial history migration audit/receipt | Workspace `historyImport`; full backups | Source alias, import ID/fingerprint, original record IDs, declared source row/column accounting, exclusions, warnings, control total and import time | No automatic expiry. It is source provenance, not a retained ChatGPT conversation. It records exporter assertions, not independent proof of source completeness. |
| Preserved unsupported Sheet details and prior approval evidence | Workspace `historyDetails` keyed by record UUID; full backups | Avoid losing source subcategory/split/reimbursement details; read-only editor inspection and corresponding ChatGPT review context | Retained with the financial record until replaced by full restore. They do not drive native accounting. Mapped transient assistant questions/reasons are not duplicated here. |
| Source alias UUID/label and genuine provider transaction identity mappings | Transaction source plus workspace source links; full backups | Identify the source and prevent duplicate intake | Retained with the financial record. Labels are not credentials. Stable provider/account identity independent of labels is still a contract gap. |
| Original and latest accepted source facts | Workspace source links; full backups | Preserve source evidence independently of manual annotations and compare updates | Both retained indefinitely with the record. Intermediate full source versions are not kept. |
| Superseded source fingerprints and pending-to-posted successor identity | Source links; full backups | Reject known older facts and prevent superseded pending IDs from regressing a posted record | Compact fingerprints/identity relationships retained indefinitely. Unknown older facts cannot be ordered reliably by weekly v1. |
| Refund allocations: purchase IDs and positive exact amounts | Refund transaction payload; full backups and read-only review context | Reduce spending on original purchase dates without changing the refund's bank date | No automatic expiry; until the user changes links or restores another state. |
| User-authored notes and the last saved user answer | Transaction payload; full backups; committed review context | Preserve user-owned facts and corrections | No automatic expiry. Approval does not erase these fields; the user can edit/clear them. They are distinct from the conversation transcript. |
| Earlier ledger notes / legacy review flag | Transaction payload; full backups | Preserve historical source evidence without inferring approval | Retained with the record; no automatic expiry. |
| Category/tag authorship, approval and discussion state, record revisions/timestamps | Transaction payload; full backups | Show current authority and reject stale changes | Current state retained with the record. Explicit Discuss opens a new discussion after closure. |
| Explicit review actions: action ID, type, base/applied revision and time | Embedded transaction review history; full backups | Explain explicit approvals/reopens and make action retries harmless | Retained with the record. This is compact action metadata, not every old financial value or an LLM transcript. |
| Assistant question/reason on a transaction | Transaction payload; full backups while present | Explain the current classification question | Cleared by Approve/Mark Resolved. Maintenance removes legacy closed assistant text with a revision increment, preserving financial fields/approval. It defers this cleanup for records with drafts or at the revision limit. Legacy ledger notes remain. |
| Unfinished transaction editor input | Workspace drafts keyed by stable record ID; full backups | Recover invalid/incomplete offline input | Until valid input commits or the user explicitly discards it. No age-based deletion. |
| Unfinished discussion reply | Workspace discussion drafts; full backups | Recover typed but unsent questions/answers | Until sent or explicitly discarded. A nonempty reply draft blocks approval/closure so text is not silently lost. |
| Committed discussion replies | Workspace reply collection; full backups | Supply an open discussion's context and send user feedback | Until discussion closure **and** associated outgoing feedback has been acknowledged. Unsent replies survive approval/closure. |
| Open assistant answers/questions | Workspace typed answer collection; full backups | Read/reply without accepting financial changes | Until approval or explicit resolution of that discussion. No arbitrary age cutoff for open work. Answers can outlive their original raw response file. |
| Discussion closure revision cursors | Workspace; full backups | Keep old questions closed and separate a later discussion | Retained with the record; contains IDs/revisions, not old question/note text. Older content-heavy closure boundaries are converted and removed. |
| Pending outgoing feedback, prior/saved values and operation IDs | Workspace pending events; full backups | Deliver additions, corrections, approval/decisions and user replies to ChatGPT | Until a validated response acknowledges those exact operations. Approval, preparing, sharing, or dismissing a response does not clear it. |
| Accepted classification guidance | Workspace current rules with IDs/text/origin and version; full backups | Recover learned rules and include them in reviews | Current accepted rules retained until edited/deleted. This batch does not add permanent rule-text version history. Limit: 1,000 current rules, enforced for manual and assistant additions alike. |
| Visibility rules by transaction/category/tag | Workspace preferences; full backups | Persistently hide records from Overview only | Until the user changes them or restores another backup. They do not filter financial exports or ChatGPT packets. |

The prototype starts with five synthetic categories; a history import now installs
the actual category catalog. Structured subcategories, general spending splits, and reimbursement
relationships are **not implemented**; do not mistake refund allocations for
those features. No bank passwords, OAuth tokens, or LLM API credentials are
stored by this app.

## Exchange data

| Data | Storage | Purpose | Retention / removal |
| --- | --- | --- | --- |
| Clipboard review text | iPad pasteboard; explicit copy only | Paste a prepared review into ChatGPT without a Files upload | App copies expire after one hour and are marked local-only. User-created ChatGPT copies have their own external retention. Clipboard limits never truncate a packet. |
| Pasted reply / initial history preview | View memory, then the existing validated staging/migration path when accepted | Explicit clipboard transport with normal validation and review | No separate clipboard log. Unconfirmed history stays in memory; accepted history retains typed records/audit/details, not the entire raw migration file. Staged reply retention follows the rows below. |
| Imported ChatGPT response JSON | Canonical bytes in workspace staged files; full backups while pending | Validate provenance and show undecided proposals | Removed as soon as acknowledgement is recorded and all actual classification/guidance proposals are handled. Open answers are extracted first. Approval settles older classification proposals; it does not accept guidance. A shared raw file may still contain closed text while another item in that file remains undecided; Dismiss Remaining Items explicitly finishes it. |
| Imported weekly JSON | Workspace staged files; full backups while pending | Review/add/reconcile incoming source facts | Removed once every row's facts are incorporated, or the user explicitly dismisses remaining rows. Unfinished files are not deleted by age. |
| Compact import receipts | Workspace; full backups | Reject changed-content file-ID reuse, repeated operations and reused item IDs after raw deletion | IDs/fingerprints kept indefinitely. Contains file ID, purpose, SHA-256 fingerprint, processing time/disposition, packet/item/decision IDs, and optional row count/reported weekly coverage. No full response or financial row copies. |
| Unread import summary | Temporary text on its receipt; full backups while unread | Avoid erasing an incoming summary before it can be displayed | Cleared from persistence when the processed file is opened. The open view keeps a memory copy only until dismissal. Re-import does not recreate a cleared summary. This is not an open classification discussion. |
| Reported weekly coverage | Raw pending batch, then its receipt; full backups | Preserve the collector's coverage claim as source evidence | Retained as compact receipt text after raw-file deletion. It is not independently verified, and is not structured complete/partial account-period coverage. |
| Active processed/proposal-ID sets | Workspace; full backups | Idempotent operations while a raw response is pending | Removed when that file is compacted; necessary IDs move into its receipt. |
| Prepared review manifests: operation IDs, record revisions, guidance version and discussion scope | Workspace; full backups | Bind returned suggestions/acknowledgements to what was actually sent | Retired after a completed file has no remaining pending operations or active staged response. Otherwise retire after 90 days when no staged response still requires it. Pending feedback is retained even if the old manifest expires. |
| Retired review-packet IDs | Workspace; full backups | Explicitly reject late results after full manifests are removed | Kept indefinitely as small ID tombstones. An expired packet needs a new review; the app never silently accepts late output. |
| Prepared review JSON / temporary manual backup export | OS temporary `FinTrackPrepared` directory | Allow share/save extensions to read a frozen file | App cleanup after 7 days on launch and successful current-backup maintenance; the OS may remove temporary files sooner. The manifest/outbox or authoritative ledger survives independently. |
| Files manually saved/shared elsewhere | User-selected Files destinations, ChatGPT attachments, other recipients | User-controlled exchange/checkpoints | Outside FinTrack's deletion control. App compaction does not delete those copies. |

No raw ChatGPT response is required forever for replay protection. Its hash/IDs
replace it. Retention runs atomically with workspace mutations, on startup, and
during active backup maintenance. Suspension/force-quit pauses maintenance;
age-based housekeeping resumes when the app runs. Opening or dismissing a file
never counts as bank verification or approval of its contents.

## Backups, recovery, configuration, and temporary state

| Data | Storage | Purpose | Retention / removal |
| --- | --- | --- | --- |
| Latest confirmed full backup | Chosen iCloud Drive folder, `FinTrack-<UUID>.fintrack` | Complete logical recovery, including unfinished work | Latest only. Previous confirmed file stays until a validated replacement has an upload confirmation. Failed old-file deletion remains in a retry queue. |
| One replacement candidate | Persistent local `BackupCandidates` plus pending iCloud file | Retry exact immutable bytes across interruption/offline periods | Until upload confirms. Local candidate/orphan archives are then cleaned; its cloud copy becomes the confirmed backup. |
| Unpublished cloud upload staging file | Selected cloud folder, `.FinTrack-upload-<UUID>.partial` | Prevent interrupted copies from acquiring a valid backup's final name | Verified and renamed into the final file after copying. Interrupted current attempts are retried/replaced; abandoned recognized staging files older than 24 hours are cleaned during successful backup maintenance in the currently selected folder. |
| Local upload journal/bookmark | `BackupConnection.json`, private app storage | Remember folder permission, generation/hash/size/time, pending candidate and cleanup queue | Current configuration/progress retained until changed. Old journals containing base64 candidate data migrate to a separate file once. These permissions/settings are excluded from logical exports. |
| Backup cleanup queue | Local upload journal | Retry deletion of replaced cloud files | Each item removed only after its file deletion succeeds and the journal is saved. Changing folders does not delete files in the old folder. |
| Active-store pointer and amount marker | `ActiveStore.json`, `.amount-sign` beside each store | Select the verified database and enforce amount convention | Current pointer/marker retained while the store is used. Prior pointer copies are preserved on replacement and removable through local recovery cleanup; pointer metadata is not a financial backup. |
| Previous, damaged, or interrupted recovery stores | Original database/sidecars or inactive `Stores/<UUID>` directories | Preserve pre-restore data without decoding it | Until explicit deletion in Backup → Preserved recovery data. The active store cannot be deleted there. Restore failures clean only the newly created attempt when safe; crash-left attempts remain discoverable. These stores are excluded from logical cloud backups. |
| Legacy `BeforeRestore.json`, previous pointer and damaged journal copies | Private app storage | Preserve older recovery evidence | No new BeforeRestore JSON is created. Copies remain until explicit Delete Superseded Local Recovery Files. This action does not delete cloud backups or the active store. |
| Legacy raw draft files | Private `Drafts/<UUID>.json` | Preserve input during migration into SwiftData | For the original store, remove only after migration and confirmation of a current cloud backup. If an isolated restore replaced that store, old drafts stay with the preserved original until its explicit deletion. |
| Partial archive files left by a crash | Private archive destination directory, `.archive-<UUID>.partial` | Unpublished interrupted writer output | Never treated as valid backups or activated stores. Ordinary failures remove them immediately. Recognized crash leftovers older than 24 hours are removed on launch or successful current-backup maintenance. |
| Search, sorting, chart selection, Show hidden, temporary category switches, session activity markers | Memory only | Current interaction state | No backup. New process resets it; category switches and chart selection also reset on date-range changes/backgrounding. |
| Derived ledger/discussion/report projections and intake date indexes | Memory only | Display current data and avoid repeated full-history matching | Rebuilt from saved records/workspace; discarded on replacement or process termination. No independent history or archive entry. |
| Startup/operation errors, transient export previews | Memory/UI | Report failures without claiming success | Until dismissed/replaced or the app process ends; no permanent diagnostic/financial telemetry log is introduced. |
| Synthetic fixtures and test archives | Synthetic source fixtures; test archives in OS temporary directories | Development/regression checks | Source fixtures remain in Git. Tests remove their own temporary directories; interrupted test leftovers follow OS/user cleanup. No real data or credentials belong in the checkout. |

Normal logical restore never requires encoding the current database. It builds a
new store, commits it, reopens and validates it, then atomically switches the
pointer. The old database and marker remain untouched. Existing logical JSON
backups remain readable. A broken/missing selected store shows recovery rather
than silently creating an empty replacement.

## Capacity, privacy, and outstanding validation

The new archive is a documented framed format with per-entry deflate compression,
SHA-256 checks and a terminal count/order digest. It is a FinTrack recovery file,
not a ZIP or ChatGPT review attachment. Native compressed archives are read by
FinTrack on Mac/iPad; portable Windows tests use the uncompressed codec.

Supported format ceilings are 250,000 records, 1 GiB logical payload, 80 MiB per
entry, one million entries, and 2 GiB physical file. Conservative precommit
capacity checks keep accepted state below those ceilings, including workspace
growth; an 80% warning appears for record/byte capacity. This is **not** a measured
iPad performance guarantee. Offline/cloud failures do not block local edits
within local capacity. AI exchange files retain their separate 50 MiB limit.

Archives are compressed, **not encrypted by FinTrack**. They contain private
financial records, notes, and unfinished drafts. Application/cloud access
protection is separate; archive encryption and recoverable keys are still an
explicit design decision before real-data use. Do not put archives in this public
repository. Provider/device backup copies, trash/version history, and manually
shared files are outside the app's retention controls; no external retention
duration is promised here.

Removal means removal from the app's **logical active state** and future logical
backups. SQLite pages/sidecars, device/provider backups, and previously shared
files can retain older bytes. This batch does not implement or promise forensic
secure erasure. The local database file can keep unused pages for later reuse
even after raw responses are compacted; logical archive size reflects live data.

Still required: Mac native tests and Xcode build, device corruption and
interruption tests, actual cloud download → empty-store restore, and iPad memory/
latency measurements above 50 MiB. Stable collector/account keys, unknown-source
freshness, structured coverage, live subcategories/splits/reimbursements, full
legacy behavioral parity, indexed workspace entities, bounded full-history review jobs, and
guidance revision history remain future work. No cloud sync, automatic ChatGPT
transport, account access, or billed API is added by this batch.
