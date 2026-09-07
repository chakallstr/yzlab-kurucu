import Foundation

/// Sunucudaki kurulum manifesti. Model / token alan adi / Node adresi degisirse
/// SADECE sunucudaki JSON duzenlenir — yeni surum dagitmaya gerek kalmaz.
struct Manifest: Codable {
    struct Api: Codable {
        let baseUrl: String
        let validateUrl: String
        let authPrefix: String
        let keyPrefix: String
    }
    struct Model: Codable, Identifiable, Hashable {
        let id: String
        let label: String
        let contextWindow: Int
        private enum CodingKeys: String, CodingKey { case id, label, contextWindow }
    }
    struct Codex: Codable {
        let minVersion: String
        let npmPackage: String
        let catalogUrl: String
        let catalogFile: String
        let profileName: String
        let profileFile: String
        let launchCommand: String
        let defaultModel: String
        let models: [Model]
        let profileTemplate: String
        let tokenField: String
    }
    struct NodePlatform: Codable {
        let url: String
        let silentArgs: String
    }
    struct Node: Codable {
        let macos: NodePlatform
    }

    let schemaVersion: Int
    let api: Api
    let codex: Codex
    let node: Node

    static let manifestUrl = URL(string: "https://yapayzekalab.org/kurulum/codex.json")!

    /// Once sunucudan cek; ulasilamazsa gomulu surume dus.
    /// Kurulumun internet kesintisinde de calismasi icin.
    static func load() async -> (Manifest, Bool) {
        var req = URLRequest(url: manifestUrl)
        req.timeoutInterval = 10
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let m = try? JSONDecoder().decode(Manifest.self, from: data) {
            return (m, true)
        }
        return (embedded, false)
    }

    static let embedded: Manifest = {
        guard let m = try? JSONDecoder().decode(Manifest.self, from: Data(embeddedJson.utf8)) else {
            fatalError("gomulu manifest bozuk — build hatasi")
        }
        return m
    }()
}
