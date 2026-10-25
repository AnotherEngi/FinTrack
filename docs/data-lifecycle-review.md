# Data lifecycle review and proposed next steps

Implementation follow-up, 2026-10-25: the first safety/retention batch addresses
several findings below in source. See [implementation and pending verification](lifecycle-validation.md)
and the [complete data inventory](data-retention.md). The follow-up passed all 108
portable tests and syntax-parsed 18 Apple files; native builds/device checks remain;
these original audit findings remain as the baseline, not an assertion that the
new source has been qualified for real data.

Reviewed 2026-10-25 against the current plans and Swift source. These are review
findings and proposals, not approved changes to the architecture or implementation.
No real financial files, Google Sheet, bank connections, or previous ChatGPT chats
were accessed. The actual history size, column layout, source IDs, and collector
output remain unknown. This was static inspection; no shell commands, Swift tests,
Mac build, or iPad/cloud experiments were run for this review.

## Assessment

Keep the selected ownership model: FinTrack owns the accepted local ledger;
providers supply source facts; ChatGPT returns analysis and proposed changes;
iCloud Drive holds complete recoverable backups. Exact money, explicit approval,
separate user/assistant text, atomic saves, revision guards, and immutable backup
candidates are appropriate foundations.

The current prototype is not ready for real-history ingestion. The highest risks
are backup capacity limits, recovery depending on a readable current database,
lossy spreadsheet migration, and duplicate intake when provider identity changes.
Several are already acknowledged in hardening notes; they now need concrete work
and acceptance criteria rather than remaining deferred behind more UI work.

## Findings

### 1. Backup capacity can be exceeded by valid local state — before real data

**Confirmed in source.** `ExchangeJSON.maximumBytes` is 50 MiB and is also used
for automatic full backup, manual full backup, restore reads, and the pre-restore
recovery copy. `FullBackup.validate` separately rejects more than 100,000 records.
Local insertion and weekly acceptance do not enforce these aggregate limits.

The workspace retains every staged incoming file as `Data`, manifests, source
links, receipts, proposal IDs, and discussions. There is no implemented pruning
path. JSON encodes embedded `Data` as base64, expanding those file bytes by about
one third. A valid incoming response can therefore fit its own exchange limit
while causing its containing full backup to exceed the same limit. The live
ledger can continue saving while automatic/manual backup fails. At that point,
restore can also be blocked by encoding the oversized current pre-restore copy.

The same mismatch exists for guidance: manual guidance saves enforce 1,000 rules,
but accepting assistant additions does not enforce that aggregate count. Full
backup validation rejects a library over 1,000 rules.

**Proposal.** Give backups a distinct, versioned format and capacity policy.
Use a self-contained compressed archive with a manifest, bounded entries,
counts, generation, hashes, and explicit compatibility information. Stream large
entries rather than constructing several complete JSON copies. Apply separate
resource bounds to ChatGPT packets and untrusted archive entries. Every accepted
app state must remain exportable and restorable within the published support
envelope. Show capacity warnings before any limit is approached. Compression
helps size but does not replace journal compaction or streaming.

