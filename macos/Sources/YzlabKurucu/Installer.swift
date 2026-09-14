import Foundation

enum KurulumHatasi: LocalizedError {
    case anahtarGecersiz(Int)
    case agHatasi(String)
    case codexKurulamadi(String)
    case claudeKurulamadi(String)
    case yazilamadi(String)

    var errorDescription: String? {
        switch self {
        case .anahtarGecersiz(401): return "Anahtar gecersiz veya iptal edilmis. Panelden yeni anahtar olustur."
        case .anahtarGecersiz(let k): return "Sunucu \(k) dondu. Birazdan tekrar dene."
        case .agHatasi(let d): return "Baglanti kurulamadi: \(d)"
        case .codexKurulamadi(let d): return "Codex kurulamadi: \(d)"
        case .claudeKurulamadi(let d): return "Claude Code kurulamadi: \(d)"
        case .yazilamadi(let d): return "Dosya yazilamadi: \(d)"
        }
    }
}

struct Bakiye { let tl: String }

@MainActor
final class Kurucu: ObservableObject {
    @Published var adim: String = "" { didSet { bildirici?(adim) } }
    @Published var calisiyor = false
    /// Bassiz modda adimlari stdout'a yazmak icin (GUI'de nil).
    var bildirici: ((String) -> Void)?

    let manifest: Manifest
    init(manifest: Manifest) { self.manifest = manifest }

    // MARK: - Dizinler

    /// Login kabugundaki bir ortam degiskeni (GUI uygulamasi kullanicinin .zprofile'ini gormez).
    /// YALNIZ stdout okunur ve deger bir yola benzemeli — kabuk gurultusu yol sanilmasin.
    private func loginKabukYolu(_ degisken: String) -> URL? {
        if let h = ProcessInfo.processInfo.environment[degisken], !h.isEmpty {
            return URL(fileURLWithPath: (h as NSString).expandingTildeInPath)
        }
        let login = Kabuk.calistir("echo -n \"$\(degisken)\"", saniye: 15, sadeceStdout: true).ciktisi
        if !login.isEmpty, !login.contains("\n"), login.hasPrefix("/") || login.hasPrefix("~") {
            return URL(fileURLWithPath: (login as NSString).expandingTildeInPath)
        }
        return nil
    }

    var codexDizini: URL {
        // CODEX_HOME tanimliysa Codex config'i ORADAN okur; ~/.codex'e yazmak
        // sessizce hicbir sey yapmaz. (2026-08-06'da bu makinede olculdu.)
        loginKabukYolu("CODEX_HOME")
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    }

