import Foundation
import AppKit

enum KurulumHatasi: LocalizedError {
    case anahtarGecersiz(Int)
    case agHatasi(String)
    case paketYok(String)
    case codexAcik
    case codexKurulamadi(String)
    case claudeKurulamadi(String)
    case yazilamadi(String)

    var errorDescription: String? {
        switch self {
        case .anahtarGecersiz(401): return "Anahtar gecersiz veya iptal edilmis. Panelden yeni anahtar olustur."
        case .anahtarGecersiz(let k): return "Sunucu \(k) dondu. Birazdan tekrar dene."
        case .agHatasi(let d): return "Baglanti test edilemedi: \(d)"
        case .paketYok(let d): return "Anahtar gecerli ama istek reddedildi (\(d)). Panelden paketini/bakiyeni kontrol et."
        case .codexAcik: return "Codex uygulamasi acik. Kapatip tekrar Kur'a bas."
        case .codexKurulamadi(let d): return "Codex ayarlanamadi: \(d)"
        case .claudeKurulamadi(let d): return "Claude Code kurulamadi: \(d)"
        case .yazilamadi(let d): return "Dosya yazilamadi: \(d)"
        }
    }
}

struct Bakiye { let tl: String }

/// Kurulumun beyni. v0.2 (2026-09-15) — HEDEF CODEX MASAUSTU:
/// - Ayar ana `config.toml`'a isaretli bloklarla yazilir (`CodexAyar`). Profil (`-p yzlab`) YAZILMAZ —
///   masaustu onu okumuyordu (musteri kamer5561: masaustu kendi hesabiyla gitti).
/// - Node / Codex CLI KURULMAZ: masaustu kendi codex'ini tasir. Dogrulama dogrudan HTTPS (Codex bicimi).
/// - Varsayilan: ChatGPT girisi DURUR (auth.json'a dokunulmaz). `anahtarGiris` → auth.json anahtar
///   moduna alinir (yedekli) — musterinin ChatGPT hesabinda hak yoksa masaustu limit afisi gosterebilir.
/// - Codex aciksa kapatilir (izinle) ve sonra yeniden acilir: acikken yazilan ayar, uygulama kapanirken
///   config.toml'u yeniden yazip EZEBILIR ve ayar ancak acilista okunur.
@MainActor
final class Kurucu: ObservableObject {
    @Published var adim: String = "" { didSet { bildirici?(adim) } }
    @Published var calisiyor = false
    /// Bassiz modda adimlari stdout'a yazmak icin (GUI'de nil).
    var bildirici: ((String) -> Void)?
    var geriAlHatalari: [String] = []

    let manifest: Manifest
    init(manifest: Manifest) { self.manifest = manifest }

    // MARK: - Dizinler (ucuz: kabuk cagrisi YOK — eskiden her ekran ciziminde `zsh -l` kosuyordu)

