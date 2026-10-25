# Instructions for ChatGPT: migrate the household Sheet into FinTrack

Give this document to the finance-review ChatGPT conversation that can actually
read your Sheet, or attach a private Sheet export there. Real financial files
must stay outside the public FinTrack repository. This document contains only
synthetic examples. Do not change the original Sheet during migration.

## Task

Inspect the complete workbook/export carefully before producing data. Inventory
every tab, header, nonempty financial row, hidden row/column, active filter,
formula-derived value, category/subcategory, tag, split, reimbursement, source
identifier, note, question/answer, review status, and refund relationship that
you can actually access. State which parts you could not inspect. Do not claim
that a connector returned the whole workbook unless you verified its coverage.
Do not invent access to files, conversations, accounts, or memories.

First return a concise migration audit and ask about ambiguous financial
meaning. Then produce ONE complete UTF-8 JSON object matching the schema below.
For a small export, put JSON directly in the message so I can copy it into
FinTrack. Also provide a downloadable `.json` file for larger histories. Never
use ellipses, truncate rows, or substitute a download URL for JSON text.
FinTrack's clipboard transport accepts 256 KiB; file imports accept 50 MiB.
If the complete result exceeds a limit, say so and provide a file within the
file limit or stop for an agreed batching design. Do not send independent
partial history files: this importer is one initial migration, not an append API.

## Required sanity check: nothing silently lost

Compare the output with the original, not merely with your own generated JSON.

1. Count original candidate data rows in every relevant tab. Record each source
   row exactly once as an imported `sourceRow` or an explicit excluded row with
   a reason. Do not count headers. Explain blank/filter/duplicate/nontransaction
   exclusions; never silently deduplicate a financial row.
2. Inventory **every source column**, including hidden/helper columns. Give each
   a distinct `audit.columns` entry: `mapped`, `preserved`, or `omitted`. Include
   a clear explanation and target. If one column feeds several meanings, preserve
   its original value and explain the derivation. Never disguise unsupported
   data as a mapped field. If headers repeat, qualify them with their tab/header
   location rather than merging two columns.
3. Include unmodeled financial fields in each row's `preservedFields`, using
   their exact audited column names and string values (empty string when absent).
   Include all columns classified `preserved` on every row. These fields are
   backed up, visible read-only in the editor, and included in relevant ChatGPT
   review context. They **do not drive app calculations**. Do not duplicate
   resolved assistant question/reason text in preserved fields.
4. Flag every omitted field, inaccessible tab, ambiguous sign/date/status,
   missing real source ID, lost formatting/formula semantics, unsupported
   structure, transformed value, and any other potentially lost detail. Explain
   whether it affects financial totals, classification, review state, or display.
   Never claim a lossless migration based only on counts or a successful parse.
5. Independently compute the included rows' net total after the explicit sign
   conversion below, using exact decimal/integer arithmetic. Put exact cents as
   `audit.netAmountMinorUnits`. Also report per-tab, per-source, per-treatment,
   date-span, debit and credit subtotals for my comparison with the Sheet. The
   audit warnings should also retain a concise textual version of those control
   totals/coverage so the app keeps that context with the migration receipt. The
   importer checks row counts and the net control total; it cannot independently
   verify your access to the source Sheet or every cell mapping.
6. If essential data cannot be represented faithfully, **stop and report it**.
   Do not discard an ambiguous financial row merely to make a valid JSON file.

Current calculation limits: USD only; one category per transaction; structured
subcategories, spending splits and reimbursements are not yet live app features.
Preserve their complete source details and amounts, flag their consequences, and
do not duplicate parent spending into extra transaction rows. Category/tag/row
visibility is supported. Linked merchant refunds are supported and reduce the
original purchases' dates/categories. Unlinked refunds remain flagged for linking.
Expected reimbursement is not repayment and must not reduce spending.

If the source actually includes accepted classification/merchant guidance, include
it as optional top-level `knowledge`: an array of `{id, text, origin}` rules with
distinct UUIDs, nonblank text up to 10,000 characters, and at most 1,000 rules.
Use origin `user` or `assistant` only when known; otherwise use `unknown`. Do not
invent new accepted rules during migration. Report unsupported global settings
or inaccessible historical learnings as limitations requiring follow-up; do not
claim they were imported. Do not insert global rules into transaction notes.