Evidence: [exchange limit](../Packages/FinTrackCore/Sources/FinTrackCore/ReviewWorkflow.swift#L10),
[backup validation](../Packages/FinTrackCore/Sources/FinTrackCore/ReviewWorkflow.swift#L573),
[backup encoding](../Apps/FinTrack/Sources/CloudBackup.swift#L164),
[pre-restore copy](../Apps/FinTrack/Sources/LedgerViewModel.swift#L197),
[guidance decisions](../Packages/FinTrackPersistence/Sources/FinTrackPersistence/LocalTransactionRepository.swift#L280).

### 2. Restore is unavailable when the current store cannot open — before real data

**Confirmed gap.** Startup failure replaces the entire working UI with an error.
The restore UI is inside the unavailable normal tabs. `restoreBackup` also
requires the existing repository and a readable, encodable current backup.
An unreadable database, failed migration, or incompatible amount marker therefore
has no independent in-app recovery path. Preserving files is good, but does not
by itself make recovery usable.

**Proposal.** Add a recovery entry point independent of the live repository.
Validate/import the selected archive into a new isolated local store, verify
logical contents and relationships, close it, and activate it through a
crash-safe store-switch procedure. Preserve the damaged original and its
sidecars/marker without requiring it to decode. Use this path both for broken
stores and fresh-device recovery. Include backup-format migrations independent
of SwiftData schema migrations. Never make inability to back up an already
damaged current store prevent recovery from a good archive.

Evidence: [startup failure UI](../Apps/FinTrack/Sources/LedgerViews.swift#L14),
[repository-dependent restore](../Apps/FinTrack/Sources/LedgerViewModel.swift#L197),
[existing documented limit](hardening.md#remaining-validation-and-limits).

### 3. The weekly adapter cannot safely replace a spreadsheet migration — before migration

**Confirmed mismatch.** Weekly v1 accepts a small set of source facts and optional
category/tags. It cannot carry the full taxonomy/subcategories, balanced splits,
reimbursement relationships, legacy notes, explicit historical approvals,
discussion state, and processing evidence described in the website handoff.
The native catalog is still five fictional choices embedded in code. Full
backup currently contains records/workspace, not an independently stored taxonomy.
Actual Sheet structure has not been inspected.

**Proposal.** Build a dedicated, deterministic, resumable legacy migration:

1. Privately inventory tabs, headers, data types, row counts, years, account aliases,
   IDs, formulas, allocation columns, notes/comments, and approval semantics. Use
   synthetic rows with the same shape for implementation. Preserve a frozen
   original export and its hash outside this public repository. A single tab CSV
   must not be assumed to capture the whole workbook or its metadata.
2. Store the actual taxonomy with stable IDs, subcategories, retired categories,
   and explicit mappings. Implement balanced allocation and reimbursement models
   wherever the inventory proves they are needed. Preserve unsupported fields as
   quarantined/read-only source evidence until they can be represented faithfully.
3. Preserve genuine bank IDs separately from legacy row IDs. If a historical row
   lacks a stable ID, assign an ID in the frozen migration manifest and preserve
   that mapping on retry; do not rely on mutable row numbers or invent bank IDs.
4. Map exact cents, signs, dates, treatment, pending status, classifications,
   authorship, and each note owner explicitly. Import a historical approval only
   from verified explicit approval evidence through a deliberate migration rule.
   Category presence and the old native prototype's review flag are insufficient.
5. Dry-run into an isolated store. Compare transaction counts and exact totals by
   source/month/currency/treatment, allocation sums, refunds, exclusions, approvals,
   and unresolved rows. Report every rejected or preserved-but-unmapped value.
   Do not double-count the parent transaction and its allocation lines.
6. Repeat the same import and a reordered/overlapping export: no duplicate rows,
   changed identities, or overwritten annotations. Require explicit reconciliation
   for changed source exports rather than silently making them a second migration.
7. Set a cutover boundary. Reconcile in-flight web feedback/receipts and stop the
   legacy workflow writing an independently authoritative Sheet. Keep the frozen
   Sheet export for reference, then reconcile the first overlapping weekly intake.
8. Restore the migrated result from its actual cloud backup before using it as the
   only working ledger. Give initial ChatGPT analysis its own bounded baseline
   review; do not require sending the entire history as one routine packet.

Evidence: [legacy behavior and fields](website-handoff-review.md#behavior-to-preserve),
[weekly contract](../Packages/FinTrackCore/Sources/FinTrackCore/ReviewWorkflow.swift#L248),
[prototype taxonomy](../Packages/FinTrackCore/Sources/FinTrackCore/Review.swift#L70).

### 4. A new provider ID can duplicate an already imported purchase — before weekly use

**Confirmed control-flow risk; not reproduced on device.** The new-row intake
paths only search *unlinked* records for possible duplicates. An imported pending
purchase already has a source link. If its posted version receives another ID,
both Add Transaction and Add All New Transactions can treat it as a new purchase.
The existing test proves explicit reconciliation works, but does not prove that
the convenient addition path blocks this duplicate.

Exact date/amount/merchant matching also misses a tip-adjusted charge, a changed
posted date/description, and slightly different legacy/manual rows.

**Proposal.** Reconcile against linked as well as unlinked records. Prefer provider
pending-to-posted linkage; otherwise flag conservative candidates using stable
source identity, a bounded date window, merchant evidence, and amount changes.
Keep ambiguous matches for the user rather than automatically merging legitimate
equal purchases. Batch preview must distinguish new, unchanged, source update,
possible duplicate, and unresolved rows, and must make skipped source updates
visible rather than merely returning an additions count.

Evidence: [single-row matching](../Packages/FinTrackPersistence/Sources/FinTrackPersistence/LocalTransactionRepository.swift#L399),
[batch matching](../Packages/FinTrackPersistence/Sources/FinTrackPersistence/LocalTransactionRepository.swift#L434),
[current reconciliation test](../Packages/FinTrackPersistence/Tests/FinTrackPersistenceTests/ExchangeRepositoryTests.swift#L210).

### 5. Source identity and freshness are too weak for a durable collector contract

**Confirmed contract gaps.** Bank identity is a mutable display alias plus a
provider transaction ID. There is no stable provider/account key independent of
the label, source revision, retrieval timestamp, collector version, or explicit
pending replacement/cancellation field. Two sources with the same alias can
collide; renaming the collector's alias can make old transactions appear new.
Replaying identical data for an identity is harmless, but older changed source
facts are not identified as older. A user can apply them after a newer update.
When pending and posted identities both link to one record, they also need an
explicit supersession relationship so an obsolete identity cannot regress it.

**Proposal.** Version the intake contract around stable opaque source UUIDs plus
provider ID/namespace, retrieval time, source revision or content fingerprint,
and explicit replacement relationships. Keep labels editable independently.
Distinguish raw provider facts from ChatGPT-derived treatment/classification and
record the guidance version used. If genuine provider IDs are unavailable, use a
separate conservative matching mode with durable reconciled mappings; never ask
ChatGPT to fabricate IDs. Preserve source evidence and cancellation/void status;
absence from one weekly file must not mean deletion.

First verify a synthetic sample matching the actual weekly collector's output.
The app's JSON fixture alone does not establish that the collector supplies these
identities or complete source data.

### 6. Missing coverage is not represented structurally

**Confirmed limitation.** Weekly coverage is free text and review exports say
coverage is unknown. Charts correctly avoid filling wholly absent months with
zero, but a month with one imported card or one imported week still has a total.
The app cannot distinguish that partial total from a complete account/month.
A verified empty statement period also cannot be distinguished from missing data.

**Proposal.** Persist per-source coverage intervals, retrieval status, complete/
partial/unknown status, and reconciliation counts/totals where supplied. Carry
them through migration, weekly intake, backups, exports, and reporting. Show
partial periods explicitly and compare only compatible source/period coverage.
Zero is justified only for a confirmed covered period with no applicable records.
Do not accept a generated coverage assertion as independently verified evidence.

Evidence: [weekly coverage field](../Packages/FinTrackCore/Sources/FinTrackCore/ReviewWorkflow.swift#L285),
[export coverage](../Packages/FinTrackCore/Sources/FinTrackCore/ReviewExport.swift#L90),
[observed-month charts](../Packages/FinTrackCore/Sources/FinTrackCore/SpendingCharts.swift#L20).

### 7. Routine editing gets more expensive as history and exchanges accumulate

**Confirmed design; performance impact unmeasured.** One SwiftData workspace row
contains a JSON blob for all exchange state, source links, and drafts. Each draft
change decodes/re-encodes the workspace. App reload fetches every ledger record
and rebuilds discussions by examining stored responses. This happens during
editing, not just full-history analysis. Backup validation also revalidates all
staged history, including comparisons with prior response IDs.

**Proposal.** Keep SwiftData initially, but split growing collections into indexed
entities: source mappings, events, manifests, responses, decisions, discussions,
and drafts. Query/filter records in the repository and update only changed
projections. Perform expensive serialization/validation off the UI actor using a
consistent immutable snapshot. Preserve atomic ledger-plus-feedback commits.

Define compaction rules: pending work, undecided proposals, and open discussions
stay intact; finished exchanges become compact durable decisions/messages and
file/proposal-ID fingerprints sufficient to reject replay or changed-content
reuse. Retiring a manifest must explicitly reject late results rather than
silently accepting them. Preserve needed recovery/audit evidence outside the hot
workspace and include it in the self-contained backup. Simply deleting raw
responses today would delete discussion history derived from those responses.

Evidence: [workspace blob](../Packages/FinTrackPersistence/Sources/FinTrackPersistence/LedgerSchema.swift#L119),
[workspace rewrites](../Packages/FinTrackPersistence/Sources/FinTrackPersistence/LocalTransactionRepository.swift#L204),
[reload](../Apps/FinTrack/Sources/LedgerViewModel.swift#L41),
[discussion projection](../Packages/FinTrackCore/Sources/FinTrackCore/Discussions.swift#L87).

### 8. Full-history ChatGPT review needs bounded, verifiable analysis

**Confirmed limitation.** Full history and the first existing-record baseline
can place the whole ledger into one JSON file. The app's 50 MiB ceiling is not a
demonstrated ChatGPT analysis capacity. A file being accepted does not establish
that every row was analyzed. Open discussions also carry earlier message history
repeatedly. Current receipts identify acknowledged operations, but there is no
per-part history-review coverage contract.

**Proposal.** Keep small automatic pending-work reviews. Give a history-review
job one frozen ledger/guidance boundary and an indexed set of bounded parts,
with hashes, record/revision scopes, exact app-computed totals, coverage, and
explicit completion/omission results. Offer a single convenient bundle if the
chosen ChatGPT workflow can reliably read it; otherwise guide staged attachments.
Partition by suitable source/date scopes, then perform a separate cross-period
synthesis so refunds, reimbursements, and recurring merchants across boundaries
are still considered. The app retains authoritative exact totals and links every
proposed edit to its original revision. Never silently truncate context or claim
completion from a generic acknowledgement. Test actual capacity in the user's
chosen iPad ChatGPT workflow rather than hard-coding a guessed token limit.

[Official OpenAI documentation](https://learn.chatgpt.com/docs/use-chatgpt)
supports attaching data exports and creating files from them; it does not establish
that this particular full-ledger contract was completely analyzed. The project
still needs its synthetic end-to-end round trip. Current manual exchange can
remain; this proposal introduces no separately billed API or automatic transport.

### 9. Recoverable classification knowledge needs explicit history and scope

**Confirmed limit.** Guidance is an ID, free text, and origin. Manual edits replace
the current text; knowledge feedback only says the library was updated. A library
version UUID does not preserve the prior rule contents or resolve contradictory
merchant advice. It also does not send the newest rules to the separate weekly
collector. Weekly intake has no field declaring which guidance version it used.

**Proposal.** Store rule revisions, scope, provenance, effective/retired status,
supersession, and accepted examples. Keep taxonomy definitions separate from
merchant advice. Attach the applicable bounded current library to reviews and
provide an explicit collector-context export. Intake must identify the guidance
version used; retain newer source facts while treating stale categorization as
provisional. A correction for one mixed-use merchant must not create a universal
rule. Do not rely on a perpetual ChatGPT conversation to recover this knowledge.

### 10. Backup confirmation and privacy need an operational acceptance step

**Existing protection worth keeping.** Backup code journals immutable candidate
bytes, checks cloud upload metadata, and preserves the previous confirmed file
until replacement confirms. These are good safeguards. They are not yet an
independent restore demonstration on this iPad.

**Proposal.** Complete the existing cloud checklist, then download the confirmed
file independently and restore it into an empty isolated store. Test interruption,
offline edits, a full destination, revoked folder access, replacement failure,
fresh-device recovery, and unreadable-current-store recovery. Validate archive
hashes and logical contents before old-backup cleanup; hashes detect corruption,
not authenticity. Show both the last protected generation/time and newer pending
work. Preserve latest-only automatic backup as selected; no automatic historical
archive is required. A manual checkpoint before migration or a large accepted
batch fits that policy and gives a recovery point for a later-discovered mistake.

Current backups are ordinary JSON containing notes and raw drafts. Review packets
include committed notes/answers by default. Provide an understandable field-level
share preview and a remembered exclusion/redaction policy that also covers event
before/after values and discussion context. Preserve opaque IDs and revisions.
Make clear that a full backup is private recovery material and is not the review
attachment. Decide archive encryption/key recovery before depending on portable
exports in shared locations; a key kept only on the lost iPad is not a recovery
solution. This is a privacy/design decision, not a proposal to add cloud sync.

## Growth scenarios and acceptance targets

These are illustrative arithmetic, not measurements of the user's Sheet or iPad.
Existing historical rows must be added to the following future growth:

| Transactions per week | New records in ten years |
| --- | ---: |
| 50 | 26,000 |
| 100 | 52,000 |
| 200 | 104,000 |

At a hypothetical 1–3 KiB of serialized ledger data per transaction, 52,000
records alone take about 51–152 MiB before source copies, imports, manifests,
drafts, and discussions. This assumption must be replaced by measurements from
synthetic data matching the actual migration shape.

| Combined retained incoming files per week | Added base64 bytes in backup per year |
| --- | ---: |
| 25 KiB | about 1.69 MiB |
| 100 KiB | about 6.77 MiB |
| 250 KiB | about 16.93 MiB |

These figures exclude ledger/source-link duplication and every other field. They
show why growth depends on retained exchanges as well as transaction count.
Repeated full-history manifests also accumulate one revision-map entry for every
reviewed record each time, even when the ledger has hardly changed.

Benchmark 10,000, 50,000, and 100,000 synthetic records with years of weekly files,
notes, review actions, source updates, and open/resolved discussions. On the real
iPad measure launch, search/sort, editing latency, peak memory, archive size,
backup duration/retry, and isolated restore duration. A suggested initial target
is responsive ordinary editing with no perceptible serialization pauses, alongside
a published supported history envelope; choose exact time/memory thresholds from
device measurements. Include a state exceeding 50 MiB and continued editing while
backup runs. No accepted state within the supported envelope may lose its backup
or restore path.

## Recommended work order

1. **Recovery and capacity:** independent startup recovery, separate backup format
   and limits, safe state-capacity invariants, and an actual cloud-to-empty-store
   restore. Keep the previous good backup throughout replacement.
2. **Real data model and contracts:** privately inventory the Sheet and collector's
   output; settle taxonomy, allocations, reimbursement links, stable sources,
   source freshness, and structured coverage using synthetic equivalents.
3. **Migration and intake:** deterministic dry run, exact reconciliation report,
   cutover/overlap handling, and duplicate blocking on both addition paths.
4. **Growth and exchange:** indexed storage/compaction, bounded baseline/history
   review, rule history, and iPad benchmarks. Complete the manual ChatGPT round trip.

This changes sequencing and completeness of the selected local-first design; it
does not require moving the live database to iCloud, adding record sync, adopting
a hosted bridge, or replacing SwiftData before measurement supports that choice.
