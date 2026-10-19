import SwiftUI

// The sidebar's search field and conversation list — the Chats destination's context list
// in SidebarView (layer 3b), on every platform. The split-view column and the iPhone drawer
// only differ in what happens around selecting a chat (`onSelect`) and in row actions.
//
// - Pinned chats in their own section on top, then Today / Yesterday / This week / Older
//   (cai-ios#335). Pin and unpin from the row's context menu, its hover `···` menu
//   (pointer), or a swipe (iPhone drawer).
// - The list is paged: the next page loads as the end of the list scrolls into view
//   (cai-ios#370).
// - Typing searches chat titles and message text on the server, a moment after typing stops,
//   with results paged the same way (cai-ios#370).

/// Search runs once the query has this many characters — the server returns nothing for less.
private let minSearchLength = 2

struct SidebarConversationList: View {
    @EnvironmentObject var chatManager: ChatManager
    /// iPhone drawer: rows swipe to pin (leading) and delete (trailing). Swipe actions
    /// only exist inside a List, so this switches the container; the split-view column
    /// keeps its ScrollView and offers the hover `···` menu instead.
    var allowsSwipeActions = false
    /// Bound to the search field so ⌘F can focus it from anywhere in the shell.
    var searchFocus: FocusState<Bool>.Binding
    /// The empty state's "Start a chat" action.
    var onStartChat: (() -> Void)?
    let onSelect: (Conversation) -> Void

