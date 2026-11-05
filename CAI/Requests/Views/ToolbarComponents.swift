import SwiftUI

// MARK: - Requests Toolbar Buttons
// The per-destination toolbar items (P6): Requests → filter, list/grid, New request;
// Projects → filter. Each Requests destination owns its NavigationStack, so these sit
// in that stack's toolbar next to the shell's sidebar control (ShellNavigationControl).
// No "+" on screens without a create endpoint — trm-ios's "Coming soon" alert was a
// dead end (P13: empty states invite action, nothing teases what doesn't exist).

struct NewRequestToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New request", systemImage: "plus")
        }
        .help("New request")
        .bfPointerHover()
        .accessibilityIdentifier("requests.newRequest")
    }
}

struct FilterToolbarButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                "Filter",
                systemImage: isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help("Filter")
        .bfPointerHover()
        .accessibilityIdentifier("requests.filter")
    }
}

/// Grid is a side-by-side status board — too cramped for compact width, so callers only
/// show this on regular width.
struct ViewModeToolbarPicker: View {
    @Binding var viewMode: ChangeRequestViewMode

    var body: some View {
        Picker("View", selection: $viewMode) {
            Label("List", systemImage: "list.bullet").tag(ChangeRequestViewMode.list)
            Label("Board", systemImage: "square.grid.2x2").tag(ChangeRequestViewMode.grid)
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .fixedSize()
        .accessibilityIdentifier("requests.viewMode")
    }
}
