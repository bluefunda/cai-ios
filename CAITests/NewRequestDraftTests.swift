import XCTest
@testable import CAI

// MARK: - New Request Draft Tests
// The web's newRequestDraft.js (#322): a half-filled New request is kept per user and per
// project, restored with its choices, expires after a week, and is cleared on Create,
// Discard draft and Cancel > Discard, and kept by Cancel > Save as draft. A form started from an assistant answer keeps its chat.

@MainActor
final class NewRequestDraftTests: XCTestCase {
    private nonisolated static let suiteName = "NewRequestDraftTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    private func store(user: String = "u-1", project: String? = nil, now: @escaping () -> Date = Date.init) -> NewRequestDraftStore {
        NewRequestDraftStore(userId: user, projectId: project, defaults: defaults, now: now)
    }

    private func makeModel(lockedProjectId: String? = nil) -> NewChangeRequestViewModel {
        NewChangeRequestViewModel(
            changeRequestService: FixtureChangeRequestService(),
            projectService: FixtureProjectService(),
            referenceDataService: FixtureReferenceDataService(),
            currentUserId: "u-1",
            lockedProjectId: lockedProjectId,
            draftStore: store(project: lockedProjectId)
        )
    }

    // MARK: Store

    func test_store_isPerUserAndPerProject() {
        var draft = NewRequestDraft()
        draft.requestName = "Add index"
        store().save(draft)

        XCTAssertEqual(store().read()?.requestName, "Add index")
        XCTAssertNil(store(user: "u-2").read(), "another account doesn't see it")
        XCTAssertNil(store(project: "28").read(), "a project's form has its own draft")
    }

    func test_store_expiresAfterAWeek() {
        var draft = NewRequestDraft()
        draft.requestName = "Old"
        let saved = Date()
        store(now: { saved }).save(draft)

        XCTAssertNotNil(store(now: { saved.addingTimeInterval(6 * 24 * 3600) }).read())
        XCTAssertNil(store(now: { saved.addingTimeInterval(7 * 24 * 3600 + 1) }).read())
        XCTAssertNil(store().read(), "an expired draft is dropped")
    }

    func test_hasContent_ignoresTheProjectAndOwnerFilledInOnTheirOwn() {
        var draft = NewRequestDraft()
        draft.projectId = "28"
        draft.ownerId = "u-1"
        XCTAssertFalse(draft.hasContent)
        draft.severityId = "3"
        XCTAssertTrue(draft.hasContent)
    }

    // MARK: Form

    func test_draft_savedAsTypedAndRestoredOnReopen() async {
        let first = makeModel()
        await first.loadOptions()
        XCTAssertFalse(first.isDraftRestored)
        first.requestName = "Add index"
        first.description = "Nightly report times out."
        first.selectedProjectId = "14"
        first.selectedSeverityId = "3"
        first.saveDraft()

        let reopened = makeModel()
        await reopened.loadOptions()
        XCTAssertTrue(reopened.isDraftRestored, "shows Draft restored")
        XCTAssertEqual(reopened.requestName, "Add index")
        XCTAssertEqual(reopened.description, "Nightly report times out.")
        XCTAssertEqual(reopened.selectedProjectId, "14")
        XCTAssertEqual(reopened.selectedSeverityId, "3")
        XCTAssertEqual(reopened.selectedOwnerId, "u-1")
    }

    func test_draft_notSavedBeforeTheRestore() async {
        var saved = NewRequestDraft()
        saved.requestName = "Kept"
        store().save(saved)

        let model = makeModel()
        model.saveDraft()  // the blank form, before loadOptions restored the draft
        XCTAssertEqual(store().read()?.requestName, "Kept")
    }

    func test_draft_clearedWhenTheFormIsEmptiedAgain() async {
        let model = makeModel()
        await model.loadOptions()
        model.requestName = "x"
        model.saveDraft()
        XCTAssertNotNil(store().read())
        model.requestName = ""
        model.saveDraft()
        XCTAssertNil(store().read())
    }

    func test_draft_clearedOnCreate() async {
        let model = makeModel()
        await model.loadOptions()
        model.requestName = "Add index"
        model.description = "Nightly report times out."
        model.selectedProjectId = "28"
        model.selectedRequestTypeId = "1"
        model.selectedSeverityId = "3"
        model.saveDraft()

        let created = await model.submit()
        XCTAssertNotNil(created)
        XCTAssertNil(store().read())
        model.saveDraft()
        XCTAssertNil(store().read(), "nothing is saved after Create")
    }

    func test_discardDraft_startsTheFormOver() async {
        let first = makeModel()
        await first.loadOptions()
        first.requestName = "Add index"
        first.selectedRequestTypeId = "1"
        first.saveDraft()

        let model = makeModel()
        await model.loadOptions()
        model.discardDraft()
        XCTAssertFalse(model.isDraftRestored)
        XCTAssertEqual(model.requestName, "")
        XCTAssertNil(model.selectedRequestTypeId)
        XCTAssertEqual(model.selectedOwnerId, "u-1", "the owner refills as on open")
        XCTAssertNil(store().read())
    }

    func test_cancel_finishesTheDraft() async {
        let model = makeModel()
        await model.loadOptions()
        model.requestName = "Add index"
        model.saveDraft()

        model.finishDraft()
        XCTAssertNil(store().read())
        model.saveDraft()
        XCTAssertNil(store().read())
    }

    func test_cancelSaveAsDraft_keepsTheLatestDraft() async {
        let model = makeModel()
        await model.loadOptions()
        model.requestName = "Add index"
        model.saveDraft()
        model.description = "Latest edit"

        model.keepDraft()
        XCTAssertEqual(store().read()?.description, "Latest edit")

        let reopened = makeModel()
        await reopened.loadOptions()
        XCTAssertTrue(reopened.isDraftRestored)
        XCTAssertEqual(reopened.requestName, "Add index")
        XCTAssertEqual(reopened.description, "Latest edit")
    }

    func test_projectDraft_keepsItsLockedProject() async {
        let first = makeModel(lockedProjectId: "9")
        await first.loadOptions()
        first.requestName = "For Platform"
        first.saveDraft()

        XCTAssertNil(store().read(), "not the general draft")
        let reopened = makeModel(lockedProjectId: "9")
        await reopened.loadOptions()
        XCTAssertEqual(reopened.requestName, "For Platform")
        XCTAssertEqual(reopened.selectedProjectId, "9")
    }

    // MARK: From an assistant answer

    func test_answerDraft_keepsItsChatAndResumesForTheSameChat() async {
        let prefill = NewRequestPrefill(chatTitle: "Slow report", answerMarkdown: "Add an index.", conversationId: "chat-1")
        let first = makeModel().applying(prefill)
        await first.loadOptions()
        first.requestName = "Edited name"
        first.saveDraft()
        XCTAssertEqual(store().read()?.conversationId, "chat-1")

        let again = makeModel().applying(prefill)
        await again.loadOptions()
        XCTAssertTrue(again.isDraftRestored)
        XCTAssertEqual(again.requestName, "Edited name", "the same answer resumes the edits")
        XCTAssertEqual(again.linkedConversationId, "chat-1")

        // New request from the list restores it too, still linked to the chat.
        let fromList = makeModel()
        await fromList.loadOptions()
        XCTAssertEqual(fromList.requestName, "Edited name")
        XCTAssertEqual(fromList.linkedConversationId, "chat-1")
    }

    func test_answerFromAnotherChat_replacesTheDraft() async {
        var saved = NewRequestDraft()
        saved.requestName = "Other work"
        saved.conversationId = "chat-old"
        store().save(saved)

        let prefill = NewRequestPrefill(chatTitle: "Slow report", answerMarkdown: "Add an index.", conversationId: "chat-1")
        let model = makeModel().applying(prefill)
        await model.loadOptions()
        XCTAssertFalse(model.isDraftRestored)
        XCTAssertEqual(model.requestName, "Slow report")
        model.saveDraft()
        XCTAssertEqual(store().read()?.conversationId, "chat-1")
    }
}
