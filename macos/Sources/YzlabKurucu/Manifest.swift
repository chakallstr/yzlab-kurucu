import Foundation

/// Sunucudaki kurulum manifesti. Model / token alan adi / Node adresi degisirse
/// SADECE sunucudaki JSON duzenlenir — yeni surum dagitmaya gerek kalmaz.
/// `codex.catalogUrl` `{{CODEX_VERSION}}` tasiyabilir (Installer.katalogAdresi doldurur).
/// `schemaVersion`: canli manifest gomuluden ESKIYSE (yeni alanlar yok) gomulu kullanilir.
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
    struct ClaudeModel: Codable, Identifiable, Hashable {
        let id: String
        let label: String
    }
    /// Claude Code (terminal + Claude masaustu uygulamasinin Code sekmesi): ikisi de
    /// ayni settings.json'i okur; profil mekanizmasi yok → yalniz `env` blogu duzenlenir.
    struct Claude: Codable {
        let npmPackage: String
        let configDir: String
        let settingsFile: String
        let baseUrl: String
        let defaultModel: String
        let smallFastModel: String
        let models: [ClaudeModel]
        let envTemplate: [String: String]
        let removeEnvKeys: [String]
        let launchCommand: String
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
    let claude: Claude
    let node: Node

    static var manifestUrl: URL {
        #if DEBUG
        // Yalniz DEBUG derlemede: yerel test sunucusuna yonlendirme.
        // Dagitilan RELEASE ikilisinde bu dal DERLENMEZ — musterinin kurucusu
        // adresi asla disaridan degistirilemez.
        if let s = ProcessInfo.processInfo.environment["YZLAB_MANIFEST_URL"],
           let u = URL(string: s) { return u }
        #endif
        return URL(string: "https://yapayzekalab.org/kurulum/codex.json")!
    }

    /// Once sunucudan cek; ulasilamazsa / eski semaysa gomulu surume dus.
    /// Kurulumun internet kesintisinde de calismasi icin.
    static func load() async -> (Manifest, Bool) {
        var req = URLRequest(url: manifestUrl)
        req.timeoutInterval = 10
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let m = try? JSONDecoder().decode(Manifest.self, from: data),
           m.schemaVersion >= embedded.schemaVersion {
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
