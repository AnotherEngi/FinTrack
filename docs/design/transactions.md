# Transaction workspace design

**Status: approved transaction workspace baseline, 2026-10-24.** The user reviewed
the refined preview and confirmed, "Looks good. Let's lock that in."
The approved table has now been shown running on the user's iPad. The first
device review corrected pill placement to category/tags and identified native
width/spacing and export-discovery refinements; these source fixes await a new
device check.
The adjacent `transaction-table.html` is an interactive, synthetic design preview,
not a replacement app, web architecture decision, or live ledger editor.

## Approved baseline

Use the current refined preview as the visual reference for native implementation:

- No in-app branding bar, duplicated page title, permanent color legend,
  transaction/approval counts, or known USD label in this workspace.
- Top search, 1/3/6-month, YTD, past-year, and custom date controls.
- Amalgamate switch: on combines rows; off separates non-approved above approved.
- Thin leading activity column with an icon heading; aligned date, amount,
  merchant, source, category, tags, and action columns.
- Category and tag pills use orange for unaccepted assistant suggestions, blue
  for user edits, and green for approved values regardless of origin. Merchant
  text is always plain, including approved rows. This supersedes the initial
  merchant-pill interpretation, as explicitly clarified in the first iPad review.
- Equally sized check/undo, conversation, and pencil action buttons.
- Comfortable row spacing and a detail sheet for editing, as shown by default.

Earlier preview controls for merchant-pill placement, compact density, and
below-table editing remain exploratory alternatives, not the approved baseline.
Future user feedback can revise this baseline. Approval settles the visual
direction. Native implementation now includes local source aliases, category/tag
provenance, process-session markers, and user-tracked discussion progress. Actual
Mac/iPad validation and automatic processing integration remain separate work.

## Standing interface decisions

Screen space belongs to useful finance information and controls. **Do not add
an in-app FinTrack branding/header bar to working screens.** The app name and
icon in the OS launcher are separate from this decision. Do not repeat the active
tab's title as a second visible page heading. Treat this as continuing guidance
for the other tabs and future native UI work, not just a preview adjustment.

The transaction workspace has no permanent color legend, saved-record count,
approved count, or USD label. Known single-user context does not need repeated
labels. Keep currency explicit in the domain model and exchange files. Make
statuses understandable through consistent affordances, accessible names, and
contextual tooltips rather than adding a standing explanatory panel.

Compact presentation still needs usable touch targets and readable text.

## User-specified layout

- Main transaction workspace uses aligned table rows with **activity first**,
  followed by date, amount, merchant, source/card/account, category, tags, and
  row actions. Activity has an icon-only heading and a narrow fixed-width column
  (44px in the preview). Combined activity states share one accessible target.
- Orange category/tag pills identify an unaccepted LLM suggestion; blue identifies
  a user edit; green identifies an accepted classification regardless of origin.
  Merchants are neutral text. The user explicitly corrected the earlier merchant
  highlight after testing on iPad; the HTML reference now follows that correction.
- Each row offers equally sized icon-only Approve/Reopen, Discuss, and Edit
  buttons: check mark, return/undo arrow, conversation bubbles, and pencil.
  Accessible names retain the action names and transaction context. Edit opens
  a detailed view. Buttons retain equal widths even when disabled/not applicable.
- The activity column indicates changes this session and discussion pending or
  in progress. More than one state can coexist.
- Each data column can sort ascending/descending. The Review column sorts review
  state; Activity sorts activity state. Sorting uses underlying dates and exact
  amounts, not formatted currency/date strings. Break ties by stable record ID.
- A true toggle switch labeled **Amalgamate** combines the rows into one table
  when on. Off means non-approved rows in an upper table and approved rows below.
  Both tables use the same columns and sort setting, without group counts.
- Search appears at the top and matches merchant, source, category, tags, notes,
  assistant question, and ISO date; it is case/accent insensitive in the preview.
  The top date buttons are **1 month, 3 months, 6 months, YTD, Past year, Custom**.
  Custom reveals inclusive From/Through date fields and validates their order.
  Search/date filtering applies to both tables and is preserved when amalgamating.

The preview defaults to 1 month and Amalgamate off. Month/year presets use calendar
subtraction with end-of-month clamping; YTD starts January 1. The synthetic
reference date is fixed at 2026-10-24 so the preview remains useful later. The
native implementation should use the user's current calendar date. Twelve
invented records span December 2025 through October 2026 to exercise each preset;
the default view still shows the original eight October records.

## Behavior to preserve

