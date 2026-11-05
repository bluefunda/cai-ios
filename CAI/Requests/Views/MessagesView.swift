import SwiftUI

// MARK: - Messages Destination
// The BlueRequests web app's Messages screen: the user's conversations, and each one's
// messages with a reply box. Same trm-gw routes as the web (see RQMessages.swift).

struct MessagesView: View {
    @ObservedObject var state: RequestsState
    var navigationControl: ShellNavigationControl = .none

    var body: some View {
        NavigationStack {
            if let model = state.messages {
                MessagesListScreen(model: model, navigationControl: navigationControl)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .shellNavigationControl(navigationControl)
            }
        }
    }
}

private struct MessagesListScreen: View {
    @ObservedObject var model: MessagesListViewModel
    let navigationControl: ShellNavigationControl

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(searchText: $model.searchText, searchPrompt: "Search messages")
            content
        }
        .background(BFColor.surfaceCanvas)
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .shellNavigationControl(navigationControl)
        .navigationDestination(for: RQConversation.self) { conversation in
            MessageThreadScreen(model: model.makeConversationModel(for: conversation))
        }
        .task { await model.loadIfNeeded() }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.conversations.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.error, model.conversations.isEmpty {
            RequestsErrorCard(message: RequestsErrorCard.message(for: error, subject: "messages")) {
                Task { await model.load() }
            }
        } else if model.filteredConversations.isEmpty {
            if model.searchText.isEmpty {
                ContentUnavailableView(
                    "No messages yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Conversations with your team will show up here.")
                )
            } else {
                ContentUnavailableView.search(text: model.searchText)
            }
        } else {
            List {
                if let error = model.error {
                    InlineErrorBanner(message: error) { Task { await model.load() } }
                        .listRowSeparator(.hidden)
                }
                ForEach(model.filteredConversations) { conversation in
                    NavigationLink(value: conversation) {
                        MessageThreadRow(conversation: conversation, currentUserId: model.currentUserId)
                    }
                    .listRowBackground(BFColor.surfaceCanvas)
                    .listRowSeparatorTint(BFColor.hairline)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct MessageThreadRow: View {
    let conversation: RQConversation
    let currentUserId: String?

    private var others: [RQParticipant] { conversation.others(excluding: currentUserId) }

    private var title: String {
        if !conversation.topic.isEmpty { return conversation.topic }
        let names = others.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? "Conversation" : names.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: BFSpacing._3) {
            RQAvatar(urlString: others.first?.profileImage, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(RQFont.rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: BFSpacing._2)
                    if let date = conversation.lastMessage?.createdAt {
                        Text(date.relativeDescription)
                            .font(RQFont.meta)
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack {
                    Text(conversation.lastMessage?.text ?? "No messages yet")
                        .font(RQFont.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: BFSpacing._2)
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(RQFont.pill)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BFColor.primary, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Conversation

private struct MessageThreadScreen: View {
    @StateObject private var model: ConversationViewModel

    init(model: ConversationViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    /// While the conversation is open, new messages are picked up this often (the web app
    /// streams them; polling keeps this screen simple).
    private static let refreshInterval: Duration = .seconds(10)

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider().overlay(BFColor.hairline)
            composer
        }
        .background(BFColor.surfaceCanvas)
        .navigationTitle(model.conversation.topic.isEmpty ? "Conversation" : model.conversation.topic)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { break }
                await model.refreshLatest()
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BFSpacing._2) {
                    if model.hasEarlier {
                        Button {
                            Task { await model.loadEarlier() }
                        } label: {
                            if model.isLoadingEarlier {
                                ProgressView()
                            } else {
                                Text("Load earlier messages").font(RQFont.meta)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BFSpacing._2)
                    }
                    if model.isLoading && model.messages.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, BFSpacing._4)
                    }
                    if let error = model.error {
                        InlineErrorBanner(message: error) { Task { await model.load() } }
                    }
                    ForEach(model.messages) { message in
                        MessageBubble(message: message, isMine: model.isMine(message))
                            .id(message.id)
                    }
                }
                .padding(BFSpacing._4)
            }
            .onChange(of: model.messages.last?.id) { _, lastId in
                guard let lastId else { return }
                withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: BFSpacing._2) {
            TextField("Write a message", text: $model.draft, axis: .vertical)
                .font(RQFont.body)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, BFSpacing._3)
                .padding(.vertical, BFSpacing._2)
                .background(BFColor.surfaceSunken, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onSubmit { Task { await model.send() } }
            Button {
                Task { await model.send() }
            } label: {
                if model.isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canSend ? BFColor.primary : Color.secondary)
            .disabled(!model.canSend)
            .accessibilityLabel("Send")
        }
        .padding(BFSpacing._3)
    }
}

private struct MessageBubble: View {
    let message: RQMessage
    let isMine: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: BFSpacing._2) {
            if isMine { Spacer(minLength: 48) } else {
                RQAvatar(urlString: message.sender?.profileImage, size: 24)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if !isMine, let name = message.sender?.name, !name.isEmpty {
                    Text(name).font(RQFont.meta).foregroundStyle(.secondary)
                }
                Text(message.text)
                    .font(RQFont.body)
                    .foregroundStyle(isMine ? Color.white : Color.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, BFSpacing._3)
                    .padding(.vertical, BFSpacing._2)
                    .background(isMine ? BFColor.primary : BFColor.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let date = message.createdAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(RQFont.meta)
                        .foregroundStyle(.tertiary)
                }
            }
            if !isMine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }
}
