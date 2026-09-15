namespace YzlabKurucu;

/// `CodexAyar` saf mantiginin testleri. macOS'taki `CodexAyarTest.swift` ile AYNI vakalar.
internal static class CodexAyarTest
{
    private const string SablonMetni =
        "# YapayZekaLab — Codex profili\n" +
        "model = \"gpt-5.6-sol\"\n" +
        "model_provider = \"yapayzekalab\"\n" +
        "model_catalog_json = \"C:\\\\Users\\\\x\\\\.codex\\\\yzlab-model-catalog.json\"\n" +
        "model_context_window = 450000\n" +
        "approval_policy = \"never\"\n" +
        "\n" +
        "[tools]\n" +
        "web_search = true\n" +
        "\n" +
        "[model_providers.yapayzekalab]\n" +
        "name = \"YapayZekaLab\"\n" +
        "base_url = \"https://yapayzekalab.org/v1\"\n" +
        "wire_api = \"responses\"\n" +
        "experimental_bearer_token = \"yzk_live_TEST\"\n";

    private const string O1 =
        "model = \"kendi-modelim\"\n" +
        "model_reasoning_effort = \"high\"\n" +
        "notify = [\"x\"]\n" +
        "\n" +
        "[mcp_servers.foo]\n" +
        "command = \"bar\"\n" +
        "\n" +
        "[model_providers.yapayzekalab]\n" +
        "name = \"eski\"\n" +
        "base_url = \"http://eski\"\n" +
        "\n" +
        "[model_providers.yapayzekalab.http_headers]\n" +
        "X = \"1\"\n" +
        "\n" +
        "[projects.\"/a\"]\n" +
        "trust_level = \"trusted\"\n";

    internal static List<string> Kume(string s) =>
        CodexAyar.SatirlaraAyir(s).Satirlar.Select(x => x.Trim()).Where(x => x.Length > 0).OrderBy(x => x, StringComparer.Ordinal).ToList();

    private static int Say(string metin, string parca) =>
        metin.Split(parca).Length - 1;

    public static void Calistir(Action<bool, string> kontrol)
    {
        var sb = CodexAyar.SablonuAyir(SablonMetni);
        kontrol(sb.Anahtarlar.SequenceEqual(new[] { "model", "model_provider", "model_catalog_json", "model_context_window", "approval_policy" }),
                "toml: sablon ust anahtarlari ayrildi");
        kontrol(sb.SaglayiciSatirlar.FirstOrDefault() == "[model_providers.yapayzekalab]" && sb.SaglayiciSatirlar.Count == 5,
                "toml: sablon saglayici tablosu ayrildi");
        kontrol(!sb.UstSatirlar.Any(x => x.Contains("web_search")) && !sb.SaglayiciSatirlar.Contains("[tools]"),
                "toml: [tools] tablosu ALINMADI (cakisma riski)");

        var (k1, y1) = CodexAyar.Uygula(O1, sb);
        kontrol(CodexAyar.Dogrula(k1) is null, "toml: kurulum sonrasi dosya gecerli (" + (CodexAyar.Dogrula(k1) ?? "ok") + ")");
        kontrol(Say(k1, "model_provider = \"yapayzekalab\"") == 1, "toml: model_provider tek sefer");
        kontrol(!k1.Contains("kendi-modelim") && y1.UstSatirlar.SequenceEqual(new[] { "model = \"kendi-modelim\"" }),
                "toml: musterinin model satiri yedege alindi");
        kontrol(k1.Contains("model_reasoning_effort = \"high\"") && k1.Contains("[mcp_servers.foo]") && k1.Contains("[projects.\"/a\"]"),
                "toml: musterinin diger ayarlari korundu");
        kontrol(!k1.Contains("http://eski") && !k1.Contains("http_headers"), "toml: eski saglayici tablolari kaldirildi");
        kontrol(y1.SaglayiciBlogu.Contains("[model_providers.yapayzekalab.http_headers]"), "toml: eski saglayici yedege alindi");
        kontrol(k1.IndexOf("model_provider = \"yapayzekalab\"", StringComparison.Ordinal) < k1.IndexOf("\n[", StringComparison.Ordinal),
                "toml: ust anahtarlar ilk tablodan ONCE");

        var (k2, _) = CodexAyar.Uygula(k1, sb);
        kontrol(k2 == k1, "toml: tekrar kurmak ayni dosyayi uretir (idempotent)");

        var g1 = CodexAyar.GeriAl(k1, y1);
        kontrol(g1 is not null && Kume(g1).SequenceEqual(Kume(O1)), "toml: geri al orijinal satirlari geri koydu");
        kontrol(g1 is not null && !g1.Contains("YapayZekaLab kurucu"), "toml: geri al isaretleri temizledi");

        var sonradan = k1 + "\n[projects.\"/b\"]\ntrust_level = \"trusted\"\n";
        var g2 = CodexAyar.GeriAl(sonradan, y1) ?? "";
        kontrol(g2.Contains("[projects.\"/b\"]") && Kume(g2).Count == Kume(O1).Count + 2,
                "toml: geri al sonradan eklenen tabloyu korudu");

        var (k3, y3) = CodexAyar.Uygula(null, sb);
        kontrol(CodexAyar.Dogrula(k3) is null && y3.DosyaYoktu, "toml: dosya yokken gecerli dosya uretildi");
        kontrol(CodexAyar.GeriAl(k3, y3) is null, "toml: dosya yoktuysa geri al dosyayi siler");

        var crlf = "\uFEFF" + O1.Replace("\n", "\r\n");
        var (k4, _) = CodexAyar.Uygula(crlf, sb);
        kontrol(CodexAyar.Dogrula(k4) is null && k4[0] != '\uFEFF' && Say(k4, "\n") == Say(k4, "\r\n"),
                "toml: CRLF korundu, BOM atildi");

        var bozuk = k1.Replace(CodexAyar.UstSon + "\n", CodexAyar.UstSon + "\nmodel = \"gpt-6-astra\"\n");
        kontrol(CodexAyar.Dogrula(bozuk) is not null, "toml: cift ust anahtar yakalandi");
        kontrol(CodexAyar.Dogrula(CodexAyar.Uygula(bozuk, sb).Metin) is null, "toml: yeniden kur cift anahtari temizledi");

        var (k5, _) = CodexAyar.Uygula("[mcp_servers.x]\ncommand = \"y\"\n", sb);
        kontrol(CodexAyar.Dogrula(k5) is null && k5.StartsWith(CodexAyar.UstBas), "toml: tablo ile baslayan dosya");
    }
}
