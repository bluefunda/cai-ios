import SwiftUI

// MARK: - App Mode

/// Top-level mode of the authenticated app: conversational Chat or the
/// ABAP development workspace (Code). Driven from the sidebar.
enum AppMode: String, CaseIterable {
    case chat
    case code

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .code: return "Code"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

// MARK: - Code Content
// The Code workspace body. The shell (AppShell) provides the top bar and the
// shared sidebar; this view only renders the connected/empty content.

struct CodeContent: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var systemStore: SAPSystemStore
    let onConnect: () -> Void

    var body: some View {
        if let active = systemStore.activeSystem {
            ObjectBrowserView(api: CodeAPIService.make(authManager: authManager, system: active))
                .id(active.id)   // rebuild the browser when the active system changes
        } else {
            CodeEmptyState(onConnect: onConnect)
        }
    }
}

// MARK: - Empty State

private struct CodeEmptyState: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("ABAP Workspace")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect a SAP system to start browsing and editing ABAP objects.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: onConnect) {
                Label("Add SAP System", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    CodeContent(systemStore: SAPSystemStore(), onConnect: {})
        .environmentObject(AuthManager())
}