## Encoding rules

- `schemaVersion`: 1. `purpose`: `fintrack-history-import`.
- `id`: new UUID for this complete migration. Each row gets a distinct app UUID,
  generated once and reused in the final JSON and any refund references. Retrying
  the same migration must keep all IDs and contents stable. These are app IDs,
  **not invented bank transaction IDs**.
- `amountSignConvention`: `outflow-positive-v1`. Spending is positive, refunds
  and income negative. Determine other treatment signs from actual source facts;
  do not negate everything based on column names alone. No currency conversions.
- `amountMinorUnits`: exact base-10 integer **string** of cents, e.g. `"1234"`.
  No floats, decimal points, currency symbols, separators, or leading zeros.
- Dates: `YYYY-MM-DD`. `date` is posted/review date; preserve a known original
  purchase/activity date separately as `activityDate`, otherwise `null`.
- `sourceName`: descriptive private workbook/export alias, not credentials or a
  sharing URL. `sourceRow`: unique locator such as `Ledger!42` for audit purposes.
- `sourceLabel`: stable account/card alias without account numbers, or `null`.
  `sourceTransactionID`: genuine provider transaction ID, or `null` if unavailable.
  Never use a Sheet row number, merchant/date hash, or new UUID as a bank ID.
  Keep aliases and genuine IDs identical for later weekly imports.
- `postingStatus`: `posted`, `pending`, or `unresolved`.
- `treatment`: `spending`, `refund`, `income`, `payment`, `statementCredit`,
  `transfer`, or `unresolved`. Do not guess ambiguous accounting meaning.
- `categories`: complete actual catalog for the imported records. Use stable IDs
  (up to 120 characters), exact labels (up to 200), and explicit `unresolved` and
  `excluded` booleans. Do not map the household's categories into sample categories.
  Mark unresolved placeholders appropriately. `categoryID` must reference this
  catalog, or be `null` when genuinely unclassified.
- `tags`: complete array, at most 20 distinct nonblank strings per transaction,
  each at most 80 characters. If source limits exceed these, stop and flag it.
- `notes` and `answer`: user-authored text. `assistantContext` holds only the
  current assistant question/reason and earlier ledger notes in separate fields.
  Preserve ownership; do not rewrite user notes as assistant text or vice versa.
- `approval`: `confirmed` **only** for documented, explicit prior user approval
  of this transaction's actual classification. `approvalEvidence` must identify
  the source field/value proving it. Do not infer from categorization, confidence,
  a generic reviewed checkbox of unclear meaning, or an assistant assertion.
  Otherwise use `unreviewed` and empty evidence. Excluded treatments require
  `notApplicable`. Pending/unresolved transactions cannot be confirmed.
  Confirmed rows cannot also request discussion. Resolved assistant questions
  and reasons are cleared on import under the user's retention decision; earlier
  ledger notes and user notes/answer remain. Mention that intentional cleanup.
- `classificationProvenance.category`: `user`, `assistant`, or `unknown`.
  Its `tags` dictionary maps known tag strings to the same origin values. If the
  source does not prove who authored something, preserve `unknown`; do not guess.
- `discussionRequested`, `exceptionalEvent`, `hiddenFromSummary`: explicit
  booleans. Exceptional events remain spending. Visibility never deletes data.
- `refundAllocations`: `null` or array of `{purchaseID, amountMinorUnits, currency}`.
  Use positive cents linked to actual earlier posted spending row UUIDs. Total
  links cannot exceed either the refund or the original purchase, including other
  refunds. Preserve real bank receipt dates. Never guess a purchase relationship.
- `preservedFields`: dictionary of audited original financial details as strings.
  Do not use keys beginning `FinTrack:` (reserved). Max 500 fields; each value at
  most 1,000,000 UTF-8 bytes. List omitted sensitive credential fields in the audit
  without including their values. Financial source files remain private.

