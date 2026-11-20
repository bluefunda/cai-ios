import Foundation

// MARK: - Inbox Store
// The bell's state: the unread badge and, while the panel is open, the list. The badge
// refreshes every `interval` only while BlueRequests is an available space and the app
// is in the foreground — `CAIApp` drives that through
// `update(isRequestsAvailable:isAppActive:)`, as it does UnreadCountPoller — so a
// personal-only user never calls trm-gw. A failed refresh keeps the last count.

@MainActor
final class InboxStore: ObservableObject {
    enum ListState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var unreadCount = 0
    @Published private(set) var items: [InboxItem] = []
    @Published private(set) var listState: ListState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var nextBefore: Date?

    static let pageSize = 20

    private let service: InboxServicing
    private let interval: TimeInterval
    private var pollTask: Task<Void, Never>?

    var isPolling: Bool { pollTask != nil }

    init(service: InboxServicing, interval: TimeInterval = 15) {
        self.service = service
        self.interval = interval
    }

    // MARK: Badge

    /// Starts or stops the badge refresh to match the current state. Idempotent. Losing
    /// the Requests space also clears the badge and list; backgrounding keeps them.
    func update(isRequestsAvailable: Bool, isAppActive: Bool) {
        if isRequestsAvailable && isAppActive {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refreshCount()
                    guard let interval = self?.interval else { return }
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
            }
        } else {
            pollTask?.cancel()
            pollTask = nil
            if !isRequestsAvailable {
                unreadCount = 0
                items = []
                listState = .idle
                nextBefore = nil
            }
        }
    }

    func refreshCount() async {
        if let count = try? await service.unreadCount() {
            unreadCount = count
        }
    }

    // MARK: List

    /// The first page, newest first. Called each time the panel opens.
    func load() async {
        listState = .loading
        do {
            let page = try await service.page(before: nil, limit: Self.pageSize)
            items = page.items
            unreadCount = page.unreadCount
            nextBefore = page.nextBefore
            listState = .loaded
        } catch {
            listState = .failed("Could not load notifications.")
        }
    }

    func loadMore() async {
        guard let before = nextBefore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await service.page(before: before, limit: Self.pageSize) else { return }
        items.append(contentsOf: page.items.filter { new in !items.contains { $0.id == new.id } })
        nextBefore = page.nextBefore
    }

    /// Marks one read at once (the row and badge update before the call), then re-reads
    /// the server's count.
    func markRead(_ item: InboxItem) async {
        guard item.isUnread, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].readAt = Date()
        unreadCount = max(0, unreadCount - 1)
        // Either way the server's count is read back, so the badge is right
        // everywhere once the read is saved (as on the web).
        try? await service.markRead(id: item.id)
        await refreshCount()
    }

    func markAllRead() async {
        let now = Date()
        for index in items.indices where items[index].isUnread {
            items[index].readAt = now
        }
        unreadCount = 0
        try? await service.markAllRead()
        await refreshCount()
    }
}
