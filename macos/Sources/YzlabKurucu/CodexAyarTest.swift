import Foundation

/// `CodexAyar` saf mantığının testleri. Windows'taki `CodexAyarTest.cs` ile AYNI vakalar.
enum CodexAyarTest {
    static let sablonMetni = """
    # YapayZekaLab — Codex profili
    model = "gpt-5.6-sol"
    model_provider = "yapayzekalab"
    model_catalog_json = "/x/yzlab-model-catalog.json"
    model_context_window = 450000
    approval_policy = "never"

    [tools]
    web_search = true

    [model_providers.yapayzekalab]
    name = "YapayZekaLab"
    base_url = "https://yapayzekalab.org/v1"
    wire_api = "responses"
    experimental_bearer_token = "yzk_live_TEST"

    """

    static let o1 = """
    model = "kendi-modelim"
    model_reasoning_effort = "high"
    notify = ["x"]

    [mcp_servers.foo]
    command = "bar"

    [model_providers.yapayzekalab]
    name = "eski"
    base_url = "http://eski"

    [model_providers.yapayzekalab.http_headers]
    X = "1"

    [projects."/a"]
    trust_level = "trusted"

    """

    static func kume(_ s: String) -> [String] {
        CodexAyar.satirlaraAyir(s).satirlar
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    static func say(_ metin: String, _ parca: String) -> Int {
        metin.components(separatedBy: parca).count - 1
    }

    static func calistir(_ kontrol: (Bool, String) -> Void) {
        let sb = CodexAyar.sablonuAyir(sablonMetni)
        kontrol(sb.anahtarlar == ["model", "model_provider", "model_catalog_json", "model_context_window", "approval_policy"],
                "toml: sablon ust anahtarlari ayrildi")
        kontrol(sb.saglayiciSatirlar.first == "[model_providers.yapayzekalab]" && sb.saglayiciSatirlar.count == 5,
                "toml: sablon saglayici tablosu ayrildi")
        kontrol(!sb.ustSatirlar.contains { $0.contains("web_search") } && !sb.saglayiciSatirlar.contains("[tools]"),
                "toml: [tools] tablosu ALINMADI (cakisma riski)")

        // Mevcut dosya: eski saglayici + alt tablo + musteri ayarlari
        let (k1, y1) = CodexAyar.uygula(o1, sb)
        kontrol(CodexAyar.dogrula(k1) == nil, "toml: kurulum sonrasi dosya gecerli (\(CodexAyar.dogrula(k1) ?? "ok"))")
        kontrol(say(k1, "model_provider = \"yapayzekalab\"") == 1, "toml: model_provider tek sefer")
        kontrol(!k1.contains("kendi-modelim") && y1.ustSatirlar == ["model = \"kendi-modelim\""],
                "toml: musterinin model satiri yedege alindi")
        kontrol(k1.contains("model_reasoning_effort = \"high\"") && k1.contains("[mcp_servers.foo]") && k1.contains("[projects.\"/a\"]"),
                "toml: musterinin diger ayarlari korundu")
        kontrol(!k1.contains("http://eski") && !k1.contains("http_headers"), "toml: eski saglayici tablolari kaldirildi")
        kontrol(y1.saglayiciBlogu.contains("[model_providers.yapayzekalab.http_headers]"), "toml: eski saglayici yedege alindi")
        let ilkBaslik = k1.range(of: "\n[")!.lowerBound
        kontrol(k1.range(of: "model_provider = \"yapayzekalab\"")!.lowerBound < ilkBaslik, "toml: ust anahtarlar ilk tablodan ONCE")

        // Tekrar kurulum: ayni sonuc, cift kayit yok
        let (k2, _) = CodexAyar.uygula(k1, sb)
        kontrol(k2 == k1, "toml: tekrar kurmak ayni dosyayi uretir (idempotent)")

        // Geri al: orijinal satirlarin hepsi geri gelir
        let g1 = CodexAyar.geriAl(k1, y1)
        kontrol(g1 != nil && kume(g1!) == kume(o1), "toml: geri al orijinal satirlari geri koydu")
        kontrol(g1.map { !$0.contains("YapayZekaLab kurucu") } ?? false, "toml: geri al isaretleri temizledi")

        // Kurulumdan sonra Codex'in ekledigi tablo geri almada korunur
        let sonradan = k1 + "\n[projects.\"/b\"]\ntrust_level = \"trusted\"\n"
        let g2 = CodexAyar.geriAl(sonradan, y1) ?? ""
        kontrol(g2.contains("[projects.\"/b\"]") && kume(g2).count == kume(o1).count + 2,
                "toml: geri al sonradan eklenen tabloyu korudu")

        // Dosya yoktu
        let (k3, y3) = CodexAyar.uygula(nil, sb)
        kontrol(CodexAyar.dogrula(k3) == nil && y3.dosyaYoktu, "toml: dosya yokken gecerli dosya uretildi")
        kontrol(CodexAyar.geriAl(k3, y3) == nil, "toml: dosya yoktuysa geri al dosyayi siler")

        // CRLF + BOM (Windows'ta yazilmis dosya)
        let crlf = "\u{FEFF}" + o1.replacingOccurrences(of: "\n", with: "\r\n")
        let (k4, _) = CodexAyar.uygula(crlf, sb)
        kontrol(CodexAyar.dogrula(k4) == nil && !k4.hasPrefix("\u{FEFF}") && say(k4, "\n") == say(k4, "\r\n"),
                "toml: CRLF korundu, BOM atildi")

        // Uygulama sonradan isaret DISINA ayni anahtari yazarsa: dogrula yakalar, yeniden kur duzeltir
        let bozuk = k1.replacingOccurrences(of: CodexAyar.ustSon + "\n", with: CodexAyar.ustSon + "\nmodel = \"gpt-6-astra\"\n")
        kontrol(CodexAyar.dogrula(bozuk) != nil, "toml: cift ust anahtar yakalandi")
        kontrol(CodexAyar.dogrula(CodexAyar.uygula(bozuk, sb).metin) == nil, "toml: yeniden kur cift anahtari temizledi")

        // Ilk satiri tablo olan dosya
        let (k5, _) = CodexAyar.uygula("[mcp_servers.x]\ncommand = \"y\"\n", sb)
        kontrol(CodexAyar.dogrula(k5) == nil && k5.hasPrefix(CodexAyar.ustBas), "toml: tablo ile baslayan dosya")
    }
}
