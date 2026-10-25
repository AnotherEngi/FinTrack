import SwiftUI
import UniformTypeIdentifiers
import FinTrackCore

enum ReviewPage: String, CaseIterable {
    case send = "Send to ChatGPT", inbox = "Import reply", backup = "Backup"
}

@MainActor
struct ReviewExportView: View {
    @Bindable var ledger: LedgerViewModel
    var showsDone = false
    @Environment(\.dismiss) private var dismiss
    @State private var preparedFile: URL?
    @State private var preparedMode: ReviewMode?
    @State private var preparedGeneration: UUID?
    @State private var page: ReviewPage
    @State private var backupDocument: BackupFileDocument?
    @State private var showBackupExporter = false
    @State private var backupNotice: String?
    @State private var preview = ""
    private enum FilePurpose: Equatable { case review, restore, folder }
    @State private var filePurpose = FilePurpose.review
    @State private var showFilePicker = false
    @State private var restoreCandidate: FullBackup?
    @State private var confirmRestore = false
    @State private var newRule = ""
    @State private var failure: String?
    @State private var working = false

    init(ledger: LedgerViewModel, showsDone: Bool = false, initialPage: ReviewPage = .send) {
        self.ledger = ledger; self.showsDone = showsDone; _page = State(initialValue: initialPage)
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Review tools", selection: $page) {
                    ForEach(ReviewPage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).listRowBackground(Color.clear)
                if page == .send {
                    reviewSection
                    if let preparedFile {
                    Section(preparedMode == .fullHistory ? "Prepared: Full history review" : "Prepared: Pending feedback and questions") {
                        ShareLink(item: preparedFile) { Label("Share Prepared Review", systemImage: "square.and.arrow.up") }
                        Text("Attach this one file in your finance ChatGPT conversation. Bring the response back using Import reply.")
                        if preparedGeneration != ledger.workspace.generation {
                            Text("You have newer saved changes. This file is the snapshot you prepared; start another review to include them.").foregroundStyle(.orange)
                        }
                        DisclosureGroup("Preview contents") {
                            Text(preview).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                        Button("Start Another Review") { preparedFileReset() }
                    }
                    }
                    knowledgeSection
                }
                if page == .inbox {
                Section("Incoming reviews and weekly transactions") {
                    Button("Import ChatGPT Reply or Weekly File", systemImage: "square.and.arrow.down") { pick(.review) }
                    ForEach(ledger.workspace.staged.reversed()) { file in
                        NavigationLink {
                            IncomingReviewView(ledger: ledger, fileID: file.id)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(file.purpose == "fintrack-weekly-intake" ? "Weekly transactions" : "ChatGPT response")
                                if ledger.workspace.processedFiles.contains(file.id) {
                                    Text("Response received").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                }
                if page == .backup { backupSection }
            }
            .disabled(working)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDone { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(working) } }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: filePurpose == .folder ? [.folder] : [.json]) {
                handleSelection($0)
            }
            .fileExporter(isPresented: $showBackupExporter, document: backupDocument, contentType: .json,
                          defaultFilename: "FinTrack-backup-\(EditorDraft.dateText(.now))") { result in
                switch result {
                case .success: backupNotice = "Full backup file saved."
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled { failure = error.localizedDescription }
                }
            }
            .interactiveDismissDisabled(working)
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
                .disabled(preparedFile != nil)
            Text("Automatically includes pending questions, additions, edits, and relevant notes. The first packet establishes your existing ledger as a baseline. Sharing does not clear pending work.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Full History Review", systemImage: "clock.arrow.circlepath") { prepare(.fullHistory) }
                .disabled(preparedFile != nil)
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
                attempt {
                    backupDocument = try BackupFileDocument(data: Data(contentsOf: ledger.exportBackup()))
                    showBackupExporter = true
                }
            }
            Text("Save a separate full backup anywhere in Files. No automatic-backup folder is needed.").font(.caption).foregroundStyle(.secondary)
            if let backupNotice { Text(backupNotice) }
            Button("Restore Full Backup", systemImage: "arrow.counterclockwise") { pick(.restore) }
        }
    }

