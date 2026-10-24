import SwiftUI

@main
@MainActor
struct FinTrackApp: App {
    @State private var ledger = LedgerViewModel()

    var body: some Scene {
        WindowGroup { TransactionListView(ledger: ledger) }
    }
}
