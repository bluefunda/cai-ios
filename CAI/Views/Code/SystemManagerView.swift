import SwiftUI

// MARK: - System Manager

struct SystemManagerView: View {
    @ObservedObject var store: SAPSystemStore
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd = false
    @State private var editing: SAPSystem?
    @State private var testing = false
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            List {
                if store.systems.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No SAP Systems",
                            systemImage: "server.rack",
                            description: Text("Add a SAP system to start working with ABAP.")
                        )
                    }
                } else {
                    Section("Systems") {
                        ForEach(store.systems) { system in
                            Button {
                                store.activeSystemID = system.id
                                testResult = nil
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(system.name).foregroundStyle(.primary)
                                        Text("\(system.displayHost) · client \(system.client) · \(system.username)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if store.activeSystemID == system.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.delete(system)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editing = system
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }

                    if let active = store.activeSystem {
                        Section {
                            Button {
                                testConnection(active)
                            } label: {
                                HStack {
                                    Label("Test Connection", systemImage: "bolt.horizontal.circle")
                                    Spacer()
                                    if testing { ProgressView() }
                                }
                            }
                            .disabled(testing)

                            if let result = testResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("Active — \(active.name)")
                        }
                    }
                }
            }
            .navigationTitle("SAP Systems")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddSystemView { store.add($0) }
            }
            .sheet(item: $editing) { system in
                AddSystemView(existing: system) { store.update($0) }
            }
        }
    }

    private func testConnection(_ system: SAPSystem) {
        testing = true
        testResult = nil
        let api = CodeAPIService.make(authManager: authManager, system: system)
        Task {
            do {
                let result = try await api.testConnection()
                if result.authenticated == true || result.status?.lowercased() == "connected" {
                    testResult = "✓ Connected"
                } else {
                    testResult = "Reached server: \(result.status ?? result.message ?? "unknown")"
                }
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
            testing = false
        }
    }
}

// MARK: - Add / Edit System

struct AddSystemView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (SAPSystem) -> Void

    private let editingID: UUID?
    @State private var name: String
    @State private var host: String
    @State private var client: String
    @State private var username: String
    @State private var password: String

    init(existing: SAPSystem? = nil, onSave: @escaping (SAPSystem) -> Void) {
        self.onSave = onSave
        self.editingID = existing?.id
        _name = State(initialValue: existing?.name ?? "")
        _host = State(initialValue: existing?.host ?? "")
        _client = State(initialValue: existing?.client ?? "100")
        _username = State(initialValue: existing?.username ?? "")
        _password = State(initialValue: existing?.password ?? "")
    }

    private var isValid: Bool {
        !name.isBlank && !host.isBlank && !client.isBlank && !username.isBlank && !password.isBlank
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("System") {
                    TextField("Name", text: $name)
                    TextField("Host (https://host:port)", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Client", text: $client)
                        .keyboardType(.numberPad)
                }
                Section("Credentials") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }
            }
            .navigationTitle(editingID == nil ? "Add System" : "Edit System")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let system = SAPSystem(
                            id: editingID ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            host: host.trimmingCharacters(in: .whitespaces),
                            client: client.trimmingCharacters(in: .whitespaces),
                            username: username.trimmingCharacters(in: .whitespaces),
                            password: password
                        )
                        onSave(system)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
