import UIKit

/// Presents `UIImagePickerController(sourceType: .camera)` imperatively and
/// drives its delegate directly — mirrors `DocumentPickerCoordinator`'s
/// approach for the same reason: a `.sheet`-wrapped
/// `UIViewControllerRepresentable` is unreliable for UIKit pickers under Mac
/// Catalyst, where the picker gets lifted into its own window and delegate
/// callbacks can silently stop firing. There's also no SwiftUI-native camera
/// capture view to reach for instead — `PhotosPicker`/`PHPickerViewController`
/// only pick existing library assets, never live camera capture.
final class CameraCaptureCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let onCapture: (UIImage) -> Void
    private let onCancel: () -> Void

    init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else {
            onCancel()
            return
        }
        onCapture(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        onCancel()
    }

    /// Presents the camera on the current foreground window's root view
    /// controller. Returns `nil` without presenting anything when no camera
    /// is available (Simulator, or Mac Catalyst — `UIImagePickerController`'s
    /// `.camera` source is never available there regardless of Mac hardware),
    /// so callers should already be hiding the menu entry via the same check
    /// rather than relying on this fallback alone.
    @discardableResult
    static func present(
        onCapture: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) -> CameraCaptureCoordinator? {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return nil }
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }

        let coordinator = CameraCaptureCoordinator(onCapture: onCapture, onCancel: onCancel)
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = coordinator
        rootVC.present(picker, animated: true)
        return coordinator
    }
}