    private func prepare(_ mode: ReviewMode) {
        attempt {
            let url = try ledger.prepareReview(mode: mode)
            let data = try Data(contentsOf: url)
            preview = data.count <= 100_000 ? String(decoding: data, as: UTF8.self)
                : "The complete packet is too large for an inline preview. Open the shared file to inspect all contents."
            preparedFile = url; preparedMode = mode; preparedGeneration = ledger.workspace.generation
        }
    }
    private func preparedFileReset() {
        preparedFile = nil; preparedMode = nil; preparedGeneration = nil; preview = ""
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

private struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= ExchangeJSON.maximumBytes else {
            throw ExchangeError.invalid("Unable to read this backup file.")
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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
    @State private var discussionRecord: LedgerTransaction?
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
        .sheet(item: $discussionRecord) { record in DiscussionDetailView(ledger: ledger, recordID: record.id) }
    }
    @ViewBuilder
    private func responseSections(_ response: ReviewResponse) -> some View {
        Section("ChatGPT response") {
            Text(response.summary)
            if ledger.workspace.processedFiles.contains(response.id) {
                Label("Response received", systemImage: "checkmark.circle")
            } else {
                Button("Mark Response Received") { attempt { try ledger.acknowledge(response.id) } }
            }
            Text("Answers are ready to read. Only an actual category or tag change needs your decision. Discussions stay open until you mark them resolved.")
                .font(.caption).foregroundStyle(.secondary)
        }
        let replies = displayAnswers(response)
        if !replies.isEmpty {
            Section("Replies and questions") {
                ForEach(replies) { answer in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ledger.record(id: answer.recordID)?.draft.payee ?? "Earlier transaction").font(.headline)
                        Text(answer.text).textSelection(.enabled)
                        if let question = answer.questionForUser, !question.isEmpty { Text("ChatGPT asks: " + question) }
                        Button("Reply / Mark Resolved", systemImage: "bubble.left.and.bubble.right") {
                            discussionRecord = ledger.record(id: answer.recordID)
                        }
                    }
                }
            }
        }
        let changes = response.proposals.filter { proposal in
            guard let record = ledger.record(id: proposal.recordID) else { return false }
            let hasFields = proposal.categoryID != nil || proposal.tags != nil
            return hasFields && (proposal.changesClassification(of: record) || ledger.workspace.decidedProposals.contains(proposal.id))
        }
        if !changes.isEmpty {
        Section("Proposed category and tag changes") {
            ForEach(changes) { proposal in
                VStack(alignment: .leading, spacing: 8) {
                    Text(ledger.record(id: proposal.recordID)?.draft.payee ?? proposal.recordID.uuidString).font(.headline)
                    if let category = proposal.categoryID {
                        Text("Category: \(ledger.catalog.category(id: ledger.record(id: proposal.recordID)?.draft.categoryID)?.label ?? "None") → \(ledger.catalog.category(id: category)?.label ?? category)")
                    }
                    if let tags = proposal.tags {
                        Text("Tags: \(ledger.record(id: proposal.recordID)?.draft.tags.joined(separator: ", ") ?? "None") → \(tags.isEmpty ? "None" : tags.joined(separator: ", "))")
                    }
                    Text(proposal.rationale)
                    actions(response: response, id: proposal.id,
                        canAccept: ledger.record(id: proposal.recordID).map { String($0.revision) == proposal.expectedRevision } ?? false)
                }
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
                Button("Apply changes") { attempt { try ledger.decide(fileID: fileID, proposalID: id, accept: true) } }.disabled(!canAccept)
                Button("Keep current") { attempt { try ledger.decide(fileID: fileID, proposalID: id, accept: false) } }
            }.buttonStyle(.bordered)
            if !canAccept { Text("Changed since this review. Keep your newer edit or request a fresh review.").font(.caption).foregroundStyle(.orange) }
        }
    }
    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { failure = error.localizedDescription }
    }
    private func displayAnswers(_ response: ReviewResponse) -> [DiscussionAnswer] {
        var answers = response.answers
        for proposal in response.proposals {
            guard let record = ledger.record(id: proposal.recordID) else { continue }
            let plainReply = proposal.categoryID == nil && proposal.tags == nil
            if plainReply || (!proposal.changesClassification(of: record) && !ledger.workspace.decidedProposals.contains(proposal.id)) {
                answers.append(DiscussionAnswer(id: proposal.id, recordID: proposal.recordID,
                    expectedRevision: proposal.expectedRevision, text: proposal.rationale, questionForUser: proposal.question))
            }
        }
        return answers
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
