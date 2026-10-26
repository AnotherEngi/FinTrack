# Current financial-framework trial

**Real migration remains paused.** This revision replaces prototype formats and
must pass native/device validation first. Earlier Mac/iCloud passes were for the
previous model. Do not use old v1 migration files or old development backup readers.

1. Publish/pull the current batch and run the commands and combined synthetic
   checks in [framework-validation.md](framework-validation.md). Keep private
   records and credentials outside the checkout.
2. On the iPad, explicitly create a separate empty synthetic ledger if the app
   reports the retired development database. No automatic conversion or reset is
   performed. Verify current-format iCloud upload/download/restore for all new
   structures, not merely a scalar transaction amount.
3. Report the new native and device results. After acceptance, enable the current
   migration preview and prove the provided synthetic initial/refund pair end to
   end. This keeps the validation gate honest before introducing private records.
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
