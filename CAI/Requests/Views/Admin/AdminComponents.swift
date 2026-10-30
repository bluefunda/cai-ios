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
        }
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
