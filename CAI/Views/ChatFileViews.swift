import SwiftUI
import QuickLook
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Attachment Chip

/// Small pill showing a file reference attached to a message (user upload or
/// LLM-generated output) — backed by the durable fileUrl/file_metadata cai-bff
/// relays on chat history, browsable in full via ConversationFilesView.
struct AttachmentChip: View {
    let filename: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
            Text(filename).font(.caption).lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(BFColor.surfaceSunken, in: Capsule())
        .overlay(Capsule().strokeBorder(BFColor.hairline, lineWidth: 0.5))
    }
}

/// A URL handed from a file card to ChatView, which presents Quick Look or Save to Files —
/// so the presentation outlives the card (see filePreviewURL / fileToSave).
struct FileURLAction {
    let open: (URL) -> Void
    func callAsFunction(_ url: URL) { open(url) }
}

private struct OpenFilePreviewKey: EnvironmentKey {
    static let defaultValue = FileURLAction { _ in }
}

private struct SaveFileKey: EnvironmentKey {
    static let defaultValue = FileURLAction { _ in }
}

/// A file to hand to the system "Save to Files" / save panel, presented by ChatView.
struct FileToSave: Identifiable {
    let url: URL
    var id: URL { url }
}

/// UIDocumentPickerViewController in export mode: iOS "Save to Files", a save panel on Mac.
/// asCopy keeps the app's own cached copy where it is.
struct FileExportPicker: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}

extension EnvironmentValues {
    var openFilePreview: FileURLAction {
        get { self[OpenFilePreviewKey.self] }
        set { self[OpenFilePreviewKey.self] = newValue }
    }

    var saveFile: FileURLAction {
        get { self[SaveFileKey.self] }
        set { self[SaveFileKey.self] = newValue }
    }
}

/// A file the assistant created (bluefunda/cai-ios#371): icon, name, type and size. Tapping
/// downloads it (or reuses the saved copy) and opens Quick Look, whose share button covers
/// Share, Save to Files and Open In.
struct GeneratedFileCard: View {
    let file: MessageFileMetadata
    @EnvironmentObject private var chatManager: ChatManager
    @Environment(\.openFilePreview) private var openFilePreview
    @Environment(\.saveFile) private var saveFile
    @State private var isHoveringDownload = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var name: String {
        file.fileName ?? URL(string: file.downloadURL ?? "")?.lastPathComponent ?? "File"
    }

    private var fileExtension: String { (name as NSString).pathExtension.lowercased() }

    private var kind: (label: String, symbol: String) {
        switch fileExtension {
        case "xlsx", "xls": return ("Excel", "tablecells")
        case "csv", "tsv": return ("CSV", "tablecells")
        case "docx", "doc": return ("Word", "doc.text")
        case "pptx", "ppt": return ("PowerPoint", "rectangle.on.rectangle")
        case "pdf": return ("PDF", "doc.richtext")
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return ("Image", "photo")
        case "zip": return ("ZIP", "doc.zipper")
        case "json", "md", "txt", "html", "xml": return (fileExtension.uppercased(), "doc.plaintext")
        default: return (fileExtension.isEmpty ? "File" : fileExtension.uppercased(), "doc")
        }
    }

    private var subtitle: String {
        guard let size = file.fileSize, size > 0 else { return kind.label }
        return "\(kind.label) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Tap the card: preview. Tap the download button: save to Files / a folder.
                Button { Task { await open(.preview) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 20))
                            .foregroundStyle(BFColor.primary)
                            .frame(width: 40, height: 40)
                            .background(BFColor.primaryTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(BFFont.bodySmall.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            Text(subtitle).font(BFFont.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(name), \(subtitle). Opens a preview.")

                Button { Task { await open(.save) } } label: {
                    Group {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            // Filled + brand blue on hover (Mac / iPad pointer): a separate action
                            // from the card, which opens the preview.
                            Image(systemName: isHoveringDownload ? "arrow.down.circle.fill" : "arrow.down.circle")
                                .font(.system(size: 22))
                        }
                    }
                    .foregroundStyle(isHoveringDownload ? AnyShapeStyle(BFColor.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .animation(.easeOut(duration: 0.12), value: isHoveringDownload)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringDownload = $0 }
                .help("Download")
                .accessibilityLabel("Download \(name)")
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: 360, alignment: .leading)
            .background(BFColor.surfaceSunken, in: RoundedRectangle(cornerRadius: BFRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BFRadius.card, style: .continuous)
                    .strokeBorder(BFColor.hairline, lineWidth: 0.5)
            )
            .disabled(isLoading)
            .bfPointerHover()

            if let errorMessage {
                Text(errorMessage).font(BFFont.caption).foregroundStyle(BFColor.error)
            }
        }
    }

    private enum Action { case preview, save }

    private func open(_ action: Action) async {
        guard let conversationId = chatManager.currentConversation?.id else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let url = try await chatManager.localFileURL(for: file, conversationId: conversationId)
            switch action {
            case .preview: openFilePreview(url)
            case .save: saveFile(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
