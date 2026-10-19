import SwiftUI

// MARK: - Shell Keyboard Shortcuts
// P10: ⌘1… jump to the active space's destinations (⌘1–⌘4 in Assistant, ⌘1–⌘5 in
// Requests), ⌃⌘1 / ⌃⌘2 switch space, ⌘F focuses the sidebar search, ⌘R refreshes the
// current Requests list. These live on invisible buttons in the shell's background
// rather than on the sidebar rows: the sidebar column can be collapsed (iPad/Mac) or the
// drawer closed (iPhone), and a shortcut must still work then. The titles are what
// iPad's hold-⌘ shortcut overlay lists. ⌘N is a menu command in CAIApp.

struct ShellKeyboardShortcuts: View {
    let destinations: [SidebarDestination]
    /// Only bound when the user has more than one space.
    let spaces: [AppSpace]
    let onDestination: (SidebarDestination) -> Void
    let onSpace: (AppSpace) -> Void
    let onFocusSearch: () -> Void
    /// Nil where there's nothing to refresh (the Assistant space).
    let onRefresh: (() -> Void)?

    var body: some View {
        ZStack {
            ForEach(Array(destinations.enumerated()), id: \.element) { index, destination in
                Button(destination.title) { onDestination(destination) }
                    .keyboardShortcut(Self.key(forIndex: index), modifiers: .command)
            }
            if spaces.count > 1 {
                ForEach(Array(spaces.enumerated()), id: \.element) { index, space in
                    Button("\(space.title) space") { onSpace(space) }
                        .keyboardShortcut(Self.key(forIndex: index), modifiers: [.command, .control])
                }
            }
            Button("Search Chats", action: onFocusSearch)
                .keyboardShortcut("f", modifiers: .command)
            if let onRefresh {
                Button("Refresh", action: onRefresh)
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// "1" for the first item, "2" for the second, …
    static func key(forIndex index: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(index + 1)))
    }
}
