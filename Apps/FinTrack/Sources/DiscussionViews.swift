import SwiftUI
import FinTrackCore

extension DiscussionStatus {
    var label: String {
        switch self {
        case .draft: "Unfinished reply"
        case .awaitingYou: "ChatGPT is asking you"
        case .readyToSend: "Ready to send to ChatGPT"
        case .waitingForChatGPT: "Waiting for ChatGPT"
        case .responseReceived: "ChatGPT replied"
        case .resolved: "Resolved"
        }
    }
}

@MainActor
struct QuestionsView: View {
    @Bindable var ledger: LedgerViewModel
    private enum Filter: String, CaseIterable { case open = "Open", awaitingYou = "Needs your reply", ready = "Ready to send", received = "ChatGPT replied", resolved = "Resolved" }
    @State private var filter = Filter.open
    @State private var search = ""
    @State private var selected: LedgerTransaction?
    @State private var showExchange = false
    @State private var page = ReviewPage.send

    private var rows: [LedgerTransaction] {
        ledger.records.filter { record in
            guard let thread = ledger.discussions[record.id] else { return false }
            let matches: Bool
            switch filter {
            case .open: matches = !thread.isResolved || thread.status == .draft
            case .awaitingYou: matches = thread.status == .awaitingYou
            case .ready: matches = thread.status == .readyToSend
            case .received: matches = thread.status == .responseReceived
            case .resolved: matches = thread.isResolved && thread.status != .draft
            }
            let text = [record.draft.payee, thread.userQuestion, thread.originalQuestion]
                + thread.answers.map(\.text) + thread.replies.map(\.text)
            return matches && (search.isEmpty || text.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Your questions to ChatGPT and questions ChatGPT has asked you. Save a reply here, then send the prepared review. Imported answers appear here; mark a discussion resolved when you are finished.")
                        .font(.callout).foregroundStyle(.secondary)
                    Picker("Show", selection: $filter) {
                        ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                if rows.isEmpty { Text("No discussions in this view.").foregroundStyle(.secondary) }
                ForEach(rows) { record in
                    if let thread = ledger.discussions[record.id] {
                        Button { selected = record } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(record.draft.payee).font(.headline); Spacer(); Text(thread.status.label).font(.caption) }
                                if thread.status == .draft {
                                    Text("Reply draft saved on this iPad. Open it to continue.")
                                } else if thread.status == .awaitingYou, let question = thread.questionForUser {
                                    Text("ChatGPT asks: " + question).lineLimit(3)
                                } else if let answer = thread.answers.last {
                                    Text("ChatGPT: " + answer.text).lineLimit(3)
                                } else if !thread.userQuestion.isEmpty { Text("You asked: " + thread.userQuestion).lineLimit(3) }
                                Text(record.draft.date.iso8601).font(.caption).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search discussions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Send replies", systemImage: "square.and.arrow.up") { page = .send; showExchange = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Import reply", systemImage: "square.and.arrow.down") { page = .inbox; showExchange = true }
                }
            }
            .sheet(item: $selected) { record in DiscussionDetailView(ledger: ledger, recordID: record.id) }
            .sheet(isPresented: $showExchange) { ReviewExportView(ledger: ledger, showsDone: true, initialPage: page) }
            .refreshable { ledger.reload() }
        }
    }
}

@MainActor
struct DiscussionDetailView: View {
    @Bindable var ledger: LedgerViewModel
    let recordID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var reply = ""
    @State private var baseRevision: Int64?
    @State private var failure: String?
    @State private var draftWriteFailed = false
    @State private var showExchange = false
    @State private var showEditor = false
    @State private var notice: String?
    @State private var draftLoaded = false

    private var record: LedgerTransaction? { ledger.record(id: recordID) }
    private var thread: DiscussionThread? { record.flatMap { ledger.discussions[$0.id] } }