Approve is an explicit per-record action covering the current classification and
tag set. It makes the category status indicator and existing tag pills
green. Reopen restores their underlying provenance colors instead of pretending
the previously accepted values were authored by the user. Suggestions, editing,
or comments alone never approve a record.

Category/tag and financial changes reopen approval; note/answer-only changes
preserve approval. Discuss requires the user's own context and preserves approval.
Pending charges cannot be approved. Payments, credits, transfers, and income
remain Not applicable for spending review. In the literal two-table grouping,
Not applicable rows are in the non-approved group with disabled approval controls, never counted
as approvable outstanding purchases. No bulk approval is implied by the layout.

Color is supported by accessible labels/tooltips. A blue activity marker can
coexist with green classification pills after approval. A discussion marker can
also coexist with approval; it must not imply the classification was reopened.
Existing valid-edit autosave, recoverable invalid drafts, revision checks, visible
write failures, and offline use remain requirements for the eventual SwiftUI view.

## Native model support and remaining integration work

| Area | Current app | Required next design/model work |
| --- | --- | --- |
| Source column | Optional local source UUID and per-record display label; weekly v1 intake adds separate scoped provider IDs and original/latest evidence | Actual bank adapters, real-history migration, and a global source catalog remain future work |
| Classification origin | Persisted category/tag origins; manual edits become user-origin, accepted assistant proposals retain assistant origin, approval/reopen retains origins | All populated values have pills; unknown historical authors remain unknown but display orange needs-review |
| Session marker | Successful distinct saves/actions register in the long-lived ledger model | Validate lifecycle behavior on iPad; never derive it from timestamps alone |
| Discussion waiting | Existing requests default to awaiting export; explicit Discuss records an action ID; open discussions remain in prepared reviews | Imported processing receipts are separate from this flag; sharing is not a receipt |
| Discussion in progress | An explicit Mark Reviewing in ChatGPT action persists the user's own workflow state | Automatic processing visibility still requires a settled integration |

Implemented session boundary: the current app process lifetime, retaining
markers through background/foreground transitions and clearing them on a fresh
launch. A named review batch or explicit reset can be a later refinement if
requested. The HTML preview uses its own
loaded lifetime and marks successful demo edits/review actions.

The latest user feedback supersedes the old neutral fallback: unknown historical
provenance stays unknown in data but displays an orange needs-review pill. Known
manual edits remain blue and approved classifications green. Never infer manual
ownership from the current revision or claim an unknown author was ChatGPT.
The category pill describes classification provenance/status. A bank's merchant
name is not an LLM classification and must not inherit category/approval colors.

## Preview and validation

Latest native additions: a thin question column after activity opens Discussions
and sorts open questions; activity stays session/draft-only. Minimum column width
is now 968 points (44 more than the earlier table). Separate up/down-arrow toolbar
actions open Send or Import. The existing HTML preview predates these additions;
use [current native flow](../review-flow.md) for discussion/export/overview design.

The preview has invented merchant/source names, amounts, categories, and tags.
It demonstrates mixed tag origins, accepted values of either origin, a pending
charge, a payment outside review, a waiting discussion, and an illustrative
in-progress discussion. It has no network/model request or native-store access.
No real financial records or credentials belong in this preview.

Try column sorting, Amalgamate, search/date filters, Approve/Reopen, Discuss, and Edit. Controls
for row density and detail-sheet versus
below-table details are available when the conversation host supports design
controls. Without them, the defaults follow the supplied direction. Demo edits
are in memory; only design/sort/grouping preferences may be retained by the host.
Native draft recovery and disk persistence are not simulated by this preview.

Browser checks exercised grouping and both amount sort directions, approval
movement/colors, note preservation, classification reopening, activity markers,
discussion preservation, pending/N/A restrictions, unfinished monetary input,
and Escape dismissal. The revised preview also passed checks for switch semantics,
44px leading status width, equal icon-button sizes, search across split groups,
all date presets, inclusive custom dates, and invalid-range feedback. Narrow layout was checked at 320px, with table overflow
contained horizontally and details fitting the viewport. Coarse-pointer action
targets were checked at 44px with no overlap. Light/dark screenshots were reviewed.
The local `file://` launch was also checked for UTF-8 and functioning controls.
These checks validate the design preview, not SwiftUI or iPad behavior.

The approved table and model support are now implemented. All 50 portable tests
pass on Windows, and ten native source/test files pass syntax parsing. The
SwiftData schema remains v2; its domain payload has backward-compatible optional
fields. Four new Apple persistence tests await Mac execution. Follow
[the combined native and ChatGPT checklist](../ipad-acceptance.md) next. No cloud
sync, LLM API, bank import, or AI suggestion import was added.
