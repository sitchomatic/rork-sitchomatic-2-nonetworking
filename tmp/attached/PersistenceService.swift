import Foundation

final class PersistenceService {
    static let shared = PersistenceService()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func saveString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func loadString(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func saveInt(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func loadInt(forKey key: String) -> Int {
        defaults.integer(forKey: key)
    }

    func saveBool(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func loadBool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    func saveCredentials(_ credentials: [LoginCredential], forSite site: BuiltInSite) {
        let codable = credentials.map { CodableCredential(id: $0.id, username: $0.username, password: $0.password, status: $0.status, addedAt: $0.addedAt, notes: $0.notes) }
        save(codable, forKey: "login_credentials_\(site.rawValue)")
    }

    func loadCredentials(forSite site: BuiltInSite) -> [LoginCredential] {
        guard let codable = load([CodableCredential].self, forKey: "login_credentials_\(site.rawValue)") else { return [] }
        return codable.map(makeCredential(from:))
    }

    func saveCombinedCredentials(_ credentials: [LoginCredential]) {
        let codable = credentials.map { CodableCredential(id: $0.id, username: $0.username, password: $0.password, status: $0.status, addedAt: $0.addedAt, notes: $0.notes) }
        save(codable, forKey: "login_credentials_combined")
    }

    func loadCombinedCredentials() -> [LoginCredential] {
        if let codable = load([CodableCredential].self, forKey: "login_credentials_combined") {
            return codable.map(makeCredential(from:))
        }

        let legacy = BuiltInSite.allCases.flatMap(loadCredentials(forSite:))
        var unique: [LoginCredential] = []
        var seen: Set<String> = []

        for credential in legacy {
            let key = "\(credential.username.lowercased())|\(credential.password)"
            if seen.insert(key).inserted {
                unique.append(credential)
            }
        }

        if !unique.isEmpty {
            saveCombinedCredentials(unique)
        }

        return unique
    }

    func loadAllCredentials() -> [LoginCredential] {
        loadCombinedCredentials()
    }

    private func makeCredential(from codable: CodableCredential) -> LoginCredential {
        let credential = LoginCredential(username: codable.username, password: codable.password, id: codable.id, addedAt: codable.addedAt)
        credential.status = codable.status
        credential.notes = codable.notes
        return credential
    }

    func saveCustomSites(_ sites: [CustomSite]) {
        save(sites, forKey: "custom_sites")
    }

    func loadCustomSites() -> [CustomSite] {
        load([CustomSite].self, forKey: "custom_sites") ?? []
    }

    func saveBillers(_ billers: [BPointBiller]) {
        save(billers, forKey: "bpoint_billers")
    }

    func loadBillers() -> [BPointBiller] {
        load([BPointBiller].self, forKey: "bpoint_billers") ?? BPointBillerPool.defaultBillers
    }

    func saveExportHistory(_ records: [ExportRecord]) {
        save(records, forKey: "export_history")
    }

    func loadExportHistory() -> [ExportRecord] {
        load([ExportRecord].self, forKey: "export_history") ?? []
    }
}

private nonisolated struct CodableCredential: Codable, Sendable {
    let id: String
    let username: String
    let password: String
    let status: CredentialStatus
    let addedAt: Date
    let notes: String
}
