import SwiftUI
import UniformTypeIdentifiers
import UIKit
import FinTrackCore

private let backupContentType = UTType(filenameExtension: "fintrack", conformingTo: .data) ?? .data

private enum ReviewPage: String, CaseIterable, Identifiable, Hashable {
    case send = "Send to ChatGPT", inbox = "Import reply", backup = "Backup"
    var id: Self { self }
}

@MainActor
struct ReviewExportView: View {
    @Bindable var ledger: LedgerViewModel
    @State private var destination: ReviewPage?
    var body: some View {
        NavigationStack {
            List {
                Button("Send to ChatGPT", systemImage: "square.and.arrow.up") { destination = .send }
                Button("Import ChatGPT Reply or Weekly File", systemImage: "square.and.arrow.down") { destination = .inbox }
                Button("Backup", systemImage: "externaldrive") { destination = .backup }
            }
            .sheet(item: $destination) { page in
                switch page {
                case .send: SendReviewView(ledger: ledger)
                case .inbox: ImportReviewView(ledger: ledger)
                case .backup: BackupSettingsView(ledger: ledger)
                }
            }
        }
    }
}

@MainActor
struct SendReviewView: View {
    var ledger: LedgerViewModel
    var body: some View { TransferForm(ledger: ledger, page: .send) }
}

@MainActor
struct ImportReviewView: View {
    var ledger: LedgerViewModel
    var body: some View { TransferForm(ledger: ledger, page: .inbox) }
}

@MainActor
struct BackupSettingsView: View {
    var ledger: LedgerViewModel
    var body: some View { TransferForm(ledger: ledger, page: .backup) }
}

@MainActor
private struct TransferForm: View {
    @Bindable var ledger: LedgerViewModel
    let page: ReviewPage
    @Environment(\.dismiss) private var dismiss
    @State private var preparedFile: URL?
    @State private var preparedMode: ReviewMode?
    @State private var preparedGeneration: UUID?
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
    @State private var deleteStoreID: String?
    @State private var confirmDeleteStore = false
    @State private var confirmCleanup = false
    @State private var transferNotice: String?
    @State private var historyCandidate: HistoryImport?