    var body: some View {
        NavigationStack {
            List {
                if let record {
                    Section {
                        Text(record.draft.payee).font(.headline)
                        Text(record.draft.date.iso8601 + " · " + record.draft.amount.decimalText).foregroundStyle(.secondary)
                        if let thread { Label(thread.status.label, systemImage: thread.isResolved ? "checkmark.bubble" : "questionmark.bubble") }
                        Button("Open Transaction") { showEditor = true }
                    }
                    if let thread {
                        if !thread.userQuestion.isEmpty { Section("You asked ChatGPT") { Text(thread.userQuestion).textSelection(.enabled) } }
                        if !thread.originalQuestion.isEmpty { Section("ChatGPT asked you") { Text(thread.originalQuestion).textSelection(.enabled) } }
                        if !record.draft.answer.isEmpty, thread.replies.isEmpty {
                            Section("Your saved answer") { Text(record.draft.answer).textSelection(.enabled) }
                        }
                        ForEach(thread.answers) { answer in
                            Section("ChatGPT reply") {
                                Text(answer.text).textSelection(.enabled)
                                if let question = answer.questionForUser, !question.isEmpty { Text("Question for you: " + question) }
                                if answer.expectedRevision != String(record.revision) {
                                    Text("This reply refers to an earlier saved version of the transaction.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !thread.replies.isEmpty {
                            Section("Your saved messages") {
                                ForEach(thread.replies) { Text($0.text).textSelection(.enabled) }
                            }
                        }
                    } else {
                        Text("Ask ChatGPT about this transaction below. The question saves here first; prepare and share a review to send it.")
                    }
                    replySection(record)
                    if let thread, !thread.isResolved {
                        Section {
                            Button("Mark Resolved", systemImage: "checkmark.bubble") {
                                attempt { try ledger.resolveDiscussion(record); notice = "Discussion resolved. Transaction approval is unchanged." }
                            }.disabled(!reply.isEmpty || draftWriteFailed)
                        }
                    }
                    if let notice { Text(notice).font(.callout) }
                } else { Text("This transaction is unavailable.") }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(draftWriteFailed) } }
            .onAppear {
                if !draftLoaded { loadDraft(); draftLoaded = true }
            }
            .onChange(of: reply) { _, _ in persistDraft() }
            .interactiveDismissDisabled(draftWriteFailed)
            .sheet(isPresented: $showExchange) { ReviewExportView(ledger: ledger, showsDone: true) }
            .sheet(isPresented: $showEditor, onDismiss: { if reply.isEmpty { baseRevision = record?.revision } }) {
                if let record { TransactionEditorView(ledger: ledger, draft: ledger.editor(for: record)) { _ in } }
            }
            .alert("Unable to Save Discussion", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") { failure = nil }
            } message: { Text(failure ?? "") }
        }
    }

    @ViewBuilder private func replySection(_ record: LedgerTransaction) -> some View {
        Section(thread == nil ? "Your question" : "Your reply") {
            TextField("Write to ChatGPT", text: $reply, axis: .vertical).lineLimit(3...10)
            if baseRevision != record.revision, !reply.isEmpty {
                Text("The transaction changed while this draft was open. Your reply is preserved; review the latest transaction before saving.").foregroundStyle(.orange)
                Button("Use Latest Transaction for This Reply") { self.baseRevision = record.revision; persistDraft() }
            }
            Button("Save Reply for ChatGPT", systemImage: "tray.and.arrow.up") {
                attempt {
                    guard let baseRevision else { throw LedgerError.recordNotFound }
                    try ledger.reply(recordID: recordID, expectedRevision: baseRevision, text: reply)
                    self.baseRevision = self.record?.revision; reply = ""
                    notice = "Reply saved. Prepare a review to send it to ChatGPT."
                }
            }.disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftWriteFailed)
            Button("Prepare Review for ChatGPT", systemImage: "square.and.arrow.up") { showExchange = true }
            if !reply.isEmpty {
                Button("Discard Reply Draft", role: .destructive) {
                    attempt {
                        try ledger.saveDiscussionDraft(recordID: recordID, expectedRevision: record.revision, text: "")
                        baseRevision = record.revision; reply = ""; draftWriteFailed = false
                    }
                }
            }
            if draftWriteFailed { Button("Retry Saving Draft") { persistDraft() } }
            Text("Drafts save on this iPad. Saved replies join your next review automatically. Reading an answer or resolving a discussion never approves a transaction.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func loadDraft() {
        guard let record else { return }
        baseRevision = record.revision
        if let saved = ledger.workspace.discussionDrafts?[recordID.uuidString] {
            reply = saved.text
            if saved.expectedRevision != String(record.revision) {
                baseRevision = Int64(saved.expectedRevision)
            }
        }
    }
    private func persistDraft() {
        guard let baseRevision else { return }
        do {
            try ledger.saveDiscussionDraft(recordID: recordID, expectedRevision: baseRevision, text: reply)
            draftWriteFailed = false
        } catch { draftWriteFailed = true; failure = "Your draft could not be saved. Keep this window open and retry. " + error.localizedDescription }
    }
    private func attempt(_ action: () throws -> Void) { do { try action() } catch { failure = error.localizedDescription } }
}