    /// Codex MASAUSTU uygulamasinin okudugu dizin. Finder'dan acilan uygulama launchd ortamini
    /// devralir → `launchctl setenv CODEX_HOME` burada gorunur. Ortamda yoksa `launchctl getenv`
    /// sorulur (terminalden acilma), o da yoksa ~/.codex.
    /// ⚠️ Ortamda CODEX_HOME VARSA YALNIZ o kullanilir: testler gecici dizin verir; launchctl'deki
    /// gercek dizine (bu Mac'te sahibin masaustu kurulumu) ASLA yazilmasin.
    lazy var codexDizini: URL = {
        if let h = ProcessInfo.processInfo.environment["CODEX_HOME"], !h.isEmpty {
            return URL(fileURLWithPath: (h as NSString).expandingTildeInPath)
        }
        if let l = Kurucu.launchctlGetenv("CODEX_HOME"), l.hasPrefix("/") || l.hasPrefix("~") {
            return URL(fileURLWithPath: (l as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    }()

    var ayarYolu: URL { codexDizini.appendingPathComponent("config.toml") }
    var yedekYolu: URL { codexDizini.appendingPathComponent("yzlab-kurucu-yedek.json") }
    var ayarAnlikYedekYolu: URL { codexDizini.appendingPathComponent("config.toml.bak-yzlab") }
    var authYolu: URL { codexDizini.appendingPathComponent("auth.json") }
    var authYedekYolu: URL { codexDizini.appendingPathComponent("auth.json.bak-yzlab") }
    var authYokIsareti: URL { codexDizini.appendingPathComponent("auth.json.yok-yzlab") }
    var katalogYolu: URL { codexDizini.appendingPathComponent(manifest.codex.catalogFile) }
    /// v0.1.x kalintisi (profil). Kurulumda ve Geri Al'da silinir.
    var eskiProfilYolu: URL { codexDizini.appendingPathComponent(manifest.codex.profileFile) }

    /// Claude Code'un karsiligi CLAUDE_CONFIG_DIR. Masaustu uygulamasi da ayni dizini okur.
    lazy var claudeDizini: URL = {
        if let h = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !h.isEmpty {
            return URL(fileURLWithPath: (h as NSString).expandingTildeInPath)
        }
        if let l = Kurucu.launchctlGetenv("CLAUDE_CONFIG_DIR"), l.hasPrefix("/") || l.hasPrefix("~") {
            return URL(fileURLWithPath: (l as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(manifest.claude.configDir)
    }()
    var claudeAyarYolu: URL { claudeDizini.appendingPathComponent(manifest.claude.settingsFile) }
    var claudeYedekYolu: URL { claudeDizini.appendingPathComponent(manifest.claude.settingsFile + ".bak-yzlab") }
    var claudeYokIsareti: URL { claudeDizini.appendingPathComponent(manifest.claude.settingsFile + ".yok-yzlab") }
    var claudeKisayolYolu: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/yzlab-claude")
    }

    var kuruluMu: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: yedekYolu.path) || fm.fileExists(atPath: eskiProfilYolu.path)
            || fm.fileExists(atPath: authYedekYolu.path) || fm.fileExists(atPath: authYokIsareti.path)
    }
    var claudeKuruluMu: Bool {
        FileManager.default.fileExists(atPath: claudeYedekYolu.path)
            || FileManager.default.fileExists(atPath: claudeYokIsareti.path)
    }

    /// Dogrulama HER ZAMAN en hizli/ucuz modelle (2026-09-15: astra ile "ok" 36-61 sn surdu).
    var dogrulamaModeli: String { manifest.claude.smallFastModel }

    nonisolated static func launchctlGetenv(_ ad: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["getenv", ad]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
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

    // MARK: - 2. Tam kurulum

    func kur(anahtar: String, model: Manifest.Model, claude: Bool = false,
             anahtarGiris: Bool = false, codexKapatIzni: Bool = false) async throws {
        calisiyor = true
        defer { calisiyor = false }

        adim = "Anahtar dogrulaniyor…"
        _ = try await anahtariDogrula(anahtar)

        adim = "Codex uygulamasi kontrol ediliyor…"
        var yenidenAc: [URL] = []
        if !Kurucu.acikCodexUygulamalari().isEmpty {
            guard codexKapatIzni else { throw KurulumHatasi.codexAcik }
            adim = "Codex kapatiliyor…"
            yenidenAc = try await codexUygulamasiniKapat()
        }

        do {
            adim = "Model katalogu indiriliyor…"
            let surum = await codexSurumuBul()
            try await kataloguIndir(anahtar: anahtar, surum: surum)

            adim = "Codex ayari yaziliyor…"
            try codexAyariYaz(anahtar: anahtar, model: model, anahtarGiris: anahtarGiris)

            adim = "Baglanti test ediliyor…"
            try await baglantiyiDogrula(anahtar: anahtar, secilenModel: model.id)

            if claude {
                adim = "Claude Code aranıyor…"
                try await claudeHazirla()
                adim = "Claude Code ayari yaziliyor…"
                try claudeAyarYaz(anahtar: anahtar, modelId: model.id)
                adim = "Claude Code kisayolu…"
                try claudeKisayolYaz()
                adim = "Claude Code dogrulaniyor…"
                try await claudeDogrula()
            }
        } catch {
            if !yenidenAc.isEmpty { await codexUygulamasiniAc(yenidenAc) }
            throw error
        }

        if !yenidenAc.isEmpty {
            adim = "Codex yeniden aciliyor…"
            await codexUygulamasiniAc(yenidenAc)
        }
        adim = "Kuruldu"
    }

    // MARK: - Codex masaustu uygulamasi (acik mi / kapat / ac)

    nonisolated static let masaustuKimlikleri = ["com.openai.codex"]

    static func acikCodexUygulamalari() -> [NSRunningApplication] {
        #if DEBUG
        // Yalniz DEBUG: bu Mac'te sahibin Codex'i acikken testler onu KAPATMASIN.
        if ProcessInfo.processInfo.environment["YZLAB_CODEX_KONTROL"] == "kapali" { return [] }
        #endif
        return masaustuKimlikleri.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    }

    func codexUygulamasiniKapat() async throws -> [URL] {
        let acik = Kurucu.acikCodexUygulamalari()
        let adresler = acik.compactMap { $0.bundleURL }
        for a in acik { a.terminate() }
        for _ in 0..<40 {   // 20 sn
            if Kurucu.acikCodexUygulamalari().isEmpty { return adresler }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        throw KurulumHatasi.codexAcik
    }

    func codexUygulamasiniAc(_ adresler: [URL]) async {
        for u in adresler {
            _ = try? await NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Katalog (canli API'den)

    /// "codex-cli 0.153.4" → "0.153.4". Once `codex-cli x.y.z` satiri; yoksa ilk x.y.z.
    nonisolated static func surumAyikla(_ s: String) -> String? {
        if let r = s.range(of: #"codex-cli\s+(\d+\.\d+\.\d+)"#, options: .regularExpression) {
            let m = String(s[r])
            return m.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression).map { String(m[$0]) }
        }
        guard let r = s.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) else { return nil }
        return String(s[r])
    }

    /// Masaustu kendi codex'ini tasidigindan yerel CLI'a bakilmaz: npm'deki son surum (gateway o
    /// surume gore katalog semasi doner). Ulasilamazsa manifestteki minimum.
    func codexSurumuBul() async -> String {
        var req = URLRequest(url: URL(string: "https://registry.npmjs.org/@openai/codex/latest")!)
        req.timeoutInterval = 10
        if let (d, r) = try? await URLSession.shared.data(for: req),
           (r as? HTTPURLResponse)?.statusCode == 200,
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let v = j["version"] as? String, let s = Kurucu.surumAyikla(v) {
            return s
        }
        return manifest.codex.minVersion
    }

    func katalogAdresi(surum: String?) -> URL {
        let v = surum ?? manifest.codex.minVersion
        let s = manifest.codex.catalogUrl.replacingOccurrences(
            of: "{{CODEX_VERSION}}",
            with: v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)
        return URL(string: s) ?? URL(string: manifest.codex.catalogUrl)!
    }

    private func kataloguIndir(anahtar: String, surum: String) async throws {
        var req = URLRequest(url: katalogAdresi(surum: surum))
        req.timeoutInterval = 30
        req.setValue(manifest.api.authPrefix + anahtar, forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modeller = j["models"] as? [Any], !modeller.isEmpty else {
            throw KurulumHatasi.agHatasi("model katalogu indirilemedi")
        }
        try? FileManager.default.createDirectory(at: codexDizini, withIntermediateDirectories: true)
        do { try data.write(to: katalogYolu, options: .atomic) }
        catch { throw KurulumHatasi.yazilamadi(katalogYolu.path) }
    }

    // MARK: - config.toml + auth.json

    nonisolated static func tomlKacis(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Manifestteki profil sablonunu doldurur ve config.toml'a girecek parcalara ayirir.
    func sablon(anahtar: String, model: Manifest.Model, anahtarGiris: Bool) -> CodexAyar.Sablon {
        let dolu = manifest.codex.profileTemplate
            .replacingOccurrences(of: "{{MODEL}}", with: model.id)
            .replacingOccurrences(of: "{{CONTEXT}}", with: String(model.contextWindow))
            .replacingOccurrences(of: "{{BASE_URL}}", with: manifest.api.baseUrl)
            .replacingOccurrences(of: "{{CATALOG_PATH}}", with: Kurucu.tomlKacis(katalogYolu.path))
            .replacingOccurrences(of: "{{TOKEN_FIELD}}", with: manifest.codex.tokenField)
            .replacingOccurrences(of: "{{TOKEN}}", with: Kurucu.tomlKacis(anahtar))
        var s = CodexAyar.sablonuAyir(dolu)
        // Anahtar modunda web kitiyle birebir (canlida calisan "normal kurulum").
        if anahtarGiris { s.saglayiciSatirlar.append("requires_openai_auth = true") }
        return s
    }

    func codexAyariYaz(anahtar: String, model: Manifest.Model, anahtarGiris: Bool) throws {
        let fm = FileManager.default
        do { try fm.createDirectory(at: codexDizini, withIntermediateDirectories: true) }
        catch { throw KurulumHatasi.yazilamadi(codexDizini.path) }

        var mevcut: String? = nil
        if fm.fileExists(atPath: ayarYolu.path) {
            guard let d = fm.contents(atPath: ayarYolu.path), let s = String(data: d, encoding: .utf8) else {
                throw KurulumHatasi.codexKurulamadi("config.toml okunamadi (UTF-8 degil)")
            }
            mevcut = s
            if !fm.fileExists(atPath: ayarAnlikYedekYolu.path) {
                try? fm.copyItem(at: ayarYolu, to: ayarAnlikYedekYolu)   // elle kurtarma icin tam kopya
            }
        }

        let (yeni, buSeferki) = CodexAyar.uygula(mevcut, sablon(anahtar: anahtar, model: model, anahtarGiris: anahtarGiris))
        if let hata = CodexAyar.dogrula(yeni) { throw KurulumHatasi.codexKurulamadi(hata) }

        // ILK kurulumun yedegi korunur (yeniden kurmak kurulum-oncesi hali ezmesin).
        var yedek = buSeferki
        if let d = fm.contents(atPath: yedekYolu.path), var eski = try? JSONDecoder().decode(CodexAyar.Yedek.self, from: d) {
            eski.yonetilenAnahtarlar = Array(Set(eski.yonetilenAnahtarlar).union(buSeferki.yonetilenAnahtarlar)).sorted()
            yedek = eski
        }
        do {
            try JSONEncoder().encode(yedek).write(to: yedekYolu, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: yedekYolu.path)
            try Data(yeni.utf8).write(to: ayarYolu, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ayarYolu.path)
        } catch { throw KurulumHatasi.yazilamadi(ayarYolu.path) }

        if anahtarGiris {
            if !fm.fileExists(atPath: authYedekYolu.path) && !fm.fileExists(atPath: authYokIsareti.path) {
                if fm.fileExists(atPath: authYolu.path) {
                    do { try fm.copyItem(at: authYolu, to: authYedekYolu) }
                    catch { throw KurulumHatasi.yazilamadi(authYedekYolu.path) }
                } else {
                    fm.createFile(atPath: authYokIsareti.path, contents: Data())
                }
            }
            do {
                let icerik = try JSONSerialization.data(withJSONObject: ["auth_mode": "apikey", "OPENAI_API_KEY": anahtar],
                                                        options: [.prettyPrinted, .sortedKeys])
                try icerik.write(to: authYolu, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authYolu.path)
            } catch { throw KurulumHatasi.yazilamadi(authYolu.path) }
        } else {
            // Mod degisti (once anahtarla girilmisti): ChatGPT girisi geri gelsin.
            do { try authGeriKoy() } catch { throw KurulumHatasi.yazilamadi(authYolu.path) }
        }

        if fm.fileExists(atPath: eskiProfilYolu.path) { try? fm.removeItem(at: eskiProfilYolu) }
    }

    private func authGeriKoy() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: authYedekYolu.path) {
            let veri = try Data(contentsOf: authYedekYolu)
            try veri.write(to: authYolu, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authYolu.path)
            try fm.removeItem(at: authYedekYolu)
        } else if fm.fileExists(atPath: authYokIsareti.path) {
            if fm.fileExists(atPath: authYolu.path) { try fm.removeItem(at: authYolu) }
            try fm.removeItem(at: authYokIsareti)
        }
    }

    // MARK: - Baglanti testi (Codex biciminde, CLI'siz)

    enum AkisSonuc: Equatable { case tamam, hata(String), devam }

    /// Tek SSE satirini isler. Ilk TERMINAL olay kazanir: `response.completed` → tamam;
    /// `response.failed` / `error` → hata. (Gateway bazen tamamlandiktan SONRA bir `response.failed`
    /// daha yolluyor — olculdu 09-15; Codex ilk terminal olayda durdugu icin zararsiz, biz de oyle.)
    nonisolated static func akisSatiri(_ satir: String) -> AkisSonuc {
        guard satir.hasPrefix("data:") else { return .devam }
        let js = satir.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let d = js.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let tip = o["type"] as? String else { return .devam }
        switch tip {
        case "response.completed":
            return .tamam
        case "response.failed", "error":
            let h = ((o["response"] as? [String: Any])?["error"] as? [String: Any]) ?? (o["error"] as? [String: Any])
            return .hata((h?["message"] as? String) ?? tip)
        default:
            return .devam
        }
    }

    enum IstekSonucu { case basarili, yetkisiz, hakYok(String), gecici(String) }

    private func tekIstek(anahtar: String, model: String) async -> IstekSonucu {
        var taban = manifest.api.baseUrl
        while taban.hasSuffix("/") { taban.removeLast() }
        guard let url = URL(string: taban + "/responses") else { return .gecici("adres gecersiz") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(manifest.api.authPrefix + anahtar, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Codex'in gonderdigi bicim: bazi bacaklar string input'u ve store:true'yu REDDEDIYOR (olculdu).
        let govde: [String: Any] = [
            "model": model,
            "instructions": "Kisa cevap ver.",
            "input": [["type": "message", "role": "user",
                       "content": [["type": "input_text", "text": "Sadece ok yaz"]]]],
            "store": false,
            "stream": true,
            "reasoning": ["effort": "low"],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: govde)
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            let kod = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if kod == 401 { return .yetkisiz }
            if kod == 402 || kod == 403 { return .hakYok("HTTP \(kod)") }
            guard kod == 200 else { return .gecici("HTTP \(kod)") }
            var sayac = 0
            for try await satir in bytes.lines {
                sayac += 1
                switch Kurucu.akisSatiri(satir) {
                case .tamam: return .basarili
                case .hata(let m): return .gecici(m)
                case .devam: if sayac > 20000 { return .gecici("akis cok uzun") }
                }
            }
            return .gecici("akis tamamlanmadi")
        } catch {
            return .gecici(error.localizedDescription)
        }
    }

    /// Once hizli model (3 deneme); paket o modeli kapsamiyorsa secilen modelle (3 deneme).
    func baglantiyiDogrula(anahtar: String, secilenModel: String) async throws {
        var modeller = [dogrulamaModeli]
        if secilenModel != dogrulamaModeli { modeller.append(secilenModel) }
        var sonHata = "bilinmeyen"
        var hakYok = false
        for model in modeller {
            hakYok = false
            denemeler: for deneme in 1...3 {
                switch await tekIstek(anahtar: anahtar, model: model) {
                case .basarili: return
                case .yetkisiz: throw KurulumHatasi.anahtarGecersiz(401)
                case .hakYok(let m): sonHata = "\(model): \(m)"; hakYok = true; break denemeler
                case .gecici(let m):
                    sonHata = "\(model): \(m)"
                    if deneme < 3 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
                }
            }
        }
        throw hakYok ? KurulumHatasi.paketYok(sonHata) : KurulumHatasi.agHatasi(sonHata)
    }

    // MARK: - Node / npm (yalniz Claude Code icin)

    private func nodeHazirla() async throws {
        if await Kabuk.varMiAsync("npm") { return }
        adim = "Node.js kuruluyor… (birkac dakika)"
        let url = manifest.node.macos.url
        let pkg = NSTemporaryDirectory() + "node-yzlab.pkg"
        let indir = await Kabuk.calistirAsync("curl -fsSL -o '\(pkg)' '\(url)'", saniye: 600)
        guard indir.basarili else { throw KurulumHatasi.claudeKurulamadi("Node indirilemedi: \(indir.ciktisi)") }
        let kur = await Kabuk.calistirAsync(
            "osascript -e 'do shell script \"installer -pkg \\\"\(pkg)\\\" \(manifest.node.macos.silentArgs)\" with administrator privileges'",
            saniye: 900)
        guard kur.basarili else { throw KurulumHatasi.claudeKurulamadi("Node kurulumu reddedildi veya basarisiz") }
    }

    private func npmGlobalBiniPathEkle() async {
        let r = await Kabuk.calistirAsync("npm prefix -g", saniye: 30, sadeceStdout: true)
        guard r.basarili, let prefix = r.ciktisi.split(separator: "\n").last.map(String.init),
              prefix.hasPrefix("/") else { return }
        Kabuk.ekPath = prefix + "/bin"
    }

    /// Codex/Claude ciktisinda GERCEK yetki reddi var mi? Sayilarin icindeki "401"e kanmaz.
    nonisolated static func yetkiReddiMi(_ c: String) -> Bool {
        if c.contains("Unauthorized") || c.contains("authentication_error") || c.contains("Invalid API key")
            || c.contains("invalid_api_key") || c.contains("gecersiz") || c.contains("geçersiz") { return true }
        return c.range(of: #"(?i)(http|status|code)\D{0,4}401(\D|$)"#, options: .regularExpression) != nil
    }

    // MARK: - Claude Code (terminal + Claude masaustu uygulamasi) — istege bagli

    private func claudeHazirla() async throws {
        if await Kabuk.komutVarMiAsync("claude") { return }
        try await nodeHazirla()
        adim = "Claude Code kuruluyor… (birkac dakika)"
        let r = await Kabuk.calistirAsync("npm install -g \(manifest.claude.npmPackage)", saniye: 1200)
        await npmGlobalBiniPathEkle()
        guard r.basarili, await Kabuk.komutVarMiAsync("claude") else {
            throw KurulumHatasi.claudeKurulamadi(String(r.ciktisi.suffix(300)))
        }
    }

    /// settings.json'in YALNIZ `env` blogu; diger anahtarlar kalir. Ilk yazimdan once birebir yedek.
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
        let yol = claudeKisayolYolu
        let betik = """
        #!/bin/sh
        # YapayZekaLab — Claude Code baslatici. Silmek zararsiz (claude zaten ayarli).
        exec claude "$@"
        """
        do {
            try FileManager.default.createDirectory(at: yol.deletingLastPathComponent(), withIntermediateDirectories: true)
            try betik.write(to: yol, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: yol.path)
        } catch { throw KurulumHatasi.yazilamadi(yol.path) }
    }

    /// settings.json'daki env ile Claude Code'un BIZE gittigini kanitlar. IZOLE (gecici CLAUDE_CONFIG_DIR).
    private func claudeDogrula() async throws {
        let gecici = NSTemporaryDirectory() + "yzlab-claude-dogrula-" + UUID().uuidString
        let fm = FileManager.default
        try? fm.createDirectory(atPath: gecici + "/cfg", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: gecici) }
        do { try fm.copyItem(at: claudeAyarYolu, to: URL(fileURLWithPath: gecici + "/cfg/" + manifest.claude.settingsFile)) }
        catch { throw KurulumHatasi.yazilamadi("dogrulama kopyasi: \(error.localizedDescription)") }

        let r = await Kabuk.calistirAsync(
            "cd '\(gecici)' && CLAUDE_CONFIG_DIR='\(gecici)/cfg' \(Kabuk.komut("claude")) -p 'Sadece ok yaz' --model '\(dogrulamaModeli)' --output-format json 2>&1 | tail -c 4000",
            saniye: 180, env: ["CLAUDE_CONFIG_DIR": gecici + "/cfg"])
        let c = r.ciktisi
        if Kurucu.yetkiReddiMi(c) { throw KurulumHatasi.anahtarGecersiz(401) }
        guard c.contains("\"stop_reason\"") || c.contains("\"result\""), !c.contains("\"is_error\":true") else {
            throw KurulumHatasi.claudeKurulamadi("dogrulama yaniti beklenmedik:\n" + String(c.suffix(300)))
        }
        let icerik = (try? fm.contentsOfDirectory(atPath: gecici + "/cfg")) ?? []
        guard icerik.contains(where: { $0 == ".claude.json" || $0 == "projects" || $0 == "sessions" }) else {
            throw KurulumHatasi.claudeKurulamadi("dogrulama izole kosmadi (CLAUDE_CONFIG_DIR ezildi?)")
        }
    }

    // MARK: - Geri al

    /// `kisayollar: false` → HOME'a bagli kisayollara dokunulmaz (--selftest bunu kullanir).
    func geriAl(kisayollar: Bool = true) {
        geriAlHatalari = []
        let fm = FileManager.default

        if let d = fm.contents(atPath: yedekYolu.path),
           let yedek = try? JSONDecoder().decode(CodexAyar.Yedek.self, from: d) {
            let mevcut = fm.contents(atPath: ayarYolu.path).flatMap { String(data: $0, encoding: .utf8) }
            do {
                if let eski = CodexAyar.geriAl(mevcut, yedek) {
                    try Data(eski.utf8).write(to: ayarYolu, options: .atomic)
                } else if fm.fileExists(atPath: ayarYolu.path) {
                    try fm.removeItem(at: ayarYolu)
                }
                try fm.removeItem(at: yedekYolu)
            } catch { geriAlHatalari.append("config.toml: \(error.localizedDescription)") }
        }

        do { try authGeriKoy() } catch { geriAlHatalari.append("auth.json: \(error.localizedDescription)") }

        for u in [katalogYolu, eskiProfilYolu] where fm.fileExists(atPath: u.path) {
            do { try fm.removeItem(at: u) } catch { geriAlHatalari.append("\(u.lastPathComponent): \(error.localizedDescription)") }
        }

        claudeGeriAl(kisayol: kisayollar)
        adim = geriAlHatalari.isEmpty
            ? "Geri alindi. Codex ve Claude Code ayarlarin kurulumdan onceki haline dondu."
            : "Geri alma eksik kaldi: " + geriAlHatalari.joined(separator: "; ")
    }

    func claudeGeriAl(kisayol: Bool = true) {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: claudeYedekYolu.path) {
                let veri = try Data(contentsOf: claudeYedekYolu)
                try veri.write(to: claudeAyarYolu, options: .atomic)
                try fm.removeItem(at: claudeYedekYolu)
            } else if fm.fileExists(atPath: claudeYokIsareti.path) {
                if fm.fileExists(atPath: claudeAyarYolu.path) { try fm.removeItem(at: claudeAyarYolu) }
                try fm.removeItem(at: claudeYokIsareti)
            }
        } catch { geriAlHatalari.append("claude settings: \(error.localizedDescription)") }
        if kisayol, fm.fileExists(atPath: claudeKisayolYolu.path) {
            do { try fm.removeItem(at: claudeKisayolYolu) } catch { geriAlHatalari.append("claude kisayol: \(error.localizedDescription)") }
        }
    }
}
