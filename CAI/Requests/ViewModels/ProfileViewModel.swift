import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isLoading = false
    @Published var notificationsEnabled = true
    @Published var error: String?

    private let service: ProfileServicing
    private let userId: String

    init(service: ProfileServicing, userId: String) {
        self.service = service
        self.userId = userId
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            let profile = try await service.fetchProfile(userId: userId)
            self.profile = profile
            notificationsEnabled = profile.notification ?? true
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Optimistic — flips the toggle immediately, reverts it if the write fails.
    func setNotificationsEnabled(_ enabled: Bool) async {
        let previous = notificationsEnabled
        notificationsEnabled = enabled
        do {
            try await service.updateNotificationPreference(enabled, userId: userId)
        } catch {
            notificationsEnabled = previous
            self.error = error.localizedDescription
        }
    }
}
