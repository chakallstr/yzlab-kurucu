import Foundation

/// Bassiz (headless) kurulum:
///   YzlabKurucu --kur --anahtar yzk_live_… [--model id] [--kisayol 0|1] [--claude 0|1]
/// Anahtar `YZLAB_ANAHTAR` ortam degiskeninden de alinabilir (CI loglarina dusmesin diye).
/// `--geri-al` kurulumu siler (Codex + Claude Code). Cikis kodu: 0 basari, 1 hata, 2 kullanim hatasi.
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
            print("claude dizini: \(k.claudeDizini.path)")

            if argv.contains("--geri-al") {
                k.geriAl()
                if !k.geriAlHatalari.isEmpty { print("✗ \(k.adim)"); exit(1) }
                print("✓ \(k.adim)")
                exit(0)
            }

            let env = ProcessInfo.processInfo.environment
            guard let anahtar = deger("--anahtar", argv) ?? env["YZLAB_ANAHTAR"],
                  !anahtar.isEmpty else {
                print("kullanim: --kur --anahtar <yzk_live_…> [--model <id>] [--kisayol 0|1] [--claude 0|1]")
                print("          (anahtar YZLAB_ANAHTAR ortam degiskeninden de okunur)")
                exit(2)
            }
            let modelId = deger("--model", argv) ?? m.codex.defaultModel
            guard let model = m.codex.models.first(where: { $0.id == modelId }) else {
                print("bilinmeyen model: \(modelId) — secenekler: \(m.codex.models.map(\.id).joined(separator: ", "))")
                exit(2)
            }
            let kisayol = (deger("--kisayol", argv) ?? "1") != "0"
            let claude = (deger("--claude", argv) ?? "1") != "0"

            do {
                try await k.kur(anahtar: anahtar, model: model, kisayol: kisayol, claude: claude)
                print("✓ kuruldu: \(k.profilYolu.path)")
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
