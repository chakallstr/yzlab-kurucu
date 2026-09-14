import Foundation

enum KurulumHatasi: LocalizedError {
    case anahtarGecersiz(Int)
    case agHatasi(String)
    case codexKurulamadi(String)
    case yazilamadi(String)

    var errorDescription: String? {
        switch self {
        case .anahtarGecersiz(401): return "Anahtar gecersiz veya iptal edilmis. Panelden yeni anahtar olustur."
        case .anahtarGecersiz(let k): return "Sunucu \(k) dondu. Birazdan tekrar dene."
        case .agHatasi(let d): return "Baglanti kurulamadi: \(d)"
        case .codexKurulamadi(let d): return "Codex kurulamadi: \(d)"
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

    var codexDizini: URL {
        // CODEX_HOME tanimliysa Codex config'i ORADAN okur; ~/.codex'e yazmak
        // sessizce hicbir sey yapmaz. (2026-08-06'da bu makinede olculdu.)
        if let h = ProcessInfo.processInfo.environment["CODEX_HOME"], !h.isEmpty {
            return URL(fileURLWithPath: (h as NSString).expandingTildeInPath)
        }
        // Login kabugundaki CODEX_HOME (GUI uygulamasi kullanicinin .zprofile'ini gormez).
        // YALNIZ stdout okunur ve deger bir yola benzemeli — kabuk gurultusu yol sanilmasin.
        let login = Kabuk.calistir("echo -n \"$CODEX_HOME\"", saniye: 15, sadeceStdout: true).ciktisi
        if !login.isEmpty, !login.contains("\n"), login.hasPrefix("/") || login.hasPrefix("~") {
            return URL(fileURLWithPath: (login as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    }

    var profilYolu: URL { codexDizini.appendingPathComponent(manifest.codex.profileFile) }
    var katalogYolu: URL { codexDizini.appendingPathComponent(manifest.codex.catalogFile) }
    var kisayolYolu: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/yzlab-codex")
    }

    var kuruluMu: Bool { FileManager.default.fileExists(atPath: profilYolu.path) }

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

    func kur(anahtar: String, model: Manifest.Model, kisayol: Bool) async throws {
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

        adim = "Dogrulaniyor…"
        try dogrula()

        adim = "Kuruldu"
    }

    /// Codex KURULUYSA hic dokunma — boylece musterinin Codex'i acik olsa bile
    /// dosya kilidi/guncelleme sorunu cikmaz, kapatmasi gerekmez.
    private func codexHazirla() async throws {
        if Kabuk.varMi("codex") { return }

        if !Kabuk.varMi("npm") {
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

        adim = "Codex CLI kuruluyor… (birkac dakika)"
        let r = Kabuk.calistir("npm install -g \(manifest.codex.npmPackage)", saniye: 1200)
        guard r.basarili, Kabuk.varMi("codex") else {
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
        Kurucu.surumAyikla(Kabuk.calistir("codex --version", saniye: 20).ciktisi)
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

    private func kisayolYaz() throws {
        let dizin = kisayolYolu.deletingLastPathComponent()
        let betik = """
        #!/bin/sh
        # YapayZekaLab — Codex baslatici. Silmek zararsiz.
        exec codex -p \(manifest.codex.profileName) "$@"
        """
        do {
            try FileManager.default.createDirectory(at: dizin, withIntermediateDirectories: true)
            try betik.write(to: kisayolYolu, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: kisayolYolu.path)
        } catch { throw KurulumHatasi.yazilamadi(kisayolYolu.path) }
    }

    /// Profilin gercekten yuklendigini ve BIZE gittigini kanitlar.
    ///
    /// IZOLE calisir: gecici bir CODEX_HOME'a yalniz bizim profil kopyalanir (katalog
    /// yolu gercek dosyaya bakar). Sebep: `codex exec` calistigi dizin icin config.toml'a
    /// `[projects.*] trust_level` YAZAR (0.153'te olculdu) — musterinin config.toml'una
    /// dokunmama sozunu bozmamak ve musterinin MCP sunucularini bosuna baslatmamak icin.
    private func dogrula() throws {
        let gecici = NSTemporaryDirectory() + "yzlab-dogrula-" + UUID().uuidString
        let fm = FileManager.default
        try? fm.createDirectory(atPath: gecici, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: gecici) }
        do {
            try fm.copyItem(at: profilYolu, to: URL(fileURLWithPath: gecici).appendingPathComponent(manifest.codex.profileFile))
        } catch { throw KurulumHatasi.yazilamadi("dogrulama kopyasi: \(error.localizedDescription)") }

        let r = Kabuk.calistir(
            "codex exec -p \(manifest.codex.profileName) --skip-git-repo-check -C '\(gecici)' 'ok' 2>&1 | tail -40",
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
    }

    // MARK: - Geri al

    func geriAl() {
        for u in [profilYolu, katalogYolu, kisayolYolu] {
            try? FileManager.default.removeItem(at: u)
        }
        adim = "Geri alindi. Codex ayarlarin kurulumdan onceki haline dondu."
    }
}
