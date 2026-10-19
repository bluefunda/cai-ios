import SwiftUI

// MARK: - Inbox
// trm-ios's Messages screen was a placeholder, and NotificationsService exposes no
// activity feed — only unread counts per change request (UnreadCounts). So the Inbox
// lists the requests that have unread activity, straight from those counts, and
// otherwise says plainly what will appear here. No invented endpoint.

struct InboxView: View {
    @ObservedObject var state: RequestsState
    @EnvironmentObject var unreadPoller: UnreadCountPoller
    var navigationControl: ShellNavigationControl = .none

    private var unread: [UnreadCounts.PerChangeRequestUnreadCount] {
        (unreadPoller.counts?.perCRUnreadCounts ?? []).filter { $0.count > 0 }
    }

    var body: some View {
        NavigationStack {
            Group {
                if unread.isEmpty {
                    ContentUnavailableView(
                        "You're all caught up",
                        systemImage: "tray",
                        description: Text("Activity from your requests will show up here.")
                    )
                } else {
                    List(unread, id: \.crNumber) { item in
                        RequestRowLink(id: item.crNumber) {
                            InboxRow(item: item, known: knownRequest(item.crNumber))
                        }
                        .listRowBackground(BFColor.surfaceCanvas)
                        .listRowSeparatorTint(BFColor.hairline)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BFColor.surfaceCanvas)
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .shellNavigationControl(navigationControl)
            .navigationDestination(for: String.self) { id in
                ChangeRequestDetailView(changeRequestId: id, state: state)
            }
        }
    }

    /// Number and title when the request is already loaded or was viewed recently; the
    /// counts themselves only carry the id.
    private func knownRequest(_ id: String) -> RecentRequest? {
        if let cr = state.changeRequests?.changeRequests.first(where: { $0.id == id }) {
            return RecentRequest(id: cr.id, number: cr.requestNumber, title: cr.title)
        }
        return state.recents.items.first { $0.id == id }
    }
}

private struct InboxRow: View {
    let item: UnreadCounts.PerChangeRequestUnreadCount
    let known: RecentRequest?

    var body: some View {
        HStack(spacing: BFSpacing._3) {
            Circle()
                .fill(BFColor.primary)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(known?.number ?? "Request \(item.crNumber)")
                    .font(RQFont.number)
                    .foregroundStyle(.secondary)
                Text(known?.title ?? "New activity")
                    .font(RQFont.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text("\(item.count) new")
                .font(RQFont.meta.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(BFColor.primary)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}
