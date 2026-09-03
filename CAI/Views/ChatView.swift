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
    /// Keeps the camera delegate alive for the duration of an imperative
    /// presentation (see CameraCaptureCoordinator).
    @State private var cameraCoordinator: CameraCaptureCoordinator?
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
    /// Tracked separately from `latestUserMessageID` so the very first send can align the
    /// scroll view's layout (see the `.onChange(of: hasMessages)` handler) before the animated
    /// per-message scroll runs — matches cai-android's `LaunchedEffect(messages.isNotEmpty())`.
    private var hasMessages: Bool {
        !(chatManager.currentConversation?.messages.isEmpty ?? true)
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
                                    // The isStreaming half is keyed on the specific message id
                                    // (streamingMessageId), not array position — an early Stop can
                                    // remove trailing messages, and without identity-matching the
                                    // new "last" message (an older, already-completed response)
                                    // would briefly inherit isStreaming's true value and look like
                                    // it had resumed streaming. isReconciling stays position-based:
                                    // reconcileAfterBackground() clears isStreaming immediately
                                    // (before its retry loop even starts) to stop the dead local
                                    // stream task from racing the re-fetch, so without this the
                                    // still-empty assistant bubble would fall out of the streaming
                                    // state and show an empty response box (and the composer's mic
                                    // button instead of Stop) for the seconds reconciliation takes —
                                    // and the re-fetched message may not keep the same local id.
                                    let isThisMessageStreaming = (chatManager.isStreaming && message.id == chatManager.streamingMessageId)
                                        || (chatManager.isReconciling && index == conversation.messages.count - 1)
                                    // Identity-based for the same reason as isThisMessageStreaming
                                    // above — didStopCurrentMessage alone, matched by position,
                                    // would mislabel an older message once an early Stop removes
                                    // trailing ones.
                                    let wasThisMessageStopped = chatManager.didStopCurrentMessage
                                        && message.id == chatManager.stoppedMessageId
                                    let isLastMessage = index == conversation.messages.count - 1
                                    MessageView(
                                        message: message,
                                        precedingQuestion: precedingQuestion,
                                        isThisMessageStreaming: isThisMessageStreaming,
                                        wasStopped: wasThisMessageStopped,
                                        onRevealingChanged: isLastMessage
                                            ? { chatManager.isRevealingLastMessage = $0 }
                                            : { _ in }
                                    )
                                    .id(message.id)
                                }
                                // Reserves room below the last message while streaming, so
                                // scrolling the user's prompt to the top of the viewport (below)
                                // has somewhere to go instead of snapping back — matches
                                // cai-android's MessageList bottom spacer.
                                if chatManager.isStreaming {
                                    Color.clear.frame(height: outer.size.height * 0.65)
                                }
                            } else if chatManager.isLoadingChats && chatManager.conversations.isEmpty {
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
                    // `.defaultScrollAnchor(.bottom)` was tried here instead of the explicit,
                    // event-driven scrolling below, but it re-anchors continuously — every time
                    // the actively-streaming bubble grows even one line taller, it re-pins the
                    // whole scroll content to the bottom, shoving everything already visible
                    // upward on every reveal tick. That reads as text "printing from bottom to
                    // top" instead of a normal top-down reveal with the view following it down.
                    // Explicit onChange-driven scrolling (fired on real events — new message,
                    // conversation switch — not on every content-size change) doesn't have that
                    // problem, which is why it's back instead of the anchor.
                    //
                    // Mirrors cai-android's MessageList exactly, which pairs two effects:
                    // 1) `LaunchedEffect(messages.isNotEmpty())` — the instant, unanimated
                    //    `scrollToItem(lastIndex)` fired once when the list first goes from
                    //    empty to non-empty (EmptyStateView -> real rows). This is the piece
                    //    iOS was missing: without it, the very first send left the ScrollView
                    //    at its just-created top-of-content position while the animated .top
                    //    scroll below tried to align a row that didn't have settled geometry
                    //    yet, so it visually landed under the header and snapped down once
                    //    layout caught up.
                    // 2) `LaunchedEffect(latestUserMessageId)` — the animated `.top` scroll to
                    //    the newest user row, unconditionally, first message included. Once (1)
                    //    has already forced a layout pass by aligning the last row (here, the
                    //    empty assistant placeholder) to the top, this animated step is just a
                    //    one-row correction up to the user's own message, not a fresh scroll
                    //    into unmeasured content.
                    .onChange(of: hasMessages) { _, isNonEmpty in
                        guard isNonEmpty, let lastID = chatManager.currentConversation?.messages.last?.id else { return }
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                    // reconcileAfterBackground() re-fetches the conversation from the server and
                    // replaces the whole messages array with server-assigned message ids —
                    // different from the client-side ids used while the message was actively
                    // streaming. ForEach(id: \.element.id) treats that as an entirely new list
                    // (not "one row appended" like the steady-state case below), so it needs the
                    // same instant bottom-align settle as the very-first-message transition above —
                    // without it, the animated per-message scroll targets a row whose layout
                    // hasn't been established under the new identities yet, leaving the user's
                    // own prompt scrolled off above the header until something else nudges it.
                    .onChange(of: chatManager.isReconciling) { wasReconciling, isReconciling in
                        guard wasReconciling, !isReconciling,
                               let lastID = chatManager.currentConversation?.messages.last?.id else { return }
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                    .onChange(of: latestUserMessageID) { _, newID in
                        guard let newID else { return }
                        // Only scroll the user prompt to the top for subsequent messages.
                        // For the very first message, leaving it at its natural top offset is correct.
                        guard (chatManager.currentConversation?.messages.count ?? 0) > 2 else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(newID, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: chatManager.currentConversation?.id) { _, _ in
                        // Guarded on hasMessages: for a brand-new empty conversation (New Chat),
                        // there's nothing below the EmptyStateView but its "bottom" spacer —
                        // scrolling to it anchors that spacer at the viewport's bottom edge and
                        // pushes the ~300pt-tall greeting entirely above the visible area, reading
                        // as a blank screen until the user manually scrolls up to find it.
                        guard hasMessages else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onAppear {
                        scrollProxy = proxy
                        guard hasMessages else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(50))
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
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
                // Keeps Stop showing (instead of falling back to mic) through the
                // reconcileAfterBackground() retry window (see the matching comment on
                // isThisMessageStreaming above) and through PacedMarkdownView's local reveal
                // outlasting a fast/short response that already finished on the wire.
                isStreaming: chatManager.isStreaming || chatManager.isReconciling || chatManager.isRevealingLastMessage,
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
                onPickCamera: BFFeatureFlags.fileUploadEnabled && UIImagePickerController.isSourceTypeAvailable(.camera)
                    ? { presentCamera() } : nil,
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
            let prompt = text.isEmpty ? "Analyze the attached file." : text
            let override = isDumpScreenshot
                ? ST22PromptBuilder.buildPrompt(rawDump: text.isEmpty ? nil : text)
                : nil
            Task {
                // Show the user's own message immediately, independent of the attachment
                // upload — previously the upload was awaited *before* calling sendMessage at
                // all, so a slow/stalled upload left even the just-typed prompt invisible for
                // several seconds after tapping send.
                // Displays exactly what the user typed (nothing, if they only attached a file) —
                // `prompt` below (with the "Analyze the attached file." fallback) is for the
                // backend request only, via continueSendingMessage's own `text` param. The chip
                // itself renders off fileUrl, so it's seeded with the local filename immediately
                // (above the prompt, matching the requested layout) rather than staying blank
                // until the upload resolves — swapped for the real remote URL below once known.
                guard let pending = await chatManager.beginUserTurn(
                    text, fileUrl: f, personaOverride: personaForThisSend, allowBlankText: true
                ) else { return }

                var fileUrl: String?
                do {
                    fileUrl = try await chatManager.uploadAttachment(data: d, filename: f, mimeType: m)
                } catch {
                    // Was a silent `try?` — logged now so an upload failure shows up in the
                    // device console instead of just silently sending the prompt text-only.
                    print("[ChatView] attachment upload failed: \(error)")
                }
                if let fileUrl {
                    chatManager.updateUserMessageFileUrl(fileUrl, messageId: pending.userMessage.id, in: pending.conversation.id)
                    if let localMetadata {
                        chatManager.markAttachmentUploaded(localMetadata, remoteURL: fileUrl)
                    }
                }
                await chatManager.continueSendingMessage(
                    pending, text: prompt, fileUrl: fileUrl, requestPromptOverride: override
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

    /// `loadTransferable(type: Data.self)` hands back the asset's original,
    /// untranscoded bytes — on any iPhone using the default "High Efficiency"
    /// camera format, that's HEIC, not JPEG. Re-encoding through `UIImage`
    /// guarantees the bytes actually match the `image/jpeg` label sent to the
    /// backend; sending raw HEIC mislabeled as JPEG produces an undecodable
    /// image on the LLM provider's end, which reads to the user as "the
    /// backend doesn't see any image attached".
    private func loadAttachment(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.85)
        else { return }
        attachmentData = jpegData
        attachmentMIME = "image/jpeg"
        attachmentFilename = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        await persistAttachmentLocally()
    }

    /// Presents the camera imperatively — see CameraCaptureCoordinator for
    /// why (mirrors presentDocumentPicker's reasoning for Mac Catalyst).
    /// Presenting a full-screen `UIImagePickerController` camera session while the
    /// composer's text field is still first responder (mid keyboard-dismissal)
    /// corrupts the presentation transition — observed as a "Snapshotting a view
    /// ... UIKeyboardImpl ... not in a visible window" warning immediately
    /// followed by AVCapture/XPC session errors (FigCaptureSourceRemote), with no
    /// image ever delivered to the completion handler. Resigning first responder
    /// and giving the keyboard a moment to actually finish dismissing before
    /// presenting avoids the corrupted transition.
    private func presentCamera() {
        isInputFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            cameraCoordinator = CameraCaptureCoordinator.present(
                onCapture: { image in
                    Task { await loadAttachment(from: image) }
                    cameraCoordinator = nil
                },
                onCancel: {
                    cameraCoordinator = nil
                }
            )
        }
    }

    private func loadAttachment(from image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
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
    /// True when the user explicitly tapped Stop for this message — tells
    /// PacedMarkdownView to snap its reveal to whatever content arrived rather than
    /// keep trickling out an already-received backlog at typing speed.
    var wasStopped: Bool = false
    /// Reports whether PacedMarkdownView is still visibly revealing this message, so the
    /// composer can keep showing Stop for as long as text is still visibly printing — even
    /// after the network side (isThisMessageStreaming) has already finished.
    var onRevealingChanged: (Bool) -> Void = { _ in }
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
                // An attachment sent with no typed text has empty content — rendered unconditionally,
                // this still painted a visible empty rounded pill (padding + background) next to the
                // chip, even though there was nothing to show inside it.
                if !message.content.isEmpty {
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
                }
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

    // Left-aligned response, in a rounded background that grows with the content —
    // matches cai-android's MessageBubble (assistantBg + animateContentSize()).
    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mutually exclusive with the boxed content below — matches cai-android's
            // MessageBubble (`if (content.isEmpty && isStreaming) StreamingIndicator() else
            // Column(background) { ... }`). Showing both at once put an empty rounded box on
            // screen before any real text existed.
            if isThisMessageStreaming, message.content.isEmpty {
                StreamingIndicator()
            } else {
                // PacedMarkdownView reveals streamed text at a readable pace instead of
                // repainting the full markdown tree on every token.
                PacedMarkdownView(
                    messageId: message.id,
                    targetContent: message.content,
                    isStreaming: isThisMessageStreaming && !message.content.isEmpty,
                    wasStopped: wasStopped,
                    onRevealingChanged: onRevealingChanged
                )
                .font(BFFont.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu { if !message.content.isEmpty { messageActions } }
            }

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
