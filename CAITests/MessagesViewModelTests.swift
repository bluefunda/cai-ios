import XCTest
@testable import CAI

// MARK: - Messages Flow
// New conversation (pick people → create → first message, retry-safe), the thread's
// paging merge and reply, and the list's ordering and search.

private struct StubError: LocalizedError {
    var errorDescription: String? { "stub failure" }
}

/// Records every call; each step can be made to fail.
private actor RecordingMessagesService: MessagesServicing {
    var conversations: [RQConversation] = []
    var pages: [[RQMessage]] = []
    var failCreate = false
    var failSendTimes = 0

    private(set) var created: [(topic: String, recipients: [String])] = []
    private(set) var sent: [(text: String, conversationId: String)] = []
    private(set) var seen: [String] = []

    func configure(conversations: [RQConversation] = [], pages: [[RQMessage]] = [],
                   failCreate: Bool = false, failSendTimes: Int = 0) {
        self.conversations = conversations
        self.pages = pages
        self.failCreate = failCreate
        self.failSendTimes = failSendTimes
    }

    func listConversations() async throws -> [RQConversation] { conversations }

    func messages(conversationId: String, before: String?, batchSize: Int) async throws -> [RQMessage] {
        pages.isEmpty ? [] : pages.removeFirst()
    }

    private(set) var sentAttachments: [[RQAttachment]] = []

    func send(_ text: String, attachments: [RQAttachment], conversationId: String) async throws {
        if failSendTimes > 0 {
            failSendTimes -= 1
            throw StubError()
        }
        sent.append((text, conversationId))
        sentAttachments.append(attachments)
    }

    func markSeen(conversationId: String) async throws { seen.append(conversationId) }

    func createConversation(topic: String, recipientIds: [String]) async throws -> String {
        if failCreate { throw StubError() }
        created.append((topic, recipientIds))
        return "conv-\(created.count)"
    }
}

