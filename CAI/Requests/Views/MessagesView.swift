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
                MessagesListScreen(state: state, model: model, navigationControl: navigationControl)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .shellNavigationControl(navigationControl)
            }
        }
    }
}

private struct MessagesListScreen: View {
    @ObservedObject var state: RequestsState
    @ObservedObject var model: MessagesListViewModel
    let navigationControl: ShellNavigationControl
    @State private var isComposing = false

    var body: some View {
        VStack(spacing: 0) {
            ListScreenHeader(searchText: $model.searchText, searchPrompt: "Search messages")
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BFColor.surfaceCanvas)
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isComposing = true } label: {
                    Label("New message", systemImage: "square.and.pencil")
                }
                .help("New message")
                .bfPointerHover()
                .accessibilityIdentifier("messages.newMessage")
            }
        }
        .shellNavigationControl(navigationControl)
        .navigationDestination(for: RQConversation.self) { conversation in
            MessageThreadScreen(model: model.makeConversationModel(for: conversation))
        }
        .task { await model.loadIfNeeded() }
        .refreshable { await model.load() }
        .sheet(isPresented: $isComposing) {
            if let newModel = state.makeNewConversationModel() {
                NewConversationView(model: newModel) {
                    Task { await model.load() }
                }
            }
        }
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

// MARK: - New Conversation

/// Owns its view model (`@StateObject`), like NewChangeRequestView, so re-running the
/// sheet's content closure doesn't wipe what was typed.
private struct NewConversationView: View {
    @StateObject private var model: NewConversationViewModel
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(model: NewConversationViewModel, onCreated: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model)
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("To") {
                    ForEach(model.recipients) { user in
                        HStack(spacing: BFSpacing._3) {
                            RQAvatar(urlString: user.profileImage, size: 24)
                            Text(user.name).font(RQFont.body)
                            Spacer()
                            Button { model.remove(user) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(user.name)")
                        }
                    }
                    TextField("Search people", text: $model.searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if model.isSearching && model.matches.isEmpty {
                        ProgressView()
                    }
                    ForEach(model.matches) { user in
                        Button { model.add(user) } label: {
                            HStack(spacing: BFSpacing._3) {
                                RQAvatar(urlString: user.profileImage, size: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name).font(RQFont.body).foregroundStyle(.primary)
                                    if !user.email.isEmpty {
                                        Text(user.email).font(RQFont.meta).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    TextField("Topic (optional)", text: $model.topic)
                } footer: {
                    Text("Add #123 to link change request 123.")
                }

                Section("Message") {
                    TextField("Write a message", text: $model.message, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let error = model.error {
                    Section { Text(error).foregroundStyle(.red).font(RQFont.meta) }
                }
            }
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await model.send() != nil {
                                onCreated()
                                dismiss()
                            }
                        }
                    } label: {
                        if model.isSending { ProgressView() } else { Text("Send") }
                    }
                    .disabled(!model.canSend)
                }
            }
            // Debounced: a fresh search 300 ms after typing stops (and once on open).
            .task(id: model.searchText) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await model.search()
            }
        }
    }
}

// MARK: - Conversation

private struct MessageThreadScreen: View {
    @StateObject private var model: ConversationViewModel
    @State private var showFileImporter = false
    @State private var openError: String?

    init(model: ConversationViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    /// While the conversation is open, new messages are picked up this often (the web app
    /// streams them; polling keeps this screen simple).
    private static let refreshInterval: Duration = .seconds(10)

    /// Same reading column as the AI chat (ChatView.maxChatWidth), so a wide Mac window
    /// doesn't push bubbles to its far edges.
    private static let columnWidth: CGFloat = 800

    private var others: [RQParticipant] { model.conversation.others(excluding: model.currentUserId) }

    private var title: String {
        if !model.conversation.topic.isEmpty { return model.conversation.topic }
        let names = others.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? "Conversation" : names.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            messageList
            composer
        }
        .background(BFColor.surfaceCanvas)
        .navigationTitle(title)
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

    /// Who the conversation is with; the inline navigation title alone is easy to miss
    /// (and Mac Catalyst hides window titles).
    private var header: some View {
        HStack(spacing: BFSpacing._3) {
            RQAvatar(urlString: others.first?.profileImage, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RQFont.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                let names = others.map(\.name).filter { !$0.isEmpty }
                if !names.isEmpty, !model.conversation.topic.isEmpty {
                    Text(names.joined(separator: ", "))
                        .font(RQFont.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.vertical, BFSpacing._3)
        .frame(maxWidth: Self.columnWidth)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { BFHairline() }
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
                        MessageBubble(message: message, isMine: model.isMine(message)) { attachment in
                            open(attachment)
                        }
                        .id(message.id)
                    }
                }
                .padding(BFSpacing._4)
                .frame(maxWidth: Self.columnWidth)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.messages.last?.id) { _, lastId in
                guard let lastId else { return }
                withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
            }
        }
    }

    private func open(_ attachment: RQAttachment) {
        Task {
            do {
                let file = try await model.download(attachment)
                await ShareSheetPresenter.present(data: file.data, fileName: file.fileName)
            } catch {
                openError = error.localizedDescription
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: BFSpacing._2) {
            if !model.pendingAttachments.isEmpty || model.isUploadingAttachment {
                pendingChips
            }
            composerRow
        }
        .padding(BFSpacing._3)
        .frame(maxWidth: Self.columnWidth)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { BFHairline() }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            Task {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                await model.attach(fileURL: url)
            }
        }
        .alert("Couldn't open that attachment", isPresented: .constant(openError != nil)) {
            Button("OK") { openError = nil }
        } message: {
            Text(openError ?? "")
        }
    }

    private var pendingChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BFSpacing._2) {
                ForEach(model.pendingAttachments) { attachment in
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                        Text(attachment.fileName).lineLimit(1)
                        Button {
                            model.removePending(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(attachment.fileName)")
                    }
                    .font(RQFont.meta)
                    .padding(.horizontal, BFSpacing._2)
                    .padding(.vertical, 4)
                    .background(BFColor.surfaceSunken, in: Capsule())
                }
                if model.isUploadingAttachment {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: BFSpacing._2) {
            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!model.canAttach)
            .accessibilityLabel("Attach a file")
            .accessibilityIdentifier("requests.message.attach")
            .bfPointerHover()
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
    }
}

private struct MessageBubble: View {
    let message: RQMessage
    let isMine: Bool
    let onOpen: (RQAttachment) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: BFSpacing._2) {
            if isMine { Spacer(minLength: 48) } else {
                RQAvatar(urlString: message.sender?.profileImage, size: 24)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if !isMine, let name = message.sender?.name, !name.isEmpty {
                    Text(name).font(RQFont.meta).foregroundStyle(.secondary)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(RQFont.body)
                        .foregroundStyle(isMine ? Color.white : Color.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, BFSpacing._3)
                        .padding(.vertical, BFSpacing._2)
                        .background(isMine ? BFColor.primary : BFColor.surfaceSunken,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        // Long messages wrap at a readable width, as the AI chat's bubbles do.
                        .frame(maxWidth: 560, alignment: isMine ? .trailing : .leading)
                }
                ForEach(message.attachments) { attachment in
                    Button {
                        onOpen(attachment)
                    } label: {
                        Label(attachment.fileName, systemImage: "paperclip")
                            .font(RQFont.meta)
                            .lineLimit(1)
                            .padding(.horizontal, BFSpacing._3)
                            .padding(.vertical, 6)
                            .background(BFColor.surfaceSunken, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("requests.message.attachment")
                    .bfPointerHover()
                }
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
