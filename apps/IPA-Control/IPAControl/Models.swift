import Foundation

struct AltStoreSource: Decodable {
    let name: String
    let apps: [AltStoreApp]
}

struct AltStoreApp: Decodable, Identifiable {
    let name: String
    let bundleIdentifier: String
    let developerName: String?
    let localizedDescription: String?
    let iconURL: URL?
    let versions: [AltStoreVersion]?

    var id: String { bundleIdentifier }
    var latestVersion: AltStoreVersion? { versions?.first }
}

struct AltStoreVersion: Decodable {
    let version: String
    let buildVersion: String?
    let downloadURL: URL?
}

struct SavedSource: Identifiable, Codable {
    let id: UUID
    let url: URL
    let name: String

    init(url: URL, name: String) {
        self.id = UUID()
        self.url = url
        self.name = name
    }
}

struct CatalogApp: Identifiable {
    let sourceID: UUID
    let sourceName: String
    let app: AltStoreApp

    var id: String { sourceID.uuidString + ":" + app.bundleIdentifier }
}

enum ClientError: LocalizedError {
    case invalidURL
    case networkStatus(Int)
    case emptySource
    case duplicateSource
    case duplicateBundleID
    case oversizedSource

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Použij platnou HTTPS adresu."
        case .networkStatus(let code): return "Server odpověděl HTTP \(code)."
        case .emptySource: return "Zdroj neobsahuje platný název."
        case .duplicateSource: return "Tento zdroj už je přidaný."
        case .duplicateBundleID: return "Zdroj obsahuje duplicitní Bundle ID."
        case .oversizedSource: return "Soubor zdroje je příliš velký."
        }
    }
}
