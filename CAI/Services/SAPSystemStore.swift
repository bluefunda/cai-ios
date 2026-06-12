import Foundation

// MARK: - SAP System Store
// Owns the list of registered SAP systems (persisted in the Keychain) and the
// currently active one (its id in UserDefaults).

@MainActor
final class SAPSystemStore: ObservableObject {
    @Published private(set) var systems: [SAPSystem] = []
    @Published var activeSystemID: UUID? {
        didSet {
            UserDefaults.standard.set(activeSystemID?.uuidString, forKey: Self.activeKey)
        }
    }

    private static let storeKey = "sap_systems"
    private static let activeKey = "sap_active_system_id"

    var activeSystem: SAPSystem? {
        guard let id = activeSystemID else { return nil }
        return systems.first { $0.id == id }
    }

    init() {
        systems = loadSystems()
        if let raw = UserDefaults.standard.string(forKey: Self.activeKey),
           let id = UUID(uuidString: raw),
           systems.contains(where: { $0.id == id }) {
            activeSystemID = id
        } else {
            activeSystemID = systems.first?.id
        }
    }

    // MARK: - CRUD

    func add(_ system: SAPSystem) {
        systems.append(system)
        persist()
        if activeSystemID == nil { activeSystemID = system.id }
    }

    func update(_ system: SAPSystem) {
        guard let idx = systems.firstIndex(where: { $0.id == system.id }) else { return }
        systems[idx] = system
        persist()
    }

    func delete(_ system: SAPSystem) {
        systems.removeAll { $0.id == system.id }
        if activeSystemID == system.id {
            activeSystemID = systems.first?.id
        }
        persist()
    }

    // MARK: - Persistence (Keychain)

    private func loadSystems() -> [SAPSystem] {
        guard let data = KeychainStore.load(Self.storeKey),
              let decoded = try? JSONDecoder().decode([SAPSystem].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(systems) else { return }
        KeychainStore.save(data, for: Self.storeKey)
    }
}
