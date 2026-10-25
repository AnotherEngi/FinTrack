# FinTrack: Requirements Before the One-Time History Import

## Purpose and scope

Update FinTrack's data model, import contract, editor, reporting, and backup/export behavior so a one-time migration can preserve the source's financial meaning.

This document contains framework requirements only. It contains no real transactions, account identities, balances, source identifiers, or private benefit amounts. Develop and test with synthetic fixtures. Real financial files must remain outside the public repository.

These requirements were identified against the supplied history-import specification. They are not a code review of the current application. Verify which capabilities already exist, implement the gaps, and return an updated import specification before the real migration is generated.

The initial migration is one complete history import. Weekly intake and app backup are separate contracts and must not substitute for it.

## 1. Structured category allocations and subcategories

- Support a category/subcategory catalog with stable identifiers, exact labels, definitions, and explicit unresolved/excluded states.
- Retain unused catalog entries and category definitions supplied by the source.
- Support multiple category allocations within one parent transaction.
- Each allocation must identify its category, optional subcategory, and exact amount in integer minor units.
- Allocation amounts must reconcile to the parent amount under documented sign rules.
- Reports must aggregate allocations rather than count the parent and allocations as separate spending.
- Editing, filtering, reporting, backup, export, and ChatGPT review context must support the structured fields.
- Preserve category/tag provenance where known; unknown authorship remains unknown.

Read-only preservation of split or subcategory text does not meet this requirement.

## 2. Reimbursements and benefit settings

Support structured benefit/program settings, including:

- Program identity and label.
- Recorded limit and currency.
- Applicable period and eligibility rules when known.
- Explicit unknown/unspecified values rather than invented defaults.

Support transaction-level reimbursement information, including eligibility, expected amount, claim status, received amount, outstanding amount, and links to actual repayments. Support partial repayments and repayments covering multiple expenses, with allocation checks that prevent double counting.

Keep gross spending, reimbursement receipts, and any net-cost view distinguishable. Expected reimbursement must not reduce spending or be treated as money received. Import and preserve the source's reimbursement settings and defaults.

## 3. Transaction lifecycle and typed relationships

Retain superseded pending records as history rather than discarding their original facts.

- Represent pending, posted, unresolved, and superseded lifecycle states without disguising superseded records as payments or transfers.
- Preserve each version's original amount, dates, source identity, notes, and approval evidence.
- Link predecessors to successors explicitly.
- Exclude superseded versions from active spending calculations.
- Allow the posted amount and description to differ from the pending version.
- Keep uncertain duplicate relationships unresolved until supported by evidence.

Relationships must distinguish pending successors, payment counterparts, and original-purchase refund links. A generic related ID must not automatically become a refund allocation.

## 4. Refunds, credits, and reporting attribution

- Distinguish merchant refunds, payment-equivalent statement credits, repayments, income, transfers, and unresolved credits.
- Support refund allocations against actual purchases, including partial refunds and multiple allocations.
- Validate currency, sign, eligible purchase status, and cumulative allocation limits.
- Preserve real refund receipt dates independently of purchase dates.
- Preserve unlinked refund candidates and unresolved classifications without inventing purchase links.
- Support a review workflow for linking or resolving them later.

The import must retain the source's historical refund treatment and attribution basis. If FinTrack normally attributes refunds to purchase dates but the source reports them on refund dates, expose and reconcile that difference before import. Provide an explicit legacy attribution mode or another documented representation that retains the source meaning. Do not silently rewrite historical monthly/category results.

Statement credits equivalent to payments must remain excluded from spending reductions.

## 5. Approval history, notes, and review ownership

Keep current reporting eligibility separate from historical user decisions.

- Preserve earlier user approval of classification even when a transaction is pending, later superseded, or excluded from spending.
- Store the approval evidence, decision origin, and known decision time separately from current review/posting status.
- Do not infer explicit approval from provider confidence, populated categories, or unclear reviewed flags.
- Keep user notes, user answers, assistant questions, assistant reasons, and earlier ledger explanations in separate fields.
- Preserve original text and ownership where demonstrated. Retain uncertainty where ownership cannot be established.
- Support unresolved discussion independently from historical decision evidence.
- Apply resolved-question cleanup only under the explicit retention policy. Retain user text and earlier ledger notes; do not duplicate intentionally cleared assistant questions in archival fields.

