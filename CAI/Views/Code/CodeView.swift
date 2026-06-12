import SwiftUI

// MARK: - App Mode

/// Top-level mode of the authenticated app: conversational Chat or the
/// ABAP development workspace (Code).
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

// MARK: - Mode Switcher (Chat | </>Code pill)

struct ModeSwitcher: View {
    @Binding var mode: AppMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppMode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { mode = m }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: m.icon).font(.caption2)
                        Text(m.title).font(.caption).fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(mode == m ? Color.brandBlue : Color.clear, in: Capsule())
                    .foregroundStyle(mode == m ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(.systemGray6), in: Capsule())
    }
}

// MARK: - Code View

struct CodeView: View {
    @Binding var mode: AppMode
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var systemStore = SAPSystemStore()
    @State private var showSystems = false

    var body: some View {
        VStack(spacing: 0) {
            CodeTopBar(
                mode: $mode,
                activeSystem: systemStore.activeSystem,
                onSystems: { showSystems = true }
            )
            content
        }
        .sheet(isPresented: $showSystems) {
            SystemManagerView(store: systemStore)
                .environmentObject(authManager)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let active = systemStore.activeSystem {
            ObjectBrowserView(api: CodeAPIService.make(authManager: authManager, system: active))
                .id(active.id)   // rebuild the browser when the active system changes
        } else {
            CodeEmptyState(onConnect: { showSystems = true })
        }
    }
}

// MARK: - Code Top Bar

private struct CodeTopBar: View {
    @Binding var mode: AppMode
    let activeSystem: SAPSystem?
    let onSystems: () -> Void

    var body: some View {
        HStack {
            Button(action: onSystems) {
                Image(systemName: "server.rack").font(.system(size: 17))
            }
            Spacer()
            ModeSwitcher(mode: $mode)
            Spacer()
            // Invisible spacer to keep the pill centered.
            Image(systemName: "server.rack").font(.system(size: 17)).opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
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
    CodeView(mode: .constant(.code))
        .environmentObject(AuthManager())
}
