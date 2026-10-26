# Data inventory, storage and retention

2026-10-25 financial framework. This describes current source, not a claim that
this revision has passed native/iPad acceptance. See [validation](framework-validation.md).
Only independently invented transactions were used in development.

The accepted ledger is authoritative. ChatGPT replies are temporary discussion
and proposed edits, not a second permanent ledger. No retention rule silently
expires unfinished financial work or pending user feedback.

## Where data lives

The live database is local SwiftData under `Application Support/FinTrack`:
initially `FinTrack.store`; after explicit restore/new-ledger recovery,
`ActiveStore.json` points to `Stores/<UUID>/FinTrack.store`. SQLite sidecars and a
current-format marker accompany it. Transactions are indexed SwiftData rows plus
current JSON payloads; the workspace is a separate JSON payload row. Growing
workspace indexing/performance still needs device measurement.

Logical `.fintrack` archives contain current financial and recoverable workspace
state. Automatic backup writes the latest complete state to the chosen iCloud
Drive folder and confirms cloud metadata. The live DB never resides in iCloud
Drive. Local save, local candidate creation and confirmed upload are different
states. Manual exports are independent user-controlled checkpoints.

## Financial data

All rows below are included in full logical backup/restore. They have **no
automatic age expiry**; normal edits replace current editable values, and an
explicit restore can replace the ledger. The app has no generic transaction-delete
feature or automatic deletion of old financial history.

| Data | Storage | Purpose / retention details |
| --- | --- | --- |
| Record UUID, exact money/currency, merchant, posting/treatment, dates | Transaction payload plus indexed fields | Current financial facts. Revisions prevent stale replacement. Current values remain until edited/restored. |
| Primary category/subcategory, exact expense allocations, tags and per-field origin | Transaction payload | Classify one parent without double counting. Allocation UUIDs support refund/repayment links. Keep current amounts/classification indefinitely; immutable source evidence is separate. |
| Category/subcategory catalog: IDs, stored/display labels, definitions, unresolved/excluded flags, origin | Workspace catalog | Global taxonomy, including unused definitions. Manual changes are validated against all references; referenced definitions cannot disappear. |
| User notes/answers and factual ledger notes | Transaction payload; unsent changes also in feedback | Durable user/factual meaning. Approval does not clear them. No age expiry. |
| Owned source text and qualified archival fields with SourceValue presence | Transaction payload | Preserve provider details/codes/confidence/helper values and mixed/unknown ownership without treating helpers as live calculations. Known resolved assistant roles are the exception described below. |
| Source visibility/exceptional flags and original report date/timestamp evidence | Transaction payload/source versions | Preserve unknown/absent/null/false separately from current display choices. No inferred false or timestamp conversion. |
| Source versions, predecessor/successor chain, original amounts/dates/descriptions/classification, safe notes, historical decisions | Transaction payload | Permanent financial lineage. Reconciliation appends observations; ordinary editing cannot rewrite them. No known transient assistant questions/reasons are permitted here. |
| Historical source approval evidence, actor/origin and known/unknown decision/observation times | Transaction payload/source versions | Evidence independent of current approval. Unknown time remains unknown, never import time. Retained even for pending/superseded classifications. |
| Local review actions: request UUID/action/expected revision/applied revision/time | Transaction payload | Idempotent user commands and local action history. Contains action metadata, not snapshots of all earlier fields or permanent ChatGPT replies. |
| Current approval and explicit discussion intent/progress/question state | Transaction payload | Current workflow. Unresolved question means unapproved; explicit Approve closes discussion. No inferred approval. |
| Accounts: app UUID, aliases, recorded provider/provider account identity | Workspace | Source identity context without credentials. Unknown provider identities remain unknown. No expiry. |
| Source links: genuine provider identity, logical record ID, original/latest observation and superseded fingerprints | Workspace | Deduplicate/reconcile intake and reject old-source replays. No source IDs invented from audit rows. Financial observations persist; no raw ChatGPT commentary. |
| Payment-counterpart and duplicate-candidate relationships | Workspace | Typed links; neither guesses a refund nor silently removes duplicates. Retained until explicitly edited/restored. |
| Benefit programs: identity, limit, period/basis, eligibility rules/defaults/origin | Workspace | Recorded benefit configuration. Unknown settings remain unknown; no invented balance, reset or claim. No history of every settings keystroke. |
| Claims: purchase/program links, eligibility, expected money, status, source-reported received amount, notes | Workspace | Expected/source-reported values are evidence, not cash. Current state persists; no age expiry. |
| Actual repayment allocations: receipt/claim/optional purchase-component links and positive exact money | Workspace | Partial/combined receipts, outstanding balance and purchase net cost; receipt over-allocation rejected. Persists until explicitly changed/restored. |
| Reporting settings, original source-rule evidence and account-period coverage | Workspace | New York/Monday/calendar-month behavior, inclusion of unapproved posted purchases, missing coverage limitations. Settings are current; source evidence is not silently reinterpreted. |
| Original source comparison baselines and exact basis/controls | Workspace | Read-only source evidence in ordinary settings. Current reporting changes do not rewrite original totals. |
| Accepted global guidance | Workspace knowledge library | Classification knowledge stored once; manual/accepted edits replace current text, not a permanent text-version archive. Current rules retained until edited/removed. |
| Persistent Overview visibility by record/category/tag | Workspace | Display-only hiding; does not delete or exclude records elsewhere. Retained until changed/restored. A category rule affecting any component hides that whole transaction. |
| Initial migration receipt: import UUID/payload digest/record IDs/source label/row and column audit/controls/import time | Workspace | One-time migration reconciliation and replay protection. Includes deferred refunds and exclusion reasons; kept indefinitely. This is not a workbook fingerprint or artifact. |
| Dedicated refund receipt: import/migration IDs, payload digest, deferred locators/record IDs/import time | Workspace | Stage identity/replay protection; no duplicate raw refund file. Kept indefinitely. |

