import UIKit
import UniformTypeIdentifiers

/// Presents `UIDocumentPickerViewController` imperatively and drives its
/// delegate directly.
///
/// SwiftUI's `.fileImporter` completion handler is unreliable on Mac
/// Catalyst — the picker presents and dismisses fine, but the
/// `Result<[URL], Error>` callback simply never fires. Wrapping the picker
/// declaratively via `UIViewControllerRepresentable` inside a `.sheet` has
/// the same problem: Mac Catalyst lifts the document picker into its own
/// separate window, and the delegate wiring silently breaks. Presenting it
/// the old imperative UIKit way — `rootViewController.present(...)` — with a
/// delegate object the caller keeps a strong reference to (so it isn't
/// deallocated mid-presentation) is the standard, reliable workaround.
final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private let onPick: (URL) -> Void
    private let onCancel: () -> Void

    init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            onCancel()
            return
        }
        onPick(url)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onCancel()
    }

    /// Presents the picker on the current foreground window's root view
    /// controller. Returns the coordinator so the caller can hold a strong
    /// reference for the duration of the presentation.
    @discardableResult
    static func present(
        allowedContentTypes: [UTType],
        onPick: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) -> DocumentPickerCoordinator? {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }

        let coordinator = DocumentPickerCoordinator(onPick: onPick, onCancel: onCancel)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = coordinator
        rootVC.present(picker, animated: true)
        return coordinator
    }
}
