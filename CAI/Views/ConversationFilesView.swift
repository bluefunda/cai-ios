import SwiftUI
import QuickLook

/// Lists files stored locally for a conversation — user attachments and
/// LLM-generated output files — with view (QuickLook), share, and delete.
struct ConversationFilesView: View {
    @EnvironmentObject var chatManager: ChatManager
    let conversationId: String

    @State private var files: [StoredFileMetadata] = []
    @State private var isLoading = true
    @State private var previewURL: URL?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                ContentUnavailableView(
                    "No Files",
                    systemImage: "paperclip",
                    description: Text("Attachments and files from AI responses will appear here.")
                )
            } else {
                List {
                    ForEach(files) { file in
                        fileRow(file)
                    }
                }
            }
        }
        .navigationTitle("Files")
        .task { await reload() }
        .quickLookPreview($previewURL)
    }

    @ViewBuilder
    private func fileRow(_ file: StoredFileMetadata) -> some View {
        Button {
            Task { await preview(file) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: file.source == .llmOutput ? "sparkles" : "paperclip")
                    .foregroundStyle(BFColor.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.filename)
                        .font(BFFont.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(file.formattedSize) · \(file.createdAt.relativeDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await delete(file) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            ShareLink(item: file.filename) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                Task { await delete(file) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func reload() async {
        isLoading = true
        files = await chatManager.attachments(for: conversationId)
        isLoading = false
    }

    private func preview(_ file: StoredFileMetadata) async {
        previewURL = try? await chatManager.fileStore.fileURL(for: file)
    }

    private func delete(_ file: StoredFileMetadata) async {
        await chatManager.deleteAttachment(file)
        files.removeAll { $0.id == file.id }
    }
}
