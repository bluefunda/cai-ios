import SwiftUI

struct HamburgerButton: View {
    @Binding var sidebarOpen: Bool
    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { sidebarOpen.toggle() }
        } label: {
            VStack(spacing: 5) {
                Capsule().frame(width: 22, height: 2)
                Capsule().frame(width: 22, height: 2)
            }
            .foregroundStyle(BFColor.primary)
        }
        .accessibilityIdentifier("hamburgerButton")
    }
}

// MARK: - Top Bar (iPhone only — iPad/Mac use real .toolbar items, see AppShell.iPadLayout)

struct ChatTopBar: View {
    @EnvironmentObject var chatManager: ChatManager
    @Binding var sidebarOpen: Bool
    let onNewChat: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HamburgerButton(sidebarOpen: $sidebarOpen)
            NewChatButton(action: onNewChat)
            Spacer()
            AttachmentButton(conversationId: chatManager.currentConversation?.id)
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Code Top Bar

struct CodeTopBar: View {
    @Binding var sidebarOpen: Bool
    let onSystems: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HamburgerButton(sidebarOpen: $sidebarOpen)

            Text("Code")
                .font(BFFont.h5)

            Spacer()

            Button(action: onSystems) {
                Image(systemName: "server.rack")
                    .font(.system(size: BFFont.toolbarIconPt))
            }
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - New Chat / Attachment (shared by iPhone's inline bar and iPad/Mac's toolbar)

// iPad/Mac only — toggles the sidebar column (cai-ios#256). Lives in the
// detail column's trailing toolbar group, next to Attachment.
struct SidebarToggleButton: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility

    var body: some View {
        Button {
            withAnimation {
                columnVisibility = columnVisibility == .detailOnly ? .doubleColumn : .detailOnly
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: BFFont.toolbarIconPt))
        }
    }
}

#if targetEnvironment(macCatalyst)
import UIKit

// Mac Catalyst bridges NavigationSplitView to a real UISplitViewController,
// which always draws its own native sidebar-toggle icon at the window's
// top-left — that's native window chrome, not a SwiftUI toolbar item, so
// none of SwiftUI's .toolbar APIs can remove it. This finds that ancestor
// and sets displayModeButtonVisibility = .never on it, which IS applied
// (confirmed via logging) but does NOT actually remove the button — Mac
// Catalyst's top-left toggle isn't governed by this UIKit-level property
// the way it is on iPadOS. Left in as a harmless no-op pending a real fix;
// tabled for now (cai-ios#256) — see that issue before spending more time
// here. Next step if revisited: this needs reasserting continuously (e.g.
// viewDidLayoutSubviews on a UIViewController subclass) rather than once,
// and/or the button may only be removable via NSToolbar-level APIs that
// aren't reachable from pure UIKit code in a Catalyst target.
private struct HideNativeSplitViewToggle: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            var responder: UIResponder? = uiViewController
            while let current = responder {
                if let split = current as? UISplitViewController {
                    split.displayModeButtonVisibility = .never
                    split.presentsWithGesture = false
                    return
                }
                responder = (current as? UIViewController)?.parent ?? current.next
            }
        }
    }
}

extension View {
    func hidingNativeSplitViewToggle() -> some View {
        background(HideNativeSplitViewToggle().frame(width: 0, height: 0))
    }
}
#endif

struct NewChatButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: BFFont.toolbarIconPt))
        }
        .foregroundStyle(BFColor.primary)
    }
}

struct AttachmentButton: View {
    // Always visible (rather than only appearing once a conversation exists)
    // for a consistent toolbar across screens — disabled until there's a
    // conversation to attach files to.
    let conversationId: String?
    @State private var showFiles = false

    var body: some View {
        Button { showFiles = true } label: {
            Image(systemName: "paperclip")
                .font(.system(size: BFFont.toolbarIconPt - 2))
        }
        .foregroundStyle(.secondary)
        .disabled(conversationId == nil)
        .sheet(isPresented: $showFiles) {
            if let conversationId {
                NavigationStack {
                    ConversationFilesView(conversationId: conversationId)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showFiles = false }
                            }
                        }
                }
            }
        }
    }
}