    var profilYolu: URL { codexDizini.appendingPathComponent(manifest.codex.profileFile) }
    var katalogYolu: URL { codexDizini.appendingPathComponent(manifest.codex.catalogFile) }
    var kisayolYolu: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/yzlab-codex")
    }

    /// Claude Code'un karsiligi CLAUDE_CONFIG_DIR (binary'de dogrulandi). Masaustu
    /// uygulamasi da ayni dizini okur ("Desktop Settings" ile tasinabilir).
    var claudeDizini: URL {
        loginKabukYolu("CLAUDE_CONFIG_DIR")
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(manifest.claude.configDir)
    }
    var claudeAyarYolu: URL { claudeDizini.appendingPathComponent(manifest.claude.settingsFile) }
    /// Ilk yazimdan onceki settings.json — Geri Al bunu birebir geri koyar.
    var claudeYedekYolu: URL { claudeDizini.appendingPathComponent(manifest.claude.settingsFile + ".bak-yzlab") }
    /// Ilk yazimda settings.json HIC YOKTU isareti — Geri Al dosyayi siler.
    var claudeYokIsareti: URL { claudeDizini.appendingPathComponent(manifest.claude.settingsFile + ".yok-yzlab") }
    var claudeKisayolYolu: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/yzlab-claude")
    }

    var kuruluMu: Bool { FileManager.default.fileExists(atPath: profilYolu.path) }
    var claudeKuruluMu: Bool {
        FileManager.default.fileExists(atPath: claudeYedekYolu.path)
            || FileManager.default.fileExists(atPath: claudeYokIsareti.path)
    }

    // MARK: - 1. Anahtar dogrulama

    func anahtariDogrula(_ anahtar: String) async throws -> Bakiye {
        var req = URLRequest(url: URL(string: manifest.api.validateUrl)!)
        req.setValue(manifest.api.authPrefix + anahtar, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw KurulumHatasi.agHatasi(error.localizedDescription) }

        let kod = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard kod == 200 else { throw KurulumHatasi.anahtarGecersiz(kod) }

        let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tl = (j?["balance_try"] as? String) ?? "—"
        return Bakiye(tl: tl)
    }

    // MARK: - 2..5 tam kurulum

    func kur(anahtar: String, model: Manifest.Model, kisayol: Bool, claude: Bool = true) async throws {
        calisiyor = true
        defer { calisiyor = false }

        adim = "Anahtar dogrulaniyor…"
        _ = try await anahtariDogrula(anahtar)

        adim = "Codex aranıyor…"
        try await codexHazirla()

        adim = "Model katalogu indiriliyor…"
        try await kataloguIndir(anahtar: anahtar)

        adim = "Profil yaziliyor…"
        try profiliYaz(anahtar: anahtar, model: model)

        if kisayol {
            adim = "Kisayol olusturuluyor…"
            try kisayolYaz()
        }

        adim = "Codex dogrulaniyor…"
        try dogrula()

        if claude {
            adim = "Claude Code aranıyor…"
            try await claudeHazirla()

            adim = "Claude Code ayari yaziliyor…"
            try claudeAyarYaz(anahtar: anahtar, modelId: model.id)

            if kisayol {
                adim = "Claude Code kisayolu…"
                try claudeKisayolYaz()
            }

            adim = "Claude Code dogrulaniyor…"
            try claudeDogrula()
        }

        adim = "Kuruldu"
    }

    // MARK: - Node / npm

    private func nodeHazirla() throws {
        if Kabuk.varMi("npm") { return }
        adim = "Node.js kuruluyor… (birkac dakika)"
        let url = manifest.node.macos.url
        let pkg = NSTemporaryDirectory() + "node-yzlab.pkg"
        let indir = Kabuk.calistir("curl -fsSL -o '\(pkg)' '\(url)'", saniye: 600)
        guard indir.basarili else { throw KurulumHatasi.codexKurulamadi("Node indirilemedi: \(indir.ciktisi)") }
        // installer root ister: kullaniciya sifre sorulur.
        let kur = Kabuk.calistir(
            "osascript -e 'do shell script \"installer -pkg \\\"\(pkg)\\\" \(manifest.node.macos.silentArgs)\" with administrator privileges'",
            saniye: 900)
        guard kur.basarili else { throw KurulumHatasi.codexKurulamadi("Node kurulumu reddedildi veya basarisiz") }
    }

    /// Ozel npm prefix'i (.npmrc `prefix=~/.npm-global`, nvm) yalniz kullanicinin
    /// interaktif .zshrc'sinde PATH'e eklenir; bizim `zsh -lc` onu okumaz → kurulu
    /// olsa da bulunamazdi. npm'e sorup bin dizinini PATH'imize ekliyoruz.
    private func npmGlobalBiniPathEkle() {
        let r = Kabuk.calistir("npm prefix -g", saniye: 30, sadeceStdout: true)
        guard r.basarili, let prefix = r.ciktisi.split(separator: "\n").last.map(String.init),
              prefix.hasPrefix("/") else { return }
        Kabuk.ekPath = prefix + "/bin"
    }

    /// Codex KURULUYSA hic dokunma — boylece musterinin Codex'i acik olsa bile
    /// dosya kilidi/guncelleme sorunu cikmaz, kapatmasi gerekmez.
    private func codexHazirla() async throws {
        if Kabuk.komutVarMi("codex") { return }
        try nodeHazirla()
        adim = "Codex CLI kuruluyor… (birkac dakika)"
        let r = Kabuk.calistir("npm install -g \(manifest.codex.npmPackage)", saniye: 1200)
        npmGlobalBiniPathEkle()
        guard r.basarili, Kabuk.komutVarMi("codex") else {
            throw KurulumHatasi.codexKurulamadi(String(r.ciktisi.suffix(300)))
        }
    }

    // MARK: - Katalog (canli API'den, kurulu Codex surumune gore)

    /// "codex-cli 0.153.4" → "0.153.4". Codex yoksa/okunamazsa nil.
    nonisolated static func surumAyikla(_ s: String) -> String? {
        guard let r = s.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) else { return nil }
        return String(s[r])
    }

    func codexSurumu() -> String? {
        Kurucu.surumAyikla(Kabuk.calistir("\(Kabuk.komut("codex")) --version", saniye: 20).ciktisi)
    }

    /// Manifestteki katalog adresi `{{CODEX_VERSION}}` tasiyabilir: gateway kurulu
    /// Codex surumune gore dogru semayi doner. Surum bulunamazsa minimum surum yazilir.
    func katalogAdresi(surum: String?) -> URL {
        let v = surum ?? manifest.codex.minVersion
        let s = manifest.codex.catalogUrl.replacingOccurrences(
            of: "{{CODEX_VERSION}}",
            with: v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)
        return URL(string: s) ?? URL(string: manifest.codex.catalogUrl)!
    }

    private func kataloguIndir(anahtar: String) async throws {
        var req = URLRequest(url: katalogAdresi(surum: codexSurumu()))
        req.timeoutInterval = 30
        // Anahtarla istenir: gateway musterinin kendi kademesine gore katalog verir.
        req.setValue(manifest.api.authPrefix + anahtar, forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modeller = j["models"] as? [Any], !modeller.isEmpty else {
            throw KurulumHatasi.agHatasi("model katalogu indirilemedi")
        }
        try FileManager.default.createDirectory(at: codexDizini, withIntermediateDirectories: true)
        do { try data.write(to: katalogYolu, options: .atomic) }
        catch { throw KurulumHatasi.yazilamadi(katalogYolu.path) }
    }

    /// SADECE kendi dosyamizi yazar. config.toml ve auth.json'a DOKUNMAZ →
    /// musterinin ChatGPT Plus oturumu bozulmaz.
    func profiliYaz(anahtar: String, model: Manifest.Model) throws {
        let icerik = manifest.codex.profileTemplate
            .replacingOccurrences(of: "{{MODEL}}", with: model.id)
            .replacingOccurrences(of: "{{CONTEXT}}", with: String(model.contextWindow))
            .replacingOccurrences(of: "{{BASE_URL}}", with: manifest.api.baseUrl)
            .replacingOccurrences(of: "{{CATALOG_PATH}}", with: katalogYolu.path)
            .replacingOccurrences(of: "{{TOKEN_FIELD}}", with: manifest.codex.tokenField)
            .replacingOccurrences(of: "{{TOKEN}}", with: anahtar)
        do {
            try FileManager.default.createDirectory(at: codexDizini, withIntermediateDirectories: true)
            try icerik.write(to: profilYolu, atomically: true, encoding: .utf8)
            // Anahtar iceriyor: yalniz sahibi okusun.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profilYolu.path)
        } catch { throw KurulumHatasi.yazilamadi(profilYolu.path) }
    }

    private func betikYaz(_ yol: URL, _ betik: String) throws {
        let dizin = yol.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dizin, withIntermediateDirectories: true)
            try betik.write(to: yol, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: yol.path)
        } catch { throw KurulumHatasi.yazilamadi(yol.path) }
    }

    private func kisayolYaz() throws {
        try betikYaz(kisayolYolu, """
        #!/bin/sh
        # YapayZekaLab — Codex baslatici. Silmek zararsiz.
        exec codex -p \(manifest.codex.profileName) "$@"
        """)
    }

    /// Profilin gercekten yuklendigini ve BIZE gittigini kanitlar.
    ///
    /// IZOLE calisir: gecici bir CODEX_HOME'a yalniz bizim profil kopyalanir (katalog
    /// yolu gercek dosyaya bakar). Sebep: `codex exec` calistigi dizin icin config.toml'a
    /// `[projects.*] trust_level` YAZABILIR (0.153'te olculdu) — musterinin config.toml'una
    /// dokunmama sozunu bozmamak ve musterinin MCP sunucularini bosuna baslatmamak icin.
    private func dogrula() throws {
        let gecici = NSTemporaryDirectory() + "yzlab-dogrula-" + UUID().uuidString
        let fm = FileManager.default
        try? fm.createDirectory(atPath: gecici, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: gecici) }
        do {
            try fm.copyItem(at: profilYolu, to: URL(fileURLWithPath: gecici).appendingPathComponent(manifest.codex.profileFile))
        } catch { throw KurulumHatasi.yazilamadi("dogrulama kopyasi: \(error.localizedDescription)") }

        // ⚠️ CODEX_HOME komut-onu ATAMA ile verilir, Process env'iyle DEGIL: `zsh -l`
        // kullanicinin .zshenv/.zprofile'indeki `export CODEX_HOME=…`i env'den SONRA
        // uygular ve bizim gecici degeri ezerdi (QA 09-14 ZDOTDIR ile kanitladi) →
        // codex exec musterinin GERCEK config.toml'una trust yazardi. Komut-onu atama
        // butun profil dosyalarindan sonra uygulanir; ikisi birden en guvenlisi.
        let r = Kabuk.calistir(
            "CODEX_HOME='\(gecici)' \(Kabuk.komut("codex")) exec -p \(manifest.codex.profileName) --skip-git-repo-check -C '\(gecici)' 'ok' 2>&1 | tail -40",
            saniye: 120, env: ["CODEX_HOME": gecici])
        let c = r.ciktisi
        if c.contains("401") || c.contains("gecersiz") || c.contains("geçersiz") {
            throw KurulumHatasi.anahtarGecersiz(401)
        }
        if c.contains("failed to parse model_catalog_json") {
            throw KurulumHatasi.yazilamadi("model katalogu bozuk indi — tekrar dene")
        }
        // Saglayici satiri gorunmuyorsa profil hic yuklenmemis demektir.
        guard c.contains("provider: yapayzekalab") || c.contains("yapayzekalab") else {
            throw KurulumHatasi.codexKurulamadi("profil yuklenmedi:\n" + String(c.suffix(300)))
        }
        // Izolasyon KANITI: codex, calistigi CODEX_HOME'a her kosulda durum dosyalari
        // yazar (installation_id, sessions/, *.sqlite). Gecici dizinde bunlardan hicbiri
        // yoksa exec BASKA bir CODEX_HOME'da kostu demektir → sessiz ihlal yerine acik hata.
        let icerik = (try? fm.contentsOfDirectory(atPath: gecici)) ?? []
        let iz = icerik.contains { $0 == "installation_id" || $0 == "sessions" || $0.hasSuffix(".sqlite") }
        guard iz else {
            throw KurulumHatasi.codexKurulamadi("dogrulama izole kosmadi (CODEX_HOME ezildi?):\n" + String(c.suffix(200)))
        }
    }

    // MARK: - Claude Code (terminal + Claude masaustu uygulamasi)

    private func claudeHazirla() async throws {
        if Kabuk.komutVarMi("claude") { return }
        try nodeHazirla()
        adim = "Claude Code kuruluyor… (birkac dakika)"
        let r = Kabuk.calistir("npm install -g \(manifest.claude.npmPackage)", saniye: 1200)
        npmGlobalBiniPathEkle()
        guard r.basarili, Kabuk.komutVarMi("claude") else {
            throw KurulumHatasi.claudeKurulamadi(String(r.ciktisi.suffix(300)))
        }
    }

    /// settings.json'in YALNIZ `env` blogunu duzenler; diger her anahtar (permissions,
    /// hooks, model…) aynen kalir. Ilk yazimdan once birebir yedek alinir (Geri Al bunu
    /// geri koyar). Kalinti: env'de ANTHROPIC_API_KEY kalirsa AUTH_TOKEN'i EZER → silinir.
    func claudeAyarYaz(anahtar: String, modelId: String) throws {
        let fm = FileManager.default
        try? fm.createDirectory(at: claudeDizini, withIntermediateDirectories: true)

        var obj: [String: Any] = [:]
        if fm.fileExists(atPath: claudeAyarYolu.path) {
            guard let data = fm.contents(atPath: claudeAyarYolu.path) else {
                throw KurulumHatasi.yazilamadi(claudeAyarYolu.path)
            }
            if !data.isEmpty {
                guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw KurulumHatasi.claudeKurulamadi("\(claudeAyarYolu.path) gecerli JSON degil — elle duzelt, sonra tekrar dene")
                }
                obj = j
            }
            // Yedek YALNIZ ilk kurulumda alinir: yeniden kurmak yedegi ezmesin
            // (aksi halde Geri Al bizim kendi dosyamizi "geri koyardi").
            if !claudeKuruluMu {
                do { try fm.copyItem(at: claudeAyarYolu, to: claudeYedekYolu) }
                catch { throw KurulumHatasi.yazilamadi(claudeYedekYolu.path) }
            }
        } else if !claudeKuruluMu {
            fm.createFile(atPath: claudeYokIsareti.path, contents: Data())
        }

        var env = (obj["env"] as? [String: Any]) ?? [:]
        for k in manifest.claude.removeEnvKeys { env.removeValue(forKey: k) }
        for (k, v) in manifest.claude.envTemplate {
            env[k] = v
                .replacingOccurrences(of: "{{BASE_URL}}", with: manifest.claude.baseUrl)
                .replacingOccurrences(of: "{{TOKEN}}", with: anahtar)
                .replacingOccurrences(of: "{{MODEL}}", with: modelId)
                .replacingOccurrences(of: "{{SMALL_MODEL}}", with: manifest.claude.smallFastModel)
        }
        obj["env"] = env

        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: claudeAyarYolu, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claudeAyarYolu.path)
        } catch { throw KurulumHatasi.yazilamadi(claudeAyarYolu.path) }
    }

    private func claudeKisayolYaz() throws {
        try betikYaz(claudeKisayolYolu, """
        #!/bin/sh
        # YapayZekaLab — Claude Code baslatici. Silmek zararsiz (claude zaten ayarli).
        exec claude "$@"
        """)
    }

    /// settings.json'daki env ile Claude Code'un gercekten BIZE gittigini kanitlar.
    /// IZOLE: gecici CLAUDE_CONFIG_DIR'a yalniz settings.json kopyalanir — musterinin
    /// oturum/proje kayitlarina (.claude.json, projects/) dokunulmaz.
    private func claudeDogrula() throws {
        let gecici = NSTemporaryDirectory() + "yzlab-claude-dogrula-" + UUID().uuidString
        let fm = FileManager.default
        try? fm.createDirectory(atPath: gecici + "/cfg", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: gecici) }
        do { try fm.copyItem(at: claudeAyarYolu, to: URL(fileURLWithPath: gecici + "/cfg/" + manifest.claude.settingsFile)) }
        catch { throw KurulumHatasi.yazilamadi("dogrulama kopyasi: \(error.localizedDescription)") }

        let r = Kabuk.calistir(
            "cd '\(gecici)' && CLAUDE_CONFIG_DIR='\(gecici)/cfg' \(Kabuk.komut("claude")) -p 'Sadece ok yaz' --output-format json 2>&1 | tail -c 4000",
            saniye: 180, env: ["CLAUDE_CONFIG_DIR": gecici + "/cfg"])
        let c = r.ciktisi
        if c.contains("authentication_error") || c.contains("Invalid API key") || c.contains("401") {
            throw KurulumHatasi.anahtarGecersiz(401)
        }
        guard c.contains("\"stop_reason\"") || c.contains("\"result\""), !c.contains("\"is_error\":true") else {
            throw KurulumHatasi.claudeKurulamadi("dogrulama yaniti beklenmedik:\n" + String(c.suffix(300)))
        }
        // Izolasyon kaniti: claude, CLAUDE_CONFIG_DIR'a .claude.json / projects yazar.
        let icerik = (try? fm.contentsOfDirectory(atPath: gecici + "/cfg")) ?? []
        guard icerik.contains(where: { $0 == ".claude.json" || $0 == "projects" || $0 == "sessions" }) else {
            throw KurulumHatasi.claudeKurulamadi("dogrulama izole kosmadi (CLAUDE_CONFIG_DIR ezildi?)")
        }
    }

    // MARK: - Geri al

    func geriAl() {
        for u in [profilYolu, katalogYolu, kisayolYolu] {
            try? FileManager.default.removeItem(at: u)
        }
        claudeGeriAl()
        adim = "Geri alindi. Codex ve Claude Code ayarlarin kurulumdan onceki haline dondu."
    }

    func claudeGeriAl() {
        let fm = FileManager.default
        if fm.fileExists(atPath: claudeYedekYolu.path) {
            try? fm.removeItem(at: claudeAyarYolu)
            try? fm.moveItem(at: claudeYedekYolu, to: claudeAyarYolu)
        } else if fm.fileExists(atPath: claudeYokIsareti.path) {
            try? fm.removeItem(at: claudeAyarYolu)
            try? fm.removeItem(at: claudeYokIsareti)
        }
        try? fm.removeItem(at: claudeKisayolYolu)
    }
}
