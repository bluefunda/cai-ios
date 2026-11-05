import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isLoading = false
    @Published var notificationsEnabled = true
    @Published var error: String?
    @Published private(set) var profileImageURL: String?
    @Published private(set) var isSavingPhoto = false

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
            profileImageURL = profile.profileImage.flatMap { $0.isEmpty ? nil : $0 }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Uploads the picture, then saves its URL on the profile, as the web's profile page.
    func setPhoto(_ jpeg: Data) async {
        isSavingPhoto = true
        defer { isSavingPhoto = false }
        do {
            let url = try await service.uploadProfileImage(jpeg, userId: userId)
            try await service.setProfileImage(url, userId: userId)
            // A new upload keeps the same URL; the query makes the image reload.
            profileImageURL = url + "?t=\(Int(Date().timeIntervalSince1970))"
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removePhoto() async {
        isSavingPhoto = true
        defer { isSavingPhoto = false }
        do {
            try await service.setProfileImage("", userId: userId)
            profileImageURL = nil
        } catch {
            self.error = error.localizedDescription
        }
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
