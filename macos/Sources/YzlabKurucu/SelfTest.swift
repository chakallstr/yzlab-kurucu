import Foundation

/// Windows'taki SelfTest ile ayni invaryantlar. Ag gerektiren adimlar "bilgi" olarak gecer;
/// kurulum mantigi (yazma/geri alma/dokunmama) SERT test edilir.
enum SelfTest {
    private static var gecen = 0, kalan = 0

    private static func kontrol(_ kosul: Bool, _ ad: String) {
        if kosul { gecen += 1; print("  PASS  \(ad)") } else { kalan += 1; print("  FAIL  \(ad)") }
    }

    private static func oku(_ p: String) -> String { (try? String(contentsOfFile: p, encoding: .utf8)) ?? "" }
    private static func var_(_ p: String) -> Bool { FileManager.default.fileExists(atPath: p) }

    @MainActor
    static func calistir() async -> Int32 {
        print("YzlabKurucu — kendi kendini sinama (macOS)\n")

        // 1) Gomulu manifest bozulmadan derlendi mi?
        let gomulu = Manifest.embedded
        kontrol(!gomulu.codex.models.isEmpty, "gomulu manifest cozuluyor")
        kontrol(!gomulu.codex.profileTemplate.isEmpty, "profil sablonu dolu")
        kontrol(gomulu.codex.models.contains { $0.id == gomulu.codex.defaultModel }, "varsayilan model listede var")
        kontrol(gomulu.codex.catalogUrl.hasPrefix("https://"), "katalog adresi https")

        // 2) Canli manifest
        let (canliM, canliMi) = await Manifest.load()
        print(canliMi ? "  bilgi canli manifest CEKILDI" : "  bilgi canli manifest YOK — gomuluye dusuldu")
        let kaynak = canliMi ? canliM : gomulu

        // 3) Saf yardimcilar
        kontrol(Kurucu.surumAyikla("codex-cli 0.153.4") == "0.153.4", "codex surumu ayiklaniyor")
        kontrol(Kurucu.surumAyikla("nvm uyarisi 1.2.3\ncodex-cli 0.153.4") == "0.153.4", "gurultu icinde codex-cli satiri tercih edildi")
        kontrol(Kurucu.surumAyikla("hicbir sey") == nil, "surum yoksa nil")
        kontrol(!Kurucu.yetkiReddiMi("tokens used\n8.401\nok"), "401 iceren token sayisi ret sayilmadi")
        kontrol(!Kurucu.yetkiReddiMi("{\"duration_api_ms\":3401,\"stop_reason\":\"end_turn\"}"), "401 iceren sure ret sayilmadi")
        kontrol(Kurucu.yetkiReddiMi("401 Unauthorized: API anahtarı geçersiz veya iptal edilmiş, url: x"), "gercek codex 401 yakalandi")
        kontrol(Kurucu.yetkiReddiMi("error: HTTP 401"), "HTTP 401 yakalandi")
        kontrol(Kurucu.akisSatiri("data: {\"type\":\"response.completed\",\"response\":{}}") == .tamam, "akis: completed = tamam")
        kontrol(Kurucu.akisSatiri("event: response.completed") == .devam, "akis: event satiri atlandi")
        kontrol(Kurucu.akisSatiri("data: {\"type\":\"response.output_text.delta\",\"delta\":\"ok\"}") == .devam, "akis: delta = devam")
        kontrol(Kurucu.akisSatiri("data: {\"type\": \"error\", \"error\": {\"message\": \"Store must be set to false\"}}") == .hata("Store must be set to false"),
                "akis: error olayi = hata (mesajiyla)")
        kontrol(Kurucu.akisSatiri("data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"message\":\"x\"}}}") == .hata("x"),
                "akis: response.failed = hata")

        // 4) Izole CODEX_HOME'da GERCEK yazma yolu: config.toml birlestirme + iki giris modu + geri al
        let gecici = NSTemporaryDirectory() + "yzlab-selftest-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: gecici, withIntermediateDirectories: true)
        setenv("CODEX_HOME", gecici, 1)
        defer { unsetenv("CODEX_HOME"); try? FileManager.default.removeItem(atPath: gecici) }

        let k = Kurucu(manifest: kaynak)
        kontrol(k.codexDizini.path == gecici, "CODEX_HOME dikkate aliniyor")
        let adres = k.katalogAdresi(surum: "0.153.4").absoluteString
        kontrol(!adres.contains("{{"), "katalog adresinde yer tutucu kalmadi")

        let cfg = gecici + "/config.toml", auth = gecici + "/auth.json"
        let cfgOnce = "model = \"kendi-modelim\"\nnotify = [\"x\"]\n\n[mcp_servers.foo]\ncommand = \"bar\"\n"
        let authOnce = "{\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"x\"}}"
        try? cfgOnce.write(toFile: cfg, atomically: true, encoding: .utf8)
        try? authOnce.write(toFile: auth, atomically: true, encoding: .utf8)
        try? "eski profil".write(toFile: k.eskiProfilYolu.path, atomically: true, encoding: .utf8)

        let model = kaynak.codex.models[0]
        let anahtar = "yzk_live_TESTTESTTESTTEST"
        do { try k.codexAyariYaz(anahtar: anahtar, model: model, anahtarGiris: false); kontrol(true, "codex ayari yazildi (hesap modu)") }
        catch { kontrol(false, "codex ayari yazildi (hesap modu): \(error)") }

        let y1 = oku(cfg)
        kontrol(CodexAyar.dogrula(y1) == nil, "config.toml gecerli (\(CodexAyar.dogrula(y1) ?? "ok"))")
        kontrol(y1.contains("model_provider = \"yapayzekalab\"") && y1.contains("experimental_bearer_token = \"\(anahtar)\""),
                "saglayici + anahtar ana config'e yazildi (masaustu okur)")
        kontrol(y1.contains("model = \"\(model.id)\"") && !y1.contains("kendi-modelim"), "model yazildi, eski model yedekte")
        kontrol(y1.contains("[mcp_servers.foo]") && y1.contains("notify = [\"x\"]"), "musterinin diger ayarlari korundu")
        kontrol(!y1.contains("{{") && !y1.contains("[tools]"), "yer tutucu yok, [tools] eklenmedi")
        kontrol(!y1.contains("requires_openai_auth"), "hesap modu: requires_openai_auth YOK")
        kontrol(oku(auth) == authOnce, "hesap modu: auth.json DEGISMEDI (ChatGPT girisi durur)")
        kontrol(var_(k.yedekYolu.path) && var_(k.ayarAnlikYedekYolu.path), "yedek json + tam kopya yazildi")
        kontrol(!var_(k.eskiProfilYolu.path), "v0.1 profil kalintisi temizlendi")
        let izin = (try? FileManager.default.attributesOfItem(atPath: cfg)[.posixPermissions] as? Int) ?? 0
        kontrol(izin == 0o600, "config.toml yalniz sahibi okur (0600)")
        kontrol(k.kuruluMu, "kuruluMu dogru")

        // Anahtarla giris modu
        try? k.codexAyariYaz(anahtar: anahtar, model: model, anahtarGiris: true)
        let authJ = (try? JSONSerialization.jsonObject(with: Data(oku(auth).utf8)) as? [String: Any]) ?? [:]
        kontrol(authJ["auth_mode"] as? String == "apikey" && authJ["OPENAI_API_KEY"] as? String == anahtar,
                "anahtar modu: auth.json apikey")
        kontrol(oku(k.authYedekYolu.path) == authOnce, "anahtar modu: auth.json yedegi birebir")
        let y2 = oku(cfg)
        kontrol(y2.contains("requires_openai_auth = true") && CodexAyar.dogrula(y2) == nil, "anahtar modu: requires_openai_auth eklendi, dosya gecerli")

        // Hesap moduna geri donus
        try? k.codexAyariYaz(anahtar: anahtar, model: model, anahtarGiris: false)
        kontrol(oku(auth) == authOnce && !var_(k.authYedekYolu.path), "hesap moduna donus: ChatGPT girisi geri geldi")
        kontrol(!oku(cfg).contains("requires_openai_auth"), "hesap moduna donus: requires_openai_auth kalkti")

        // Geri al
        try? k.codexAyariYaz(anahtar: anahtar, model: model, anahtarGiris: true)
        k.geriAl(kisayollar: false)
        kontrol(CodexAyarTest.kume(oku(cfg)) == CodexAyarTest.kume(cfgOnce), "geri al: config.toml onceki satirlar")
        kontrol(oku(auth) == authOnce, "geri al: auth.json ayni")
        kontrol(!var_(k.yedekYolu.path) && !var_(k.authYedekYolu.path), "geri al: yedekler temizlendi")
        kontrol(k.geriAlHatalari.isEmpty, "geri al: hata yok")

        // Dosya yokken
        try? FileManager.default.removeItem(atPath: cfg)
        try? k.codexAyariYaz(anahtar: anahtar, model: model, anahtarGiris: false)
        kontrol(CodexAyar.dogrula(oku(cfg)) == nil, "config.toml yokken gecerli dosya olustu")
        k.geriAl(kisayollar: false)
        kontrol(!var_(cfg), "geri al: dosya yoktuysa silindi")

        // 5) Claude Code settings.json birlestirme + yedek + geri al (izole CLAUDE_CONFIG_DIR)
        let cdir = gecici + "/claude"
        try? FileManager.default.createDirectory(atPath: cdir, withIntermediateDirectories: true)
        setenv("CLAUDE_CONFIG_DIR", cdir, 1)
        defer { unsetenv("CLAUDE_CONFIG_DIR") }
        let kc = Kurucu(manifest: kaynak)
        kontrol(kc.claudeDizini.path == cdir, "CLAUDE_CONFIG_DIR dikkate aliniyor")
        let ayar = cdir + "/" + kaynak.claude.settingsFile
        let orijinal = "{\n  \"permissions\": {\"allow\": [\"Bash\"]},\n  \"env\": {\"ANTHROPIC_API_KEY\": \"sk-eski\", \"FOO\": \"bar\"},\n  \"model\": \"x\"\n}\n"
        try? orijinal.write(toFile: ayar, atomically: true, encoding: .utf8)
        do { try kc.claudeAyarYaz(anahtar: anahtar, modelId: "gpt-5.6-luna"); kontrol(true, "claude settings yazildi") }
        catch { kontrol(false, "claude settings yazildi: \(error)") }
        kontrol(oku(kc.claudeYedekYolu.path) == orijinal, "claude yedek birebir")
        if let d = FileManager.default.contents(atPath: ayar),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let env = j["env"] as? [String: Any] {
            kontrol((j["permissions"] as? [String: Any]) != nil && (j["model"] as? String) == "x", "claude diger anahtarlar korundu")
            kontrol(env["FOO"] as? String == "bar", "claude env'deki yabanci anahtar korundu")
            kontrol(env["ANTHROPIC_API_KEY"] == nil, "claude kalinti ANTHROPIC_API_KEY silindi")
            kontrol(env["ANTHROPIC_AUTH_TOKEN"] as? String == anahtar, "claude AUTH_TOKEN yazildi")
            kontrol(env["ANTHROPIC_BASE_URL"] as? String == kaynak.claude.baseUrl, "claude BASE_URL yazildi (kok, /v1 yok)")
            kontrol(env["ANTHROPIC_MODEL"] as? String == "gpt-5.6-luna", "claude MODEL yazildi")
        } else { kontrol(false, "claude settings.json cozulemedi") }
        try? kc.claudeAyarYaz(anahtar: "yzk_live_IKINCI", modelId: "gpt-5.6-sol")
        kontrol(oku(kc.claudeYedekYolu.path) == orijinal, "yeniden kurmak yedegi ezmedi")
        kc.claudeGeriAl(kisayol: false)
        kontrol(oku(ayar) == orijinal, "claude geri al orijinali birebir geri koydu")
        try? FileManager.default.removeItem(atPath: ayar)
        try? kc.claudeAyarYaz(anahtar: anahtar, modelId: "gpt-5.6-luna")
        kontrol(var_(kc.claudeYokIsareti.path), "claude 'dosya yoktu' isareti")
        kc.claudeGeriAl(kisayol: false)
        kontrol(!var_(ayar), "claude geri al (dosya yoktu) dosyayi sildi")
        try? "{bozuk".write(toFile: ayar, atomically: true, encoding: .utf8)
        var bozukHata = false
        do { try kc.claudeAyarYaz(anahtar: "x", modelId: "y") } catch { bozukHata = true }
        kontrol(bozukHata && oku(ayar) == "{bozuk", "bozuk settings.json → hata, dosya dokunulmadi")

        // 5b) config.toml isaretli blok birlestirici
        CodexAyarTest.calistir { kontrol($0, $1) }

        // 6) Kabuk calisiyor mu?
        kontrol(Kabuk.calistir("echo merhaba", saniye: 10).ciktisi == "merhaba", "kabuk calisiyor")

        print("\n\(gecen) gecti, \(kalan) kaldi")
        return kalan == 0 ? 0 : 1
    }
}
