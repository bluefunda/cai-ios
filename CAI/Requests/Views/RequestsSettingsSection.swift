import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Profile photo and notifications
// The BlueRequests profile, split across cai's Settings: the profile photo in
// Account, and the request notification preference in Notifications. Both are
// stored on the trm side, so they only show when the Requests space is available
// (SettingsView filters them).

/// Loads the signed-in user's BlueRequests profile for a Settings view.
private struct RequestsProfileLoader<Content: View>: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.requestsServices) private var services
    @StateObject private var box = ProfileBox()
    /// Shown instead of the default spinner / "not available" text until the profile loads.
    var fallback: AnyView?
    @ViewBuilder let content: (ProfileViewModel) -> Content

    var body: some View {
        Group {
            if let model = box.model {
                content(model)
            } else if let fallback {
                fallback
            } else if services == nil || authManager.currentUser == nil {
                Text("Not available for this account.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
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

/// Account → the name card, whose avatar is the BlueRequests profile photo:
/// tap it to choose, change or remove the photo shown next to your name in
/// requests, comments and messages.
struct AccountProfileSection: View {
    let user: User

    var body: some View {
        Section {
            RequestsProfileLoader(fallback: AnyView(UserInfoRow(user: user))) { model in
                VStack(alignment: .leading, spacing: 6) {
                    UserInfoRow(user: user, avatar: AnyView(EditableProfileAvatar(model: model, name: user.name)))
                    if let error = model.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        } footer: {
            Text("Tap your picture to change it. It's shown next to your name in requests, comments and messages.")
                #if targetEnvironment(macCatalyst)
                .font(MacSettingsFont.secondary)
                #endif
        }
    }
}

private struct EditableProfileAvatar: View {
    @ObservedObject var model: ProfileViewModel
    let name: String
    @State private var choosingAction = false
    @State private var presenter = ProfilePhotoPresenter()

    private var size: CGFloat { UserInfoRow.avatarSize }

    var body: some View {
        // A plain button: on Mac a Menu draws its label at the image's full size.
        Button {
            choosingAction = true
        } label: {
            avatar
        }
        .buttonStyle(.plain)
        .disabled(model.profile == nil || model.isSavingPhoto)
        .bfPointerHover()
        .accessibilityLabel(model.profileImageURL == nil ? "Add profile photo" : "Change profile photo")
        .accessibilityIdentifier("settings.account.photo")
        .confirmationDialog("Profile photo", isPresented: $choosingAction) {
            Button("Choose from Photos") { afterDismiss { presenter.choosePhoto(then: crop) } }
                .accessibilityIdentifier("settings.account.photo.choose")
            // The Photos picker only shows the Photos library; this one opens Files (Finder on Mac).
            Button("Choose from Files") { afterDismiss { presenter.chooseFile(then: crop) } }
                .accessibilityIdentifier("settings.account.photo.file")
            if model.profileImageURL != nil {
                Button("Remove photo", role: .destructive) {
                    Task { await model.removePhoto() }
                }
                .accessibilityIdentifier("settings.account.photo.remove")
            }
        }
    }

    private var avatar: some View {
        Group {
            if model.profileImageURL != nil {
                RQAvatar(urlString: model.profileImageURL, size: size)
            } else {
                UserInitialAvatar(name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if model.isSavingPhoto { ProgressView() }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "pencil.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, BFColor.primary)
                .font(.system(size: size * 0.36))
                .offset(x: 2, y: 2)
        }
    }

    /// Opens the cropper; the photo is saved only once it's confirmed there.
    private func crop(_ data: Data) {
        guard let image = ProfilePhoto.image(from: data) else {
            model.error = "That picture couldn't be read. Choose a JPEG, PNG or HEIC photo."
            return
        }
        model.error = nil
        afterDismiss {
            presenter.crop(image) { cropped in
                guard let jpeg = cropped.jpegData(compressionQuality: 0.85) else {
                    model.error = "That picture couldn't be read."
                    return
                }
                Task { await model.setPhoto(jpeg) }
            }
        }
    }

    /// Runs `present` once the dialog or picker that's closing has gone: presenting
    /// while another one is still dismissing does nothing.
    private func afterDismiss(_ present: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            present()
        }
    }
}

/// Presents the Photos picker, the Files picker and the cropper from the frontmost view
/// controller. SwiftUI's own picker modifiers don't open from a row of the Settings list
/// on Mac.
@MainActor
private final class ProfilePhotoPresenter: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private var onPicked: ((Data) -> Void)?

    func choosePhoto(then onPicked: @escaping (Data) -> Void) {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        self.onPicked = onPicked
        Self.topViewController()?.present(picker, animated: true)
    }

    func chooseFile(then onPicked: @escaping (Data) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: ProfilePhoto.fileTypes, asCopy: true)
        picker.delegate = self
        self.onPicked = onPicked
        Self.topViewController()?.present(picker, animated: true)
    }

    func crop(_ image: UIImage, onSave: @escaping (UIImage) -> Void) {
        var host: UIViewController?
        let cropper = ProfilePhotoCropper(image: image) {
            host?.dismiss(animated: true)
        } onSave: { cropped in
            host?.dismiss(animated: true)
            onSave(cropped)
        }
        let controller = UIHostingController(rootView: cropper)
        controller.modalPresentationStyle = .formSheet
        controller.preferredContentSize = CGSize(width: 420, height: 520)
        host = controller
        Self.topViewController()?.present(controller, animated: true)
    }

    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let provider = results.first?.itemProvider
        Task { @MainActor in
            picker.dismiss(animated: true)
            guard let provider, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                Task { @MainActor in
                    if let data { self.deliver(data) }
                }
            }
        }
    }

    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if scoped { url.stopAccessingSecurityScopedResource() }
        Task { @MainActor in
            if let data { self.deliver(data) }
        }
    }

    private func deliver(_ data: Data) {
        let onPicked = onPicked
        self.onPicked = nil
        onPicked?(data)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow
            ?? scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// Move and zoom a picked photo inside the circle, then save or cancel.
private struct ProfilePhotoCropper: View {
    let image: UIImage
    let onCancel: () -> Void
    let onSave: (UIImage) -> Void

    private let side: CGFloat = 280
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                photo
                    .frame(width: side, height: side)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                    .contentShape(Rectangle())
                    .gesture(drag.simultaneously(with: magnify))
                Slider(value: zoomBinding, in: 1...4) {
                    Text("Zoom")
                } minimumValueLabel: {
                    Image(systemName: "minus.magnifyingglass")
                } maximumValueLabel: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .frame(width: side)
                .accessibilityIdentifier("settings.account.photo.zoom")
                Text("Drag to move, pinch or use the slider to zoom.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Move and scale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("settings.account.photo.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(rendered()) }
                        .accessibilityIdentifier("settings.account.photo.save")
                }
            }
        }
    }

    private var zoomBinding: Binding<CGFloat> {
        Binding(get: { zoom }, set: { newZoom in
            zoom = newZoom
            lastZoom = newZoom
            offset = clamped(offset)
            lastOffset = offset
        })
    }

    /// The image filling the square at the current zoom and position.
    private var photo: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: side * zoom, height: side * zoom)
            .offset(offset)
            .frame(width: side, height: side)
            .clipped()
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(CGSize(width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height))
            }
            .onEnded { _ in lastOffset = offset }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(4, max(1, lastZoom * value.magnification))
                offset = clamped(offset)
            }
            .onEnded { _ in
                lastZoom = zoom
                lastOffset = offset
            }
    }

    /// Keeps the image covering the whole circle.
    private func clamped(_ proposed: CGSize) -> CGSize {
        let aspect = image.size.width / max(image.size.height, 1)
        let fill = side * zoom
        let width = aspect >= 1 ? fill * aspect : fill
        let height = aspect >= 1 ? fill : fill / aspect
        let maxX = max(0, (width - side) / 2)
        let maxY = max(0, (height - side) / 2)
        return CGSize(width: min(maxX, max(-maxX, proposed.width)),
                      height: min(maxY, max(-maxY, proposed.height)))
    }

    /// The visible square, at 512 points (scale 1), ready to upload.
    private func rendered() -> UIImage {
        let renderer = ImageRenderer(content: photo)
        renderer.scale = 512 / side
        return renderer.uiImage ?? image
    }
}

