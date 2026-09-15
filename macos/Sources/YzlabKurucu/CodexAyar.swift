import Foundation

/// Codex `config.toml`'a YapayZekaLab yönlendirmesini İŞARETLİ bloklarla ekler / kaldırır.
///
/// NEDEN PROFİL DEĞİL: Codex MASAÜSTÜ uygulaması `-p yzlab` profilini okumaz. 2026-09-15 müşteri
/// kamer5561: kurucu "Kuruldu" dedi (testi profil üzerinden bize geldi) ama masaüstü kendi ChatGPT
/// hesabıyla gitti → "hakkınız yok". Sahibin ÇALIŞAN masaüstü kurulumu da ana config.toml'da
/// `model_provider = "yapayzekalab"` + `[model_providers.yapayzekalab]` (experimental_bearer_token)
/// kullanıyor; auth.json'daki ChatGPT girişi duruyor. Bu modül tam olarak onu yazar.
///
/// Saf metin işlemi (dosya G/Ç yok). Windows karşılığı `CodexAyar.cs` BİREBİR aynı kurallar.
enum CodexAyar {
    static let ustBas = "# >>> YapayZekaLab kurucu: ust ayarlar (Geri Al kaldirir; elle degistirme)"
    static let ustSon = "# <<< YapayZekaLab kurucu: ust ayarlar"
    static let sagBas = "# >>> YapayZekaLab kurucu: saglayici"
    static let sagSon = "# <<< YapayZekaLab kurucu: saglayici"
    static let saglayici = "yapayzekalab"

    /// Kurulumdan ÖNCE dosyada olup bizim kaldırdığımız şeyler. Geri Al bunları geri koyar.
    struct Yedek: Codable, Equatable {
        var dosyaYoktu: Bool
        var ustSatirlar: [String]
        var saglayiciBlogu: [String]
        var yonetilenAnahtarlar: [String]
    }

    /// Manifestteki (doldurulmuş) şablondan çıkarılan parçalar.
    struct Sablon: Equatable {
        var ustSatirlar: [String]
        var anahtarlar: [String]
        var saglayiciSatirlar: [String]
    }

    // MARK: - Satır yardımcıları

    static func satirlaraAyir(_ metin: String) -> (satirlar: [String], nl: String) {
        var s = metin
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        let nl = s.contains("\r\n") ? "\r\n" : "\n"
        var parca = s.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if parca.last == "" { parca.removeLast() }
        return (parca, nl)
    }

    static func bosMu(_ l: String) -> Bool { l.trimmingCharacters(in: .whitespaces).isEmpty }
    static func basliMi(_ l: String) -> Bool { l.trimmingCharacters(in: .whitespaces).hasPrefix("[") }

    /// `anahtar = deger` satırının anahtarı (yorum/başlık/boş satırda nil).
    static func anahtar(_ l: String) -> String? {
        let t = l.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.hasPrefix("#"), !t.hasPrefix("["), let e = t.firstIndex(of: "=") else { return nil }
        var k = t[..<e].trimmingCharacters(in: .whitespaces)
        if k.count >= 2, (k.hasPrefix("\"") && k.hasSuffix("\"")) || (k.hasPrefix("'") && k.hasSuffix("'")) {
            k = String(k.dropFirst().dropLast())
        }
        return k.isEmpty ? nil : k
    }

