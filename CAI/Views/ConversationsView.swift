import SwiftUI

struct ConversationsView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Binding var selectedTab: Int
    @State private var searchText = ""

    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return chatManager.conversations
        }
        return chatManager.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if chatManager.conversations.isEmpty {
                    EmptyHistoryView()
                } else {
                    List {
                        ForEach(filteredConversations) { conversation in
                            ConversationRow(conversation: conversation)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    chatManager.selectConversation(conversation)
                                    // Switch to Chat tab
                                    selectedTab = 0
                                }
                        }
                        .onDelete(perform: deleteConversations)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Conversations")
            .searchable(text: $searchText, prompt: "Search conversations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private func deleteConversations(at offsets: IndexSet) {
        for index in offsets {
            let conversation = filteredConversations[index]
            chatManager.deleteConversation(conversation)
        }
    }
}

// MARK: - Conversation Row

extension ConversationRow {
    func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateStyle = .none; f.timeStyle = .short
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let daysAgo = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        let f = DateFormatter()
        if daysAgo < 7 {
            f.dateFormat = "EEEE"          // "Monday"
        } else if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            f.dateFormat = "MMM d"         // "Jun 25"
        } else {
            f.dateFormat = "MMM d, yyyy"   // "Jun 25, 2024"
        }
        return f.string(from: date)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation
    @EnvironmentObject var chatManager: ChatManager

    var isSelected: Bool {
        chatManager.currentConversation?.id == conversation.id
    }

    var lastMessage: ChatMessage? {
        conversation.messages.last
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Circle()
                .fill(isSelected ? BFColor.primary : BFColor.neutral200)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundColor(isSelected ? BFColor.textInverse : BFColor.neutral500)
                }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)

                if let message = lastMessage {
                    Text(message.content)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text(formattedDate(conversation.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Checkmark if selected
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(BFColor.primary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isSelected ? BFColor.primary.opacity(0.15) : Color.clear)
    }
}

// MARK: - Empty History View

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Conversations Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your chat history will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ConversationsView(selectedTab: .constant(1))
        .environmentObject(ChatManager(service: BFFChatService()))
}
