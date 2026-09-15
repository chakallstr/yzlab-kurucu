import Foundation

/// Bassiz (headless) kurulum:
///   YzlabKurucu --kur --anahtar yzk_live_… [--model id] [--claude 0|1] [--anahtar-giris 0|1] [--codex-kapat 0|1]
/// Anahtar `YZLAB_ANAHTAR` ortam degiskeninden de alinabilir (CI loglarina dusmesin diye).
/// `--codex-kapat 1`: Codex masaustu aciksa kapatip kurulumdan sonra yeniden acar (yoksa hata verir).
/// `--geri-al` kurulumu geri alir. Cikis kodu: 0 basari, 1 hata, 2 kullanim hatasi.
enum KomutSatiri {
    static func deger(_ ad: String, _ argv: [String]) -> String? {
        guard let i = argv.firstIndex(of: ad), i + 1 < argv.count else { return nil }
        return argv[i + 1]
    }

    static func calistir(_ argv: [String]) -> Never {
        Task { @MainActor in
            let (m, canli) = await Manifest.load()
            print("manifest: \(canli ? "canli" : "gomulu") (sema v\(m.schemaVersion))")
            let k = Kurucu(manifest: m)
            k.bildirici = { print("› \($0)") }
            print("codex dizini: \(k.codexDizini.path)")

            if argv.contains("--geri-al") {
                print("claude dizini: \(k.claudeDizini.path)")
                k.geriAl()
                if !k.geriAlHatalari.isEmpty { print("✗ \(k.adim)"); exit(1) }
                print("✓ \(k.adim)")
                exit(0)
            }

            let env = ProcessInfo.processInfo.environment
            guard let anahtar = deger("--anahtar", argv) ?? env["YZLAB_ANAHTAR"],
                  !anahtar.isEmpty else {
                print("kullanim: --kur --anahtar <yzk_live_…> [--model <id>] [--claude 0|1] [--anahtar-giris 0|1] [--codex-kapat 0|1]")
                print("          (anahtar YZLAB_ANAHTAR ortam degiskeninden de okunur)")
                exit(2)
            }
            let modelId = deger("--model", argv) ?? m.codex.defaultModel
            guard let model = m.codex.models.first(where: { $0.id == modelId }) else {
                print("bilinmeyen model: \(modelId) — secenekler: \(m.codex.models.map(\.id).joined(separator: ", "))")
                exit(2)
            }
            let claude = (deger("--claude", argv) ?? "0") != "0"
            let anahtarGiris = (deger("--anahtar-giris", argv) ?? "0") != "0"
            let kapat = (deger("--codex-kapat", argv) ?? "0") != "0"
            if claude { print("claude dizini: \(k.claudeDizini.path)") }

            do {
                try await k.kur(anahtar: anahtar, model: model, claude: claude,
                                anahtarGiris: anahtarGiris, codexKapatIzni: kapat)
                print("✓ kuruldu: \(k.ayarYolu.path) (\(anahtarGiris ? "anahtarla giris" : "ChatGPT girisi korundu"))")
                if claude { print("✓ claude code: \(k.claudeAyarYolu.path)") }
                exit(0)
            } catch {
                print("✗ \(error.localizedDescription)")
                exit(1)
            }
        }
        dispatchMain()
    }
}
