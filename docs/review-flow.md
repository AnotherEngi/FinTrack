# Discussions, review files, and spending views

Updated from physical-iPad feedback on 2026-10-24. The user confirmed separate
discussion/record-change flows and category/month/year spending visualizations.

## Color correction

Every populated category/tag now has a pill: orange needs review, blue is the
user's edit, green is approved. The oldest examples lacked provenance; the app
previously left them uncolored. Those values now show orange while their stored
author remains unknown. Nothing rewrites old transactions or guesses their author.
New fictional examples explicitly identify their simulated assistant suggestions.
Missing categories needing classification show an orange Choose category pill;
optional absent tags and excluded treatments do not invent classifications.

## Two different kinds of ChatGPT output

**Discussion answers** explain or ask for context. They have no accept/reject
action and cannot change a transaction. Examples: you ask why a purchase was
classified a certain way; ChatGPT explains. ChatGPT asks whether a shop purchase
was groceries or household supplies; you answer with that factual context.

**Proposed category/tag changes** compare the current and proposed values.
Apply changes saves an explicit revision-checked edit; Keep current dismisses the
proposal. Neither approves the transaction. Applying a changed classification
reopens approval as before. Plain explanations/no-op proposals in old response
files display as replies rather than asking for meaningless acceptance.

New response JSON has an additive `answers` array: id, recordID, exact string
expectedRevision, text, optional questionForUser. These IDs/revisions must match
the sent manifest. The embedded return template now explicitly shows `answers: []`.
Older v1 files remain readable/idempotent; absent optional fields decode safely.
The original category/tag proposal contract remains for genuine record changes.

Importing a validated response now records its matching processing acknowledgement
automatically. It does not accept changes, approve transactions, or close a
discussion. Only acknowledged operation IDs clear; later edits remain pending.
Older unacknowledged imported files retain a Mark Response Received action.

## Discussions tab and transaction question column

Discussions replaces the ambiguous Questions tab. It shows both directions with
states: ChatGPT is asking you, ready to send, waiting for ChatGPT, ChatGPT replied,
and resolved. Search includes conversation text; filters expose open, your reply,
ready, received, or resolved discussions. There is no implicit network connection.

1. Use a transaction's conversation button to ask a question. A thin question
   column beside activity opens the associated discussion; a resolved icon retains
   its history. Activity remains a session/draft marker. The question column sorts
   open discussions separately.
2. Draft text saves locally/offline, including in full backups. Save Reply for
   ChatGPT commits a user message and queues it with feedback. Uncommitted reply
   drafts stay out of review packets. A stale draft is retained until the user
   explicitly reviews/rebases it to the latest record.
3. Prepare Review for ChatGPT opens the sending flow. Share the prepared JSON
   manually in the chosen ChatGPT conversation. Import reply is a separate down-
   arrow action in Transactions and Discussions.
4. Imported answers appear without acceptance buttons. Read, reply, or Mark
   Resolved. Resolve preserves approval and closes only that discussion; a new
   question/message reopens it. Unrelated classification proposals do not reopen
   a previously resolved discussion.

The packet includes earlier user messages and replies as discussion context.
Messages/closure/drafts are additive optional workspace payload fields; the
SwiftData V3 entity schema is unchanged. A new resolveDiscussion action is stored
in review history. Older app binaries do not understand that action; do not
downgrade after saving new actions.

## Send, import, and backup are separate pages

Review & backup has Send to ChatGPT, Import reply, and Backup pages. The up-arrow
prepares/shares outgoing work; the down-arrow imports replies/weekly data. The
backup status strip opens Backup directly.

Choosing Review with ChatGPT or Full History Review freezes that prepared file
and disables both choices. Its heading explicitly identifies Pending feedback
and questions or Full history review. Start Another Review clears the local
selection without losing pending work. If saved state changes, a note explains
that the prepared file is an older snapshot; it is never silently swapped.

Export Full Backup opens the Files save dialog immediately, independent of any
automatic iCloud folder selection. Cancel leaves data intact. The old implementation
only created a file and changed a section higher up the page, explaining the
apparent no-op. Saving a manual file is separate from automatic cloud confirmation.

## Overview

The overview now uses native Swift Charts, not a list of review counts:

- Category bars show where posted spending goes, including negative refund totals.
- Monthly bars show observed spending through time.
- Calendar-month lines/points compare available years. Missing months break line
  segments; they are never filled with invented zeroes. Partial years have explicit
  coverage limits, not misleading percentage comparisons.

Totals/grouping remain exact integer minor units. Charts receive integer coordinates;
no floating-point accounting totals are introduced. Pending charges stay separate.
Date presets/custom dates and category/tag/Exceptional Event exclusions affect
display only. Tap category/month values to inspect their actual transactions.

Use Add Synthetic Chart Examples in Overview's secondary toolbar actions to
append fictional prior/current-year data. At 2026-10-24 this adds 66 records.
Stable IDs make repeat loads harmless and preserve edits. Nothing loads implicitly.

Native chart APIs follow [Apple's chart interaction documentation](https://developer.apple.com/videos/play/wwdc2023/10037/).
Windows verifies portable models/contracts; SwiftUI/Charts/SwiftData/file-save UI
still require the [combined Mac/iPad check](ipad-acceptance.md).
