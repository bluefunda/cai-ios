import Foundation

@MainActor
final class NewChangeRequestViewModel: ObservableObject {
    @Published var requestName = ""
    @Published var description = ""
    @Published var selectedProjectId: String?
    @Published var selectedRequestTypeId: String?
    @Published var selectedSeverityId: String?
    @Published var selectedOwnerId: String?
    @Published var ticketUrl = ""

    @Published private(set) var projects: [RQProject] = []
    @Published private(set) var requestTypes: [RequestTypeOption] = []
    @Published private(set) var severities: [SeverityOption] = []
    @Published private(set) var users: [UserOption] = []

    @Published private(set) var isLoadingOptions = false
    @Published private(set) var isSubmitting = false
    @Published var error: String?

    /// Set when launched from Project Detail — locks the Project picker to that project,
    /// matching how trm's own web form pre-fills (but still shows) the project field there.
    let lockedProjectId: String?

    private let changeRequestService: ChangeRequestServicing
    private let projectService: ProjectServicing
    private let referenceDataService: ReferenceDataServicing
    private let currentUserId: String?

    init(
        changeRequestService: ChangeRequestServicing,
        projectService: ProjectServicing,
        referenceDataService: ReferenceDataServicing,
        currentUserId: String?,
        lockedProjectId: String? = nil
    ) {
        self.changeRequestService = changeRequestService
        self.projectService = projectService
        self.referenceDataService = referenceDataService
        self.currentUserId = currentUserId
        self.lockedProjectId = lockedProjectId
    }

    /// Matches the real web form's own required-field set exactly (see the trm-ios plan's
    /// field-scope table) — Ticket Link is the only optional field.
    var isValid: Bool {
        !requestName.trimmingCharacters(in: .whitespaces).isEmpty
            && !description.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedProjectId != nil
            && selectedRequestTypeId != nil
            && selectedSeverityId != nil
            && selectedOwnerId != nil
    }

    func loadOptions() async {
        isLoadingOptions = true
        error = nil
        do {
            async let p = projectService.listProjects(forceRefresh: false)
            async let rt = referenceDataService.requestTypes(forceRefresh: false)
            async let sv = referenceDataService.severities(forceRefresh: false)
            async let us = referenceDataService.users(forceRefresh: false)
            (projects, requestTypes, severities, users) = try await (p, rt, sv, us)
            if let lockedProjectId { selectedProjectId = lockedProjectId }
            if selectedOwnerId == nil { selectedOwnerId = currentUserId }
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingOptions = false
    }

    func submit() async -> ChangeRequest? {
        guard isValid,
              let projectId = selectedProjectId,
              let requestType = selectedRequestTypeId,
              let severity = selectedSeverityId,
              let owner = selectedOwnerId,
              let currentUserId
        else { return nil }

        isSubmitting = true
        error = nil
        defer { isSubmitting = false }

        let trimmedTicket = ticketUrl.trimmingCharacters(in: .whitespaces)
        let payload = NewChangeRequestPayload(
            shortDescription: requestName.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            projectId: projectId,
            requestType: requestType,
            severity: severity,
            requestedBy: owner,
            createdBy: currentUserId,
            ticketUrl: trimmedTicket.isEmpty ? nil : trimmedTicket
        )
        do {
            return try await changeRequestService.create(payload)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
