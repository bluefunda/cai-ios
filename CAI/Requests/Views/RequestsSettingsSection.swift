import PhotosUI
import SwiftUI

// MARK: - BlueRequests Settings
// trm-ios's SettingsView profile part, as one category in cai's Settings: the
// notification preference, plus the department, role and team that only live on the
// trm side. Only listed when the Requests space is available (SettingsView filters it).

struct RequestsSettingsSection: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.requestsServices) private var services
    @StateObject private var box = ProfileBox()

    var body: some View {
        List {
            if let model = box.model {
                RequestsProfileRows(model: model)
            } else if services == nil || authManager.currentUser == nil {
                Text("BlueRequests isn't available for this account.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("BlueRequests")
        .settingsInlineTitle()
        .task {
            guard box.model == nil, let services, let userId = authManager.currentUser?.id else { return }
            let model = ProfileViewModel(service: services.profileService, userId: userId)
            box.model = model
            await model.load()
        }
    }

    private final class ProfileBox: ObservableObject {
        @Published var model: ProfileViewModel?
    }
}

private struct RequestsProfileRows: View {
    @ObservedObject var model: ProfileViewModel
    @State private var pickedPhoto: PhotosPickerItem?

    var body: some View {
        Section {
            HStack(spacing: 14) {
                RQAvatar(urlString: model.profileImageURL, size: 56)
                    .overlay {
                        if model.isSavingPhoto { ProgressView() }
                    }
                VStack(alignment: .leading, spacing: 8) {
                    // Read outside: the picker's label closure is Sendable.
                    let pickTitle = model.profileImageURL == nil ? "Choose photo" : "Change photo"
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label(pickTitle, systemImage: "photo")
                    }
                    .accessibilityIdentifier("settings.requests.photo.choose")
                    if model.profileImageURL != nil {
                        Button("Remove photo", role: .destructive) {
                            Task { await model.removePhoto() }
                        }
                        .accessibilityIdentifier("settings.requests.photo.remove")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(model.profile == nil || model.isSavingPhoto)
                .bfPointerHover()
            }
            .padding(.vertical, 4)
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                pickedPhoto = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let jpeg = ProfilePhoto.jpeg(from: data) else {
                        model.error = "That picture couldn't be read."
                        return
                    }
                    await model.setPhoto(jpeg)
                }
            }
            if let error = model.error, model.profile != nil {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Profile photo")
        } footer: {
            Text("Shown next to your name in requests, comments and messages.")
                #if targetEnvironment(macCatalyst)
                .font(MacSettingsFont.secondary)
                #endif
        }

        Section {
            Toggle(isOn: Binding(
                get: { model.notificationsEnabled },
                set: { newValue in Task { await model.setNotificationsEnabled(newValue) } }
            )) {
                Label("Request notifications", systemImage: "bell")
                    #if targetEnvironment(macCatalyst)
                    .font(MacSettingsFont.row)
                    #endif
            }
            .disabled(model.profile == nil)
            .bfPointerHover()
            .accessibilityIdentifier("settings.requests.notifications")
        } footer: {
            Text("Whether BlueRequests notifies you about changes and comments on your requests.")
                #if targetEnvironment(macCatalyst)
                .font(MacSettingsFont.secondary)
                #endif
        }

        Section("Your profile") {
            if model.isLoading && model.profile == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let error = model.error, model.profile == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        model.error = nil
                        Task { await model.load() }
                    }
                    .bfPointerHover()
                }
            } else {
                row("Department", value: model.profile?.department)
                row("Role", value: model.profile?.role)
                row("Team", value: model.profile?.teamName)
            }
        }
    }

    private func row(_ label: String, value: String?) -> some View {
        LabeledContent(label) {
            Text(value.flatMap { $0.isBlank ? nil : $0 } ?? "Not set")
                .foregroundStyle(.secondary)
        }
        #if targetEnvironment(macCatalyst)
        .font(MacSettingsFont.row)
        #endif
    }
}

/// A picked picture as a square-ish JPEG no larger than 512 points on its long side.
enum ProfilePhoto {
    static func jpeg(from data: Data, maxSide: CGFloat = 512) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
