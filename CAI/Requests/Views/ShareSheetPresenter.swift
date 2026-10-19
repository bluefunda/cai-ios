// Ported unchanged from trm-ios.
import UIKit

// MARK: - Share Sheet Presenter
// Presents the system share sheet for a downloaded attachment's bytes. Writes to a temp
// file first (not raw Data) so the receiving app sees a real filename/extension, matching
// how a Files-app "Save to Files" or a Mail attachment would look. Finds the key window's
// root view controller the same way AuthManager's ASWebAuthenticationPresentationContextProviding
// does, since there's no SwiftUI view identity to hang a `.sheet` off of here (the action
// happens from a button in a `List` row, not a dedicated presenter view).

@MainActor
enum ShareSheetPresenter {
    static func present(data: Data, fileName: String) async {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            return
        }

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        var top = root
        while let presented = top.presentedViewController { top = presented }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(activityVC, animated: true)
    }
}
