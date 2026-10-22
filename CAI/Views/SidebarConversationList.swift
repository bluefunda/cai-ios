import SwiftUI

// The sidebar's search field and conversation list, shared by both sidebars — SidebarContent
// (iPad/Mac split view) and SidebarDrawer (iPhone overlay drawer), which only differ in what
// happens around selecting a chat (`onSelect`).
//
// - Pinned chats in their own section on top, then Today / Yesterday / This Week / Older
//   (cai-ios#335). Pin and unpin from the row's context menu.
// - The list is paged: the next page loads as the end of the list scrolls into view
//   (cai-ios#370).
// - Typing searches chat titles and message text on the server, a moment after typing stops,
//   with results paged the same way (cai-ios#370).

/// Search runs once the query has this many characters — the server returns nothing for less.
private let minSearchLength = 2

struct SidebarConversationList: View {
    @EnvironmentObject var chatManager: ChatManager
    let onSelect: (Conversation) -> Void

    @State private var searchText = ""
    @State private var search = SearchState()

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
                emptyState("No conversations yet")
            } else {
                conversationList
            }
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

    private var conversationList: some View {
        // The rows are an equatable snapshot: ChatManager publishes on every streamed chunk, and
        // rebuilding each row then (fonts, context menus) held the main thread ~200ms at a time
        // on the Mac — the stalls in the answer's reveal. Now the rows only redraw when a title,
        // a pin, the selection or the paging state actually changes.
        ScrollView {
            SidebarConversationRows(
                rows: chatManager.conversations.map(SidebarRowItem.init),
                selectedId: chatManager.currentConversation?.id,
                hasMorePages: chatManager.chatListNextCursor != nil,
                actions: SidebarRowActions(
                    select: { id in
                        if let convo = chatManager.conversations.first(where: { $0.id == id }) { onSelect(convo) }
                    },
                    setPinned: { id, pinned in
                        if let convo = chatManager.conversations.first(where: { $0.id == id }) {
                            chatManager.setPinned(convo, pinned)
                        }
                    },
                    markdownExport: { id in
                        chatManager.conversations.first(where: { $0.id == id })?.markdownExport ?? ""
                    },
                    delete: { id in
                        if let convo = chatManager.conversations.first(where: { $0.id == id }) {
                            chatManager.deleteConversation(convo)
                        }
                    },
                    loadMore: { Task { await chatManager.loadMoreChats() } }
                )
            )
            .equatable()
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResults: some View {
        if search.results.isEmpty {
            if search.failed {
                VStack(spacing: 10) {
                    emptyStateContent("Couldn't search right now")
                    Button("Try Again") {
                        Task { await runSearch(trimmedQuery, cursor: nil) }
                    }
                    .font(BFFont.sidebarItem)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if search.isLoading || search.query != trimmedQuery {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState("No results")
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

    private func emptyState(_ text: String) -> some View {
        emptyStateContent(text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

// MARK: - Conversation rows

/// What a sidebar row shows — compared by value, unlike Conversation (whose == compares only id).
struct SidebarRowItem: Identifiable, Equatable {
    let id: String
    let title: String
    let isPinned: Bool
    let createdAt: Date

    init(_ conversation: Conversation) {
        id = conversation.id
        title = conversation.title
        isPinned = conversation.isPinned
        createdAt = conversation.createdAt
    }
}

/// The row actions, kept out of SidebarConversationRows' == so new closures each render don't
/// count as a change.
struct SidebarRowActions {
    let select: (String) -> Void
    let setPinned: (String, Bool) -> Void
    let markdownExport: (String) -> String
    let delete: (String) -> Void
    let loadMore: () -> Void
}

private struct SidebarConversationRows: View, Equatable {
    let rows: [SidebarRowItem]
    let selectedId: String?
    let hasMorePages: Bool
    let actions: SidebarRowActions

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rows == rhs.rows && lhs.selectedId == rhs.selectedId && lhs.hasMorePages == rhs.hasMorePages
    }

    var body: some View {
        LazyVStack(spacing: 2) {
            let pinned = rows.filter(\.isPinned)
            if !pinned.isEmpty {
                sectionHeader("Pinned")
                ForEach(pinned) { row(for: $0) }
            }

            ForEach(groupedRows(rows.filter { !$0.isPinned }), id: \.title) { group in
                sectionHeader(group.title)
                ForEach(group.rows) { row(for: $0) }
            }

            if hasMorePages {
                // Coming into view near the end of the list loads the next page.
                ProgressView()
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .onAppear { actions.loadMore() }
            }
        }
        .padding(.horizontal, 8)
    }

    private func row(for item: SidebarRowItem) -> some View {
        SidebarConversationRow(
            title: item.title,
            isSelected: selectedId == item.id,
            isPinned: item.isPinned,
            onTogglePin: { actions.setPinned(item.id, !item.isPinned) }
        )
        .onTapGesture { actions.select(item.id) }
        .bfPointerHover()
        .accessibilityIdentifier("conversationRow")
        .contextMenu {
            Button {
                actions.setPinned(item.id, !item.isPinned)
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            ShareLink(item: actions.markdownExport(item.id)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                actions.delete(item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(BFFont.sidebarSection)
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    /// Groups by recency of creation, in list order.
    private func groupedRows(_ rows: [SidebarRowItem]) -> [(title: String, rows: [SidebarRowItem])] {
        let now = Date()
        let cal = Calendar.current

        var today: [SidebarRowItem] = []
        var yesterday: [SidebarRowItem] = []
        var thisWeek: [SidebarRowItem] = []
        var older: [SidebarRowItem] = []

        for row in rows {
            switch cal.dateComponents([.day], from: row.createdAt, to: now).day ?? 0 {
            case ...0: today.append(row)
            case 1: yesterday.append(row)
            case 2..<7: thisWeek.append(row)
            default: older.append(row)
            }
        }

        return [("Today", today), ("Yesterday", yesterday), ("This Week", thisWeek), ("Older", older)]
            .filter { !$0.1.isEmpty }
            .map { (title: $0.0, rows: $0.1) }
    }
}
