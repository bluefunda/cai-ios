import SwiftUI
import SafariServices

// MARK: - Safari View
// In-app browser wrapper for SFSafariViewController, used for Help & Support
// and Upgrade Plan links so users stay inside the app.

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor(Color.brandBlue)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

// MARK: - URL Identifiable
// Lets URL drive `.sheet(item:)` presentation directly.

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