    @State private var searchText = ""
    @State private var search = SearchState()
    /// Every delete path (swipe, hover menu, context menu) asks first (P4).
    @State private var pendingDelete: Conversation?

    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { trimmedQuery.count >= minSearchLength }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if isSearching {
                searchResults
            } else if chatManager.isLoadingChats && chatManager.conversations.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chatManager.conversations.isEmpty {
                VStack(spacing: 10) {
                    emptyStateContent("No conversations yet")
                    if let onStartChat {
                        Button("Start a chat", action: onStartChat)
                            .font(BFFont.sidebarItemMed)
                            .foregroundStyle(BFColor.primary)
                            .bfPointerHover()
                            .accessibilityIdentifier("sidebar.startChat")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                conversationList
            }
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { convo in
            Button("Delete", role: .destructive) {
                chatManager.deleteConversation(convo)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { convo in
            Text("\u{201C}\(convo.title)\u{201D} and its messages will be deleted.")
        }
        // Restarts on every keystroke; the sleep makes it wait for a pause in typing, and a
        // newer query cancels the older one's request.
        .task(id: trimmedQuery) {
            guard isSearching else {
                search = SearchState()
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await runSearch(trimmedQuery, cursor: nil)
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search conversations", text: $searchText)
                .font(BFFont.sidebarItem)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused(searchFocus)
                .accessibilityIdentifier("sidebar.search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BFColor.surfaceSunken, in: Capsule())
        .overlay(Capsule().strokeBorder(BFColor.hairline, lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Conversation list

    @ViewBuilder
    private var conversationList: some View {
        if allowsSwipeActions {
            List {
                Group { listRows }
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) { listRows }
                    .padding(.horizontal, 8)
            }
        }
    }

    /// Shared by both containers; the List-only row modifiers above are no-ops in the
    /// LazyVStack.
    @ViewBuilder
    private var listRows: some View {
        let pinned = chatManager.conversations.filter(\.isPinned)
        if !pinned.isEmpty {
            SidebarSectionHeader(title: "Pinned")
            ForEach(pinned) { row(for: $0) }
        }

        ForEach(groupedConversations(chatManager.conversations.filter { !$0.isPinned })) { group in
            SidebarSectionHeader(title: group.title)
            ForEach(group.conversations) { row(for: $0) }
        }

        if chatManager.chatListNextCursor != nil {
            // Coming into view near the end of the list loads the next page.
            ProgressView()
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .onAppear { Task { await chatManager.loadMoreChats() } }
        }
    }

    private func row(for convo: Conversation) -> some View {
        SidebarConversationRow(
            title: convo.title,
            meta: convo.createdAt.formatted(.relative(presentation: .named)),
            isSelected: chatManager.currentConversation?.id == convo.id,
            isPinned: convo.isPinned,
            hoverMenuRows: [
                BFDropdownRow(
                    convo.isPinned ? "Unpin" : "Pin",
                    systemImage: convo.isPinned ? "pin.slash" : "pin"
                ) { chatManager.setPinned(convo, !convo.isPinned) },
                BFDropdownRow("Delete", systemImage: "trash", role: .destructive) {
                    pendingDelete = convo
                }
            ]
        )
        .onTapGesture { onSelect(convo) }
        .bfPointerHover()
        .accessibilityIdentifier("conversationRow")
        .contextMenu {
            Button {
                chatManager.setPinned(convo, !convo.isPinned)
            } label: {
                Label(convo.isPinned ? "Unpin" : "Pin", systemImage: convo.isPinned ? "pin.slash" : "pin")
            }
            ShareLink(item: convo.markdownExport) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                pendingDelete = convo
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                chatManager.setPinned(convo, !convo.isPinned)
            } label: {
                Label(convo.isPinned ? "Unpin" : "Pin", systemImage: convo.isPinned ? "pin.slash" : "pin")
            }
            .tint(BFColor.secondaryAdaptive)
        }
        // Not `role: .destructive` — that animates the row away before the
        // confirmation has been answered.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                pendingDelete = convo
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    /// Groups by recency of creation, in list order.
    private func groupedConversations(_ conversations: [Conversation]) -> [ConversationGroup] {
        let now = Date()
        let cal = Calendar.current

        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var thisWeek: [Conversation] = []
        var older: [Conversation] = []

        for conversation in conversations {
            switch cal.dateComponents([.day], from: conversation.createdAt, to: now).day ?? 0 {
            case ...0: today.append(conversation)
            case 1: yesterday.append(conversation)
            case 2..<7: thisWeek.append(conversation)
            default: older.append(conversation)
            }
        }

        return [("Today", today), ("Yesterday", yesterday), ("This week", thisWeek), ("Older", older)]
            .filter { !$0.1.isEmpty }
            .map { ConversationGroup(title: $0.0, conversations: $0.1) }
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResults: some View {
        if search.results.isEmpty {
            if search.failed {
                VStack(spacing: 10) {
                    emptyStateContent("Couldn't search right now")
                    Button("Try again") {
                        Task { await runSearch(trimmedQuery, cursor: nil) }
                    }
                    .font(BFFont.sidebarItem)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if search.isLoading || search.query != trimmedQuery {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    emptyStateContent("No chats match \u{201C}\(trimmedQuery)\u{201D}")
                    Button("Clear search") { searchText = "" }
                        .font(BFFont.sidebarItem)
                        .foregroundStyle(BFColor.primary)
                        .bfPointerHover()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(search.results) { result in
                        SidebarSearchResultRow(
                            result: result,
                            isSelected: chatManager.currentConversation?.id == result.id
                        )
                        .onTapGesture { onSelect(chatManager.conversation(forSearchResult: result)) }
                        .bfPointerHover()
                        .accessibilityIdentifier("searchResultRow")
                    }

                    if let cursor = search.nextCursor {
                        ProgressView()
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .onAppear { Task { await runSearch(search.query, cursor: cursor) } }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    /// Runs a search, or loads its next page when `cursor` is set. Results for a query the user
    /// has since changed are dropped.
    private func runSearch(_ query: String, cursor: String?) async {
        if cursor == nil {
            search = SearchState(query: query, isLoading: true)
        } else {
            guard !search.isLoading, search.query == query else { return }
            search.isLoading = true
        }
        do {
            let page = try await chatManager.searchChats(query: query, cursor: cursor)
            guard search.query == query else { return }
            let known = Set(search.results.map(\.id))
            search.results += page.results.filter { !known.contains($0.id) }
            search.nextCursor = page.nextCursor.flatMap { $0.isEmpty ? nil : $0 }
            search.failed = false
        } catch {
            guard search.query == query, !(error is CancellationError) else { return }
            print("[Sidebar] search error: \(error)")
            // A failed first page shows the error; a failed later page just stops paging.
            if cursor == nil { search.failed = true }
            search.nextCursor = nil
        }
        search.isLoading = false
    }

    // MARK: - Empty states

    private func emptyStateContent(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(BFFont.sidebarItem)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Search results for one query, and how far they're loaded.
private struct SearchState {
    var query = ""
    var results: [ChatSearchResultDTO] = []
    var nextCursor: String?
    var isLoading = false
    var failed = false
}

// MARK: - Search result row

/// A chat found by search: its title, the matching text, and when the chat was last active.
struct SidebarSearchResultRow: View {
    let result: ChatSearchResultDTO
    let isSelected: Bool

    @State private var isHovered = false

    private var background: Color {
        if isSelected { return BFColor.primary.opacity(0.15) }
        if isHovered { return BFColor.rowHover }
        return .clear
    }

    private var date: String? {
        guard let date = result.lastUpdatedAt.flatMap(Date.fromISO8601) else { return nil }
        return date.formatted(.relative(presentation: .named))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(result.title ?? "Chat")
                    .font(isSelected ? BFFont.sidebarItemMed : BFFont.sidebarItem)
                    .foregroundStyle(isSelected ? BFColor.primary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if result.pinned == true {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(45))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .accessibilityLabel("Pinned")
                }
                if let date {
                    Text(date)
                        .font(BFFont.sidebarMeta)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            // A title match's snippet is the title itself — no need to show it twice.
            if result.matchedIn != "title" {
                Text(result.snippet)
                    .font(BFFont.sidebarMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous))
        .contentShape(Rectangle())
        .animation(BFMotion.easingDefault, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