    /// `[ model_providers . "yapayzekalab" ]` → `model_providers.yapayzekalab` (boşluk/tırnak atılır).
    static func baslikAdi(_ l: String) -> String? {
        let t = l.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("["), let kapa = t.lastIndex(of: "]") else { return nil }
        let ic = String(t[t.startIndex...kapa]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return ic.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
    }

    static func saglayiciBasligiMi(_ l: String) -> Bool {
        guard let ad = baslikAdi(l) else { return false }
        return ad == "model_providers.\(saglayici)" || ad.hasPrefix("model_providers.\(saglayici).")
    }

    /// Bizim işaretli bloklarımızı (başlangıç..bitiş dahil) atar. Sonu olmayan işaret → yalnız o satır.
    static func isaretlileriSil(_ L: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < L.count {
            let t = L[i].trimmingCharacters(in: .whitespaces)
            if t == ustBas || t == sagBas {
                let son = (t == ustBas) ? ustSon : sagSon
                if let j = L[(i + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == son }) {
                    i = j + 1
                    continue
                }
                i += 1
                continue
            }
            if t == ustSon || t == sagSon { i += 1; continue }
            out.append(L[i])
            i += 1
        }
        return out
    }

    /// Yönetilen üst anahtarları ve yapayzekalab sağlayıcı tablolarını ayıklar (işaret DIŞINDA olsalar da).
    static func ayikla(_ L: [String], anahtarlar: Set<String>)
        -> (ust: [String], kalan: [String], yUst: [String], ySag: [String]) {
        let ilk = L.firstIndex(where: basliMi) ?? L.count
        var ust: [String] = [], yUst: [String] = []
        for l in L[..<ilk] {
            if let k = anahtar(l), anahtarlar.contains(k) { yUst.append(l) } else { ust.append(l) }
        }
        var kalan: [String] = [], ySag: [String] = []
        var siliyor = false
        for l in L[ilk...] {
            if basliMi(l) { siliyor = saglayiciBasligiMi(l) }
            if siliyor { ySag.append(l) } else { kalan.append(l) }
        }
        while let s = ySag.last, bosMu(s) { ySag.removeLast() }
        while let f = ust.first, bosMu(f) { ust.removeFirst() }
        return (ust, kalan, yUst, ySag)
    }

    // MARK: - Şablon

    /// Doldurulmuş profil şablonunu üst anahtarlara + sağlayıcı tablosuna ayırır.
    /// `[tools]` gibi DİĞER tablolar ALINMAZ: müşterinin kendi tablosuyla çakışıp TOML'u bozar.
    static func sablonuAyir(_ dolu: String) -> Sablon {
        let L = satirlaraAyir(dolu).satirlar
        var ust: [String] = [], anah: [String] = [], sag: [String] = []
        var baslikGoruldu = false, saglayicida = false
        for l in L {
            if basliMi(l) {
                baslikGoruldu = true
                saglayicida = saglayiciBasligiMi(l)
                if saglayicida { sag.append(l.trimmingCharacters(in: .whitespaces)) }
                continue
            }
            let t = l.trimmingCharacters(in: .whitespaces)
            if !baslikGoruldu {
                if let k = anahtar(l) { ust.append(t); anah.append(k) }
            } else if saglayicida, !t.isEmpty, !t.hasPrefix("#") {
                sag.append(t)
            }
        }
        return Sablon(ustSatirlar: ust, anahtarlar: anah, saglayiciSatirlar: sag)
    }

    // MARK: - Uygula / Geri al / Doğrula

    /// `mevcut` nil → dosya yoktu. Dönen `yedek` bu çağrıda kaldırılanlardır; çağıran İLK kurulumun
    /// yedeğini korumalıdır (yeniden kurmak yedeği ezmesin).
    static func uygula(_ mevcut: String?, _ sablon: Sablon) -> (metin: String, yedek: Yedek) {
        let (ham, nl) = satirlaraAyir(mevcut ?? "")
        let a = ayikla(isaretlileriSil(ham), anahtarlar: Set(sablon.anahtarlar))
        var out = [ustBas] + sablon.ustSatirlar + [ustSon]
        let govde = a.ust + a.kalan
        if !govde.isEmpty { out.append(""); out += govde }
        while let s = out.last, bosMu(s) { out.removeLast() }
        out += ["", sagBas] + sablon.saglayiciSatirlar + [sagSon]
        let yedek = Yedek(dosyaYoktu: mevcut == nil, ustSatirlar: a.yUst,
                          saglayiciBlogu: a.ySag, yonetilenAnahtarlar: sablon.anahtarlar)
        return (out.joined(separator: nl) + nl, yedek)
    }

    /// Kurulum öncesine döner. nil → dosya kurulumdan önce YOKTU ve geriye bir şey kalmadı (sil).
    /// Kurulumdan SONRA eklenenler (ör. Codex'in yazdığı `[projects.*]`) korunur.
    static func geriAl(_ mevcut: String?, _ yedek: Yedek) -> String? {
        let (ham, nl) = satirlaraAyir(mevcut ?? "")
        let a = ayikla(isaretlileriSil(ham), anahtarlar: Set(yedek.yonetilenAnahtarlar))
        var govde = a.ust + a.kalan
        while let f = govde.first, bosMu(f) { govde.removeFirst() }
        var out = yedek.ustSatirlar
        if !out.isEmpty, let f = govde.first, basliMi(f) { out.append("") }
        out += govde
        while let s = out.last, bosMu(s) { out.removeLast() }
        if !yedek.saglayiciBlogu.isEmpty {
            if !out.isEmpty { out.append("") }
            out += yedek.saglayiciBlogu
        }
        if out.allSatisfy(bosMu) { return yedek.dosyaYoktu ? nil : "" }
        return out.joined(separator: nl) + nl
    }

    /// Codex'i AÇILMAZ yapacak hataları yakalar (TOML'da tekrar eden anahtar/tablo). nil = sorun yok.
    static func dogrula(_ metin: String) -> String? {
        let L = satirlaraAyir(metin).satirlar
        let ilk = L.firstIndex(where: basliMi) ?? L.count
        var gorulen = Set<String>()
        for l in L[..<ilk] {
            guard let k = anahtar(l) else { continue }
            if gorulen.contains(k) { return "config.toml'da ayni ust anahtar iki kez: \(k)" }
            gorulen.insert(k)
        }
        var basliklar = Set<String>()
        for l in L[ilk...] where basliMi(l) {
            if l.trimmingCharacters(in: .whitespaces).hasPrefix("[[") { continue }
            guard let ad = baslikAdi(l) else { continue }
            if basliklar.contains(ad) { return "config.toml'da ayni tablo iki kez: [\(ad)]" }
            basliklar.insert(ad)
        }
        guard basliklar.contains("model_providers.\(saglayici)") else { return "saglayici tablosu yazilamadi" }
        let saglayiciSatiri = L[..<ilk].first { anahtar($0) == "model_provider" }
        guard let s = saglayiciSatiri, s.contains("\"\(saglayici)\"") else { return "model_provider yapayzekalab degil" }
        return nil
    }
}