The import contract must accommodate mixed source columns without forcing all text into one author role.

## 6. Global knowledge and reporting configuration

Import supported source settings as structured configuration or global knowledge, including:

- Category definitions and accepted classification guidance.
- Account aliases and source identity mappings.
- Pending, payment, transfer, and statement-credit treatment rules.
- Exceptional-event and visibility behavior.
- Reporting time zone, report date, and period definitions.
- Distinctions between calendar periods, month to date, and completed rolling periods.
- Source coverage and freshness limitations.

Global rules must not be repeated in individual transaction notes. Record provenance when known; do not invent an origin for source documentation.

Knowledge import must not claim to include historical conversations or external review files that were never inspected.

## 7. Archival source fields and source-document preservation

Preserve unmodeled details using the existing preserved-fields mechanism or an equivalent supported structure:

- Provider descriptions, merchant fields, category/detail codes, and confidence.
- Genuine transaction/account identifiers and original account-label mappings.
- Full original timestamps, source lineage, and decision-maker evidence.
- Original treatment/status text when normalized into multiple app fields.
- Cached helper values and source allocation details.

Use distinct audited column names, qualifying repeated headers by tab and location. Preserve absent values consistently. Archival fields must survive editing, backup, export, and relevant ChatGPT review context.

Clearly distinguish archival fields from fields driving calculations. Archived helper values do not reproduce live spreadsheet formulas.

Allow the original workbook/export to be retained privately with the migration record, or explicitly referenced as a separately retained source artifact. Spreadsheet styling, formulas, table behavior, frozen panes, filters, and layout are not automatically reproduced by a transaction import. Document which reporting behavior is recreated and which presentation details remain only in the source artifact.

## 8. Versioned import contract and validation

Publish an updated, complete import specification covering all supported structures above. Version incompatible schema changes explicitly. Do not require the migration producer to invent unsupported JSON properties.

Retain these existing protections:

- Exact integer minor-unit strings, explicit signs, and supported currency validation.
- Separate genuine source identities from generated app UUIDs.
- Stable migration/row IDs and unchanged contents when replaying the same migration.
- Explicit reconciliation of changed facts rather than silent overwrites.
- Complete per-column handling and per-row accounting.
- Imported, archived/superseded, and excluded records distinguishable in the receipt.
- Original financial rows never silently deduplicated.
- Unknown financial meaning represented as unresolved rather than fabricated.
- Full source/date/status coverage and omissions recorded.
- Independent debit, credit, net, spending, per-source, per-tab, and per-treatment controls.
- A preview showing unsupported fields, transformations, exclusions, and reporting differences before commitment.
- Atomic import: validation failure must not leave a partially imported history.
- Safe replay handling and a recoverable pre-import backup or rollback mechanism.

Support one complete file within the documented file-size limit. Clipboard limits must not cause truncation or silently produce multiple partial-history imports.

## 9. Acceptance checks before the real import

Use synthetic integration fixtures to demonstrate:

1. A split purchase is counted once and allocated correctly across categories and subcategories.
2. Expected reimbursement leaves spending unchanged; partial and combined repayments reconcile correctly.
3. Pending-to-posted replacement preserves both versions while counting only the active eligible version.
4. Historical classification approval survives lifecycle changes without falsely confirming current posting eligibility.
5. Partial, multiple, and unlinked refunds retain their dates and treatment; reporting attribution differences are explicit.
6. Payment-equivalent credits and transfers do not reduce spending.
7. User notes, answers, assistant context, and unknown provenance survive import and export with correct ownership.
8. Catalog definitions, unused categories, settings, and global knowledge survive backup/export.
9. Every source row/column has an accountable disposition; independent control totals reconcile.
10. Replaying a migration creates no duplicates; invalid input causes no partial write.
11. A backup/export round trip retains all supported financial structures, archival fields, and relationships.

Return the revised import contract, supported-capability checklist, synthetic validation results, and any remaining limitations. Keep the real import paused until financial data or behavior would no longer be silently lost.
