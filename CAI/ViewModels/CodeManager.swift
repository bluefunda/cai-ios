import Foundation

// MARK: - Code Manager
// State owner for the </>Code tab (SAP ABAP development). Phase 0 is a stub;
// later phases add SAP systems, the object browser, open-object tabs, etc.

@MainActor
final class CodeManager: ObservableObject {
    // Phase 1+: active SAP system, connection status, open objects…
    @Published var connectionStatus: ConnectionStatus = .disconnected
}
