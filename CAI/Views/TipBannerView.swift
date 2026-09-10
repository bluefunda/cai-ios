import SwiftUI

/// Displays a Tip Engine-selected tip (bluefunda/cai-ios#155) above the
/// composer. Same compact banner shape as `RateLimitBanner`/`ST22DumpBanner`
/// in `ChatView.swift` — icon + text + tinted background, no elevation —
/// but neutral/branded rather than warning/error toned, and dismissible
/// (tips aren't alerts).
struct TipBannerView: View {
    let tip: TipManifestEntry
    let onDismiss: () -> Void
    let onTap: () -> Void

    private var tipTitle: String { tip.render.ios?.title ?? "" }
    private var tipBody: String { tip.render.ios?.body ?? "" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(BFColor.primary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(tipTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(tipBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(BFColor.primary.opacity(0.1))
    }
}
