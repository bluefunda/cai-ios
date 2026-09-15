import SwiftUI

// Sidebar list primitives, split out of ContentView.swift to stay under
// SwiftLint's file_length limit (bluefunda/cai-ios#261 precedent — see
// ChatView+Scroll.swift and ChatManager+Background.swift). Shared verbatim by
// both sidebars: SidebarContent (iPad/Mac split view) and SidebarDrawer
// (iPhone overlay drawer).

// MARK: - Conversation Grouping

struct ConversationGroup: Identifiable {
    let id: String      // == title, always unique within a list
    let title: String
    let conversations: [Conversation]

    init(title: String, conversations: [Conversation]) {
        self.id = title
        self.title = title
        self.conversations = conversations
    }
}

// MARK: - Sidebar Row

struct SidebarConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool

    /// Pointer hover (Mac Catalyst / iPad with a trackpad) — touch never sets
    /// this, so rows are simply selected-or-not there.
    @State private var isHovered = false

    /// Pill rows, not square ones — `BFRadius.full` on a ~34-pt row resolves
    /// to a true capsule, the shape both reference sidebars use.
    private var background: Color {
        if isSelected { return BFColor.primary.opacity(0.15) }
        if isHovered { return BFColor.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(conversation.title)
                .font(isSelected ? BFFont.sidebarItemMed : BFFont.sidebarItem)
                .lineLimit(1)
                .truncationMode(.tail)
                // The leading bubble glyph that used to sit here is gone — the
                // pill plus brand-blue title already marks selection.
                .foregroundStyle(isSelected ? BFColor.primary : .primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(background, in: RoundedRectangle(cornerRadius: BFRadius.full, style: .continuous))
        .contentShape(Rectangle())
        .animation(BFMotion.easingDefault, value: isHovered)
        .onHover { isHovered = $0 }
        .bfPointerHover()
    }
}

// MARK: - Sidebar Nav Button

struct SidebarNavButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(label)
                    .font(BFFont.sidebarItem)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            // Same capsule-on-hover shape as SidebarConversationRow, so the nav
            // entries and the conversation list read as one column.
            .background(
                isHovered ? BFColor.rowHover : Color.primary.opacity(0.0001),
                in: RoundedRectangle(cornerRadius: BFRadius.full, style: .continuous)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
        .animation(BFMotion.easingDefault, value: isHovered)
        .onHover { isHovered = $0 }
        .bfPointerHover()
    }
}
