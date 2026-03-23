import Foundation

nonisolated struct ExclusionEntry: Codable, Sendable, Identifiable {
    let id: UUID
    let email: String
    let sites: [String]
    let outcome: String
    let dateAdded: Date

    init(email: String, sites: [AutomationSite], outcome: DualLoginOutcome) {
        self.id = UUID()
        self.email = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.sites = sites.map(\.rawValue)
        self.outcome = outcome.rawValue
        self.dateAdded = Date()
    }
}

@Observable
@MainActor
final class ExclusionListService {
    static let shared = ExclusionListService()

    private(set) var permExclusions: [ExclusionEntry] = []
    private(set) var noAccountExclusions: [ExclusionEntry] = []

    private let permKey = "sitchomatic.v16.exclusion.perm"
    private let noAccountKey = "sitchomatic.v16.exclusion.noAccount"

    private init() {
        load()
    }

    func isFullyExcluded(email: String) -> Bool {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if noAccountExclusions.contains(where: { $0.email == normalized }) {
            return true
        }
        let permSites = permExcludedSites(for: normalized)
        return permSites.contains(.joe) && permSites.contains(.ignition)
    }

    func permExcludedSites(for email: String) -> Set<AutomationSite> {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var sites = Set<AutomationSite>()
        for entry in permExclusions where entry.email == normalized {
            for siteRaw in entry.sites {
                if let site = AutomationSite(rawValue: siteRaw) {
                    sites.insert(site)
                }
            }
        }
        return sites
    }

    func isNoAccount(email: String) -> Bool {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return noAccountExclusions.contains { $0.email == normalized }
    }

    func addPermExclusion(email: String, sites: [AutomationSite]) {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let existingSites = permExcludedSites(for: normalized)
        let newSites = sites.filter { !existingSites.contains($0) }
        guard !newSites.isEmpty else { return }
        let entry = ExclusionEntry(email: normalized, sites: newSites, outcome: .permDisabled)
        permExclusions.append(entry)
        save()
    }

    func addNoAccountExclusion(email: String) {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !noAccountExclusions.contains(where: { $0.email == normalized }) else { return }
        let entry = ExclusionEntry(email: normalized, sites: AutomationSite.allCases, outcome: .noAccount)
        noAccountExclusions.append(entry)
        save()
    }

    func clearPermExclusions() {
        permExclusions.removeAll()
        save()
    }

    func clearNoAccountExclusions() {
        noAccountExclusions.removeAll()
        save()
    }

    func clearAll() {
        permExclusions.removeAll()
        noAccountExclusions.removeAll()
        save()
    }

    var permCount: Int { permExclusions.count }
    var noAccountCount: Int { noAccountExclusions.count }
    var totalCount: Int { permCount + noAccountCount }

    private func save() {
        if let data = try? JSONEncoder().encode(permExclusions) {
            UserDefaults.standard.set(data, forKey: permKey)
        }
        if let data = try? JSONEncoder().encode(noAccountExclusions) {
            UserDefaults.standard.set(data, forKey: noAccountKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: permKey),
           let decoded = try? JSONDecoder().decode([ExclusionEntry].self, from: data) {
            permExclusions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: noAccountKey),
           let decoded = try? JSONDecoder().decode([ExclusionEntry].self, from: data) {
            noAccountExclusions = decoded
        }
    }
}