/// Settings → Notifications: which notifications you get.
struct NotificationsSettingsView: View {
    var body: some View {
        List {
            Section {
                RequestsProfileLoader { model in
                    RequestNotificationsToggle(model: model)
                }
            } footer: {
                Text("Approvals, assignments, mentions, messages and decisions on your requests: "
                     + "in the app, as push notifications and by email.")
                    #if targetEnvironment(macCatalyst)
                    .font(MacSettingsFont.secondary)
                    #endif
            }
        }
        .navigationTitle("Notifications")
        .settingsInlineTitle()
    }
}

/// The checkbox changes nothing until Save writes it to the profile.
private struct RequestNotificationsToggle: View {
    @ObservedObject var model: ProfileViewModel
    @State private var draft: Bool?
    @State private var isSaving = false
    @State private var saved = false

    private var value: Bool { draft ?? model.notificationsEnabled }
    private var hasChanges: Bool { draft != nil && draft != model.notificationsEnabled }

    var body: some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { newValue in
                draft = newValue
                saved = false
                model.error = nil
            }
        )) {
            Label("Requests notifications", systemImage: "bell")
                #if targetEnvironment(macCatalyst)
                .font(MacSettingsFont.row)
                #endif
        }
        .disabled(model.profile == nil || isSaving)
        .bfPointerHover()
        .accessibilityIdentifier("settings.notifications.requests")

        HStack {
            if let error = model.error, model.profile != nil {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if saved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            Spacer()
            if isSaving { ProgressView().controlSize(.small) }
            Button("Save") {
                guard let draft else { return }
                isSaving = true
                Task {
                    await model.setNotificationsEnabled(draft)
                    isSaving = false
                    if model.error == nil {
                        self.draft = nil
                        saved = true
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasChanges || isSaving)
            .bfPointerHover()
            .accessibilityIdentifier("settings.notifications.save")
        }
    }
}

/// Reading a picked picture.
enum ProfilePhoto {
    /// What the Files picker offers: pictures UIImage reads, plus SVG for the photo inside one.
    static let fileTypes: [UTType] = [.jpeg, .png, .heic, .heif, .gif, .tiff, .bmp, .webP, .svg]

    /// The picture in `data`. An SVG can't be drawn here, but one exported from a photo
    /// usually embeds it as a base64 PNG or JPEG, which is used instead.
    static func image(from data: Data) -> UIImage? {
        if let image = UIImage(data: data) { return image }
        guard let text = String(data: data, encoding: .utf8),
              let start = text.range(of: #"data:image/(png|jpe?g|webp|gif);base64,"#, options: .regularExpression)
        else { return nil }
        let rest = text[start.upperBound...]
        let end = rest.firstIndex { $0 == "\"" || $0 == "'" || $0 == ")" } ?? rest.endIndex
        let base64 = rest[..<end].filter { !$0.isWhitespace }
        return Data(base64Encoded: String(base64)).flatMap(UIImage.init(data:))
    }
}
