import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// `@MainActor` so every `Task { ... }` created in this view's methods stays
/// pinned to the main actor for its whole lifetime — without it, synchronous
/// calls into `ChatManager` (also `@MainActor`) from a Task resumed after an
/// `await` aren't guaranteed to still be on the main thread, which traps
/// under the Main Thread Checker / actor-isolation runtime checks.
@MainActor
struct ChatView: View {
    @EnvironmentObject var chatManager: ChatManager
    @EnvironmentObject var authManager: AuthManager
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    /// Personalised greeting for the empty-chat screen.
    private var greetingText: String {
        if !chatManager.greeting.isEmpty { return chatManager.greeting }
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        if let first = authManager.currentUser?.name.split(separator: " ").first {
            return "\(part), \(first)"
        }
        return part
    }

    // Attachment state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachmentData: Data?
    @State private var attachmentFilename: String?
    @State private var attachmentMIME: String?
    @State private var attachmentLocalMetadata: StoredFileMetadata?
    @State private var showPhotoPicker = false
    /// Keeps the document-picker delegate alive for the duration of an
    /// imperative presentation (see DocumentPickerCoordinator).
    @State private var documentPickerCoordinator: DocumentPickerCoordinator?
    /// Set when the in-flight photo pick was started via "Decode ST22 Dump"
    /// rather than the plain photo-library action (bluefunda/cai-ios#182) —
    /// read once at send time to decide whether to wrap the request prompt.
    @State private var attachmentIsForDumpDecode = false

    /// True when the composer's current text looks like a pasted ST22 short
    /// dump (bluefunda/cai-ios#182) — offers to decode it instead of sending
    /// it as a plain question.
    private var showDumpDecodeBanner: Bool {
        ST22DumpDetector.looksLikeDump(inputText)
    }

    private let importableTypes: [UTType] = [.pdf, .plainText, .commaSeparatedText, .json, .image, .zip, .data]

    // Voice input state
    @StateObject private var voiceInput = VoiceInputManager()

    // Scroll management
    @State private var scrollProxy: ScrollViewProxy?

    /// The most recently sent user message, if any — scrolling this to the
    /// top of the viewport on send (rather than jumping straight to the
    /// bottom) is what leaves room below it for the streaming response to
    /// fill in, matching cai-android's `MessageList` behavior.
    private var latestUserMessageID: String? {
        chatManager.currentConversation?.messages.last(where: { $0.role == .user })?.id
    }
    // Keyboard: focus only fires once per session on first launch
    @State private var hasTriggeredInitialFocus = false

    // Max readable width, centred — matches ChatGPT / Claude desktop.
    // On iPhone the screen is narrower so the constraint never triggers.
    private let maxChatWidth: CGFloat = 800

