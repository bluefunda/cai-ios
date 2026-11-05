import SwiftUI

// MARK: - Admin scaffolding
// Shared by the admin destinations (User Management, Request Templates, Manage Teams,
// Configurations) and Git. Each owns its own state: unlike the main lists, nothing else
// in the shell reads it, so it doesn't live in RequestsState.

/// One fetched list, with the load/error flags the screens render from.
@MainActor
final class AdminLoader<Item>: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var error: String?

    private var task: Task<Void, Never>?

    /// Cancels an older load so a slow, stale response can't overwrite a newer one.
    func load(_ fetch: @escaping () async throws -> [Item]) async {
        task?.cancel()
        let current = Task { @MainActor in
            isLoading = true
            error = nil
            do {
                let result = try await fetch()
                guard !Task.isCancelled else { return }
                items = result
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isLoading = false
            hasLoaded = true
        }
        task = current
        await current.value
    }
}

/// The admin service and signed-in user id, once RequestsState has them.
struct AdminContext {
    let service: AdminServicing
    let userId: String
}

/// A destination's NavigationStack, waiting for RequestsState to be configured.
struct AdminDestination<Content: View>: View {
    @ObservedObject var state: RequestsState
    let navigationControl: ShellNavigationControl
    @ViewBuilder let content: (AdminContext) -> Content

    var body: some View {
        NavigationStack {
            Group {
                if let services = state.services, let userId = state.currentUserId {
                    content(AdminContext(service: services.adminService, userId: userId))
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .shellNavigationControl(navigationControl)
        }
    }
}

/// Loading, error, empty or the list itself — the same states the other Requests lists show.
struct AdminListContent<Item, Rows: View>: View {
    @ObservedObject var loader: AdminLoader<Item>
    let subject: String
    let emptyTitle: String
    let emptyIcon: String
    var isFiltered = false
    let reload: () async -> Void
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        if loader.isLoading && loader.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loader.error, loader.items.isEmpty {
            RequestsErrorCard(message: RequestsErrorCard.message(for: error, subject: subject)) {
                Task { await reload() }
            }
        } else if loader.items.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: emptyIcon)
        } else {
            List {
                if let error = loader.error {
                    InlineErrorBanner(message: error) { Task { await reload() } }
                        .listRowSeparator(.hidden)
                }
                rows()
                    .listRowBackground(BFColor.surfaceCanvas)
                    .listRowSeparatorTint(BFColor.hairline)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // A readable column on a wide Mac or iPad window rather than rows spread edge
            // to edge; no effect on an iPhone.
            .frame(maxWidth: AdminLayout.columnWidth)
            .frame(maxWidth: .infinity)
        }
    }
}

enum AdminLayout {
    static let columnWidth: CGFloat = 760
}

extension View {
    /// An admin screen's content as one centred, readable column (header and list together).
    func adminColumn() -> some View {
        frame(maxWidth: AdminLayout.columnWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(BFColor.surfaceCanvas)
    }
}

/// The top of an admin screen, inside its column: the title and a count, the screen's main
/// action, then search and any extra control (User Management's Active/Inactive). Replaces
/// the toolbar "+" and a search field spread to the window's corners on a Mac.
struct AdminScreenHeader<Extra: View>: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var actionIcon = "plus"
    var actionIdentifier: String?
    var isBusy = false
    var action: (() -> Void)?
    var search: Binding<String>?
    var searchPrompt = "Search"
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: BFSpacing._3) {
            HStack(alignment: .center, spacing: BFSpacing._3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(RQFont.meta)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: BFSpacing._3)
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                if let actionTitle, let action {
                    Button(action: action) {
                        Label(actionTitle, systemImage: actionIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                    .bfPointerHover()
                    .accessibilityIdentifier(actionIdentifier ?? "admin.header.action")
                }
            }
            if search != nil || Extra.self != EmptyView.self {
                HStack(spacing: BFSpacing._3) {
                    if let search {
                        AdminSearchField(text: search, prompt: searchPrompt)
                    }
                    extra()
                }
            }
        }
        .padding(.horizontal, BFSpacing._4)
        .padding(.top, BFSpacing._4)
        .padding(.bottom, BFSpacing._3)
    }
}

extension AdminScreenHeader where Extra == EmptyView {
    init(title: String, subtitle: String? = nil, actionTitle: String? = nil, actionIcon: String = "plus",
         actionIdentifier: String? = nil, isBusy: Bool = false, action: (() -> Void)? = nil,
         search: Binding<String>? = nil, searchPrompt: String = "Search") {
        self.init(title: title, subtitle: subtitle, actionTitle: actionTitle, actionIcon: actionIcon,
                  actionIdentifier: actionIdentifier, isBusy: isBusy, action: action, search: search,
                  searchPrompt: searchPrompt, extra: { EmptyView() })
    }
}

/// A count for the header ("1 user", "3 users"); nil until something has loaded.
func adminCount(_ count: Int, _ noun: String, loaded: Bool) -> String? {
    guard loaded else { return nil }
    return count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
}

struct AdminSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: BFSpacing._2) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, BFSpacing._3)
        .padding(.vertical, BFSpacing._2)
        .background(BFColor.surfaceSunken, in: RoundedRectangle(cornerRadius: BFRadius.row, style: .continuous))
    }
}

/// A form sheet's Cancel/Save toolbar and the save-in-progress state.
struct AdminFormToolbar: ToolbarContent {
    let canSave: Bool
    let isSaving: Bool
    let save: () -> Void
    let cancel: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: cancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button("Save", action: save).disabled(!canSave)
            }
        }
    }
}

/// A small label/value row for detail screens.
struct AdminField: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

extension String {
    var trimmedValue: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