## Temporary analysis and unfinished work

| Data | Storage | Retention / removal |
| --- | --- | --- |
| Current assistant question/reason | Transaction assistant context and known-role source/archival fields | Only while unresolved. Explicit Approve/Resolve clears known text, including archival copies; known resolved import text is cleared before commitment. User/factual/mixed/unknown text survives. |
| Imported discussion answers and follow-up questions | Pending response JSON, then extracted active answer objects | Retained while discussion is open. Removed from active answer storage after closure. A shared response file can still contain closed text until all its other items finish or the user dismisses remaining items. |
| User discussion replies | Workspace | Until discussion closes and the associated pending feedback is acknowledged. Durable transaction notes/answers remain separate. |
| Discussion closure revision | Workspace | Compact revision cursor retained indefinitely, without copying closed question/answer text. No old text-boundary compatibility objects. |
| Raw transaction draft, including invalid text and its base evidence/revision | Workspace opaque draft bytes | Until successful save/explicit discard. Included in archives; no age expiry. Current decoder and reference checks protect restore. Never booked as money until valid. |
| Unfinished discussion draft | Workspace | Until sent/discarded. Future revisions are rejected; stale drafts remain recoverable and require review. Closure cannot silently discard unfinished replies. |
| Pending feedback: operation UUID/revisions/exact prior and saved fields | Workspace | Until an acknowledgement explicitly covers those operation IDs. Unsent consecutive autosaves can coalesce. Later edits survive older acknowledgements. Includes allocation/subcategory changes. |
| Imported review-response or weekly JSON | Workspace staged files | Full canonical file retained while work is unfinished. Removed after acknowledgement and proposal settlement/all weekly facts incorporated, or explicit dismissal. No age-based deletion. |
| Compact import receipt: digest, file/packet/item/decision IDs, disposition/time, optional coverage/count | Workspace | Kept indefinitely for replay/ID-reuse checks after raw deletion. Does not keep all reply text or duplicate financial rows. |
| Unread response summary | Receipt until first processed-file view | Cleared from persistence when opened; memory copy survives only that view. Re-import does not recreate a read summary. |
| Prepared manifest: selected revisions, pending operation IDs, guidance version, discussion scope | Workspace | Retired once completed and no remaining dependent work, or after 90 days without a staged dependency. Pending feedback survives expiration; prepare a new review for late replies. |
| Retired packet IDs | Workspace | Small indefinite tombstones rejecting late output after full manifest deletion. |
| History/refund import candidate and preview | View memory before confirmation | Discarded on dismissal. Accepted typed facts/audit/receipt persist; no full raw migration file is retained. |
| Prepared review/manual archive files | OS temporary `FinTrackPrepared` directory | App cleans recognized files older than 7 days on launch/maintenance; OS may remove them sooner. The ledger/outbox remains authoritative. |
| Clipboard review text | Explicit local-only iPad pasteboard copy | App-set copy expires after one hour; no clipboard log. User copies from ChatGPT have external retention. Paste is explicit; never read the clipboard on launch. |
| Charts, selections, temporary category toggles, Show Hidden, session activity | Memory | No backup. Category selections reset on app background/date-range changes; all reset on process termination. |

## Backup/recovery and external copies

| Data | Location | Retention / removal |
| --- | --- | --- |
| Current archive candidates and upload journal | Local `BackupCandidates` / `BackupConnection.json` | Keep pending candidate and last confirmed metadata until a complete replacement is confirmed. Candidate files are current bounded archives, never base64 JSON compatibility copies. |
| Security-scoped folder bookmark | Local backup journal | Until folder reconfiguration. It is not included in logical archives or AI review packets. |
| Last confirmed cloud archive | Chosen iCloud Drive folder | Preserve until replacement upload confirmation. Old confirmed/candidate cleanup then runs; failed cleanup may leave extra files. No automatic long-term version history is promised. |
| Damaged journal, previous/current/abandoned recovery stores | Local Application Support | Preserve until explicit user deletion or verified-current-backup cleanup of eligible retired files. Incompatible development files are not decoded/migrated or silently reset. |
| Atomic-write partial files | Local backup/temp directories, or unpublished cloud staging | Failed operations clean their own unpublished partial; recognized interrupted local partials older than one day are cleaned. Finalized backups are not treated as partial files. |
| User-saved/shared exports, ChatGPT text/attachments and original Sheet/workbook | Outside app-controlled retention | User/external service controls retention. App compaction cannot erase these copies. FinTrack does not copy, fingerprint, reference or manage the original workbook. |

No bank passwords, OAuth tokens, API keys or LLM billing credentials are stored by
FinTrack. Uninstalling/deleting the app or restoring another archive can change
local retention; cloud and externally saved copies follow their separate rules.
