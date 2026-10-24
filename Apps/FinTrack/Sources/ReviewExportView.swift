import SwiftUI
import UniformTypeIdentifiers
import FinTrackCore

@MainActor
struct ReviewExportView: View {
    @Bindable var ledger: LedgerViewModel
    var showsDone = false
    @Environment(\.dismiss) private var dismiss
    @State private var sharedFile: URL?
    @State private var preview = ""
    private enum FilePurpose: Equatable { case review, restore, folder }
    @State private var filePurpose = FilePurpose.review
    @State private var showFilePicker = false
    @State private var restoreCandidate: FullBackup?
    @State private var confirmRestore = false
    @State private var newRule = ""
    @State private var failure: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                reviewSection
                if let sharedFile {
                    Section("Prepared file") {
                        ShareLink(item: sharedFile) { Label("Share or Save File", systemImage: "square.and.arrow.up") }
                        Text("Attach this one file in your finance ChatGPT conversation. It includes instructions and context. Return ChatGPT's JSON result using Import below.")
                        DisclosureGroup("Preview contents") {
                            Text(preview).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
                Section("Incoming reviews and weekly transactions") {
                    Button("Import ChatGPT or Weekly File", systemImage: "square.and.arrow.down") { pick(.review) }
                    ForEach(ledger.workspace.staged.reversed()) { file in
                        NavigationLink {
                            IncomingReviewView(ledger: ledger, fileID: file.id)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(file.purpose == "fintrack-weekly-intake" ? "Weekly transactions" : "ChatGPT response")
                                Text(file.id.uuidString).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                knowledgeSection
                backupSection
            }
            .disabled(working)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDone { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: filePurpose == .folder ? [.folder] : [.json]) {
                handleSelection($0)
            }
            .confirmationDialog("Replace saved data with this backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Restore Backup", role: .destructive) {
                    attempt { if let restoreCandidate { try ledger.restoreBackup(restoreCandidate) } }
                    restoreCandidate = nil
                }
                Button("Cancel", role: .cancel) { restoreCandidate = nil }
            } message: {
                Text("Replace the ledger, drafts, pending reviews, and guidance with \(restoreCandidate?.records.count ?? 0) transactions from this backup. A local recovery copy is kept first.")
            }
            .alert("Unable to Complete Action", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") { failure = nil }
            } message: { Text(failure ?? "") }
        }
    }

    private var reviewSection: some View {
        Section {
            Button("Review with ChatGPT", systemImage: "bubble.left.and.text.bubble.right") { prepare(.pending) }
            Text("Automatically includes pending questions, additions, edits, and relevant notes. The first packet establishes your existing ledger as a baseline. Sharing does not clear pending work.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Full History Review", systemImage: "clock.arrow.circlepath") { prepare(.fullHistory) }
            Text("Includes every saved transaction and current guidance. Use periodically to refine categories and tags. Unfinished drafts stay private until saved.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var knowledgeSection: some View {
        Section("Classification guidance") {
            ForEach(ledger.workspace.knowledge) { rule in
                NavigationLink { KnowledgeRuleEditor(ledger: ledger, rule: rule) } label: { Text(rule.text).lineLimit(3) }
            }
            TextField("Add guidance for future reviews", text: $newRule, axis: .vertical)
            Button("Add Guidance") {
                attempt {
                    var rules = ledger.workspace.knowledge
                    rules.append(KnowledgeRule(text: newRule))
                    try ledger.saveKnowledge(rules)
                    newRule = ""
                }
            }.disabled(newRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var backupSection: some View {
        Section("iCloud backup") {
            Label(ledger.backup?.status ?? "Automatic backup is unavailable. Relaunch and check its error.",
                  systemImage: ledger.backup?.isCurrent == true ? "checkmark.icloud" : "icloud.and.arrow.up")
            if let date = ledger.backup?.lastConfirmed {
                LabeledContent("Last confirmed snapshot") { Text(date, format: .dateTime) }
            }
            if let error = ledger.backup?.failure { Text(error).foregroundStyle(.red) }
            Button(ledger.backup?.configured == true ? "Change iCloud Backup Folder" : "Enable Automatic iCloud Backup",
                   systemImage: "folder.badge.gearshape") { pick(.folder) }
            Button("Retry Backup Now") { Task { await ledger.backupNow() } }.disabled(ledger.backup?.configured != true)
            Text("Choose a dedicated folder inside iCloud Drive once. Saved changes back up automatically while FinTrack can run; interrupted or offline work retries on return. The previous complete backup stays until its replacement uploads.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Export Full Backup", systemImage: "externaldrive") {
                attempt { sharedFile = try ledger.exportBackup(); preview = "Full private backup: ledger, drafts, pending reviews, and guidance." }
            }
            Button("Restore Full Backup", systemImage: "arrow.counterclockwise") { pick(.restore) }
        }
    }

    private func prepare(_ mode: ReviewMode) {
        attempt {
            let url = try ledger.prepareReview(mode: mode)
            sharedFile = url
            let data = try Data(contentsOf: url)
            preview = data.count <= 100_000 ? String(decoding: data, as: UTF8.self)
                : "The complete packet is too large for an inline preview. Open the shared file to inspect all contents."
        }
    }
    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { failure = error.localizedDescription }
    }
    private func pick(_ purpose: FilePurpose) { filePurpose = purpose; showFilePicker = true }
    private func handleSelection(_ result: Result<URL, Error>) {
        switch filePurpose {
        case .review: receive(result) { try ledger.stageIncoming($0) }
        case .restore: receive(result) { restoreCandidate = try ledger.validateBackup($0); confirmRestore = true }
        case .folder:
            switch result {
            case .failure(let error): failure = error.localizedDescription
            case .success(let folder):
                working = true
                Task {
                    defer { working = false }
                    do {
                        guard let backup = ledger.backup else { throw ExchangeError.invalid("Backup is unavailable. Relaunch and check its error.") }
                        try await backup.configure(folder: folder)
                    } catch { failure = error.localizedDescription }
                }
            }
        }
    }
    private func receive(_ result: Result<URL, Error>, action: @escaping (Data) throws -> Void) {
        switch result {
        case .failure(let error): failure = error.localizedDescription
        case .success(let url):
            working = true
            Task {
                defer { working = false }
                do { try action(await IncomingFileReader.read(url)) }
                catch { failure = error.localizedDescription }
            }
        }
    }
}

private enum IncomingFileReader {
    static func read(_ url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard url.startAccessingSecurityScopedResource() else {
                throw ExchangeError.invalid("Cannot access the selected file. Select it again in Files.")
            }
            defer { url.stopAccessingSecurityScopedResource() }
            var output: Data?
            var failure: Error?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
                do {
                    let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values.isRegularFile == true, let size = values.fileSize, size <= ExchangeJSON.maximumBytes else {
                        throw ExchangeError.invalid("Choose a regular JSON file smaller than 50 MB.")
                    }
                    let handle = try FileHandle(forReadingFrom: source)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: ExchangeJSON.maximumBytes + 1) ?? Data()
                    guard data.count <= ExchangeJSON.maximumBytes else { throw ExchangeError.invalid("File exceeds 50 MB.") }
                    output = data
                } catch { failure = error }
            }
            if let coordinationError { throw coordinationError }
            if let failure { throw failure }
            guard let output else { throw ExchangeError.invalid("The selected file could not be read.") }
            return output
        }.value
    }
}

@MainActor
private struct KnowledgeRuleEditor: View {
    @Bindable var ledger: LedgerViewModel
    let rule: KnowledgeRule
    @State private var text = ""
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("Guidance", text: $text, axis: .vertical)
            Button("Save") {
                do {
                    var rules = ledger.workspace.knowledge
                    guard let index = rules.firstIndex(where: { $0.id == rule.id }), rules[index] == rule else { throw LedgerError.staleRevision }
                    rules[index].text = text; rules[index].origin = "user"
                    try ledger.saveKnowledge(rules); dismiss()
                } catch { failure = error.localizedDescription }
            }
            Button("Delete Guidance", role: .destructive) {
                do {
                    guard ledger.workspace.knowledge.first(where: { $0.id == rule.id }) == rule else { throw LedgerError.staleRevision }
                    try ledger.saveKnowledge(ledger.workspace.knowledge.filter { $0.id != rule.id }); dismiss()
                } catch { failure = error.localizedDescription }
            }
        }.onAppear { text = rule.text }.modifier(ReviewFailureAlert(message: $failure))
    }
}

@MainActor
private struct IncomingReviewView: View {
    @Bindable var ledger: LedgerViewModel
    let fileID: UUID
    @State private var failure: String?
    var body: some View {
        List {
            if let file = ledger.workspace.staged.first(where: { $0.id == fileID }) {
                if file.purpose == "fintrack-review-response",
                   let response = try? ExchangeJSON.decode(ReviewResponse.self, from: file.data) { responseSections(response) }
                else if file.purpose == "fintrack-weekly-intake",
                        let batch = try? ExchangeJSON.decode(WeeklyBatch.self, from: file.data) {
                    Section("Source coverage") {
                        Text(batch.coverage)
                        Button("Add All New Transactions") { attempt { try ledger.acceptWeeklyBatch(fileID) } }
                        Text("Existing source IDs are skipped. Ambiguous matches stop the batch so you can reconcile them first.").font(.caption)
                    }
                    Section("Transactions") {
                        ForEach(Array(batch.transactions.enumerated()), id: \.offset) { entry in
                            WeeklyIntakeRow(ledger: ledger, fileID: fileID, transaction: entry.element)
                        }
                    }
                } else { Text("This stored file could not be decoded. It has been preserved.").foregroundStyle(.red) }
            }
        }.modifier(ReviewFailureAlert(message: $failure))
    }
    @ViewBuilder
    private func responseSections(_ response: ReviewResponse) -> some View {
        Section("ChatGPT response") {
            Text(response.summary)
            Button(ledger.workspace.processedFiles.contains(response.id) ? "Receipt recorded" : "Record Processing Receipt") {
                attempt { try ledger.acknowledge(response.id) }
            }.disabled(ledger.workspace.processedFiles.contains(response.id))
            Text("Clears only acknowledged feedback. Suggestions still need your decision, and discussions remain open until you resolve them.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Transaction suggestions") {
            ForEach(response.proposals) { proposal in
                VStack(alignment: .leading, spacing: 8) {
                    Text(ledger.record(id: proposal.recordID)?.draft.payee ?? proposal.recordID.uuidString).font(.headline)
                    if let category = proposal.categoryID { Text("Category: \(ledger.catalog.category(id: category)?.label ?? category)") }
                    if let tags = proposal.tags { Text("Tags: \(tags.isEmpty ? "None" : tags.joined(separator: ", "))") }
                    if let question = proposal.question { Text("Question: \(question)") }
                    Text(proposal.rationale)
                    actions(response: response, id: proposal.id,
                        canAccept: ledger.record(id: proposal.recordID).map { String($0.revision) == proposal.expectedRevision } ?? false)
                }
            }
        }
        Section("Suggested guidance") {
            ForEach(response.knowledgeProposals) { proposal in
                VStack(alignment: .leading, spacing: 8) {
                    Text(proposal.text); Text(proposal.rationale).font(.caption)
                    actions(response: response, id: proposal.id,
                        canAccept: ledger.workspace.knowledgeVersion == response.knowledgeVersion || ledger.workspace.knowledgeResponseID == response.id)
                }
            }
        }
    }
    @ViewBuilder
    private func actions(response: ReviewResponse, id: UUID, canAccept: Bool) -> some View {
        if ledger.workspace.decidedProposals.contains(id) { Label("Decision recorded", systemImage: "checkmark") }
        else {
            HStack {
                Button("Accept") { attempt { try ledger.decide(fileID: fileID, proposalID: id, accept: true) } }.disabled(!canAccept)
                Button("Reject", role: .destructive) { attempt { try ledger.decide(fileID: fileID, proposalID: id, accept: false) } }
            }.buttonStyle(.bordered)
            if !canAccept { Text("Changed since this review. Keep your newer edit or request a fresh review.").font(.caption).foregroundStyle(.orange) }
        }
    }
    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { failure = error.localizedDescription }
    }
}

@MainActor
private struct WeeklyIntakeRow: View {
    @Bindable var ledger: LedgerViewModel
    let fileID: UUID
    let transaction: WeeklyTransaction
    @State private var reconcile = false
    @State private var failure: String?
    private var link: SourceLink? { ledger.workspace.sourceLinks.first { $0.identity == transaction.identity } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(transaction.merchant).font(.headline)
            Text("\(transaction.date) · \(transaction.identity.sourceAlias) · \(transaction.amountMinorUnits) minor units")
            if link?.latest == transaction { Label("Already imported", systemImage: "checkmark") }
            else {
                HStack {
                    if link == nil {
                        Button("Add Transaction") {
                            do { try ledger.acceptWeekly(fileID: fileID, identity: transaction.identity) }
                            catch { failure = error.localizedDescription }
                        }
                    }
                    Button(link == nil ? "Reconcile / Separate Purchase" : "Review Source Update") { reconcile = true }
                }.buttonStyle(.bordered)
            }
        }.sheet(isPresented: $reconcile) {
            WeeklyReconciliationView(ledger: ledger, fileID: fileID, transaction: transaction, linkedID: link?.recordID)
        }.modifier(ReviewFailureAlert(message: $failure))
    }
}

