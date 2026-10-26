# Current financial-framework trial

The user reports that the corrected Mac tests and app build pass. The normal
initial-history and deferred-refund import actions are now enabled, allowing
current-contract synthetic files to complete preview, confirmation, commitment
and replay testing. There is no fixture-only path or test switch. Actual real-data
intake should wait for device/backup verification and private source reconciliation.
Do not use old v1 migration files or old development backup readers.

1. Publish/pull the current batch and run the commands and combined synthetic
   checks in [framework-validation.md](framework-validation.md). Keep private
   records and credentials outside the checkout.
2. On the iPad, explicitly create a separate empty synthetic ledger if the app
   reports the retired development database. No automatic conversion or reset is
   performed. Verify current-format iCloud upload/download/restore for all new
   structures, not merely a scalar transaction amount.
3. Prove the provided synthetic initial/refund pair end to end through the normal
   enabled import actions, including replay without duplicates. Report the new
   native and device results before introducing private records.
4. Give your finance-review ChatGPT workflow the
   [new migration request](chatgpt-history-migration.md),
   [current contracts and examples](contracts/financial-framework.md), and your
   private source. Review complete independent source controls and every blocker /
   omission. Never share the real source with this public repository or coding tests.
5. Import one complete gross non-refund history into a separate ledger. Verify the
   private audit and catalog/program/claim/source context. Confirm its latest full
   iCloud backup and a downloaded-current-archive restore before regular intake.
6. Prepare the dedicated complete deferred-refund supplement against fresh exact
   purchase revisions. Confirm actual purchase/category attribution and compare
   gross, adjusted purchase-date totals and original source baselines. Re-import
   identical files must do nothing; changed facts require explicit reconciliation.
7. Trial a genuine weekly file: review coverage, new provider IDs and ambiguous
   pending/posted matches; preserve manual edits. Send pending feedback by Copy /
   Paste, read answers in Discussions, and explicitly review actual proposed edits.

Clipboard cap is 256 KiB, with complete JSON-file fallback up to 50 MiB. Full
current archives use a separate framed `.fintrack` path. Nothing is silently
truncated or split into independent partial histories. Keep the original workbook
privately yourself; FinTrack does not manage it.

The existing one-initial-history-per-ledger protection remains. Before the
synthetic initial import, save a full checkpoint of the starting ledger that has
no initial-history receipt. After completing the synthetic trial, restore that
pre-import checkpoint before importing the real initial history. Restore activates
a separate verified store; the synthetic ledger remains preserved. An identical
history replay is a no-op, and a changed/different initial migration is still
rejected in a ledger whose initial history is already established. No synthetic
record or test setting should be merged into the real history.
