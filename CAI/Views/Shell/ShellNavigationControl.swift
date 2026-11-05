import SwiftUI

// MARK: - Shell Navigation Control
// Files and Agents render inside their own NavigationStack (Agents pushes its
// connect/detail screens; Files has its own search and toolbar). Toolbar items the
// shell attaches outside that stack never reach its navigation bar, so the shell
// hands the one control it needs — the iPhone drawer's hamburger, or the Mac
// Catalyst sidebar toggle — to the destination, which places it inside.
//
// iPad (non-Catalyst) needs nothing: its sidebar toggle lives in the sidebar
// header (cai-ios#256).

enum ShellNavigationControl {
    case none
    case drawer(isOpen: Binding<Bool>)
    case sidebarToggle(columnVisibility: Binding<NavigationSplitViewVisibility>)
}

extension View {
    /// Apply inside the destination's own NavigationStack.
    @ViewBuilder
    func shellNavigationControl(_ control: ShellNavigationControl) -> some View {
        switch control {
        case .none:
            self
        case .drawer(let isOpen):
            toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HamburgerButton(sidebarOpen: isOpen)
                }
            }
        case .sidebarToggle(let columnVisibility):
            toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SidebarToggleButton(columnVisibility: columnVisibility)
                }
            }
        }
    }
}
