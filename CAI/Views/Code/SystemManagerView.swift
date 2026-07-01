import SwiftUI

// MARK: - System Manager

struct SystemManagerView: View {
    @ObservedObject var store: SAPSystemStore
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd = false
    @State private var editing: SAPSystem?
    @State private var testTarget: SAPSystem?
    @State private var testResult: String?
    @State private var testing = false

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
                            systemRow(system)
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
            .alert(
                "Test Connection — \(testTarget?.name ?? "")",
                isPresented: Binding(get: { testTarget != nil }, set: { if !$0 { testTarget = nil; testResult = nil } })
            ) {
                Button("OK", role: .cancel) { testTarget = nil; testResult = nil }
            } message: {
                if testing {
                    Text("Testing connection…")
                } else {
                    Text(testResult ?? "")
                }
            }
        }
    }

    @ViewBuilder
    private func systemRow(_ system: SAPSystem) -> some View {
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
        .contentShape(Rectangle())
        .onTapGesture {
            store.activeSystemID = system.id
        }
        // iOS: swipe actions
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
            Button {
                beginTest(system)
            } label: {
                Label("Test", systemImage: "bolt.horizontal.circle")
            }
            .tint(.orange)
        }
        // macOS + iOS long-press: context menu
        .contextMenu {
            if store.activeSystemID != system.id {
                Button {
                    store.activeSystemID = system.id
                } label: {
                    Label("Set Active", systemImage: "checkmark.circle")
                }
                Divider()
            }
            Button {
                editing = system
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                beginTest(system)
            } label: {
                Label("Test Connection", systemImage: "bolt.horizontal.circle")
            }
            Divider()
            Button(role: .destructive) {
                store.delete(system)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func beginTest(_ system: SAPSystem) {
        testTarget = system
        testResult = nil
        testing = true
        let api = CodeAPIService.make(authManager: authManager, system: system)
        Task {
            do {
                let result = try await api.testConnection()
                if result.authenticated == true || result.status?.lowercased() == "connected" {
                    testResult = "✓ Connected to \(system.name)"
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
    @EnvironmentObject var authManager: AuthManager
    let onSave: (SAPSystem) -> Void

    private let editingID: UUID?
    @State private var name: String
    @State private var host: String
    @State private var client: String
    @State private var username: String
    @State private var password: String
    @State private var testing = false
    @State private var testResult: String?

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

    private var draft: SAPSystem {
        SAPSystem(
            id: editingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            client: client.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces),
            password: password
        )
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
                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "bolt.horizontal.circle")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(!isValid || testing)

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.hasPrefix("✓") ? .green : .secondary)
                    }
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
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func testConnection() {
        testing = true
        testResult = nil
        let api = CodeAPIService.make(authManager: authManager, system: draft)
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
