import SwiftUI

struct ChatView: View {
    @EnvironmentObject var chatManager: ChatManager
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection Status Banner
                if chatManager.connectionStatus != .connected {
                    ConnectionBanner(status: chatManager.connectionStatus)
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            if let conversation = chatManager.currentConversation,
                               !conversation.messages.isEmpty {
                                ForEach(conversation.messages) { message in
                                    MessageView(message: message)
                                        .id(message.id)
                                }

                                // Streaming indicator
                                if chatManager.isStreaming {
                                    StreamingIndicator()
                                        .id("streaming")
                                }
                            } else {
                                EmptyStateView()
                                    .frame(maxHeight: .infinity)
                            }

                            // Anchor for scrolling
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.vertical)
                        .frame(minHeight: 300)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: chatManager.currentConversation?.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: chatManager.currentConversation?.messages.last?.content.count) { _, _ in
                        // Scroll as streaming content grows
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: chatManager.isStreaming) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }

                Divider()

                // Input Area
                ChatInputView(
                    text: $inputText,
                    isStreaming: chatManager.isStreaming,
                    onSend: sendMessage,
                    onStop: stopStreaming
                )
                .focused($isInputFocused)
            }
            .navigationTitle(chatManager.currentConversation?.title ?? "New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        chatManager.newConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ModelPicker(selectedModel: $chatManager.selectedModel)
                }
            }
            .alert("Error", isPresented: .constant(chatManager.error != nil)) {
                Button("OK") {
                    chatManager.error = nil
                }
            } message: {
                Text(chatManager.error ?? "")
            }
        }
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        let message = inputText
        inputText = ""

        Task {
            await chatManager.sendMessage(message)
        }
    }

    private func stopStreaming() {
        Task {
            await chatManager.stopStreaming()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

// MARK: - Connection Banner

struct ConnectionBanner: View {
    let status: ConnectionStatus

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
            Text(status.description)
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(statusColor.opacity(0.2))
        .foregroundColor(statusColor)
    }

    private var statusIcon: String {
        switch status {
        case .connecting, .reconnecting:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle"
        default:
            return "wifi.slash"
        }
    }

    private var statusColor: Color {
        switch status {
        case .connecting, .reconnecting:
            return .orange
        case .error:
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - Message View

struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(message.role == .user ? Color.blue : Color.green)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: message.role == .user ? "person.fill" : "brain.head.profile")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(message.role.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text(message.content)
                    .textSelection(.enabled)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
        HStack {
            Circle()
                .fill(Color.green)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }

            Text("Thinking" + String(repeating: ".", count: dotCount + 1))
                .foregroundColor(.secondary)
                .font(.subheadline)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 3
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Start a Conversation")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Ask anything about SAP, ABAP, or use MCP tools")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // Text Field
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .lineLimit(1...5)

            // Send/Stop Button
            Button {
                if isStreaming {
                    onStop()
                } else {
                    onSend()
                }
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(isStreaming ? .red : (text.isEmpty ? .gray : .blue))
            }
            .disabled(!isStreaming && text.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - Model Picker

struct ModelPicker: View {
    @Binding var selectedModel: LLMModel
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        Menu {
            ForEach(chatManager.availableModels) { model in
                Button {
                    selectedModel = model
                } label: {
                    HStack {
                        Text(model.name)
                        if model.id == selectedModel.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedModel.provider.uppercased())
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(ChatManager(service: BFFChatService()))
}
