import SwiftUI

// Sidebar list primitives, split out of ContentView.swift to stay under
// SwiftLint's file_length limit (bluefunda/cai-ios#261 precedent — see
// ChatView+Scroll.swift and ChatManager+Background.swift). Used by SidebarView's
// chat history (SidebarConversationList) on every platform.

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
    // Takes the title, not the whole Conversation: Conversation's == compares only id,
    // so SwiftUI treated a row as unchanged when just its title changed (e.g. a generated
    // title landing after the list loaded) and kept the stale "New Chat" until something
    // else — like tapping the row and flipping isSelected — forced a redraw.
    let title: String
    /// Quiet second line under the title — when the chat started, for now.
    var meta: String?
    let isSelected: Bool
    /// Pinned rows carry a small pin at the trailing edge (cai-ios#335).
    var isPinned = false
    /// Set → hovering the row (pointer only) shows a `···` menu with these actions in
    /// place of the pin.
    var hoverMenuRows: [BFDropdownRow] = []

    /// Pointer hover (Mac Catalyst / iPad with a trackpad) — touch never sets
    /// this, so rows are simply selected-or-not there.
    @State private var isHovered = false

    /// Softly rounded rows (`BFRadius.row`, 10pt) — a full capsule read as too curved for the
    /// selected chat.
    private var background: Color {
        if isSelected { return BFColor.primary.opacity(0.15) }
        if isHovered { return BFColor.rowHover }
        return .clear
    }

    private var showsHoverMenu: Bool { isHovered && !hoverMenuRows.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(isSelected ? BFFont.sidebarItemMed : BFFont.sidebarItem)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // The leading bubble glyph that used to sit here is gone — the
                    // pill plus brand-blue title already marks selection.
                    .foregroundStyle(isSelected ? BFColor.primary : .primary)
                if let meta {
                    Text(meta)
                        .font(BFFont.sidebarMeta)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            ZStack {
                if isPinned && !showsHoverMenu {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(45))
                        .foregroundStyle(isSelected ? BFColor.primary.opacity(0.7) : Color.secondary.opacity(0.6))
                        .accessibilityLabel("Pinned")
                }
                if !hoverMenuRows.isEmpty {
                    // Kept in the hierarchy (just invisible) when not hovered: the menu's
                    // popover anchors to this button, and removing it the moment the
                    // pointer moves into the popover would dismiss the menu. BFDropdownMenu,
                    // not Menu — this sits inside the split view's sidebar column, where a
                    // native Menu collapses the sidebar on iPadOS (cai-ios#292/#293).
                    BFDropdownMenu(rows: hoverMenuRows) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(showsHoverMenu ? 1 : 0)
                    .allowsHitTesting(showsHoverMenu)
                    .help("More")
                    .accessibilityLabel("More actions")
                    .accessibilityHidden(!showsHoverMenu)
                }
            }
            .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(background, in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous))
        .contentShape(Rectangle())
        .animation(BFMotion.easingDefault, value: isHovered)
        .onHover { isHovered = $0 }
        .bfPointerHover()
    }
}
