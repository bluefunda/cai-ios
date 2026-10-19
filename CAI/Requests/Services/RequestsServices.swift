import SwiftUI

// MARK: - Requests Services
// One shared RequestsAPIClient (and its token-provider closure) backing every
// BlueRequests domain service, so services never need their own token-refresh logic —
// they all defer to cai's AuthManager, the app's single identity (P1). Ported from
// trm-ios's AppServices.

struct RequestsServices {
    let changeRequestService: ChangeRequestServicing
    let commentService: CommentServicing
    let notificationsService: NotificationsServicing
    let profileService: ProfileServicing
    let projectService: ProjectServicing
    let releaseService: ReleaseServicing
    let referenceDataService: ReferenceDataServicing
    let attachmentService: AttachmentServicing
    let crFileService: CRFileServicing
    let teamService: TeamServicing

    init(authManager: AuthManager, useFixtures: Bool = BFFeatureFlags.requestsFixtures) {
        if useFixtures {
            projectService = FixtureProjectService()
            changeRequestService = FixtureChangeRequestService()
            commentService = FixtureCommentService()
            notificationsService = FixtureNotificationsService()
            profileService = FixtureProfileService()
            releaseService = FixtureReleaseService()
            referenceDataService = FixtureReferenceDataService()
            attachmentService = FixtureAttachmentService()
            crFileService = FixtureCRFileService()
            teamService = FixtureTeamService()
            return
        }

        // validAccessToken() refreshes when near expiry. A nil here means there's no
        // usable session at all; this client never ends one itself (see RequestsAPIError).
        let client = RequestsAPIClient(baseURL: AppConfig.requestsBaseURL) { [weak authManager] in
            guard let token = await authManager?.validAccessToken() else {
                throw RequestsAPIError.notSignedIn
            }
            return token
        }
        let currentUserProvider: @Sendable () async -> User? = { [weak authManager] in await authManager?.currentUser }

        projectService = ProjectService(client: client)
        changeRequestService = ChangeRequestService(client: client, projectService: projectService)
        commentService = CommentService(client: client, currentUserProvider: currentUserProvider)
        notificationsService = NotificationsService(client: client, currentUserProvider: currentUserProvider)
        profileService = ProfileService(client: client)
        releaseService = ReleaseService(client: client)
        referenceDataService = ReferenceDataService(client: client)
        attachmentService = AttachmentService(client: client, currentUserProvider: currentUserProvider)
        crFileService = CRFileService(client: client)
        teamService = TeamService(client: client)
    }
}

// MARK: - Environment Injection

private struct RequestsServicesKey: EnvironmentKey {
    /// No default instance on purpose: CAIApp sets this explicitly, and a missing value
    /// should fail loudly in previews/tests rather than silently talk to the network
    /// with no auth.
    static let defaultValue: RequestsServices? = nil
}

extension EnvironmentValues {
    var requestsServices: RequestsServices? {
        get { self[RequestsServicesKey.self] }
        set { self[RequestsServicesKey.self] = newValue }
    }
}
