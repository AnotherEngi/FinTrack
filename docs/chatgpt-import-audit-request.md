# Next request to the finance ChatGPT workflow: audit and separate refunds

FinTrack's real migration is paused until its full financial framework and new
import contracts are implemented and validated. **Do not generate a v1 history
import, invent new JSON fields, or attempt the real import yet.** This request is
for source inspection and an accountable migration plan. Do not modify the Sheet.

Use only the workbook/export and connections you actually have access to. State
access, hidden/filtered data and coverage limitations. Do not claim access to
uninspected conversations, external files, account services or historical rules.
Keep all real records and private audit output outside the public source repo.

## Inspect the complete financial meaning

Inventory all relevant tabs, rows/columns, formulas/helper values, category and
subcategory definitions (including unused entries), splits, reimbursement and
benefit settings, actual repayment relationships, source identities, complete
pending/posted/superseded facts, historical approvals, notes and author ownership,
current questions, reporting rules, source coverage and accepted global guidance.
Flag missing/ambiguous information instead of filling it with invented defaults.
Global rules belong in global configuration/knowledge, not repeated row notes.

Identify every field or behavior that cannot yet be represented. The updated app
must implement structured financial behavior; merely archiving split or benefit
text does not satisfy that prerequisite. Preserve unknown values/authorship and
report unsupported global settings. Formula text, formatting and workbook layout
are not recreated by a transaction import; explain their financial consequences.
FinTrack will not copy, fingerprint, reference or manage the original workbook;
the user retains it separately. Do not request that feature in the new contract.

## Separate merchant refunds for later import

- Identify merchant-refund rows and place them in a separate **deferred refund
  set**, excluded from the proposed initial history file but never discarded.
  Preserve their real receipt dates, amounts/currency, identities, source row
  locations, notes, classifications, evidence and known purchase relationships.
- Do not classify payment-equivalent statement credits, reimbursement receipts,
  income, transfers or ambiguous credits as merchant refunds merely because
  their amounts are negative. Keep their distinct meanings; flag ambiguity.
- The initial purchases must retain **original gross amounts**. Identify any
  purchase cells/helpers already reduced by refunds or linked credits. Recover
  gross amounts only from actual evidence. Otherwise stop and ask; do not guess
  or export already-netted amounts that would be reduced a second time later.
- Preserve stable generated app UUIDs for original purchases once the new
  contract assigns them. Those UUIDs are distinct from genuine provider IDs.
  Later refund allocations will reference the original purchase UUIDs. Never
  invent a bank ID from a Sheet row number or merchant/date hash.
- Later linked refunds reduce the original purchase dates/categories while
  keeping the actual refund receipt dates. Preserve partial/multiple/unlinked
  refund cases; do not guess links. Unlinked cases need explicit later review.
- Wait for FinTrack's revised **dedicated refund-import contract** before
  serializing the deferred set. Do not substitute weekly intake, another partial
  history migration, or a backup for it. Until refunds arrive, the app will show
  gross purchases; explicitly explain the resulting temporary comparison gap.

## Approval, retention and reporting choices

- A transaction with a current unresolved question is **unapproved**, even if
  earlier classification approval evidence exists. Preserve that historical
  evidence separately, including known origin/time, without inventing either.
  Do not clear a current question merely because an old approval was found.
- Keep user notes/answers, assistant questions/reasons, earlier ledger notes and
  mixed/unknown authorship distinguishable. Known resolved assistant questions
  follow the explicit cleanup policy; do not duplicate them in archival fields.
- Reporting timezone is **America/New_York**; weeks start **Monday**.
- “6 months” is the current partial calendar month plus the prior five full
  months. Through October 25, 2026, this is May 1–October 25, inclusive.
- Report source timezone/period/treatment differences explicitly. Do not shift
  an already date-only value as though it were a UTC timestamp, or silently
  rewrite source classifications or historical report totals.

## Return now

Return an audit identifying supported structures, missing information, every
potential omission/transformation, and questions that need the user's decision.
Provide independent debit, credit, net, spending, per-source, per-tab and
per-treatment controls, with their sign/date/status bases stated.

Account for every candidate source row in exactly one partition: initial active
record, retained historical/superseded record, deferred merchant refund, or
explicit exclusion with a reason. Account for every column as mapped, preserved
or explicitly omitted. Reconcile the partition counts and totals to the complete
original source, not just to your own exported subset. Show deferred-refund totals
separately so that omissions cannot masquerade as a reconciled initial import.

Do not produce import-ready financial JSON until the revised contracts are
provided. FinTrack cannot independently prove that you inspected every source
cell; clearly identify what the user should compare against the original.
