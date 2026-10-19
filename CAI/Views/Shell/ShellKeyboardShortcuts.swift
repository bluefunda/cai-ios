import SwiftUI

// MARK: - Shell Keyboard Shortcuts
// ⌘1–⌘4 jump to the Assistant destinations and ⌘F focuses the sidebar search (P10).
// These live on invisible buttons in the shell's background rather than on the
// sidebar rows themselves: the sidebar column can be collapsed (iPad/Mac) or the
// drawer closed (iPhone), and a shortcut must still work then. The titles are what
// iPad's hold-⌘ shortcut overlay lists. ⌘N (New Chat) is a menu command in CAIApp.

struct ShellKeyboardShortcuts: View {
    let onDestination: (AssistantDestination) -> Void
    let onFocusSearch: () -> Void

    var body: some View {
        ZStack {
            ForEach(Array(AssistantDestination.allCases.enumerated()), id: \.element) { index, destination in
                Button(destination.title) { onDestination(destination) }
                    .keyboardShortcut(Self.key(forIndex: index), modifiers: .command)
            }
            Button("Search Chats", action: onFocusSearch)
                .keyboardShortcut("f", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// "1" for the first destination, "2" for the second, …
    static func key(forIndex index: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(index + 1)))
    }
}
