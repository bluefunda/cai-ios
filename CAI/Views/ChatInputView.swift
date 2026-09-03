import SwiftUI

// Split out of ChatView.swift to stay under SwiftLint's file_length limit
// (bluefunda/cai-ios#261 precedent — see ChatManager+Background.swift).

struct ChatInputView: View {
    @Binding var text: String
    let isStreaming: Bool
    let attachmentFilename: String?
    var isFocused: FocusState<Bool>.Binding
    var rateLimitExceeded: Bool = false
    var isRecording: Bool = false
    var recordingElapsed: TimeInterval = 0
    let onSend: () -> Void
    let onStop: () -> Void
    let onClearAttachment: () -> Void
    /// nil = file upload feature disabled; non-nil = show the attach button
    let onPickPhoto: (() -> Void)?
    let onPickFile: (() -> Void)?
    /// nil = camera unavailable (Simulator, Mac Catalyst, or feature disabled)
    /// — the "Take Photo" entry is hidden rather than shown disabled.
    var onPickCamera: (() -> Void)? = nil
    /// nil = file upload feature disabled; non-nil = show the "Decode ST22
    /// Dump" attach option (bluefunda/cai-ios#182).
    var onPickDumpScreenshot: (() -> Void)? = nil
    var onMicTap: (() -> Void)? = nil
    var onCancelRecording: (() -> Void)? = nil
    var onConfirmRecording: (() -> Void)? = nil
    /// false = the SAP persona feature is off device-wide (Settings) — the
    /// composer's toggle/dropdown is hidden entirely rather than shown disabled.
    var personaFeatureEnabled: Bool = false
    var personaToggleOn: Binding<Bool> = .constant(false)
    var currentPersona: Persona = .general
    var personaOptions: [Persona] = Persona.fallbackCatalog
    var onSelectPersona: (Persona) -> Void = { _ in }
    // Mac Catalyst only — see ModeModelPicker.showMenu for why the attach
    // Menu needs a popover instead (cai-ios#257 follow-up).
    @State private var showAttachMenu = false

    private var canSend: Bool { !rateLimitExceeded && (!text.isEmpty || attachmentFilename != nil) }
    private var attachEnabled: Bool { onPickPhoto != nil || onPickFile != nil }

    /// SF Symbol for the attachment chip, picked from the filename's extension
    /// rather than a MIME type — only the display filename reaches this view.
    private func attachmentIcon(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp":
            return "photo.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "csv", "xlsx":
            return "tablecells.fill"
        case "json", "xml", "yaml", "yml":
            return "curlybraces"
        case "zip":
            return "doc.zipper"
        default:
            return "doc.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let filename = attachmentFilename {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: attachmentIcon(for: filename))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(
                                BFColor.primary.gradient,
                                in: RoundedRectangle(cornerRadius: BFRadius.md, style: .continuous)
                            )
                        Text(filename)
                            .font(BFFont.bodySmall)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.primary)
                        Button(action: onClearAttachment) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .background(Color(.systemGray4), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 2)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BFRadius.xl, style: .continuous)
                            .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                    )
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, BFSpacing._4)
                .padding(.top, 10)
                .padding(.bottom, 2)
            }

            if isRecording {
                recordingRow
            } else {
                composerRow
            }
        }
    }

    // Two-row layout (text field on top, accessory controls below) —
    // matches the Claude/ChatGPT composer shape (bluefunda/cai-ios#217
    // follow-up). Keeps the persona toggle's visible "Persona" label from
    // fighting the text field and send button for horizontal space on
    // narrow screens, which is exactly what a single-row layout couldn't do.
    private var composerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(rateLimitExceeded ? "Daily limit reached" : "Message...", text: $text, axis: .vertical)
                .font(BFFont.body)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .lineLimit(1...5)
                .padding(.horizontal, 4)
                // Without this, a multi-line (axis: .vertical) TextField only claims its own
                // intrinsic content width as its tappable frame inside this leading-aligned
                // VStack — the empty space to the right of the placeholder/typed text looks
                // like part of the composer but silently doesn't respond to taps.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

            HStack(alignment: .center, spacing: 6) {
                // Attach button — only rendered when the feature flag is on
                if attachEnabled {
                    // Plain Menu — matches the profile menu's recipe
                    // (ContentView.swift's bottom-left account row), which
                    // has correct upward-flip and mouse-hover behavior on
                    // Mac Catalyst. A popover-based rebuild here regressed
                    // mouse-click reliability, so back to Menu (cai-ios#257
                    // follow-up).
                    Menu {
                        if let pickCamera = onPickCamera {
                            Button { pickCamera() } label: {
                                Label("Take Photo", systemImage: "camera")
                            }
                        }
                        if let pickPhoto = onPickPhoto {
                            Button { pickPhoto() } label: {
                                Label("Photo Library", systemImage: "photo")
                            }
                        }
                        if let pickFile = onPickFile {
                            Button { pickFile() } label: {
                                Label("Browse Files", systemImage: "folder")
                            }
                        }
                        if let pickDumpScreenshot = onPickDumpScreenshot {
                            Button { pickDumpScreenshot() } label: {
                                Label("Decode ST22 Dump", systemImage: "exclamationmark.triangle")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .disabled(isStreaming)
                }

                if personaFeatureEnabled {
                    PersonaComposerControl(
                        isOn: personaToggleOn,
                        currentPersona: currentPersona,
                        options: personaOptions,
                        onSelect: onSelectPersona
                    )
                    .disabled(isStreaming)
                }

                Spacer(minLength: 0)

                // Lives inside the composer (like Persona on the left) rather
                // than the top bar — right side, directly next to mic/send.
                ModeModelPicker()
                    .disabled(isStreaming)

                // Mic button — replaced by the send button once there's something to send, and
                // by the stop button while streaming (canSend alone goes false once the
                // composer clears post-send, which without the isStreaming check here would
                // fall through to showing the mic button instead of Stop during the response).
                if let micTap = onMicTap, !canSend, !isStreaming {
                    Button(action: micTap) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStreaming)
                } else {
                    Button {
                        isStreaming ? onStop() : onSend()
                    } label: {
                        let active = isStreaming || canSend
                        Circle()
                            .fill(active ? BFColor.primary : Color(.systemGray4))
                            .frame(width: 30, height: 30)
                            .overlay {
                                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                                    .font(.system(size: isStreaming ? 12 : 14, weight: .bold))
                                    .foregroundStyle(active ? .white : .secondary)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isStreaming && !canSend)
                    // ⌘↩ sends on Mac (and external keyboards on iOS); plain ↩ adds a newline
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var recordingRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
            Text(formattedElapsed)
                .font(BFFont.body.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { onCancelRecording?() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
            Button(action: { onConfirmRecording?() }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(BFColor.primary)
            }
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var formattedElapsed: String {
        let minutes = Int(recordingElapsed) / 60
        let seconds = Int(recordingElapsed) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
