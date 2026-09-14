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

        // 5) Kabuk calisiyor mu (login PATH)?
        kontrol(Kabuk.calistir("echo merhaba", saniye: 10).ciktisi == "merhaba", "kabuk calisiyor")

        print("\n\(gecen) gecti, \(kalan) kaldi")
        return kalan == 0 ? 0 : 1
    }
}