    var body: some View {
        VStack(spacing: 0) {
            if chatManager.connectionStatus != .connected {
                ConnectionBanner(status: chatManager.connectionStatus)
            }
            messageScrollArea
            Divider()
            inputArea
                .frame(maxWidth: maxChatWidth)
                .frame(maxWidth: .infinity)
        }
        // Dismiss keyboard the moment the response starts rendering
        .onChange(of: chatManager.isStreaming) { _, streaming in
            guard streaming else { return }
            isInputFocused = false
            // FocusState alone doesn't always force UIKit to resign; do it explicitly
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
        // Load messages when active conversation changes (fixes history)
        .task(id: chatManager.currentConversation?.id) {
            guard let id = chatManager.currentConversation?.id else { return }
            await chatManager.loadMessages(for: id)
        }
        // Auto-focus for new drafts (shouldAutoFocusInput) or first-launch empty state
        .onChange(of: chatManager.shouldAutoFocusInput) { _, should in
            guard should else { return }
            chatManager.shouldAutoFocusInput = false
            hasTriggeredInitialFocus = true
            triggerFocus(delay: 150)
        }
        // Focus whenever showing the empty / new-chat state (no conversation open).
        // Guards with hasTriggeredInitialFocus so it fires at most once per session.
        .onChange(of: chatManager.isLoadingChats) { _, loading in
            guard !loading, !hasTriggeredInitialFocus else { return }
            guard chatManager.currentConversation == nil else { return }
            hasTriggeredInitialFocus = true
            triggerFocus(delay: 300)
        }
        .onAppear {
            if chatManager.shouldAutoFocusInput {
                chatManager.shouldAutoFocusInput = false
                hasTriggeredInitialFocus = true
                triggerFocus(delay: 300)
            } else if !hasTriggeredInitialFocus, chatManager.currentConversation == nil {
                hasTriggeredInitialFocus = true
                triggerFocus(delay: 500)
            }
        }
        .alert("Error", isPresented: .constant(chatManager.error != nil)) {
            Button("OK") { chatManager.error = nil }
        } message: {
            Text(chatManager.error ?? "")
        }
        .alert("Voice Input", isPresented: .constant(voiceInput.error != nil)) {
            if let denied = voiceInput.deniedPermission {
                Button("Open Settings") {
                    openSystemSettings(for: denied)
                    voiceInput.error = nil
                    voiceInput.deniedPermission = nil
                }
                Button("Cancel", role: .cancel) {
                    voiceInput.error = nil
                    voiceInput.deniedPermission = nil
                }
            } else {
                Button("OK") { voiceInput.error = nil }
            }
        } message: {
            Text(voiceInput.error ?? "")
        }
        .overlay {
            if chatManager.showRateLimitModal {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { chatManager.showRateLimitModal = false }
                RateLimitModal(
                    info: chatManager.rateLimit,
                    period: chatManager.rateLimitEventPeriod,
                    resetLabel: chatManager.rateLimit?.resetLabel ?? chatManager.rateLimitEventResetLabel,
                    onClose: { chatManager.showRateLimitModal = false },
                    onUpgrade: { chatManager.showRateLimitModal = false }
                )
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var messageScrollArea: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { outer in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if let conversation = chatManager.currentConversation,
                               !conversation.messages.isEmpty {
                                ForEach(Array(conversation.messages.enumerated()), id: \.element.id) { index, message in
                                    // The question this answer was replying to, so a shared
                                    // card (bluefunda/cai-ios#197) can show both — looked up
                                    // here where the surrounding list is available, since
                                    // MessageView only sees a single message.
                                    let precedingQuestion = index > 0 ? conversation.messages[index - 1].content : nil
                                    let isThisMessageStreaming = chatManager.isStreaming
                                        && index == conversation.messages.count - 1
                                    MessageView(
                                        message: message,
                                        precedingQuestion: precedingQuestion,
                                        isThisMessageStreaming: isThisMessageStreaming
                                    )
                                    .id(message.id)
                                }
                                // Reads "Elevating your answer…" etc., which only makes sense
                                // before any text has appeared — once the reveal ticker starts
                                // painting real content, the inline cursor in MessageView takes
                                // over instead of also showing this alongside it.
                                if chatManager.isStreaming, conversation.messages.last?.content.isEmpty != false {
                                    StreamingIndicator()
                                }
                                // Reserves room below the last message while streaming, so
                                // scrolling the user's prompt to the top of the viewport (below)
                                // has somewhere to go instead of snapping back — matches
                                // cai-android's MessageList bottom spacer.
                                if chatManager.isStreaming {
                                    Color.clear.frame(height: outer.size.height * 0.85)
                                }
                            } else if chatManager.isLoadingChats {
                                ProgressView()
                                    .padding(.top, 40)
                                    .frame(maxWidth: .infinity)
                            } else {
                                EmptyStateView(greeting: greetingText)
                                    .frame(maxWidth: .infinity, minHeight: 300)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .frame(maxWidth: maxChatWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical)
                    }
                    .coordinateSpace(name: "chatScroll")
                    .scrollDismissesKeyboard(.interactively)
                    // Scrolls the newly-sent prompt to the *top* of the viewport (not the
                    // bottom) — leaves room below for the response to fill in as it streams,
                    // matching cai-android's `animateScrollToItem(latestUserMessageIndex)`.
                    .onChange(of: latestUserMessageID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .top)
                        }
                    }
                    .onChange(of: chatManager.currentConversation?.id) { _, _ in
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onAppear {
                        scrollProxy = proxy
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
            }
            if chatManager.isStreaming {
                streamingBottomShade
            }
        }
    }

    @ViewBuilder
    private var inputArea: some View {
        VStack(spacing: 0) {
            if let info = chatManager.rateLimit, info.status != .normal {
                RateLimitBanner(
                    status: info.status,
                    percent: info.dailyPercent,
                    resetLabel: info.resetLabel
                )
            }
            if showDumpDecodeBanner {
                ST22DumpBanner(onDecode: decodeDump)
            }
            ChatInputView(
                text: $inputText,
                isStreaming: chatManager.isStreaming,
                attachmentFilename: attachmentFilename,
                isFocused: $isInputFocused,
                rateLimitExceeded: chatManager.rateLimit?.status == .exceeded || chatManager.rateLimit?.status == .blocked,
                isRecording: voiceInput.isRecording,
                recordingElapsed: voiceInput.elapsed,
                onSend: sendMessage,
                onStop: stopStreaming,
                onClearAttachment: { clearAttachment() },
                onPickPhoto: BFFeatureFlags.fileUploadEnabled ? { showPhotoPicker = true } : nil,
                onPickFile:  BFFeatureFlags.fileUploadEnabled ? { presentDocumentPicker() } : nil,
                onPickDumpScreenshot: BFFeatureFlags.fileUploadEnabled ? {
                    attachmentIsForDumpDecode = true
                    showPhotoPicker = true
                } : nil,
                onMicTap: startRecording,
                onCancelRecording: cancelRecording,
                onConfirmRecording: confirmRecording,
                personaFeatureEnabled: chatManager.personaEnabled,
                personaToggleOn: $chatManager.chatPersonaEnabled,
                currentPersona: chatManager.chatPersonaOverride ?? chatManager.persona,
                personaOptions: chatManager.availablePersonas,
                onSelectPersona: { chatManager.chatPersonaOverride = $0 }
            )
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await loadAttachment(from: item) }
            }
            Text("AI responses may be inaccurate. Verify important information.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
    }

    /// What this chat's next message should use as its persona override,
    /// resolved from the composer's chat-local toggle/selection
    /// (bluefunda/cai-ios#217): `.general` when the toggle is off, so the
    /// send path's existing `personaEnabled ? (personaOverride ?? persona) :
    /// nil` resolution in `ChatManager.sendMessage` needs no changes — a
    /// non-nil `.general` override already means "no persona" there. Unlike
    /// the old per-message override (#205/#206), this is never reset after
    /// send: it's chat-scoped, not message-scoped.
    private var personaForActiveChat: Persona {
        chatManager.chatPersonaEnabled ? (chatManager.chatPersonaOverride ?? chatManager.persona) : .general
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !inputText.isEmpty || attachmentData != nil else { return }
        // Dismiss keyboard immediately — don't wait for isStreaming to flip
        isInputFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        let text = inputText
        inputText = ""
        let personaForThisSend = personaForActiveChat

        // Scrolling to the new prompt happens reactively via
        // .onChange(of: latestUserMessageID) once it actually appears in the
        // conversation, not here — chatManager.sendMessage appends it
        // asynchronously inside its own Task.

        if let data = attachmentData, let filename = attachmentFilename, let mime = attachmentMIME {
            let d = data; let f = filename; let m = mime
            let localMetadata = attachmentLocalMetadata
            let isDumpScreenshot = attachmentIsForDumpDecode
            clearAttachment(deleteLocal: false)
            Task {
                let fileUrl = try? await chatManager.uploadAttachment(data: d, filename: f, mimeType: m)
                if let fileUrl, let localMetadata {
                    chatManager.markAttachmentUploaded(localMetadata, remoteURL: fileUrl)
                }
                let prompt = text.isEmpty ? "Analyze the attached file." : text
                let override = isDumpScreenshot
                    ? ST22PromptBuilder.buildPrompt(rawDump: text.isEmpty ? nil : text)
                    : nil
                await chatManager.sendMessage(
                    prompt, fileUrl: fileUrl, requestPromptOverride: override, personaOverride: personaForThisSend
                )
            }
        } else {
            Task { await chatManager.sendMessage(text, personaOverride: personaForThisSend) }
        }
    }

    /// Sends the composer's pasted dump text wrapped in the decoder's
    /// instruction template (bluefunda/cai-ios#182), triggered by the
    /// "Decode" banner shown when the text looks like an ST22 short dump.
    private func decodeDump() {
        guard !inputText.isEmpty else { return }
        isInputFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        let text = inputText
        inputText = ""
        let personaForThisSend = personaForActiveChat
        Task {
            await chatManager.sendMessage(
                text,
                requestPromptOverride: ST22PromptBuilder.buildPrompt(rawDump: text),
                personaOverride: personaForThisSend
            )
        }
    }

    private func stopStreaming() {
        Task { await chatManager.stopStreaming() }
    }

    private func loadAttachment(from item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        attachmentData = data
        attachmentMIME = "image/jpeg"
        attachmentFilename = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        await persistAttachmentLocally()
    }

    /// Removes the in-progress attachment. Deletes the locally-persisted copy
    /// too unless the caller is about to send it (it's kept in that case, so
    /// it survives independent of whether the upload succeeds).
    private func clearAttachment(deleteLocal: Bool = true) {
        if deleteLocal, let metadata = attachmentLocalMetadata {
            Task { await chatManager.deleteAttachment(metadata) }
        }
        attachmentData = nil; attachmentFilename = nil
        attachmentMIME = nil; selectedPhotoItem = nil
        attachmentLocalMetadata = nil
        attachmentIsForDumpDecode = false
    }

    /// Presents the document picker imperatively — SwiftUI's `.fileImporter`
    /// (and even a `.sheet`-wrapped `UIViewControllerRepresentable`) silently
    /// fail to deliver their completion callback on Mac Catalyst.
    private func presentDocumentPicker() {
        documentPickerCoordinator = DocumentPickerCoordinator.present(
            allowedContentTypes: importableTypes,
            onPick: { url in
                handleFileImport(url)
                documentPickerCoordinator = nil
            },
            onCancel: {
                documentPickerCoordinator = nil
            }
        )
    }

    /// Copies the picked file (`asCopy: true`) into a location we already
    /// own, so no security-scoped access dance is needed.
    private func handleFileImport(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        attachmentData = data
        attachmentFilename = url.lastPathComponent
        attachmentMIME = mimeType(for: url.pathExtension)
        Task { await persistAttachmentLocally() }
    }

    /// Saves the currently-picked attachment via LocalFileStore so it
    /// persists with the conversation independent of the upload/send flow.
    private func persistAttachmentLocally() async {
        guard let data = attachmentData, let filename = attachmentFilename, let mime = attachmentMIME else { return }
        let conversationId = chatManager.conversationIdForAttachment()
        attachmentLocalMetadata = await chatManager.saveLocalAttachment(
            data: data, filename: filename, mimeType: mime, conversationId: conversationId
        )
    }

    // MARK: - Voice Input

    private func startRecording() {
        Task {
            guard await voiceInput.requestPermissions() else { return }
            do {
                try voiceInput.startRecording()
            } catch {
                voiceInput.error = "Couldn't start recording: \(error.localizedDescription)"
            }
        }
    }

    private func cancelRecording() {
        voiceInput.cancelRecording()
    }

    private func confirmRecording() {
        Task {
            guard let result = await voiceInput.stopRecordingAndTranscribe() else { return }
            if let transcript = result.transcript, !transcript.isBlank {
                inputText = inputText.isBlank ? transcript : inputText + " " + transcript
            }
            if let audioData = result.audioData {
                let conversationId = chatManager.conversationIdForAttachment()
                await chatManager.saveLocalAttachment(
                    data: audioData, filename: result.filename, mimeType: "audio/m4a", conversationId: conversationId
                )
            }
        }
    }

    /// Deep-links to the right permission pane. iOS/iPadOS has a per-app
    /// Settings page; Mac Catalyst has no such page — it must open System
    /// Settings' Privacy & Security pane via its own URL scheme instead.
    private func openSystemSettings(for denied: VoiceInputManager.DeniedPermission) {
        #if targetEnvironment(macCatalyst)
        let anchor = denied == .microphone ? "Privacy_Microphone" : "Privacy_SpeechRecognition"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        #else
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        #endif
        UIApplication.shared.open(url)
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "heic":        return "image/heic"
        case "webp":        return "image/webp"
        case "pdf":         return "application/pdf"
        case "txt":         return "text/plain"
        case "csv":         return "text/csv"
        case "json":        return "application/json"
        case "zip":         return "application/zip"
        default:            return "application/octet-stream"
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    /// Fades the last bit of streamed text into the background at the bottom
    /// edge of the scroll area, echoing cai-android's `StreamingBottomShade`.
    private var streamingBottomShade: some View {
        let background = Color(.systemBackground)
        return LinearGradient(
            stops: [
                .init(color: background.opacity(0), location: 0),
                .init(color: background.opacity(0.6), location: 0.45),
                .init(color: background.opacity(0.96), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 72)
        .allowsHitTesting(false)
    }

    private func triggerFocus(delay milliseconds: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            isInputFocused = true
        }
    }

}

// MARK: - Connection Banner

struct ConnectionBanner: View {
    let status: ConnectionStatus

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
            Text(status.description).font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(statusColor.opacity(0.2))
        .foregroundStyle(statusColor)
    }

    private var statusIcon: String {
        switch status {
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle"
        default: return "wifi.slash"
        }
    }

    private var statusColor: Color {
        switch status {
        case .connecting, .reconnecting: return BFColor.warning
        case .error: return BFColor.error
        default: return BFColor.neutral400
        }
    }
}

// MARK: - Message View

struct MessageView: View {
    let message: ChatMessage
    /// The user's question this answer replied to, if any — used only to
    /// build the shareable answer card (bluefunda/cai-ios#197); nil for user
    /// messages and for the very first message in a conversation.
    var precedingQuestion: String?
    /// True only for the single assistant message currently being streamed into.
    var isThisMessageStreaming: Bool = false
    @State private var didCopy = false

    /// Rendered on demand (not cached) since it's only needed when the user
    /// actually taps "Share as Card" — recomputing per tap is cheap for a
    /// single small card image.
    private var cardImage: UIImage? {
        guard !message.content.isEmpty else { return nil }
        let card = ShareableAnswerCard(question: precedingQuestion, answer: message.content)
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    var body: some View {
        if message.role == .user {
            userBubble
        } else {
            assistantContent
        }
    }

    /// Small "· FI" style tag shown next to the timestamp when this message
    /// carried a specific persona (bluefunda/cai-ios#207) — omitted for
    /// `.general` (the no-specific-persona baseline) and for messages with no
    /// recorded persona at all (predates the field, or the feature was off).
    @ViewBuilder
    private var personaBadge: some View {
        if let raw = message.persona, let persona = Persona.resolve(raw), persona != .general {
            HStack(spacing: 3) {
                Image(systemName: persona.icon)
                Text(persona.shortLabel)
            }
        }
    }

    // Long-press actions shared by user prompts and assistant responses.
    @ViewBuilder
    private var messageActions: some View {
        Button {
            UIPasteboard.general.string = message.content
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        ShareLink(item: message.content) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    // Right-aligned bubble — matches ChatGPT / Claude iOS style
    private var userBubble: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 3) {
                if let fileUrl = message.fileUrl, !fileUrl.isEmpty {
                    AttachmentChip(filename: URL(string: fileUrl)?.lastPathComponent ?? "Attachment")
                }
                Text(message.content)
                    .font(BFFont.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        BFColor.primary.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .contextMenu { messageActions }
                HStack(spacing: 6) {
                    personaBadge
                    Text(message.timestamp, style: .time)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, 6)
    }

    // Left-aligned response — full width, no background
    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // PacedMarkdownView reveals streamed text at a readable pace instead of repainting the
            // full markdown tree on every token (only once text has actually started — before
            // that, StreamingIndicator's spinner+caption above covers the "waiting for the first
            // token" state instead).
            PacedMarkdownView(
                messageId: message.id,
                targetContent: message.content,
                isStreaming: isThisMessageStreaming && !message.content.isEmpty
            )
            .font(BFFont.body)
            .contextMenu { if !message.content.isEmpty { messageActions } }

            if let fileMetadata = message.fileMetadata, !fileMetadata.isEmpty {
                HStack(spacing: 8) {
                    ForEach(fileMetadata, id: \.self) { meta in
                        AttachmentChip(filename: meta.fileName ?? URL(string: meta.downloadURL ?? meta.originalURL ?? "")?.lastPathComponent ?? "File")
                    }
                }
            }

            if !message.content.isEmpty {
                HStack(spacing: 20) {
                    Button {
                        UIPasteboard.general.string = message.content
                        didCopy = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            didCopy = false
                        }
                    } label: {
                        Label(didCopy ? "Copied" : "Copy",
                              systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    ShareLink(item: message.content) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    if let cardImage {
                        ShareLink(
                            item: Image(uiImage: cardImage),
                            preview: SharePreview("BlueFunda AI Answer", image: Image(uiImage: cardImage))
                        ) {
                            Label("Share as Card", systemImage: "photo.badge.arrow.down.fill")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                personaBadge
                Text(message.timestamp, style: .time)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, 12)
    }
}

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
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.systemGray6), in: Capsule())
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let greeting: String

    var body: some View {
        VStack(spacing: 14) {
            // A bottom Spacer with a larger minLength than the top one
            // biases the greeting upward by a constant gap, away from the
            // keyboard that's shown by default on this screen (cai-ios#255)
            // — plain maxHeight:.infinity centering re-centers into whatever
            // shrunk space remains once the keyboard appears, leaving no
            // real clearance above it.
            Spacer(minLength: 24)
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(BFColor.primary.gradient)
            Text(greeting)
                .font(BFFont.h4)
                .multilineTextAlignment(.center)
            Text("How can I help you today?")
                .font(BFFont.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 64)
        }
        .padding(BFSpacing._5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chat Input View

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

    var body: some View {
        VStack(spacing: 0) {
            if let filename = attachmentFilename {
                HStack(spacing: 10) {
                    Image(systemName: "paperclip").foregroundStyle(BFColor.primary)
                    Text(filename).font(BFFont.bodySmall).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onClearAttachment) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, BFSpacing._4)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
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

                // Mic button — replaced by the send button once there's something to send
                if let micTap = onMicTap, !canSend {
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
                        Image(systemName: isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(canSend || isStreaming ? BFColor.primary : .secondary)
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

// MARK: - ST22 Dump Decode Banner

/// Shown above the composer when the pasted text looks like an ST22 short
/// dump (bluefunda/cai-ios#182), offering a structured decode instead of
/// sending it as a plain question.
struct ST22DumpBanner: View {
    let onDecode: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BFColor.warning)
            Text("This looks like an ST22 dump")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Decode", action: onDecode)
                .font(.caption)
                .fontWeight(.semibold)
                .buttonStyle(.plain)
                .foregroundStyle(BFColor.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(BFColor.warning.opacity(0.1))
    }
}

// MARK: - Rate Limit Banner

struct RateLimitBanner: View {
    let status: RateLimitStatus
    let percent: Double
    let resetLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                .foregroundColor(bannerColor)
            Text(message)
                .font(.caption)
                .foregroundColor(bannerColor)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(bannerColor.opacity(0.1))
    }

    private var bannerColor: Color {
        status == .warning ? BFColor.warning : BFColor.error
    }

    private var message: String {
        switch status {
        case .warning:
            return "You've used \(Int(percent * 100))% of your daily token limit"
        case .exceeded:
            return "Token limit reached. Resets in \(resetLabel)."
        case .blocked:
            return "Your account has been temporarily blocked."
        case .normal:
            return ""
        }
    }
}

// MARK: - Rate Limit Modal

struct RateLimitModal: View {
    let info: RateLimitInfo?
    let period: String
    let resetLabel: String
    let onClose: () -> Void
    let onUpgrade: () -> Void

    private var planName: String { info?.planName ?? "current" }

    private var isMonthly: Bool {
        if let info, info.monthlyPercent >= 1.0 && info.dailyPercent < 1.0 { return true }
        return period == "monthly"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Badge-icon header — mirrors the "You're on Pro" treatment in
            // SubscriptionView (tinted circle + SF Symbol) instead of a solid
            // color banner, so this reads as an in-brand alert rather than a
            // raw system-red warning.
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(BFColor.error.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(BFColor.error)
                }
                Text("Token Limit Reached")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(BFColor.textHeading)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, BFSpacing._6)
            .padding(.bottom, BFSpacing._3)

            VStack(alignment: .leading, spacing: 8) {
                Text("You've reached your **\(planName)** plan's token limit.")
                    .font(.body)
                    .foregroundStyle(BFColor.textBody)
                Text("\(isMonthly ? "Monthly" : "Daily") limit resets in **\(resetLabel)**.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider()

            HStack(spacing: 12) {
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
                Button("Upgrade to Premium", action: onUpgrade)
                    .buttonStyle(.borderedProminent)
                    .tint(BFColor.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: BFRadius.xl))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
        .padding(.horizontal, 24)
    }
}

#Preview {
    ChatView()
        .environmentObject(ChatManager(service: BFFChatService()))
        .environmentObject(AuthManager())
}
