import SwiftUI

// MARK: - Object Browser (root)

struct ObjectBrowserView: View {
    let api: CodeAPIService

    var body: some View {
        NavigationStack {
            BrowserList(api: api)
                .navigationDestination(for: ObjectRef.self) { ref in
                    SourceView(api: api, ref: ref)
                }
                .navigationDestination(for: PackageRef.self) { pkg in
                    PackageContentsView(api: api, packageName: pkg.name)
                }
        }
    }
}

// MARK: - Browser root list (favorites + search)

private struct BrowserList: View {
    let api: CodeAPIService

    @AppStorage("code_favorite_packages") private var favoritesRaw = ""
    @State private var searchText = ""
    @State private var results: [ADTObject] = []
    @State private var searching = false
    @State private var showAddPackage = false
    @State private var newPackage = ""

    private var favorites: [String] {
        favoritesRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        List {
            if !searchText.isEmpty {
                Section("Results") {
                    if searching {
                        HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                    } else if results.isEmpty {
                        Text("No objects found").foregroundStyle(.secondary)
                    } else {
                        ForEach(results) { obj in
                            NavigationLink(value: ObjectRef(objectType: obj.type, objectName: obj.name, description: obj.description)) {
                                ObjectRow(name: obj.name, type: obj.type, description: obj.description)
                            }
                        }
                    }
                }
            } else {
                Section("Favorite Packages") {
                    if favorites.isEmpty {
                        Text("Add a package to browse its objects.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(favorites, id: \.self) { pkg in
                            NavigationLink(value: PackageRef(name: pkg)) {
                                Label(pkg, systemImage: "folder.fill")
                                    .foregroundStyle(.primary)
                            }
                            .swipeActions {
                                Button(role: .destructive) { removeFavorite(pkg) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search objects (e.g. Z*)")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty { results = [] }
        }
        .navigationTitle("Repository")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddPackage = true } label: { Image(systemName: "folder.badge.plus") }
            }
        }
        .alert("Add Package", isPresented: $showAddPackage) {
            TextField("Package name", text: $newPackage)
            Button("Add") { addFavorite() }
            Button("Cancel", role: .cancel) { newPackage = "" }
        }
    }

    private func runSearch() async {
        let pattern = searchText.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return }
        searching = true
        defer { searching = false }
        results = (try? await api.searchObjects(pattern)) ?? []
    }

    private func addFavorite() {
        let name = newPackage.trimmingCharacters(in: .whitespaces).uppercased()
        newPackage = ""
        guard !name.isEmpty, !favorites.contains(name) else { return }
        favoritesRaw = (favorites + [name]).joined(separator: ",")
    }

    private func removeFavorite(_ pkg: String) {
        favoritesRaw = favorites.filter { $0 != pkg }.joined(separator: ",")
    }
}

// MARK: - Package contents (drill-down)

private struct PackageContentsView: View {
    let api: CodeAPIService
    let packageName: String

    @State private var nodes: [PackageNode] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if loading {
                HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            } else if let error {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if nodes.isEmpty {
                Text("Empty package").foregroundStyle(.secondary)
            } else {
                ForEach(nodes) { node in
                    if node.isPackage {
                        NavigationLink(value: PackageRef(name: node.name)) {
                            Label(node.name, systemImage: "folder.fill")
                        }
                    } else {
                        NavigationLink(value: ObjectRef(objectType: node.type, objectName: node.name, description: node.description)) {
                            ObjectRow(name: node.name, type: node.type, description: node.description)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(packageName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: packageName) { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            nodes = try await api.packageContents(packageName)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Object Row

private struct ObjectRow: View {
    let name: String
    let type: String
    let description: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                if let description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer()

            Text(type.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var icon: String {
        switch type.uppercased() {
        case let t where t.hasPrefix("PROG"): return "doc.plaintext"
        case let t where t.hasPrefix("CLAS"): return "shippingbox"
        case let t where t.hasPrefix("INTF"): return "circle.dashed"
        case let t where t.hasPrefix("FUGR"), let t where t.hasPrefix("FUNC"): return "square.stack.3d.up"
        case let t where t.hasPrefix("TABL"), let t where t.hasPrefix("STRU"): return "tablecells"
        case let t where t.hasPrefix("DDLS"): return "cylinder.split.1x2"
        default: return "doc"
        }
    }

    private var tint: Color {
        switch type.uppercased() {
        case let t where t.hasPrefix("PROG"): return .blue
        case let t where t.hasPrefix("CLAS"): return .purple
        case let t where t.hasPrefix("INTF"): return .teal
        case let t where t.hasPrefix("FUGR"), let t where t.hasPrefix("FUNC"): return .orange
        case let t where t.hasPrefix("TABL"), let t where t.hasPrefix("STRU"): return .green
        default: return .secondary
        }
    }
}
