import Foundation

// MARK: - Storage Item

struct StorageItem: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let isFolder: Bool
    let size: Int64?
    let lastModified: String?

    // Convenience init for locally-created items (new folder, etc.)
    init(key: String, name: String, isFolder: Bool, size: Int64? = nil, lastModified: String? = nil) {
        self.key = key
        self.name = name
        self.isFolder = isFolder
        self.size = size
        self.lastModified = lastModified
    }

    /// A listed entry: trm-s3 names it relative to the listed `prefix`, so its key is the
    /// prefix plus the name (a folder's ends in "/").
    init?(from dto: StorageObjectDTO, prefix: String, isFolder: Bool) {
        let name = dto.name.hasSuffix("/") ? String(dto.name.dropLast()) : dto.name
        guard !name.isEmpty, !name.contains("/") else { return nil }
        self.key = prefix + name + (isFolder ? "/" : "")
        self.name = name
        self.isFolder = isFolder
        self.size = isFolder ? nil : dto.size
        self.lastModified = dto.lastModified
    }

    var formattedSize: String {
        guard let size, !isFolder else { return "—" }
        let b = Double(size)
        if b < 1_024 { return "\(size) B" }
        if b < 1_048_576 { return String(format: "%.1f KB", b / 1_024) }
        return String(format: "%.1f MB", b / 1_048_576)
    }

    var systemIcon: String {
        if isFolder { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":               return "doc.richtext"
        case "jpg", "jpeg",
             "png", "gif",
             "heic", "webp":     return "photo"
        case "mp4", "mov",
             "avi", "mkv":       return "video"
        case "mp3", "wav",
             "aac", "m4a":       return "music.note"
        case "zip", "gz",
             "tar", "7z":        return "archivebox"
        case "swift":             return "chevron.left.forwardslash.chevron.right"
        case "json":              return "curlybraces"
        case "csv", "xls",
             "xlsx":              return "tablecells"
        default:                  return "doc.fill"
        }
    }
}

// MARK: - Storage View Model

@MainActor
final class StorageViewModel: ObservableObject {
    @Published var items: [StorageItem] = []
    @Published var breadcrumbs: [String] = []
    @Published var stats: StorageStatsDTO?
    @Published var isLoading = false
    @Published var isUploading = false
    @Published var error: String?
    @Published var searchText = ""

    private(set) var isBound = false
    private var apiService: BFFAPIService?

    /// The signed-in user's realm, as the web's Cloud Storage uses it.
    private(set) var bucket = ""

    // MARK: - Derived

    var currentPrefix: String {
        breadcrumbs.isEmpty ? "" : breadcrumbs.joined(separator: "/") + "/"
    }

    var filteredItems: [StorageItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var folders: [StorageItem] { filteredItems.filter(\.isFolder) }
    var files: [StorageItem] { filteredItems.filter { !$0.isFolder } }

    // MARK: - Binding

    func bind(apiService: BFFAPIService, bucket: String) {
        self.apiService = apiService
        self.bucket = bucket
        isBound = true
    }

    // MARK: - Load

    func load() async {
        guard let api = apiService else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let prefix = currentPrefix
            async let listTask  = api.listStorage(bucket: bucket, prefix: prefix)
            // The totals are a nicety; a failure there doesn't hide the files.
            async let statsTask = try? api.storageStats(bucket: bucket)
            let (listing, statsDTO) = try await (listTask, statsTask)

            let byName: (StorageItem, StorageItem) -> Bool = {
                $0.name.localizedCompare($1.name) == .orderedAscending
            }
            // Folders first, then files, each alphabetical.
            items = listing.folders.compactMap { StorageItem(from: $0, prefix: prefix, isFolder: true) }.sorted(by: byName)
                + listing.files.compactMap { StorageItem(from: $0, prefix: prefix, isFolder: false) }.sorted(by: byName)
            stats = statsDTO
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Navigation

    func enterFolder(_ name: String) async {
        breadcrumbs.append(name)
        items = []
        await load()
    }

    func navigateTo(index: Int) async {
        guard index < breadcrumbs.count else { return }
        breadcrumbs = Array(breadcrumbs.prefix(index + 1))
        items = []
        await load()
    }

    func navigateToRoot() async {
        breadcrumbs = []
        items = []
        await load()
    }

    // MARK: - CRUD

    func deleteItem(_ item: StorageItem) async throws {
        guard let api = apiService else { return }
        try await api.deleteStorageObject(bucket: bucket, key: item.key)
        items.removeAll { $0.key == item.key }
    }

    func createFolder(name: String) async throws {
        guard let api = apiService else { return }
        let folderKey = currentPrefix + name + "/"
        try await api.createFolder(bucket: bucket, folder: folderKey)
        let newItem = StorageItem(key: folderKey, name: name, isFolder: true)
        items.insert(newItem, at: 0)
    }

    func upload(data: Data, filename: String, mimeType: String) async throws {
        guard let api = apiService else { return }
        isUploading = true
        defer { isUploading = false }
        try await api.uploadFile(data: data, filename: filename, mimeType: mimeType, bucket: bucket, prefix: currentPrefix)
        await load()
    }

    // MARK: - Download

    func downloadURL(for item: StorageItem) async -> URL? {
        guard let api = apiService,
              let urlString = try? await api.getPresignedURL(bucket: bucket, key: item.key),
              let url = URL(string: urlString) else { return nil }
        return url
    }
}
