import SwiftUI

// MARK: - Storage View
// Basic cloud storage browser backed by /storage/* endpoints.

struct StorageView: View {
    @EnvironmentObject var chatManager: ChatManager

    // For now we show a placeholder — full MinIO browser is Phase 3.
    var body: some View {
        NavigationStack {
            StoragePlaceholder()
                .navigationTitle("Cloud Storage")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct StoragePlaceholder: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Cloud Storage")
                .font(.title2)
                .fontWeight(.semibold)

            Text("File browsing is coming in a future update.\nAccess your files at cai.bluefunda.com.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    StorageView()
        .environmentObject(ChatManager(service: BFFChatService()))
}
