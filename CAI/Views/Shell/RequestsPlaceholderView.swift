import SwiftUI

// MARK: - Requests Placeholder
// Stands in for each Requests destination until the BlueRequests screens are ported.
// Only reachable with `bf_feature_requests` on AND `trm` org membership, so no
// production user sees it.

struct RequestsPlaceholderView: View {
    let destination: RequestsDestination
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                destination.title,
                systemImage: destination.icon,
                description: Text("This part of BlueRequests isn't in the app yet.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BFColor.surfaceCanvas)
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .shellNavigationControl(navigationControl)
        }
        .accessibilityIdentifier("requests.placeholder.\(destination.rawValue)")
    }
}
