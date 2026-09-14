import Foundation

/// Windows'taki SelfTest ile birebir ayni invaryantlar. Ag gerektiren adimlar
/// "bilgi" olarak gecer; kurulum mantigi (yazma/geri alma/dokunmama) SERT test edilir.
enum SelfTest {
    private static var gecen = 0, kalan = 0

    private static func kontrol(_ kosul: Bool, _ ad: String) {
        if kosul { gecen += 1; print("  PASS  \(ad)") } else { kalan += 1; print("  FAIL  \(ad)") }
    }

    @MainActor
    static func calistir() async -> Int32 {
        print("YzlabKurucu — kendi kendini sinama (macOS)\n")

        // 1) Gomulu manifest bozulmadan derlendi mi?
        let gomulu = Manifest.embedded
        kontrol(!gomulu.codex.models.isEmpty, "gomulu manifest cozuluyor")
        kontrol(!gomulu.codex.profileTemplate.isEmpty, "profil sablonu dolu")
        kontrol(gomulu.codex.models.contains { $0.id == gomulu.codex.defaultModel }, "varsayilan model listede var")
        kontrol(gomulu.codex.catalogUrl.hasPrefix("https://"), "katalog adresi https")

        // 2) Canli manifest + katalog (bilgi; sunucu manifesti veriyorsa katalog da GELMELI)
        let (canliM, canliMi) = await Manifest.load()
        print(canliMi ? "  bilgi canli manifest CEKILDI" : "  bilgi canli manifest YOK — gomuluye dusuldu")
        let kaynak = canliMi ? canliM : gomulu

        // 3) Surum ayiklama + katalog adresi yer tutucusu
        kontrol(Kurucu.surumAyikla("codex-cli 0.153.4") == "0.153.4", "codex surumu ayiklaniyor")
        kontrol(Kurucu.surumAyikla("hicbir sey") == nil, "surum yoksa nil")

        // 4) Izole bir CODEX_HOME kurup gercek yazma yolunu calistir.
        let gecici = NSTemporaryDirectory() + "yzlab-selftest-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: gecici, withIntermediateDirectories: true)
        setenv("CODEX_HOME", gecici, 1)
        defer { unsetenv("CODEX_HOME"); try? FileManager.default.removeItem(atPath: gecici) }

        let k = Kurucu(manifest: kaynak)
        kontrol(k.codexDizini.path == gecici, "CODEX_HOME dikkate aliniyor")
        let adres = k.katalogAdresi(surum: "0.153.4").absoluteString
        kontrol(!adres.contains("{{"), "katalog adresinde yer tutucu kalmadi")
        if kaynak.codex.catalogUrl.contains("{{CODEX_VERSION}}") {
            kontrol(adres.contains("client_version=0.153.4"), "katalog adresine codex surumu yazildi")
        }

        // ⚠️ EN ONEMLI INVARYANT: musterinin mevcut dosyalarina DOKUNMAMALIYIZ.
        let cfg = gecici + "/config.toml", auth = gecici + "/auth.json"
        try? "model = \"kendi-modelim\"\n".write(toFile: cfg, atomically: true, encoding: .utf8)
        try? "{\"auth_mode\":\"chatgpt\"}".write(toFile: auth, atomically: true, encoding: .utf8)
        let cfgOnce = try? String(contentsOfFile: cfg, encoding: .utf8)
        let authOnce = try? String(contentsOfFile: auth, encoding: .utf8)

        let model = kaynak.codex.models[0]
        do {
            try k.profiliYaz(anahtar: "yzk_live_TESTTESTTESTTEST", model: model)
            kontrol(true, "profil yazildi")
        } catch { kontrol(false, "profil yazildi: \(error)") }

        kontrol((try? String(contentsOfFile: cfg, encoding: .utf8)) == cfgOnce, "config.toml DEGISMEDI")
        kontrol((try? String(contentsOfFile: auth, encoding: .utf8)) == authOnce, "auth.json DEGISMEDI")
        kontrol(FileManager.default.fileExists(atPath: k.profilYolu.path), "profil dosyasi var")

        let profil = (try? String(contentsOfFile: k.profilYolu.path, encoding: .utf8)) ?? ""
        kontrol(!profil.contains("{{"), "sablonda doldurulmamis yer tutucu YOK")
        kontrol(profil.contains(model.id), "model yazildi")
        kontrol(profil.contains("yzk_live_TESTTESTTESTTEST"), "anahtar yazildi")
        kontrol(profil.contains(kaynak.api.baseUrl), "base_url yazildi")
        kontrol(profil.contains(kaynak.codex.tokenField), "token alani yazildi")
        let izin = (try? FileManager.default.attributesOfItem(atPath: k.profilYolu.path)[.posixPermissions] as? Int) ?? 0
        kontrol(izin == 0o600, "profil yalniz sahibi okur (0600)")

        k.geriAl()
        kontrol(!FileManager.default.fileExists(atPath: k.profilYolu.path), "geri al profili sildi")
        kontrol(FileManager.default.fileExists(atPath: cfg) && FileManager.default.fileExists(atPath: auth),
                "geri al musterinin dosyalarina dokunmadi")

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
        do { try kc.claudeAyarYaz(anahtar: "yzk_live_TESTTESTTESTTEST", modelId: "gpt-5.6-luna"); kontrol(true, "claude settings yazildi") }
        catch { kontrol(false, "claude settings yazildi: \(error)") }
        let yedek = (try? String(contentsOfFile: kc.claudeYedekYolu.path, encoding: .utf8)) ?? ""
        kontrol(yedek == orijinal, "claude yedek birebir")
        if let d = FileManager.default.contents(atPath: ayar),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let env = j["env"] as? [String: Any] {
            kontrol((j["permissions"] as? [String: Any]) != nil && (j["model"] as? String) == "x", "claude diger anahtarlar korundu")
            kontrol(env["FOO"] as? String == "bar", "claude env'deki yabanci anahtar korundu")
            kontrol(env["ANTHROPIC_API_KEY"] == nil, "claude kalinti ANTHROPIC_API_KEY silindi")
            kontrol(env["ANTHROPIC_AUTH_TOKEN"] as? String == "yzk_live_TESTTESTTESTTEST", "claude AUTH_TOKEN yazildi")
            kontrol(env["ANTHROPIC_BASE_URL"] as? String == kaynak.claude.baseUrl, "claude BASE_URL yazildi (kok, /v1 yok)")
            kontrol(env["ANTHROPIC_MODEL"] as? String == "gpt-5.6-luna", "claude MODEL yazildi")
            kontrol(env["ANTHROPIC_SMALL_FAST_MODEL"] as? String == kaynak.claude.smallFastModel, "claude SMALL_FAST_MODEL yazildi")
        } else { kontrol(false, "claude settings.json cozulemedi") }
        // Yeniden kur: yedek EZILMEMELI
        try? kc.claudeAyarYaz(anahtar: "yzk_live_IKINCI", modelId: "gpt-5.6-sol")
        kontrol(((try? String(contentsOfFile: kc.claudeYedekYolu.path, encoding: .utf8)) ?? "") == orijinal, "yeniden kurmak yedegi ezmedi")
        kc.claudeGeriAl()
        kontrol(((try? String(contentsOfFile: ayar, encoding: .utf8)) ?? "") == orijinal, "claude geri al orijinali birebir geri koydu")
        kontrol(!FileManager.default.fileExists(atPath: kc.claudeYedekYolu.path), "claude geri al yedegi kaldirdi")
        // settings.json HIC YOKKEN kur → geri al dosyayi siler
        try? FileManager.default.removeItem(atPath: ayar)
        try? kc.claudeAyarYaz(anahtar: "yzk_live_TESTTESTTESTTEST", modelId: "gpt-5.6-luna")
        kontrol(FileManager.default.fileExists(atPath: kc.claudeYokIsareti.path), "claude 'dosya yoktu' isareti")
        kc.claudeGeriAl()
        kontrol(!FileManager.default.fileExists(atPath: ayar), "claude geri al (dosya yoktu) dosyayi sildi")
        // Bozuk JSON → acik hata, dosyaya dokunma
        try? "{bozuk".write(toFile: ayar, atomically: true, encoding: .utf8)
        var bozukHata = false
        do { try kc.claudeAyarYaz(anahtar: "x", modelId: "y") } catch { bozukHata = true }
        kontrol(bozukHata && (try? String(contentsOfFile: ayar, encoding: .utf8)) == "{bozuk", "bozuk settings.json → hata, dosya dokunulmadi")

        // 6) Kabuk calisiyor mu (login PATH)?
        kontrol(Kabuk.calistir("echo merhaba", saniye: 10).ciktisi == "merhaba", "kabuk calisiyor")

        print("\n\(gecen) gecti, \(kalan) kaldi")
        return kalan == 0 ? 0 : 1
    }
}
