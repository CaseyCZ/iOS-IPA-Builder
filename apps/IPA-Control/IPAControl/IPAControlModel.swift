import Foundation
import SwiftUI

@MainActor
final class IPAControlModel: ObservableObject {
    @Published private(set) var sources: [SavedSource] = []
    @Published private(set) var catalog: [CatalogApp] = []
    @Published var serverURLString: String = "" {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Keys.serverURL) }
    }
    @Published private(set) var serverStatus: String = "Neověřeno"
    @Published private(set) var isLoading = false

    private enum Keys {
        static let sources = "ipaControl.sources.v1"
        static let serverURL = "ipaControl.serverURL.v1"
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.sources),
           let decoded = try? JSONDecoder().decode([SavedSource].self, from: data) {
            sources = decoded
        }
        serverURLString = UserDefaults.standard.string(forKey: Keys.serverURL) ?? ""
    }

    static func httpsURL(from raw: String) throws -> URL {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else {
            throw ClientError.invalidURL
        }
        return url
    }

    private static func fetchSource(_ url: URL) async throws -> AltStoreSource {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidURL }
        guard (200...299).contains(http.statusCode) else { throw ClientError.networkStatus(http.statusCode) }
        guard data.count <= 3_000_000 else { throw ClientError.oversizedSource }

        let result = try JSONDecoder().decode(AltStoreSource.self, from: data)
        guard !result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.emptySource
        }
        let ids = result.apps.map(\.bundleIdentifier)
        guard Set(ids).count == ids.count else { throw ClientError.duplicateBundleID }
        return result
    }

    func addSource(_ rawURL: String) async throws {
        let url = try Self.httpsURL(from: rawURL)
        guard !sources.contains(where: { $0.url == url }) else { throw ClientError.duplicateSource }
        let decoded = try await Self.fetchSource(url)
        sources.append(SavedSource(url: url, name: decoded.name))
        persistSources()
        rebuildCatalog(for: sources.last!.id, name: decoded.name, apps: decoded.apps)
    }

    func removeSource(_ source: SavedSource) {
        sources.removeAll { $0.id == source.id }
        catalog.removeAll { $0.sourceID == source.id }
        persistSources()
    }

    func refreshSources() async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var freshCatalog: [CatalogApp] = []
        var refreshedSources: [SavedSource] = []
        var firstError: Error?

        for source in sources {
            do {
                let manifest = try await Self.fetchSource(source.url)
                refreshedSources.append(SavedSourceRecord.keepID(source, name: manifest.name))
                freshCatalog.append(contentsOf: manifest.apps.map {
                    CatalogApp(sourceID: source.id, sourceName: manifest.name, app: $0)
                })
            } catch {
                refreshedSources.append(source)
                if firstError == nil { firstError = error }
            }
        }
        sources = refreshedSources
        catalog = freshCatalog
        persistSources()
        if let firstError { throw firstError }
    }

    func checkServer() async throws {
        let base = try Self.httpsURL(from: serverURLString)
        let url = base.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidURL }
        guard http.statusCode == 200 else {
            serverStatus = "Nedostupný (HTTP \(http.statusCode))"
            throw ClientError.networkStatus(http.statusCode)
        }
        serverStatus = "Dostupný"
    }

    private func rebuildCatalog(for id: UUID, name: String, apps: [AltStoreApp]) {
        catalog.removeAll { $0.sourceID == id }
        catalog.append(contentsOf: apps.map { CatalogApp(sourceID: id, sourceName: name, app: $0) })
    }

    private func persistSources() {
        if let encoded = try? JSONEncoder().encode(sources) {
            UserDefaults.standard.set(encoded, forKey: Keys.sources)
        }
    }
}

private enum SavedSourceRecord {
    static func keepID(_ old: SavedSource, name: String) -> SavedSource {
        // Retain stable source IDs when refreshing the manifest name.
        SavedSource(id: old.id, url: old.url, name: name)
    }
}

private extension SavedSource {
    init(id: UUID, url: URL, name: String) {
        self.id = id
        self.url = url
        self.name = name
    }
}
