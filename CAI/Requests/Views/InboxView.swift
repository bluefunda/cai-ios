import SwiftUI

// MARK: - Notifications bell
// The bell in the sidebar header while in the Requests space: the unread badge, and on
// tap the list — a popover on iPad and Mac, a sheet on iPhone (a popover's compact
// adaptation). Opening a notification marks it read and opens its change request.

struct InboxBellButton: View {
    @EnvironmentObject var inbox: InboxStore
    @State private var isOpen = false
    /// Opens a change request by id; the caller also closes the drawer.
    let onOpenRequest: (String) -> Void
    /// Opens a conversation by id (a direct-message entry).
    var onOpenConversation: (String) -> Void = { _ in }

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Image(systemName: "bell")
                .font(.system(size: BFFont.toolbarIconPt - 2))
                .foregroundStyle(BFColor.primary)
                .overlay(alignment: .topTrailing) {
                    if inbox.unreadCount > 0 {
                        UnreadBadge(count: inbox.unreadCount)
                            .offset(x: 10, y: -8)
                    }
                }
                .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notifications")
        .accessibilityValue(inbox.unreadCount > 0 ? "\(inbox.unreadCount) unread" : "")
        .accessibilityIdentifier("sidebar.notifications")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            InboxListView { item in
                isOpen = false
                // A message entry opens its conversation; anything else, its request.
                if let conversationId = item.conversationId, !conversationId.isEmpty {
                    onOpenConversation(conversationId)
                } else if let id = item.changeRequestId {
                    onOpenRequest(String(id))
                }
            }
            .frame(minWidth: 340, idealWidth: 380, minHeight: 360, idealHeight: 480)
        }
    }
}

struct InboxListView: View {
    @EnvironmentObject var inbox: InboxStore
    @Environment(\.dismiss) private var dismiss
    let onOpen: (InboxItem) -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Notifications")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") {
                            Task { await inbox.markAllRead() }
                        }
                        .disabled(inbox.unreadCount == 0)
                    }
                }
        }
        .task { await inbox.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch inbox.listState {
        case .idle, .loading:
            ProgressView("Loading notifications…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary)
                Button("Retry") { Task { await inbox.load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded where inbox.items.isEmpty:
            ContentUnavailableView(
                "You're all caught up",
                systemImage: "bell",
                description: Text("Approvals, decisions and mentions on your requests show up here.")
            )
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            ForEach(inbox.items) { item in
                Button {
                    Task { await inbox.markRead(item) }
                    onOpen(item)
                } label: {
                    InboxRow(item: item)
                }
                .buttonStyle(.plain)
                .listRowBackground(item.isUnread ? BFColor.primary.opacity(0.06) : Color.clear)
            }
            if inbox.nextBefore != nil {
                Button(inbox.isLoadingMore ? "Loading…" : "Show older") {
                    Task { await inbox.loadMore() }
                }
                .disabled(inbox.isLoadingMore)
                .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
        .refreshable { await inbox.load() }
    }
}

private struct InboxRow: View {
    let item: InboxItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // The kind's icon in a tinted circle; an unread one carries a blue dot.
            Image(systemName: item.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if item.isUnread {
                        Circle()
                            .fill(BFColor.primary)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(item.isUnread ? RQFont.rowTitle : RQFont.body)
                    .foregroundStyle(.primary)
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(RQFont.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(meta)
                    .font(RQFont.meta)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isUnread ? "Unread" : "")
    }

    private var tint: Color {
        switch item.kind {
        case .action: return .orange
        case .good: return .green
        case .bad: return .red
        case .info: return BFColor.primary
        }
    }

    private var meta: String {
        let when = item.createdAt.formatted(.relative(presentation: .named))
        return item.actorName.isEmpty ? when : "\(item.actorName) · \(when)"
    }
}
