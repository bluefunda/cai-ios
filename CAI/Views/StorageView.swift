import SwiftUI
import UniformTypeIdentifiers

// MARK: - Storage View

struct StorageView: View {
    @EnvironmentObject var chatManager: ChatManager
    @StateObject private var viewModel = StorageViewModel()

    @State private var showCreateFolder = false
    @State private var newFolderName = ""
    @State private var showFileImporter = false
    @State private var itemToDelete: StorageItem?

    var body: some View {
        NavigationStack {
            ZStack {
                mainContent

                // Full-screen upload overlay
                if viewModel.isUploading {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Uploading…")
                            .foregroundStyle(.white)
                            .font(.subheadline)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle("Cloud Storage")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Search files")
            .toolbar { toolbarContent }
            .alert("New Folder", isPresented: $showCreateFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Create") { createFolder() }
                Button("Cancel", role: .cancel) { newFolderName = "" }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
            .confirmationDialog(
                "Delete \"\(itemToDelete?.name ?? "")\"?",
                isPresented: .init(
                    get: { itemToDelete != nil },
                    set: { if !$0 { itemToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let item = itemToDelete else { return }
                    itemToDelete = nil
                    Task { try? await viewModel.deleteItem(item) }
                }
                Button("Cancel", role: .cancel) { itemToDelete = nil }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
        .onAppear {
            guard !viewModel.isBound, let api = chatManager.apiService else { return }
            viewModel.bind(apiService: api)
            Task { await viewModel.load() }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                // Stats header
                if let stats = viewModel.stats {
                    Section {
                        StorageStatsRow(stats: stats)
                    }
                    .listRowBackground(Color.clear)
                }

                // Breadcrumb navigation
                if !viewModel.breadcrumbs.isEmpty {
                    Section {
                        BreadcrumbBar(
                            breadcrumbs: viewModel.breadcrumbs,
                            onRoot: { Task { await viewModel.navigateToRoot() } },
                            onNavigate: { idx in Task { await viewModel.navigateTo(index: idx) } }
                        )
                    }
                    .listRowBackground(Color.clear)
                }

                // Folders
                if !viewModel.folders.isEmpty {
                    Section("Folders") {
                        ForEach(viewModel.folders) { folder in
                            FolderRow(folder: folder)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await viewModel.enterFolder(folder.name) }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        itemToDelete = folder
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                // Files
                if !viewModel.files.isEmpty {
                    Section("Files") {
                        ForEach(viewModel.files) { file in
                            FileRow(file: file) {
                                Task {
                                    if let url = await viewModel.downloadURL(for: file) {
                                        await UIApplication.shared.open(url)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    itemToDelete = file
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                // Empty state
                if viewModel.filteredItems.isEmpty && !viewModel.isLoading {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: viewModel.searchText.isEmpty ? "folder" : "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text(viewModel.searchText.isEmpty ? "This folder is empty" : "No results for \"\(viewModel.searchText)\"")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await viewModel.load() }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showCreateFolder = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }

                Button {
                    showFileImporter = true
                } label: {
                    Label("Upload File", systemImage: "arrow.up.doc")
                }
            } label: {
                Image(systemName: "plus")
            }
            .disabled(!viewModel.isBound || viewModel.isUploading)
        }
    }

    // MARK: - Actions

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        Task { try? await viewModel.createFolder(name: name) }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { return }
                let filename = url.lastPathComponent
                let mime = mimeType(for: url.pathExtension)
                try? await viewModel.upload(data: data, filename: filename, mimeType: mime)
            }
        case .failure(let err):
            viewModel.error = err.localizedDescription
        }
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "pdf":         return "application/pdf"
        case "txt":         return "text/plain"
        case "csv":         return "text/csv"
        case "json":        return "application/json"
        case "zip":         return "application/zip"
        default:            return "application/octet-stream"
        }
    }
}

// MARK: - Storage Stats Row

private struct StorageStatsRow: View {
    let stats: StorageStatsDTO

    private var formattedTotal: String {
        guard let size = stats.totalSize else { return "—" }
        let b = Double(size)
        if b < 1_048_576      { return String(format: "%.1f KB", b / 1_024) }
        if b < 1_073_741_824  { return String(format: "%.1f MB", b / 1_048_576) }
        return String(format: "%.2f GB", b / 1_073_741_824)
    }

    var body: some View {
        HStack {
            Label("\(stats.fileCount ?? 0) files", systemImage: "doc.on.doc")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formattedTotal)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Breadcrumb Bar

private struct BreadcrumbBar: View {
    let breadcrumbs: [String]
    let onRoot: () -> Void
    let onNavigate: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(action: onRoot) {
                    Image(systemName: "house.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { idx, crumb in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if idx < breadcrumbs.count - 1 {
                        Button(crumb) { onNavigate(idx) }
                            .font(.caption)
                            .foregroundStyle(.blue)
                    } else {
                        Text(crumb)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Folder Row

private struct FolderRow: View {
    let folder: StorageItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            Text(folder.name)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - File Row

private struct FileRow: View {
    let file: StorageItem
    let onDownload: () -> Void

    var body: some View {
        Button(action: onDownload) {
            HStack(spacing: 12) {
                Image(systemName: file.systemIcon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(file.formattedSize)

                        if let date = file.lastModified {
                            Text("·")
                            Text(date.prefix(10))  // YYYY-MM-DD
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.down.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    StorageView()
        .environmentObject(ChatManager(service: BFFChatService()))
}
