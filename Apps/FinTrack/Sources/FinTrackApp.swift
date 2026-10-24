import SwiftUI

@main
@MainActor
struct FinTrackApp: App {
    @State private var ledger = LedgerViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            FinTrackRootView(ledger: ledger)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        ledger.reload()
                        Task { await ledger.backupNow() }
                    } else if phase == .background {
                        Task { await ledger.backupNow(); ledger.backup?.pauseObservation() }
                    }
                }
        }
    }
}
