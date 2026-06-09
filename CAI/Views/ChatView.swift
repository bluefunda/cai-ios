import SwiftUI
import PhotosUI

struct ChatView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    // Attachment state
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachmentData: Data?
    @State private var attachmentFilename: String?
    @State private var attachmentMIME: String?

    // Scroll management
    @State private var isAtBottom = true
    @State private var showScrollButton = false
    // Captured proxy for the scroll button tap
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // Connection banner
            if chatManager.connectionStatus != .connected {
                ConnectionBanner(status: chatManager.connectionStatus)
            }

            // Messages + scroll-down button overlay
            ZStack(alignment: .bottomTrailing) {
                GeometryReader { outer in
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if let conversation = chatManager.currentConversation,
                                   !conversation.messages.isEmpty {
                                    ForEach(conversation.messages) { message in
                                        MessageView(message: message)
                                            .id(message.id)
                                    }

                                    if chatManager.isStreaming {
                                        StreamingIndicator()
                                    }
                                } else if chatManager.isLoadingChats {
                                    ProgressView()
                                        .padding(.top, 40)
                                        .frame(maxWidth: .infinity)
                                } else {
                                    EmptyStateView()
                                        .frame(maxWidth: .infinity, minHeight: 300)
                                }

                                // Scroll anchor + bottom-visibility probe (works iOS 17+)
                                Color.clear
                                    .frame(height: 1)
                                    .id("bottom")
                                    .background(
                                        GeometryReader { marker in
                                            Color.clear.preference(
                                                key: AtBottomPreferenceKey.self,
                                                value: marker.frame(in: .named("chatScroll")).minY
                                                    <= outer.size.height + 60
                                            )
                                        }
                                    )
                            }
                            .padding(.vertical)
                        }
                        .coordinateSpace(name: "chatScroll")
                        .defaultScrollAnchor(.bottom)
                        .scrollDismissesKeyboard(.interactively)
                        .onPreferenceChange(AtBottomPreferenceKey.self) { atBottom in
                            isAtBottom = atBottom
                            showScrollButton = !atBottom
                        }
                        // Auto-scroll only when already at the bottom
                        .onChange(of: chatManager.currentConversation?.messages.count) { _, _ in
                            if isAtBottom { scrollToBottom(proxy: proxy) }
                        }
                        .onChange(of: chatManager.currentConversation?.messages.last?.content.count) { _, _ in
                            if isAtBottom { scrollToBottom(proxy: proxy) }
                        }
                        // When streaming starts → jump to bottom and follow
                        .onChange(of: chatManager.isStreaming) { _, streaming in
                            if streaming {
                                isAtBottom = true
                                showScrollButton = false
                                scrollToBottom(proxy: proxy)
                            }
                        }
                        .onAppear { scrollProxy = proxy }
                    }
                }

                // Scroll-to-bottom button (shown when scrolled up / response overflows)
                if showScrollButton {
                    Button {
                        isAtBottom = true
                        showScrollButton = false
                        if let proxy = scrollProxy {
                            scrollToBottom(proxy: proxy)
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                            .background(Color.blue, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    }
                    .padding(.bottom, 12)
                    .padding(.trailing, 16)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(duration: 0.2), value: showScrollButton)
                }
            }

            Divider()

            // Input
            ChatInputView(
                text: $inputText,
                isStreaming: chatManager.isStreaming,
                attachmentFilename: attachmentFilename,
                selectedPhotoItem: $selectedPhotoItem,
                isFocused: $isInputFocused,
                onSend: sendMessage,
                onStop: stopStreaming,
                onClearAttachment: clearAttachment
            )
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await loadAttachment(from: item) }
            }
        }
        // Dismiss keyboard when AI starts responding
        .onChange(of: chatManager.isStreaming) { _, streaming in
            if streaming {
                isInputFocused = false
                dismissKeyboard()
            }
        }
        // Load messages when active conversation changes (fixes history)
        .task(id: chatManager.currentConversation?.id) {
            guard let id = chatManager.currentConversation?.id else { return }
            await chatManager.loadMessages(for: id)
        }
        .alert("Error", isPresented: .constant(chatManager.error != nil)) {
            Button("OK") { chatManager.error = nil }
        } message: {
            Text(chatManager.error ?? "")
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !inputText.isEmpty || attachmentData != nil else { return }
        let text = inputText
        inputText = ""

        if let data = attachmentData, let filename = attachmentFilename, let mime = attachmentMIME {
            let d = data; let f = filename; let m = mime
            clearAttachment()
            Task {
                let url = try? await chatManager.uploadAttachment(data: d, filename: f, mimeType: m)
                let prompt = url.map { text.isEmpty ? "I've attached a file: \($0)" : "\(text)\n\n[Attached: \($0)]" }
                    ?? (text.isEmpty ? "I've attached a file." : text)
                await chatManager.sendMessage(prompt)
            }
        } else {
            Task { await chatManager.sendMessage(text) }
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
    }

    private func clearAttachment() {
        attachmentData = nil; attachmentFilename = nil
        attachmentMIME = nil; selectedPhotoItem = nil
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
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
        case .connecting, .reconnecting: return .orange
        case .error: return .red
        default: return .gray
        }
    }
}