    var body: some View {
        NavigationStack {
            List {
                if page == .send {
                    reviewSection
                    if let preparedFile {
                    Section(preparedMode == .fullHistory ? "Prepared: Full history review" : "Prepared: Pending feedback and questions") {
                        Button("Copy Review Again", systemImage: "doc.on.clipboard") { attempt { try copyReview(preparedFile) } }
                        if let transferNotice { Text(transferNotice).font(.callout) }
                        Text("Open ChatGPT and paste. Copy its JSON response text, then use Paste in Import reply.").font(.callout)
                        ShareLink(item: preparedFile) { Label("Share JSON File Instead", systemImage: "square.and.arrow.up") }
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
                    PasteButton(payloadType: String.self) { values in
                        attempt {
                            guard values.count == 1, let text = values.first else { throw ExchangeError.invalid("Paste one complete JSON response at a time.") }
                            try importData(ClipboardExchange.incoming(text))
                        }
                    }
                    Text("Copy the JSON message text in ChatGPT, then paste here. This uses the same validation and review as importing a file.").font(.caption).foregroundStyle(.secondary)
                    Button("Import ChatGPT Reply or Weekly File", systemImage: "square.and.arrow.down") { pick(.review) }
                    Text("History migration JSON can also be pasted or imported here. You will review its audit before it creates a separate ledger.").font(.caption).foregroundStyle(.secondary)
                    if let transferNotice { Text(transferNotice).font(.callout) }
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
                Section("Processed files") {
                    Text("Full files are removed once their results are recorded. Open questions remain in Discussions until approval or resolution.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach((ledger.workspace.importReceipts ?? []).reversed()) { receipt in
                        NavigationLink { IncomingReviewView(ledger: ledger, fileID: receipt.id) } label: {
                            VStack(alignment: .leading) {
                                Text(receipt.purpose == "fintrack-weekly-intake" ? "Processed weekly file" : "Processed ChatGPT reply")
                                if receipt.unreadSummary != nil { Text("Unread summary").font(.caption).foregroundStyle(.blue) }
                                Text(receipt.compactedAt, format: .dateTime).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let history = ledger.workspace.historyImport {
                    Section("History migration audit") {
                        Text(history.sourceName)
                        Text("\(history.recordIDs.count) imported rows; \(history.audit.excludedRows.count) excluded source rows.")
                        DisclosureGroup("Column mapping, omissions and warnings") { HistoryAuditView(audit: history.audit) }
                    }
                }
                }
                if page == .backup { backupSection }
            }
            .disabled(working)
            .navigationTitle(page.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(working) }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: filePurpose == .folder ? [.folder] : filePurpose == .restore ? [.data, .json] : [.json]) {
                handleSelection($0)
            }
            .fileExporter(isPresented: $showBackupExporter, document: backupDocument, contentType: backupContentType,
                          defaultFilename: "FinTrack-backup-\(EditorDraft.dateText(.now)).fintrack") { result in
                switch result {
                case .success: backupNotice = "Full backup file saved."
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled { failure = error.localizedDescription }
                }
            }
            .interactiveDismissDisabled(working)
            .sheet(item: $historyCandidate) { candidate in
                HistoryImportPreview(ledger: ledger, candidate: candidate)
            }
            .confirmationDialog("Replace saved data with this backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Restore Backup", role: .destructive) {
                    let snapshot = restoreCandidate
                    restoreCandidate = nil
                    working = true
                    Task {
                        defer { working = false }
                        await Task.yield()
                        attempt { if let snapshot { try ledger.restoreBackup(snapshot) } }
                    }
                }
                Button("Cancel", role: .cancel) { restoreCandidate = nil }
            } message: {
                Text("Restore \(restoreCandidate?.records.count ?? 0) transactions, drafts, pending work, and guidance into a separate database. It is verified before activation. The previous database is preserved.")
            }
            .confirmationDialog("Delete this preserved database and its recovery data?", isPresented: $confirmDeleteStore, titleVisibility: .visible) {
                Button("Delete Preserved Database", role: .destructive) {
                    attempt { if let deleteStoreID { try ledger.deletePreservedStore(deleteStoreID) } }; deleteStoreID = nil
                }
                Button("Cancel", role: .cancel) { deleteStoreID = nil }
            } message: { Text("This cannot be undone. The active database and cloud backups are not deleted.") }
            .confirmationDialog("Delete superseded local recovery files?", isPresented: $confirmCleanup, titleVisibility: .visible) {
                Button("Delete Local Recovery Files", role: .destructive) { attempt { try ledger.deleteLegacyRecoveryFiles() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Removes older restore files, retired database pointers, and damaged backup-settings copies. Keep them if they may help recover data. Active data, active backup settings, and cloud files remain.") }
            .overlay { if working { ProgressView("Working…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
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
        Group {
        Section("iCloud backup") {
            if !ledger.canExportBackup {
                Text("The current database is unavailable. Restore can still build and verify a separate database from a good backup.").foregroundStyle(.orange)
            }
            if let notice = ledger.capacityNotice { Text(notice).foregroundStyle(.orange) }
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
                working = true
                Task {
                    defer { working = false }
                    do {
                        backupDocument = BackupFileDocument(url: try await ledger.exportBackup())
                        showBackupExporter = true
                    } catch { failure = error.localizedDescription }
                }
            }.disabled(!ledger.canExportBackup)
            Text("Save a separate full backup anywhere in Files. No automatic-backup folder is needed.").font(.caption).foregroundStyle(.secondary)
            if let backupNotice { Text(backupNotice) }
            Button("Restore Full Backup", systemImage: "arrow.counterclockwise") { pick(.restore) }
        }
        Section("Preserved recovery data") {
            ForEach(ledger.preservedStores) { store in
                HStack {
                    VStack(alignment: .leading) {
                        Text(store.id == "legacy" ? "Previous original database" : "Previous or interrupted recovery database")
                        if let date = store.createdAt { Text(date, format: .dateTime).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Delete", role: .destructive) { deleteStoreID = store.id; confirmDeleteStore = true }
                }
            }
            Text("Previous databases are kept until you delete them. Check the restored ledger and its cloud backup first.").font(.caption).foregroundStyle(.secondary)
            Button("Delete Superseded Local Recovery Files", role: .destructive) { confirmCleanup = true }
                .disabled(!ledger.canExportBackup)
        }
        }
    }

    private func prepare(_ mode: ReviewMode) {
        attempt {
            let url = try ledger.prepareReview(mode: mode)
            let data = try Data(contentsOf: url)
            preview = data.count <= 100_000 ? String(decoding: data, as: UTF8.self)
                : "The complete packet is too large for an inline preview. Open the shared file to inspect all contents."
            preparedFile = url; preparedMode = mode; preparedGeneration = ledger.workspace.generation
            do { try copyReview(url) }
            catch { transferNotice = error.localizedDescription }
        }
    }
    private func preparedFileReset() {
        preparedFile = nil; preparedMode = nil; preparedGeneration = nil; preview = ""; transferNotice = nil
    }
    private func copyReview(_ url: URL) throws {
        let text = try ClipboardExchange.reviewText(Data(contentsOf: url))
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: text]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(3600)])
        transferNotice = "Copied to this iPad's clipboard. Paste into ChatGPT. Clipboard copy expires after one hour; copying is not acknowledgement."
    }
    private func importData(_ data: Data) throws {
        struct Header: Decodable { let purpose: String; let id: UUID }
        let header = try ExchangeJSON.decode(Header.self, from: data)
        if header.purpose == "fintrack-history-import" {
            historyCandidate = try HistoryImport.decode(data)
            return
        }
        let known = ledger.workspace.staged.contains { $0.id == header.id } || ledger.workspace.importReceipts?.contains { $0.id == header.id } == true
        try ledger.stageIncoming(data)
        transferNotice = known ? "This file was already received. No financial records were changed by pasting it again."
            : "Imported. Read answers in Discussions; review any proposed record changes or weekly additions below."
    }
    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { failure = error.localizedDescription }
    }
    private func pick(_ purpose: FilePurpose) { filePurpose = purpose; showFilePicker = true }
    private func handleSelection(_ result: Result<URL, Error>) {
        switch filePurpose {
        case .review: receive(result) { try importData($0) }
        case .restore:
            switch result {
            case .failure(let error): if (error as? CocoaError)?.code != .userCancelled { failure = error.localizedDescription }
            case .success(let url):
                working = true
                Task {
                    defer { working = false }
                    do { restoreCandidate = try await ledger.readBackup(url); confirmRestore = true }
                    catch { failure = error.localizedDescription }
                }
            }
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

@MainActor
private struct HistoryImportPreview: View {
    var ledger: LedgerViewModel
    let candidate: HistoryImport
    @Environment(\.dismiss) private var dismiss
    @State private var reviewed = false
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            List {
                Section("History migration") {
                    Text(candidate.sourceName)
                    Text("\(candidate.rows.count) records; net control total \(candidate.audit.netAmountMinorUnits) minor units.")
                    Text("\(candidate.rows.filter { $0.approval == .confirmed }.count) prior explicit approvals will be preserved. Resolved assistant questions/reasons are cleared by the retention policy.")
                    Text("Creates and verifies a separate ledger. The current ledger is preserved in Backup. This is an initial migration, not a merge of weekly changes.")
                    DisclosureGroup("Prior approvals supplied by the source") {
                        ForEach(candidate.rows.filter { $0.approval == .confirmed }, id: \.id) { row in
                            Text(row.sourceRow + " · " + row.merchant + ": " + row.approvalEvidence).font(.caption)
                        }
                    }
                    DisclosureGroup("Imported category catalog") {
                        ForEach(candidate.categories) { category in
                            Text(category.label + " (" + category.id + ")" + (category.unresolved ? " · unresolved" : "") + (category.excluded ? " · excluded" : ""))
                        }
                    }
                }
                Section("Sanity check") {
                    HistoryAuditView(audit: candidate.audit)
                    ForEach(Array(candidate.reviewWarnings.enumerated()), id: \.offset) { entry in Text(entry.element).font(.callout) }
                    Toggle("I compared source counts and totals and reviewed prior approvals, omissions and limitations", isOn: $reviewed)
                    Button("Import Into Separate Ledger") {
                        do { try ledger.importHistory(candidate); dismiss() }
                        catch { failure = error.localizedDescription }
                    }.disabled(!reviewed)
                }
            }
            .navigationTitle("Review History Import")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("History Not Imported", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") { failure = nil }
            } message: { Text(failure ?? "") }
        }
    }
}

private struct HistoryAuditView: View {
    let audit: HistoryAudit
    var body: some View {
        Text("Source rows: \(audit.sourceRowCount). Net control total: \(audit.netAmountMinorUnits) minor units.")
        ForEach(Array(audit.columns.enumerated()), id: \.offset) { entry in
            Text(entry.element.name + " → " + entry.element.handling + ": " + entry.element.target + ". " + entry.element.explanation).font(.caption)
        }
        ForEach(Array(audit.excludedRows.enumerated()), id: \.offset) { entry in Text("Excluded " + entry.element.sourceRow + ": " + entry.element.reason).font(.caption) }
        ForEach(Array(audit.warnings.enumerated()), id: \.offset) { entry in Text(entry.element).font(.caption) }
    }
}

private enum IncomingFileReader {
    static func read(_ url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
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
    static var readableContentTypes: [UTType] { [backupContentType, .json] }
    static var writableContentTypes: [UTType] { [backupContentType] }
    private let url: URL?
    private let data: Data?
    init(url: URL) { self.url = url; data = nil }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= BackupCapacity.maximumFileBytes else {
            throw ExchangeError.invalid("Unable to read this backup file.")
        }
        self.data = data; url = nil
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let url { return FileWrapper(regularFileWithContents: try Data(contentsOf: url, options: .mappedIfSafe)) }
        return FileWrapper(regularFileWithContents: data ?? Data())
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
    @State private var confirmDismiss = false
    @State private var shownSummary: String?
    @State private var loadedSummary = false
    var body: some View {
        List {
            if let file = ledger.workspace.staged.first(where: { $0.id == fileID }) {
                if file.purpose == "fintrack-review-response",
                   let response = try? ExchangeJSON.decode(ReviewResponse.self, from: file.data) { responseSections(response) }
                else if file.purpose == "fintrack-weekly-intake",
                        let batch = try? ExchangeJSON.decode(WeeklyBatch.self, from: file.data) {
                    Section("Source coverage") {
                        Text(batch.coverage)
                        let links = Dictionary(uniqueKeysWithValues: ledger.workspace.sourceLinks.map { ($0.identity, $0.latest) })
                        let unchanged = batch.transactions.filter { links[$0.identity] == $0 }.count
                        let changed = batch.transactions.filter { links[$0.identity] != nil && links[$0.identity] != $0 }.count
                        Text("\(batch.transactions.count - unchanged - changed) unmatched source IDs; \(unchanged) unchanged; \(changed) source updates requiring individual review.").font(.caption)
                        Button("Add All New Transactions") { attempt { try ledger.acceptWeeklyBatch(fileID) } }
                        Text("Unmatched IDs are checked against linked purchases and other rows before saving. Changed source facts are left for individual review. Ambiguous matches stop the entire batch.").font(.caption)
                    }
                    Section("Transactions") {
                        ForEach(Array(batch.transactions.enumerated()), id: \.offset) { entry in
                            WeeklyIntakeRow(ledger: ledger, fileID: fileID, transaction: entry.element)
                        }
                    }
                } else { Text("This stored file could not be decoded. It has been preserved.").foregroundStyle(.red) }
                Section {
                    Button("Dismiss Remaining Items in This File", role: .destructive) { confirmDismiss = true }
                }
            } else if let receipt = ledger.workspace.importReceipts?.first(where: { $0.id == fileID }) {
                Section("Processed file") {
                    Text("The full imported file has been removed. Accepted results remain in your ledger and guidance.")
                    if let shownSummary { Text(shownSummary).textSelection(.enabled) }
                    if let coverage = receipt.reportedCoverage { Text("Reported coverage (not independently verified): " + coverage).font(.caption) }
                    let itemIDs = Set(receipt.itemIDs)
                    let answers = (ledger.workspace.discussionAnswers ?? []).filter { itemIDs.contains($0.id) }
                    ForEach(answers) { answer in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ledger.record(id: answer.recordID)?.draft.payee ?? "Transaction").font(.headline)
                            Text(answer.text)
                            if let question = answer.questionForUser { Text(question) }
                            Button("Reply / Mark Resolved") { discussionRecord = ledger.record(id: answer.recordID) }
                        }
                    }
                    if answers.isEmpty { Text("There are no retained open discussion answers from this file.").foregroundStyle(.secondary) }
                }.onAppear {
                    guard !loadedSummary else { return }
                    loadedSummary = true; shownSummary = receipt.unreadSummary
                    if receipt.unreadSummary != nil { attempt { try ledger.markImportSummaryRead(fileID) } }
                }
            }
        }.modifier(ReviewFailureAlert(message: $failure))
        .confirmationDialog("Dismiss unapplied items?", isPresented: $confirmDismiss, titleVisibility: .visible) {
            Button("Dismiss Remaining Items", role: .destructive) { attempt { try ledger.dismissIncoming(fileID) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Unapplied proposals or remaining weekly rows will be dismissed. Saved records, unsent feedback, and open discussions are kept. The raw file is replaced by a replay-protection receipt.") }
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
            Text("Answers are ready to read. Only an actual category or tag change needs your decision. Approve or Mark Resolved closes the current discussion.")
                .font(.caption).foregroundStyle(.secondary)
        }
        let replies = displayAnswers(response).filter { answer in
            guard let record = ledger.record(id: answer.recordID) else { return false }
            let closed = ledger.workspace.discussionClosureRevision(for: record)
            return closed == 0 || (Int64(answer.expectedRevision) ?? 0) > closed
        }
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