@MainActor
private struct WeeklyReconciliationView: View {
    @Bindable var ledger: LedgerViewModel
    let fileID: UUID
    let transaction: WeeklyTransaction
    let linkedID: UUID?
    @State private var selected: UUID?
    @State private var selectedRecord: LedgerTransaction?
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Incoming source facts") {
                    Text(transaction.merchant)
                    Text("\(transaction.date) · \(transaction.amountMinorUnits) minor units · \(transaction.postingStatus.label)")
                }
                Section("Match an existing transaction") {
                    Picker("Existing transaction", selection: $selected) {
                        Text("Choose a transaction").tag(nil as UUID?)
                        ForEach(ledger.records) { record in
                            Text("\(record.draft.date.iso8601) · \(record.draft.payee) · \(record.draft.amount.decimalText)").tag(Optional(record.id))
                        }
                    }.disabled(linkedID != nil)
                    if let selectedRecord {
                        Text("Current: \(selectedRecord.draft.date.iso8601) · \(selectedRecord.draft.payee) · \(selectedRecord.draft.amount.decimalText)")
                        Text("Replace date, merchant, amount, posting, treatment, and source. Keep your notes, category, and tags. Financial changes reopen approval.")
                        Button("Apply Source Facts to This Transaction") {
                            do { try ledger.acceptWeekly(fileID: fileID, identity: transaction.identity, matching: selectedRecord); dismiss() }
                            catch { failure = error.localizedDescription }
                        }
                    }
                }
                if linkedID == nil {
                    Section {
                        Button("Add as a Separate Purchase") {
                            do { try ledger.acceptWeekly(fileID: fileID, identity: transaction.identity, allowSeparate: true); dismiss() }
                            catch { failure = error.localizedDescription }
                        }
                        Text("Use only for a different purchase, even if another record has the same merchant, date, and amount.")
                    }
                }
            }
            .onAppear { selected = linkedID; selectedRecord = linkedID.flatMap { ledger.record(id: $0) } }
            .onChange(of: selected) { _, id in selectedRecord = id.flatMap { ledger.record(id: $0) } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.modifier(ReviewFailureAlert(message: $failure))
    }
}

@MainActor
private struct ReviewFailureAlert: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("Unable to Complete Action", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
}
