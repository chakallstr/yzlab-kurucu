import Foundation

struct Sonuc {
    let cikisKodu: Int32
    let ciktisi: String
    var basarili: Bool { cikisKodu == 0 }
}

enum Kabuk {
    /// Codex'i login-shell PATH'iyle arar. Kullanicinin nvm/homebrew/npm-prefix
    /// kurulumu yalnizca login shell'de PATH'te olabilir — GUI uygulamasi onu gormez.
    static let loginPath: String = {
        #if DEBUG
        // Yalniz DEBUG: "codex yok" yolunu bu makinede test edebilmek icin PATH daraltilabilir.
        if let p = ProcessInfo.processInfo.environment["YZLAB_LOGIN_PATH"], !p.isEmpty { return p }
        #endif
        return "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }()

    @discardableResult
    static func calistir(_ komut: String, saniye: Double = 120, env ekEnv: [String: String] = [:],
                         sadeceStdout: Bool = false) -> Sonuc {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        var loginKabuk = true
        #if DEBUG
        // Test kancasi: PATH daraltildiysa /etc/zprofile (path_helper) de devreye girmesin.
        if ProcessInfo.processInfo.environment["YZLAB_LOGIN_PATH"]?.isEmpty == false { loginKabuk = false }
        #endif
        p.arguments = [loginKabuk ? "-lc" : "-c", komut]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = loginPath + ":" + (env["PATH"] ?? "")
        for (k, v) in ekEnv { env[k] = v }
        p.environment = env

        // ⚠️ stdin KAPALI olmali: `codex exec` stdin bir boru/terminal ise
        // "Reading additional input from stdin..." deyip EOF bekler ve ASILI KALIR.
        p.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        p.standardOutput = pipe
        // Varsayilan: stdout+stderr birlikte (hata mesajlari musteriye gosterilir).
        // sadeceStdout: kullanicinin login kabugu stderr'e gurultu basarsa (bozuk
        // .zprofile, nvm uyarisi) DEGER olarak okunmasin diye stderr atilir.
        p.standardError = sadeceStdout ? FileHandle.nullDevice : pipe

        do { try p.run() } catch {
            return Sonuc(cikisKodu: 127, ciktisi: "calistirilamadi: \(error.localizedDescription)")
        }

        // Ciktiyi ARKA PLANDA oku: boru dolarsa (64 KB) surec bloklanir, biz de
        // waitUntilExit'te sonsuza kadar bekleriz.
        var data = Data()
        let okuma = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            okuma.signal()
        }

        // macOS'ta `timeout` yok — kendi zaman asimimizi kuruyoruz.
        let bitti = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { p.waitUntilExit(); bitti.signal() }
        if bitti.wait(timeout: .now() + saniye) == .timedOut {
            p.terminate()
            _ = okuma.wait(timeout: .now() + 5)
            return Sonuc(cikisKodu: 124, ciktisi: "zaman asimi (\(Int(saniye)) sn)")
        }

        okuma.wait()
        return Sonuc(cikisKodu: p.terminationStatus,
                     ciktisi: String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    static func varMi(_ komut: String) -> Bool {
        calistir("command -v \(komut) >/dev/null 2>&1", saniye: 15).basarili
    }
}
