import XCTest
@testable import CAI

// MARK: - Notifications Bell
// The badge's polling lifecycle, the list's paging, and marking read (optimistic, with
// the count re-read when the server refuses).

private struct StubError: Error {}

private actor RecordingInboxService: InboxServicing {
    var pages: [InboxPage] = []
    var count = 0
    var failList = false
    var failMark = false
    private(set) var befores: [Date?] = []
    private(set) var marked: [String] = []
    private(set) var markedAll = 0

    func configure(pages: [InboxPage] = [], count: Int = 0, failList: Bool = false, failMark: Bool = false) {
        self.pages = pages
        self.count = count
        self.failList = failList
        self.failMark = failMark
    }

    func page(before: Date?, limit: Int) async throws -> InboxPage {
        befores.append(before)
        if failList { throw StubError() }
        return pages.isEmpty ? InboxPage(items: [], unreadCount: count, nextBefore: nil) : pages.removeFirst()
    }

    func unreadCount() async throws -> Int { count }

    func markRead(id: String) async throws {
        marked.append(id)
        if failMark { throw StubError() }
    }

    func markAllRead() async throws {
        markedAll += 1
        if failMark { throw StubError() }
    }
}

private func item(_ id: String, minutesAgo: Double, read: Bool = false) -> InboxItem {
    let at = Date().addingTimeInterval(-minutesAgo * 60)
    return InboxItem(
        id: id, type: "cr.approved", changeRequestId: 7, title: "CR-7 \(id)", summary: "",
        actorName: "Ada", createdAt: at, readAt: read ? at : nil
    )
}

@MainActor
final class InboxStoreTests: XCTestCase {
    func test_pollsOnlyWhenRequestsAvailableAndAppActive_andLosingItClears() async throws {
        let service = RecordingInboxService()
        await service.configure(count: 3)
        let store = InboxStore(service: service, interval: 3600)

        store.update(isRequestsAvailable: false, isAppActive: true)
        XCTAssertFalse(store.isPolling)
        store.update(isRequestsAvailable: true, isAppActive: true)
        XCTAssertTrue(store.isPolling)
        for _ in 0..<50 where store.unreadCount == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(store.unreadCount, 3)

        store.update(isRequestsAvailable: true, isAppActive: false)
        XCTAssertFalse(store.isPolling)
        XCTAssertEqual(store.unreadCount, 3, "backgrounding keeps the badge")
        store.update(isRequestsAvailable: false, isAppActive: false)
        XCTAssertEqual(store.unreadCount, 0)
    }

    func test_loadAndLoadMorePageNewestFirst() async {
        let service = RecordingInboxService()
        let boundary = Date().addingTimeInterval(-600)
        await service.configure(pages: [
            InboxPage(items: [item("a", minutesAgo: 1), item("b", minutesAgo: 10)],
                      unreadCount: 2, nextBefore: boundary),
            InboxPage(items: [item("c", minutesAgo: 20, read: true)], unreadCount: 2, nextBefore: nil),
        ])
        let store = InboxStore(service: service)

        await store.load()
        XCTAssertEqual(store.listState, .loaded)
        XCTAssertEqual(store.items.map(\.id), ["a", "b"])
        XCTAssertEqual(store.unreadCount, 2)
        XCTAssertEqual(store.nextBefore, boundary)

        await store.loadMore()
        XCTAssertEqual(store.items.map(\.id), ["a", "b", "c"])
        XCTAssertNil(store.nextBefore)
        let befores = await service.befores
        XCTAssertEqual(befores, [nil, boundary])
    }

    func test_loadFailureShowsAnError() async {
        let service = RecordingInboxService()
        await service.configure(failList: true)
        let store = InboxStore(service: service)
        await store.load()
        XCTAssertEqual(store.listState, .failed("Could not load notifications."))
    }

    func test_markReadIsOptimistic_andRereadsTheCount() async {
        let service = RecordingInboxService()
        await service.configure(pages: [
            InboxPage(items: [item("a", minutesAgo: 1), item("b", minutesAgo: 2), item("c", minutesAgo: 3, read: true)],
                      unreadCount: 2, nextBefore: nil),
        ], count: 2)
        let store = InboxStore(service: service)
        await store.load()

        await service.configure(count: 1) // the server's count once the read is saved
        await store.markRead(store.items[0])
        XCTAssertFalse(store.items[0].isUnread)
        XCTAssertEqual(store.unreadCount, 1, "the server's count is read back")
        await store.markRead(store.items[2])
        let marked = await service.marked
        XCTAssertEqual(marked, ["a"], "an already-read one is not sent")

        await service.configure(count: 1, failMark: true)
        await store.markRead(store.items[1])
        XCTAssertEqual(store.unreadCount, 1, "the server's count after a refused mark")
    }

    func test_markAllRead() async {
        let service = RecordingInboxService()
        await service.configure(pages: [
            InboxPage(items: [item("a", minutesAgo: 1), item("b", minutesAgo: 2)], unreadCount: 2, nextBefore: nil),
        ])
        let store = InboxStore(service: service)
        await store.load()
        await store.markAllRead()
        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertTrue(store.items.allSatisfy { !$0.isUnread })
        let markedAll = await service.markedAll
        XCTAssertEqual(markedAll, 1)
    }

    func test_pageDecodesTheServerShape() throws {
        let json = """
        {"items":[{"id":"n1","type":"comment.mentioned","changeRequestId":7,"title":"Bob mentioned you on CR-7",
        "summary":"check?","actorName":"Bob","createdAt":"2026-11-20T09:00:00.123Z","readAt":null},
        {"id":"n2","type":"cr.completed","changeRequestId":null,"title":"t","summary":"","actorName":"",
        "conversationId":"c9",
        "createdAt":"2026-11-20T08:00:00Z","readAt":"2026-11-20T08:30:00Z"}],
        "unreadCount":1,"nextBefore":null}
        """
        let page = try RequestsAPIClient.makeDecoder().decode(InboxPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.count, 2)
        XCTAssertTrue(page.items[0].isUnread)
        XCTAssertEqual(page.items[0].changeRequestId, 7)
        XCTAssertNil(page.items[1].changeRequestId)
        XCTAssertNil(page.items[0].conversationId)
        XCTAssertEqual(page.items[1].conversationId, "c9", "a message entry names its conversation")
        XCTAssertFalse(page.items[1].isUnread)
        XCTAssertNil(page.nextBefore)
    }
}

// MARK: - Push Notifications
// What a tapped push opens, from its data.

final class PushTargetTests: XCTestCase {
    func test_requestWinsOverConversation_andNumbersAreAccepted() {
        XCTAssertEqual(PushTarget(userInfo: ["changeRequestId": "7", "conversationId": "c1"]), .request(id: "7"))
        XCTAssertEqual(PushTarget(userInfo: ["changeRequestId": NSNumber(value: 42)]), .request(id: "42"))
        XCTAssertEqual(PushTarget(userInfo: ["conversationId": "c1"]), .conversation(id: "c1"))
    }

    func test_nothingToOpen() {
        XCTAssertNil(PushTarget(userInfo: [:]))
        XCTAssertNil(PushTarget(userInfo: ["changeRequestId": "", "type": "cr.approved"]))
    }
}
