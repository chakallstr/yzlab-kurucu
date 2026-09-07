import Foundation

struct Sonuc {
    let cikisKodu: Int32
    let ciktisi: String
    var basarili: Bool { cikisKodu == 0 }
}

enum Kabuk {
    /// Codex'i login-shell PATH'iyle arar. Kullanicinin nvm/homebrew/npm-prefix
    /// kurulumu yalnizca login shell'de PATH'te olabilir — GUI uygulamasi onu gormez.
    static let loginPath = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    @discardableResult
    static func calistir(_ komut: String, saniye: Double = 120) -> Sonuc {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", komut]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = loginPath + ":" + (env["PATH"] ?? "")
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        do { try p.run() } catch {
            return Sonuc(cikisKodu: 127, ciktisi: "calistirilamadi: \(error.localizedDescription)")
        }

        // macOS'ta `timeout` yok — kendi zaman asimimizi kuruyoruz.
        let bitti = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { p.waitUntilExit(); bitti.signal() }
        if bitti.wait(timeout: .now() + saniye) == .timedOut {
            p.terminate()
            return Sonuc(cikisKodu: 124, ciktisi: "zaman asimi (\(Int(saniye)) sn)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return Sonuc(cikisKodu: p.terminationStatus,
                     ciktisi: String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    static func varMi(_ komut: String) -> Bool {
        calistir("command -v \(komut) >/dev/null 2>&1", saniye: 15).basarili
    }
}
