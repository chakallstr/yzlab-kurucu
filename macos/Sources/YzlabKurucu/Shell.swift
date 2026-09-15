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

    /// Kurulum sirasinda kesfedilen ek PATH (npm global bin). Bkz. Kurucu.npmGlobalBiniPathEkle.
    static var ekPath: String = ""

    /// Komut: kullanicinin .zshenv'i PATH'i EZEBILIR (olculdu) → npm bin dizinini
    /// biliyorsak TAM YOLLA cagiririz, PATH'e guvenmeyiz.
    static func komut(_ ad: String) -> String {
        let tam = ekPath + "/" + ad
        if !ekPath.isEmpty, FileManager.default.isExecutableFile(atPath: tam) { return "'" + tam + "'" }
        return ad
    }

    static func komutVarMi(_ ad: String) -> Bool {
        if !ekPath.isEmpty, FileManager.default.isExecutableFile(atPath: ekPath + "/" + ad) { return true }
        return varMi(ad)
    }

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
        env["PATH"] = (ekPath.isEmpty ? "" : ekPath + ":") + loginPath + ":" + (env["PATH"] ?? "")
        for (k, v) in ekEnv { env[k] = v }
        p.environment = env

        // ⚠️ stdin KAPALI olmali: `codex exec` / `claude -p` stdin bir boru/terminal ise
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

    /// Ayni sey, ama ana is parcacigini BLOKLAMADAN (SwiftUI penceresi donmasin;
    /// npm install dakikalar, codex exec / claude -p 5-20 sn surer).
    static func calistirAsync(_ komut: String, saniye: Double = 120, env ekEnv: [String: String] = [:],
                              sadeceStdout: Bool = false) async -> Sonuc {
        await Task.detached(priority: .userInitiated) {
            calistir(komut, saniye: saniye, env: ekEnv, sadeceStdout: sadeceStdout)
        }.value
    }

    static func varMiAsync(_ komut: String) async -> Bool {
        await Task.detached { varMi(komut) }.value
    }

    static func komutVarMiAsync(_ ad: String) async -> Bool {
        await Task.detached { komutVarMi(ad) }.value
    }

    static func varMi(_ komut: String) -> Bool {
        calistir("command -v \(komut) >/dev/null 2>&1", saniye: 15).basarili
    }
}
