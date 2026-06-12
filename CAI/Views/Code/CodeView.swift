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

// MARK: - Code View (Phase 0 placeholder)

struct CodeView: View {
    @Binding var mode: AppMode
    @StateObject private var codeManager = CodeManager()

    var body: some View {
        VStack(spacing: 0) {
            CodeTopBar(mode: $mode)
            CodeEmptyState()
        }
    }
}

// MARK: - Code Top Bar

private struct CodeTopBar: View {
    @Binding var mode: AppMode

    var body: some View {
        HStack {
            Spacer()
            ModeSwitcher(mode: $mode)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Empty State

private struct CodeEmptyState: View {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    CodeView(mode: .constant(.code))
}
