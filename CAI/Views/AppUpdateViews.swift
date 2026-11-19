import SwiftUI

/// "Update available": a banner across the top that pushes the app down rather than
/// covering it, so the app — the message composer included — stays usable and the
/// banner can simply be ignored. Closable.
struct AppUpdateBanner: View {
    let latest: String
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: BFSpacing._3) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(BFColor.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available")
                    .font(.subheadline.weight(.semibold))
                Text("Version \(latest) is ready to install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: BFSpacing._2)
            Button("Update", action: onUpdate)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .bfPointerHover()
                .accessibilityIdentifier("appUpdate.banner.update")
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .bfPointerHover()
            .accessibilityLabel("Dismiss update")
            .accessibilityIdentifier("appUpdate.banner.dismiss")
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, BFSpacing._2)
        .frame(maxWidth: .infinity)
        .background(BFColor.primary.opacity(0.1))
        .accessibilityElement(children: .contain)
    }
}

/// "Update required": covers the app when the installed version is below the
/// minimum. The only way on is the store.
struct AppUpdateRequiredView: View {
    let latest: String
    let onUpdate: () -> Void

    var body: some View {
        VStack(spacing: BFSpacing._4) {
            Spacer()
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 56))
                .foregroundStyle(BFColor.primary)
            Text("Update required")
                .font(.title2.weight(.semibold))
            Text("This version of BlueFunda AI is no longer supported. "
                 + "Update to version \(latest) to keep using the app.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button(action: onUpdate) {
                Text("Update")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .bfPointerHover()
            .accessibilityIdentifier("appUpdate.required.update")
            Spacer()
        }
        .padding(BFSpacing._4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }
}

extension View {
    /// The update banner and the blocking screen, driven by `checker`.
    func appUpdateNotice(_ checker: AppUpdateChecker) -> some View {
        modifier(AppUpdateNoticeModifier(checker: checker))
    }
}

private struct AppUpdateNoticeModifier: ViewModifier {
    @ObservedObject var checker: AppUpdateChecker
    @Environment(\.openURL) private var openURL

    private var latest: String {
        switch checker.state {
        case .upToDate: return ""
        case .available(let latest, _), .required(let latest, _): return latest
        }
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if checker.showsBanner {
                    AppUpdateBanner(latest: latest, onUpdate: openStore, onDismiss: checker.dismissBanner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: checker.showsBanner)
            .fullScreenCover(isPresented: .constant(checker.isUpdateRequired)) {
                AppUpdateRequiredView(latest: latest, onUpdate: openStore)
            }
    }

    private func openStore() {
        if let url = checker.storeURL { openURL(url) }
    }
}
