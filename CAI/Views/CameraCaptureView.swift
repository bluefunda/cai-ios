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

    /// Presents the camera on the view controller currently on screen.
    /// Returns `nil` without presenting anything when no camera is available
    /// (Simulator, or Mac Catalyst — `UIImagePickerController`'s `.camera`
    /// source is never available there regardless of Mac hardware), so callers
    /// should already be hiding the menu entry via the same check rather than
    /// relying on this fallback alone.
    ///
    /// Presenting from the root view controller failed silently (#369): "Take
    /// Photo" runs as the attach sheet closes, and UIKit refuses to present from
    /// a controller that is still presenting — or still dismissing — something,
    /// with only a console warning, so the camera never appeared. Presenting
    /// from the topmost controller, after any in-flight transition completes,
    /// doesn't depend on how long that dismissal takes.
    @discardableResult
    static func present(
        onCapture: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) -> CameraCaptureCoordinator? {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return nil }
        guard let top = topViewController() else {
            print("[Camera] no foreground window to present the camera from")
            return nil
        }

        let coordinator = CameraCaptureCoordinator(onCapture: onCapture, onCancel: onCancel)
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = coordinator

        let presentPicker = {
            guard let presenter = topViewController() else {
                print("[Camera] no view controller to present the camera from")
                onCancel()
                return
            }
            presenter.present(picker, animated: true)
        }
        // `animate` returns false when it couldn't queue the completion (the
        // transition already ended) — present right away in that case.
        if let transition = top.transitionCoordinator,
           transition.animate(alongsideTransition: nil, completion: { _ in presentPicker() }) {
            // presented from the completion
        } else {
            presentPicker()
        }
        return coordinator
    }

    /// The view controller actually on screen: the key window's root, followed
    /// down its chain of presented controllers, skipping one that is on its way
    /// out (presenting on top of a dismissing controller is refused too).
    private static func topViewController() -> UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