Allowed `mapped` targets are the row field names above, except `preservedFields`,
plus `assistantContext.question`, `assistantContext.reason`,
`assistantContext.ledgerNotes`, `classificationProvenance.category`, and
`classificationProvenance.tags`. Use target `preservedFields` for preserved columns
and an empty target for omitted columns. All entries require explanations.

## Synthetic schema example (replace all example values)

```json
{
  "schemaVersion": 1,
  "purpose": "fintrack-history-import",
  "id": "11111111-1111-4111-8111-111111111111",
  "amountSignConvention": "outflow-positive-v1",
  "sourceName": "Fictional household Sheet",
  "categories": [
    {"id": "groceries", "label": "Groceries", "unresolved": false, "excluded": false}
  ],
  "rows": [
    {
      "id": "22222222-2222-4222-8222-222222222222",
      "sourceRow": "Ledger!2",
      "date": "2026-03-01",
      "activityDate": null,
      "merchant": "Fictional Market",
      "amountMinorUnits": "1234",
      "currency": "USD",
      "sourceLabel": "Fictional Card",
      "sourceTransactionID": null,
      "postingStatus": "posted",
      "treatment": "spending",
      "categoryID": "groceries",
      "tags": [],
      "notes": "",
      "answer": "",
      "approval": "unreviewed",
      "approvalEvidence": "",
      "discussionRequested": false,
      "assistantContext": {"question": "", "reason": "", "ledgerNotes": ""},
      "classificationProvenance": {"category": "unknown", "tags": {}},
      "exceptionalEvent": false,
      "hiddenFromSummary": false,
      "refundAllocations": null,
      "preservedFields": {"Subcategory": "Fictional pantry"}
    }
  ],
  "audit": {
    "sourceRowCount": 1,
    "netAmountMinorUnits": "1234",
    "columns": [
      {"name": "Date", "handling": "mapped", "target": "date", "explanation": "Original posted date"},
      {"name": "Merchant", "handling": "mapped", "target": "merchant", "explanation": "Original merchant text"},
      {"name": "Amount", "handling": "mapped", "target": "amountMinorUnits", "explanation": "Exact conversion to positive outflow cents"},
      {"name": "Category", "handling": "mapped", "target": "categoryID", "explanation": "Catalog preserves original category label"},
      {"name": "Subcategory", "handling": "preserved", "target": "preservedFields", "explanation": "Read-only; not used as a live subcategory"}
    ],
    "excludedRows": [],
    "warnings": ["Synthetic schema example only; bank IDs unavailable; subcategory reporting is not implemented."]
  }
}
```

## Subsequent weekly trial

After migration, retain the category ID/label mapping and source aliases from
this export. For a small first trial, fetch a bounded date range from only the
authorized sources you actually have. Report source/date coverage and omissions.
Return a **weekly intake**, not another history migration and not an app backup:

```json
{
  "schemaVersion": 1,
  "purpose": "fintrack-weekly-intake",
  "id": "33333333-3333-4333-8333-333333333333",
  "coverage": "Describe actual sources, inclusive dates, pending/posted coverage and any omissions. This example contains no real records.",
  "transactions": [
    {
      "identity": {"sourceAlias": "Fictional Card", "transactionID": "genuine-provider-id-required"},
      "date": "2026-03-08",
      "activityDate": null,
      "merchant": "Fictional Bakery",
      "amountMinorUnits": "500",
      "currency": "USD",
      "postingStatus": "posted",
      "treatment": "spending",
      "categoryID": "groceries",
      "tags": []
    }
  ]
}
```

Use real provider IDs in actual data, never the example literal. If provider IDs
are unavailable, stop and report that rather than inventing IDs. A replay of the
same file must retain its file ID and facts. An actual later provider update uses
a new file ID and the same transaction identity. FinTrack requires explicit
reconciliation for changed facts, pending-to-posted variants, and plausible
duplicates; it does not infer source chronology or overwrite user notes/tags.
Copy the complete JSON message and use Paste in FinTrack's Import reply screen,
or import its `.json` file. Do not include extra prose inside the JSON.
