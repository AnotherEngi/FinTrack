import SwiftUI
import FinTrackCore

extension LedgerReviewFilter {
    var label: String {
        switch self {
        case .all: "All transactions"
        case .unreviewed: "Unreviewed"
        case .discussion: "Needs discussion"
        case .approved: "Approved"
        case .pending: "Pending"
        case .excluded: "Outside spending review"
        case .questions: "Questions or discussion"
        }
    }
}

@MainActor
struct ReviewExportView: View {
    @Bindable var ledger: LedgerViewModel
    /// When opened from Transactions, constrain the export to that visible set.
    var initialIDs: Set<UUID>? = nil
    var showsDone = false
    @Environment(\.dismiss) private var dismiss
    @State private var scope = DisplayScope()
    @State private var filter = LedgerReviewFilter.all
    @State private var search = ""
    @State private var omittedIDs: Set<UUID> = []
    @State private var options = ReviewExportOptions()
    @State private var prepared: PreparedReviewExport?
    @State private var preparedDirectory: URL?
    @State private var failure: String?

    private var candidates: [LedgerTransaction] {
        var selection = scope.selection
        selection.search = search
        selection.reviewFilter = filter
        selection.categoryLabels = Dictionary(uniqueKeysWithValues: ledger.catalog.categories.map { ($0.id, $0.label) })
        return selection.records(in: ledger.records.filter { initialIDs?.contains($0.id) ?? true })
    }
    private var selected: [LedgerTransaction] { candidates.filter { !omittedIDs.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                Section("Choose saved records") {
                    Text("Synthetic development data only").font(.callout).foregroundStyle(.secondary)
                    if initialIDs != nil {
                        Text("Starting with the transactions shown in Transactions.").font(.caption)
                    }
                    DisplayScopeControls(scope: $scope)
                    Picker("Review filter", selection: $filter) {
                        ForEach(LedgerReviewFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    LabeledContent("Selected / matching", value: "\(selected.count) / \(candidates.count)")
                    Button("Select All Matching") { omittedIDs.subtract(candidates.map(\.id)) }
                        .disabled(candidates.isEmpty)
                    Button("Deselect All Matching") { omittedIDs.formUnion(candidates.map(\.id)) }
                        .disabled(candidates.isEmpty)
                }
                Section("Context to include") {
                    Toggle("Include your notes and answers", isOn: $options.includeUserContext)
                    Toggle("Include assistant context and earlier ledger notes", isOn: $options.includeAssistantContext)
                    Text("The selected records include payees, dates, amounts, source labels/local IDs, categories, tags, origins, and review/discussion state. These switches add the separately owned notes. Unsaved drafts and action history are never exported.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Prepare Export (\(selected.count) Records)", systemImage: "square.and.arrow.up") { prepare() }
                        .disabled(selected.isEmpty || !scope.isValid || ledger.startupFailure != nil)
                    Text("Preview first, then choose Save to Files or share. FinTrack makes no network request. Saving to iCloud Drive is a manual file copy; this is not a backup or sync.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Select individual records") {
                    if candidates.isEmpty { Text("No saved transactions match this selection.").foregroundStyle(.secondary) }
                    ForEach(candidates) { record in
                        Toggle(isOn: Binding(get: { !omittedIDs.contains(record.id) },
                            set: { if $0 { omittedIDs.remove(record.id) } else { omittedIDs.insert(record.id) } })) {
                            LedgerRecordRow(record: record, catalog: ledger.catalog)
                        }
                        .toggleStyle(.switch)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search payees, notes, answers, and tags")
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                }
            }
            .sheet(item: $prepared, onDismiss: removePreparedFiles) { item in
                ExportPreviewView(prepared: item)
            }
            .alert("Unable to Prepare Export", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                    Button("OK") { failure = nil }
                } message: { Text(failure ?? "") }
        }
    }

    private func prepare() {
        do {
            let export = try ReviewExport(records: selected, catalog: ledger.catalog, options: options)
            let item = try PreparedReviewExport(export: export)
            preparedDirectory = item.directory
            prepared = item
        } catch { failure = error.localizedDescription }
    }

    private func removePreparedFiles() {
        guard let directory = preparedDirectory else { return }
        do {
            try FileManager.default.removeItem(at: directory)
            preparedDirectory = nil
        } catch {
            failure = "The export preview closed, but its temporary files could not be removed: \(error.localizedDescription)"
        }
    }
}

/// Only generated packet UUIDs and fixed filenames form paths. Never writes to
/// the live store or removes arbitrary paths supplied by a file/user/assistant.
private struct PreparedReviewExport: Identifiable {
    var id: UUID { export.packet.packetID }
    let export: ReviewExport
    let directory: URL
    let files: [URL]

    init(export: ReviewExport) throws {
        self.export = export
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinTrackReviewExports", isDirectory: true)
            .appendingPathComponent(export.packet.packetID.uuidString, isDirectory: true)
        directory = destination
        files = [export.jsonFileName, export.csvFileName, export.promptFileName]
            .map { destination.appendingPathComponent($0) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try export.json.write(to: files[0], options: .atomic)
            try Data(export.csv.utf8).write(to: files[1], options: .atomic)
            try Data(export.prompt.utf8).write(to: files[2], options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

@MainActor
private struct ExportPreviewView: View {
    let prepared: PreparedReviewExport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Ready to share") {
                    LabeledContent("Saved records", value: String(prepared.export.packet.transactions.count))
                    LabeledContent("Observed dates", value: prepared.export.packet.earliestDate + " – " + prepared.export.packet.latestDate)
                    LabeledContent("Your notes and answers", value: prepared.export.packet.options.includeUserContext ? "Included" : "Omitted")
                    LabeledContent("Assistant and earlier ledger context", value: prepared.export.packet.options.includeAssistantContext ? "Included" : "Omitted")
                    ShareLink(items: prepared.files) { Label("Save or Share All 3 Files", systemImage: "square.and.arrow.up") }
                    Text("Choose Save to Files, then a folder such as iCloud Drive. In ChatGPT, attach the JSON and prompt files; CSV is an optional readable companion. If your chosen share destination cannot receive several files, share them individually below.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Suggestion import is not implemented. Review ChatGPT's advice and make any chosen edits manually in FinTrack.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Files") {
                    ForEach(prepared.files, id: \.self) { file in
                        ShareLink(item: file) { Label(file.lastPathComponent, systemImage: "doc") }
                    }
                }
                Section("Review prompt") {
                    Text(prepared.export.prompt).font(.callout).textSelection(.enabled)
                }
                Section("JSON preview") {
                    Text(String(decoding: prepared.export.json, as: UTF8.self))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                Section {
                    Text("Prepared locally; FinTrack cannot confirm an upload to ChatGPT or iCloud. Closing this preview removes its temporary files; saved copies remain wherever you chose to put them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Review export")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
