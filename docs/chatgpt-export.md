# ChatGPT export and display tabs

Implemented in source on 2026-10-24. All development records are synthetic.
Portable rules have 50 passing Windows tests. The native table, new payload
fields, screens, and system share sheet still require the
[combined Mac/iPad/ChatGPT check](ipad-acceptance.md).

## Export on iPad

1. Open **ChatGPT export**. Choose All history, Last 8 weeks, or a custom inclusive
   date range. Choose a review filter or search payees, notes, answers, and tags.
   Alternatively, use the export icon in Transactions to start with just that
   table's current visible records.
2. Select/deselect individual records. Both optional context switches start off:
   **Include your notes and answers** and **Include assistant context and earlier
   ledger notes**. Turn them on only when that context belongs in the review.
3. Choose **Prepare Export**, then inspect the record count, observed dates,
   context settings, prompt, and exact JSON preview.
4. Choose **Save or Share All 3 Files**. In the iPad share sheet, choose **Save to
   Files** and a folder, such as one in iCloud Drive. Individual file share
   actions are available if a destination does not support sharing several files.
5. In the ChatGPT conversation you choose, attach the JSON and prompt text files.
   Ask ChatGPT to follow the attached review prompt. CSV is an optional readable
   companion. You can also select/copy the prompt text from FinTrack's preview.
6. Review the analysis and make any chosen changes manually in FinTrack.
   **Suggestion import, automated acceptance, and processing receipts are not
   implemented.** A returned file cannot yet be opened/applied by FinTrack.

FinTrack makes no model request, authenticates no ChatGPT account, and introduces
no LLM API usage. The manual workflow uses the user's existing ChatGPT session;
its account settings and upload/usage limits still apply. The app does not know
whether a share destination received a file or whether iCloud finished uploading.
Official documentation confirms attaching spreadsheets and data exports for
analysis: [Use ChatGPT: attach files](https://learn.chatgpt.com/docs/use-chatgpt).
This route was rechecked on 2026-10-24. Native subscription sign-in remains a
separate, unresolved integration option.

## Version 1 export contract

Three UTF-8 files share a randomly generated packet UUID in their names:

| File | Purpose |
| --- | --- |
| `review-<packetID>.json` | Exact structured snapshot and category definitions |
| `transactions-<packetID>.csv` | Readable spreadsheet companion |
| `review-prompt-<packetID>.txt` | Review instructions, scope, context settings, and limits |

JSON has `schemaVersion: 1`, `purpose: fintrack-review-export`, packet ID, UTC
export time, amount-sign convention, selected-record coverage disclaimer, earliest
and latest observed transaction dates, privacy options, category definitions, and
selected saved records. Observed bounds are not proof of continuous coverage.
The full available category catalog is included so analysis can use valid IDs.

Each record includes stable UUID, **base revision as a decimal string**, review/
posted date, optional activity date, payee, **minor units and decimal amount as
strings**, currency, posting, treatment, category ID, tags, Exceptional Event,
approval, and discussion state. It now also includes optional local source UUID/
label, category/individual-tag origins, and explicitly user-tracked discussion
progress as additive version 1 fields. Source aliases are not bank import
identities or account numbers. Unknown older source/origin values remain unknown.
String encoding preserves the full Int64 range
in JavaScript-based tools. There is no binary floating-point monetary conversion.
User notes/answers and assistant context are distinct optional fields; when their
switch is off, those keys and CSV columns are omitted. Their absence means
context was not provided, not that the user gave an empty answer.

CSV quotes every cell, doubles embedded quotes, and preserves Unicode, commas,
and multiline text. Text that could be interpreted as a spreadsheet formula is
prefixed with an apostrophe. Generated monetary numbers retain their sign.
JSON always retains the original exact text and is the canonical export.

The export excludes unsaved drafts, action history, internal storage payloads,
credentials, and unrelated records. Creating it does not save editor drafts,
change approval, increment revisions, or modify the ledger. A prepared preview
is a fixed snapshot; close and prepare a new export after later ledger edits.
Temporary files are created in an app-owned temporary UUID directory and removed
when the preview is normally dismissed. An interrupted process may leave temporary
files until the OS cleans them up. Copies saved/shared elsewhere remain there.

This is an export-only review contract, not the SwiftData serialization format,
bank import format, future proposal-import contract, or a backup archive.
Future imports still require validation, explicit acceptance, duplicate protection,
revision conflicts, persisted outcomes, and safe undo before they can edit records.

## Display tabs

| Tab | Current behavior |
| --- | --- |
| Overview | Selected-record posted and pending spending, review counts, category/month totals and record drilldowns; date scope; tag and Exceptional Event exclusions |
| Transactions | Approved sortable table with leading activity, source/origin pills, equal icon actions, search/date presets, Amalgamate, editor, recoverable drafts, and export of shown rows |
| Questions | Unanswered assistant questions or explicit discussion requests; optional discussion-only filter; opens the existing editor |
| Review history | Explicit saved Approve/Discuss/Reopen decisions, action IDs, timestamps, base/applied revisions, and links to current records; filters by **decision date** |
| ChatGPT export | Date/review/search selection, individual selection, privacy options, snapshot preview, and file sharing |

Overview exclusions affect display only. A record matching multiple exclusions
is omitted once. Without an explicit exclusion, tags/events do not remove spending.
Only spending/refund treatments with posted/pending status contribute; unknown
posting, income, transfers, payments, and credits do not. Categories use the
prototype's invented catalog. No missing months are filled with zero; there are
no complete-source claims, projections, or comparison percentages. Overflow
shows an unavailable-total message rather than a wrapped or rounded result.

History names reflect the current payee. The stored action history has no prior
field snapshots and is not a full edit audit log. Skip produces no decision.
Questions and discussion do not contact ChatGPT or imply remote processing.
Reimbursements, full taxonomy/splits, cloud connections, and the old website's
connection settings are not added by these display tabs.

SwiftUI uses Apple's native multi-file
[ShareLink](https://developer.apple.com/documentation/swiftui/sharelink/init(items:subject:message:label:)-piai).
No third-party dependencies or cloud capabilities were added. SwiftData schema
v2 remains unchanged; its domain payload now carries source/provenance/progress.

## One combined Mac/iPad acceptance session

Use [ipad-acceptance.md](ipad-acceptance.md) for the single current checklist.
It covers the Mac package suites, old-store preservation, the approved native
table, tab behavior, offline/draft/lifecycle checks, and an actual synthetic
file handoff with ChatGPT. Keep the existing store. Four new Apple persistence
tests verify the new payload fields and safe opt-in example append.

Record results in [device-verification.md](device-verification.md). Backup/restore
verification remains required before any real-data use.