private func adminUser(_ id: String, _ name: String) throws -> RQAdminUser {
    try JSONDecoder().decode(RQAdminUser.self, from: Data(#"{"id":"\#(id)","name":"\#(name)","email":"\#(id)@example.com"}"#.utf8))
}

private func message(_ id: Int, _ at: String, sender: String = "u-1") -> RQMessage {
    RQMessage(id: id, senderId: sender, text: "m\(id)", createdAtRaw: at, sender: nil)
}

@MainActor
final class NewConversationViewModelTests: XCTestCase {
    private func makeModel(_ service: RecordingMessagesService,
                           users: [RQAdminUser] = [],
                           searchError: Error? = nil) -> NewConversationViewModel {
        NewConversationViewModel(
            messagesService: service,
            searchUsers: { _ in
                if let searchError { throw searchError }
                return users
            },
            currentUserId: "me"
        )
    }

    func test_search_hidesCurrentUserAndPeopleAlreadyAdded() async throws {
        let users = [try adminUser("me", "Me"), try adminUser("u-1", "Ann"), try adminUser("u-2", "Bob")]
        let model = makeModel(RecordingMessagesService(), users: users)

        await model.search()
        XCTAssertEqual(model.matches.map(\.id), ["u-1", "u-2"])

        model.add(users[1])
        XCTAssertEqual(model.recipients.map(\.id), ["u-1"])
        XCTAssertEqual(model.matches.map(\.id), ["u-2"])

        await model.search()
        XCTAssertEqual(model.matches.map(\.id), ["u-2"], "an added person isn't offered again")
    }

    /// As the web's drawer: everyone loads once, and typing matches name or email here
    /// (the server's name+active filter found no one in production).
    func test_search_loadsEveryoneOnceAndMatchesNameOrEmail() async throws {
        let users = [try adminUser("u-1", "Phani Kumar"), try adminUser("u-2", "Bob"), try adminUser("pha", "Zed")]
        var loads: [String] = []
        let model = NewConversationViewModel(
            messagesService: RecordingMessagesService(),
            searchUsers: { query in loads.append(query); return users },
            currentUserId: "me")

        model.searchText = "pha"
        await model.search()
        XCTAssertEqual(model.matches.map(\.name), ["Phani Kumar", "Zed"], "name, or email (pha@example.com)")
        model.searchText = "BOB"
        await model.search()
        XCTAssertEqual(model.matches.map(\.id), ["u-2"], "case doesn't matter")
        XCTAssertEqual(loads, [""], "one unfiltered load, as the web's getSystemUserApp()")
    }

    func test_search_hidesDeactivatedUsers() async throws {
        func user(_ json: String) throws -> RQAdminUser {
            try JSONDecoder().decode(RQAdminUser.self, from: Data(json.utf8))
        }
        let users = [
            try user(#"{"id":"a","name":"Active Ann","status":true}"#),
            try user(#"{"id":"b","name":"Gone Bob","status":false}"#),
            try user(#"{"id":"c","name":"Text Cy","status":"in-active"}"#),
            try user(#"{"id":"d","name":"Unknown Dee"}"#)
        ]
        let model = NewConversationViewModel(messagesService: RecordingMessagesService(),
                                             searchUsers: { _ in users }, currentUserId: "me")
        await model.search()
        XCTAssertEqual(model.matches.map(\.id), ["a", "d"], "deactivated hidden; no status counts as active")
    }

    func test_addTwice_keepsOneRecipient_andRemoveWorks() throws {
        let ann = try adminUser("u-1", "Ann")
        let model = makeModel(RecordingMessagesService())
        model.add(ann)
        model.add(ann)
        XCTAssertEqual(model.recipients.count, 1)
        model.remove(ann)
        XCTAssertTrue(model.recipients.isEmpty)
    }

    func test_searchFailure_setsError_andNextSuccessClearsIt() async throws {
        let failing = makeModel(RecordingMessagesService(), searchError: StubError())
        await failing.search()
        XCTAssertEqual(failing.error, "stub failure")
        XCTAssertTrue(failing.matches.isEmpty)
    }

    func test_canSend_needsRecipientAndNonBlankMessage() throws {
        let model = makeModel(RecordingMessagesService())
        XCTAssertFalse(model.canSend)
        model.add(try adminUser("u-1", "Ann"))
        XCTAssertFalse(model.canSend)
        model.message = "   \n "
        XCTAssertFalse(model.canSend, "whitespace isn't a message")
        model.message = "Hello"
        XCTAssertTrue(model.canSend)
    }

    func test_send_createsConversationThenPostsFirstMessage() async throws {
        let service = RecordingMessagesService()
        let model = makeModel(service)
        model.add(try adminUser("u-1", "Ann"))
        model.topic = "  Rollout #42 "
        model.message = "  Hello team  "

        let id = await model.send()

        XCTAssertEqual(id, "conv-1")
        let created = await service.created
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(created.first?.topic, "Rollout #42")
        XCTAssertEqual(created.first?.recipients, ["u-1"])
        let sent = await service.sent
        XCTAssertEqual(sent.map(\.text), ["Hello team"])
        XCTAssertEqual(sent.map(\.conversationId), ["conv-1"])
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isSending)
    }

    func test_emptyTopic_fallsBackToStartOfMessage() async throws {
        let service = RecordingMessagesService()
        let model = makeModel(service)
        model.add(try adminUser("u-1", "Ann"))
        model.message = String(repeating: "a", count: 120)

        _ = await model.send()

        let topic = await service.created.first?.topic
        XCTAssertEqual(topic?.count, 80)
    }

    func test_firstMessageFails_retryResendsWithoutCreatingAnotherConversation() async throws {
        let service = RecordingMessagesService()
        await service.configure(failSendTimes: 1)
        let model = makeModel(service)
        let ann = try adminUser("u-1", "Ann")
        model.add(ann)
        model.message = "Hello"

        let first = await model.send()
        XCTAssertNil(first)
        XCTAssertEqual(model.createdConversationId, "conv-1")
        XCTAssertNotNil(model.error)

        model.remove(ann)
        XCTAssertEqual(model.recipients.count, 1, "recipients are fixed once the conversation exists")

        let retry = await model.send()
        XCTAssertEqual(retry, "conv-1")
        let created = await service.created.count
        XCTAssertEqual(created, 1, "the retry must not create a duplicate conversation")
        let sent = await service.sent.map(\.conversationId)
        XCTAssertEqual(sent, ["conv-1"])
        XCTAssertNil(model.error)
    }

    func test_createFails_reportsErrorAndSendsNothing() async throws {
        let service = RecordingMessagesService()
        await service.configure(failCreate: true)
        let model = makeModel(service)
        model.add(try adminUser("u-1", "Ann"))
        model.message = "Hello"

        let id = await model.send()

        XCTAssertNil(id)
        XCTAssertNil(model.createdConversationId)
        XCTAssertEqual(model.error, "stub failure")
        let sent = await service.sent
        XCTAssertTrue(sent.isEmpty)
    }
}

@MainActor
final class ConversationViewModelTests: XCTestCase {
    private let conversation = RQConversation(
        id: "c-1", topic: "", isGroup: false, lastMessage: nil,
        participants: [RQParticipant(id: "u-1", name: "Ann", profileImage: nil)], unreadCount: 1
    )

    func test_load_ordersOldestFirst_dedupesOverlappingPages_andMarksSeen() async {
        let service = RecordingMessagesService()
        // Pages overlap at their boundary (the backend's page is inclusive).
        await service.configure(pages: [
            [message(3, "2026-11-03T10:03:00Z"), message(2, "2026-11-03T10:02:00Z")],
            [message(2, "2026-11-03T10:02:00Z"), message(1, "2026-11-03T10:01:00Z")]
        ])
        let model = ConversationViewModel(conversation: conversation, service: service, currentUserId: "me")

        await model.load()
        XCTAssertEqual(model.messages.map(\.id), [2, 3])
        let seen = await service.seen
        XCTAssertEqual(seen, ["c-1"])

        await model.refreshLatest()
        XCTAssertEqual(model.messages.map(\.id), [1, 2, 3], "merged by id, no duplicate of 2")
    }

    func test_send_clearsDraftOnSuccess_keepsItOnFailure() async {
        let service = RecordingMessagesService()
        await service.configure(failSendTimes: 1)
        let model = ConversationViewModel(conversation: conversation, service: service, currentUserId: "me")

        model.draft = "Reply"
        await model.send()
        XCTAssertEqual(model.draft, "Reply", "a failed send keeps the text so it isn't lost")
        XCTAssertNotNil(model.error)

        await model.send()
        XCTAssertEqual(model.draft, "")
        let sent = await service.sent.map(\.text)
        XCTAssertEqual(sent, ["Reply"])
    }

    func test_attachmentGoesWithTheNextMessage() async throws {
        let service = RecordingMessagesService()
        let model = ConversationViewModel(conversation: conversation, service: service, currentUserId: "me",
                                          attachmentService: FixtureAttachmentService())
        XCTAssertFalse(model.canSend)

        await model.attach(fileURL: URL(fileURLWithPath: "/tmp/spec.pdf"))
        XCTAssertEqual(model.pendingAttachments.map(\.fileName), ["spec.pdf"])
        XCTAssertTrue(model.canSend, "a file alone can be sent, as on the web")

        await model.send()
        let sent = await service.sentAttachments
        XCTAssertEqual(sent.first?.map(\.fileName), ["spec.pdf"])
        XCTAssertTrue(model.pendingAttachments.isEmpty)

        await model.attach(fileURL: URL(fileURLWithPath: "/tmp/a.txt"))
        model.removePending(model.pendingAttachments[0])
        XCTAssertFalse(model.canSend)
    }

    func test_withoutAnAttachmentService_attachingIsOff() {
        let model = ConversationViewModel(conversation: conversation, service: RecordingMessagesService(), currentUserId: "me")
        XCTAssertFalse(model.canAttach)
    }

    func test_blankDraft_isNotSent() async {
        let service = RecordingMessagesService()
        let model = ConversationViewModel(conversation: conversation, service: service, currentUserId: "me")
        model.draft = "   "
        XCTAssertFalse(model.canSend)
        await model.send()
        let sent = await service.sent
        XCTAssertTrue(sent.isEmpty)
    }

    func test_isMine_comparesSender() {
        let model = ConversationViewModel(conversation: conversation, service: RecordingMessagesService(), currentUserId: "me")
        XCTAssertTrue(model.isMine(message(1, "2026-11-03T10:00:00Z", sender: "me")))
        XCTAssertFalse(model.isMine(message(2, "2026-11-03T10:00:00Z", sender: "u-1")))
    }
}

@MainActor
final class MessagesListViewModelTests: XCTestCase {
    func test_load_sortsNewestFirst_andSearchMatchesTopicOrPeople() async {
        let service = RecordingMessagesService()
        let older = RQConversation(id: "a", topic: "Release plan", isGroup: false,
                                   lastMessage: message(1, "2026-11-01T10:00:00Z"),
                                   participants: [RQParticipant(id: "u-1", name: "Ann", profileImage: nil)], unreadCount: 0)
        let newer = RQConversation(id: "b", topic: "", isGroup: false,
                                   lastMessage: message(2, "2026-11-03T10:00:00Z"),
                                   participants: [RQParticipant(id: "u-2", name: "Bob", profileImage: nil)], unreadCount: 2)
        await service.configure(conversations: [older, newer])
        let model = MessagesListViewModel(service: service, currentUserId: "me")

        await model.load()
        XCTAssertEqual(model.conversations.map(\.id), ["b", "a"])
        XCTAssertTrue(model.hasLoaded)

        model.searchText = "release"
        XCTAssertEqual(model.filteredConversations.map(\.id), ["a"])
        model.searchText = "bob"
        XCTAssertEqual(model.filteredConversations.map(\.id), ["b"])
    }
}
