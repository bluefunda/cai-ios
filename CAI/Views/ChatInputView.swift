import SwiftUI

// Split out of ChatView.swift to stay under SwiftLint's file_length limit
// (bluefunda/cai-ios#261 precedent — see ChatManager+Background.swift).

struct ChatInputView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var iapManager: IAPManager
    @Binding var text: String
    let isStreaming: Bool
    let attachmentFilename: String?
    var isFocused: FocusState<Bool>.Binding
    // Mac Catalyst-only mirror of `isFocused`, as a plain (non-FocusState) Binding<Bool> —
    // see MacComposerTextView.swift and ChatView's isInputFocusedMac for why. Defaults to a
    // fresh, unused constant since only the Mac branch below ever reads/writes it.
    var isFocusedMac: Binding<Bool> = .constant(false)
    // Mac-only: bumped by ChatView whenever `text` is changed programmatically (e.g. cleared
    // after sending) rather than by the user typing. See MacComposerTextView.swift and
    // ChatView's composerExternalUpdateToken for why this replaced inferring that from
    // "focus was lost" once the composer started staying focused through send on Mac.
    var externalUpdateToken: Int = 0
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
    @State private var showAttachSheet = false
    // "Manage Agents" inside the attach sheet needs to present Settings —
    // NOT as a sheet nested inside the attach sheet (that combination left
    // the whole app stuck in a loading state), but as a sibling presented
    // only after the attach sheet has actually finished dismissing.
    @State private var pendingManageAgents = false
    @State private var showManageAgentsSettings = false

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
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .bfPointerHover()
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
            #if targetEnvironment(macCatalyst)
            // MacComposerTextView (see that file): a vertical-axis TextField's underlying
            // UITextView claims a bare Return for its own "insert newline" handling before
            // SwiftUI's .onKeyPress ever sees it — confirmed live, that approach had zero
            // effect — so Mac Catalyst gets a real UITextView wrapper that intercepts Return
            // at the UIKit level instead. Shift+Return still inserts a newline.
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(rateLimitExceeded ? "Usage limit reached" : "Message...")
                        .font(BFFont.body)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
                // isFocusedMac, not `isFocused` (a FocusState<Bool>.Binding) or even a plain
                // Binding<Bool> that proxies through to isFocused.wrappedValue — confirmed
                // live with debug logging that BOTH still never observed ChatView's
                // `isInputFocused = true` from inside MacComposerTextView's updateUIView, no
                // matter how long after. FocusState<Bool>.Binding is built to feed a
                // `.focused(_:)` modifier on an actual SwiftUI-native focusable view; read
                // anywhere else — directly, or through a plain Binding's closures that
                // ultimately still call its .wrappedValue — it doesn't propagate. isFocusedMac
                // is backed by a genuine @State in ChatView (isInputFocusedMac), kept in
                // lockstep with isInputFocused by ChatView's setInputFocused(_:) helper, with
                // no FocusState in this read path at all.
                MacComposerTextView(
                    text: $text,
                    isFocused: isFocusedMac,
                    externalUpdateToken: externalUpdateToken
                ) {
                    guard canSend, !isStreaming else { return }
                    onSend()
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            #else
            TextField(rateLimitExceeded ? "Usage limit reached" : "Message...", text: $text, axis: .vertical)
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
            #endif

            HStack(alignment: .center, spacing: 6) {
                // "+" button — attach options and/or per-chat Connectors
                // toggles, shown whenever either has something to offer.
                if attachEnabled || !chatManager.visibleMCPServers.isEmpty {
                    Button {
                        showAttachSheet = true
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
                    .bfPointerHover()
                    .sheet(isPresented: $showAttachSheet, onDismiss: {
                        if pendingManageAgents {
                            pendingManageAgents = false
                            showManageAgentsSettings = true
                        }
                    }) {
                        ComposerAttachSheet(
                            onPickCamera: onPickCamera,
                            onPickPhoto: onPickPhoto,
                            onPickFile: onPickFile,
                            onPickDumpScreenshot: onPickDumpScreenshot,
                            onManageAgents: { pendingManageAgents = true }
                        )
                    }
                    .sheet(isPresented: $showManageAgentsSettings) {
                        // Explicit re-injection, same as ContentView's own SettingsView
                        // sheet (cai-ios#254) — its NavigationSplitView sidebar doesn't
                        // reliably inherit environment objects on Mac Catalyst, which
                        // crashed the app ("No ObservableObject of type AuthManager
                        // found") the moment this sheet's sidebar column appeared.
                        SettingsView(initialCategory: .connectors)
                            .environmentObject(authManager)
                            .environmentObject(chatManager)
                            .environmentObject(iapManager)
                    }
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
                    .transaction {
                        $0.animation = nil
                        $0.disablesAnimations = true
                    }

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
                    .bfPointerHover()
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
                    .bfPointerHover()
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
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .bfPointerHover()
            Button(action: { onConfirmRecording?() }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(BFColor.primary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .bfPointerHover()
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