// MARK: - Message View

struct MessageView: View {
    let message: ChatMessage
    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(message.role == .user ? Color.blue : Color.green)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: message.role == .user ? "person.fill" : "brain.head.profile")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(message.role.displayName)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)

                if message.role == .user {
                    Text(message.content).textSelection(.enabled)
                } else {
                    MarkdownView(content: message.content)
                }

                // Copy / Share actions on AI responses
                if message.role == .assistant, !message.content.isEmpty {
                    HStack(spacing: 16) {
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
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)

                        ShareLink(item: message.content) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(message.role == .user ? Color.blue.opacity(0.05) : Color.clear)
    }
}

// MARK: - Streaming Indicator

struct StreamingIndicator: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.green)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14)).foregroundStyle(.white)
                }
            Text("Thinking" + String(repeating: ".", count: dotCount + 1))
                .foregroundStyle(.secondary).font(.subheadline)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onReceive(timer) { _ in dotCount = (dotCount + 1) % 3 }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Start a Conversation")
                .font(.title2).fontWeight(.semibold)
            Text("Ask anything about SAP, ABAP, or use MCP tools")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chat Input View

struct ChatInputView: View {
    @Binding var text: String
    let isStreaming: Bool
    let attachmentFilename: String?
    @Binding var selectedPhotoItem: PhotosPickerItem?
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void
    let onClearAttachment: () -> Void

    private var canSend: Bool { !text.isEmpty || attachmentFilename != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Attachment preview strip
            if let filename = attachmentFilename {
                HStack(spacing: 8) {
                    Image(systemName: "photo").foregroundStyle(.blue)
                    Text(filename).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onClearAttachment) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: attachmentFilename != nil ? "photo.fill" : "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(attachmentFilename != nil ? .blue : .secondary)
                        .frame(width: 36, height: 36)
                }

                TextField("Message...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused(isFocused)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .lineLimit(1...5)

                Button {
                    isStreaming ? onStop() : onSend()
                } label: {
                    Image(systemName: isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(isStreaming ? .red : (canSend ? .blue : .secondary))
                }
                .disabled(!isStreaming && !canSend)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Mode + Model Picker

/// Single dropdown combining the thinking mode (Auto / Quick Response /
/// Think Deeper) and the LLM, mirroring the cai web app.
struct ModeModelPicker: View {
    @EnvironmentObject var chatManager: ChatManager

    // Exactly one of {a thinking mode, an explicit LLM} is active, mirroring
    // the cai web UnifiedModeSelector.
    private func modeIsActive(_ mode: ThinkingMode) -> Bool {
        !chatManager.userPickedModel && chatManager.thinkingMode == mode
    }
    private func modelIsActive(_ model: LLMModel) -> Bool {
        chatManager.userPickedModel && chatManager.selectedModel.id == model.id
    }

    var body: some View {
        Menu {
            // Thinking modes
            Section {
                ForEach(ThinkingMode.allCases) { mode in
                    Button {
                        chatManager.selectThinkingMode(mode)
                    } label: {
                        if modeIsActive(mode) {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Label(mode.label, systemImage: mode.icon)
                        }
                    }
                }
            }

            // LLMs
            Section("LLM") {
                ForEach(chatManager.availableModels) { model in
                    Button {
                        chatManager.selectModel(model)
                    } label: {
                        if modelIsActive(model) {
                            Label(model.name, systemImage: "checkmark")
                        } else {
                            Text(model.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: chatManager.userPickedModel ? "cpu" : chatManager.thinkingMode.icon)
                    .font(.caption2)
                Text(chatManager.userPickedModel
                     ? chatManager.selectedModel.name
                     : chatManager.thinkingMode.label)
                    .font(.caption).fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

// MARK: - Scroll Position Tracking (cross-version, iOS 17+)

/// True when the bottom anchor is at/near the visible bottom of the scroll view.
private struct AtBottomPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

#Preview {
    ChatView()
        .environmentObject(ChatManager(service: BFFChatService()))
}
