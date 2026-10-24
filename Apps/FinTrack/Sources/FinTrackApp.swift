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
                    if phase == .active { ledger.reload() }
                }
        }
    }
}
