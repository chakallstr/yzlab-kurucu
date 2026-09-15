using System.Text;
using System.Text.Json;

namespace YzlabKurucu;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--selftest")
            return SelfTest.Calistir();
        if (args.Contains("--kur") || args.Contains("--geri-al"))
            return KomutSatiri.Calistir(args);

        ApplicationConfiguration.Initialize();
        var (m, canli) = Manifest.LoadAsync().GetAwaiter().GetResult();
        Application.Run(new MainForm(m, canli));
        return 0;
    }
}

/// Bassiz kurulum:
///   YzlabKurucu.exe --kur --anahtar yzk_live_… [--model id] [--claude 0|1] [--anahtar-giris 0|1] [--codex-kapat 0|1]
/// Anahtar YZLAB_ANAHTAR ortam degiskeninden de alinabilir. `--geri-al` geri alir.
/// Cikis kodu: 0 basari, 1 hata, 2 kullanim hatasi.
internal static class KomutSatiri
{
    private static string? Deger(string ad, string[] args)
    {
        var i = Array.IndexOf(args, ad);
        return i >= 0 && i + 1 < args.Length ? args[i + 1] : null;
    }

    public static int Calistir(string[] args)
    {
        var (m, canli) = Manifest.LoadAsync().GetAwaiter().GetResult();
        Console.WriteLine("manifest: " + (canli ? "canli" : "gomulu") + " (sema v" + m.SchemaVersion + ")");
        var k = new Kurucu(m);
        Console.WriteLine("codex dizini: " + k.CodexDizini);

        if (args.Contains("--geri-al"))
        {
            Console.WriteLine("claude dizini: " + k.ClaudeDizini);
            k.GeriAl();
            if (k.GeriAlHatalari.Count > 0)
            {
                foreach (var h in k.GeriAlHatalari) Console.WriteLine("✗ " + h);
                return 1;
            }
            Console.WriteLine("✓ geri alindi");
            return 0;
        }

        var anahtar = Deger("--anahtar", args) ?? Environment.GetEnvironmentVariable("YZLAB_ANAHTAR");
        if (string.IsNullOrWhiteSpace(anahtar))
        {
            Console.WriteLine("kullanim: --kur --anahtar <yzk_live_…> [--model <id>] [--claude 0|1] [--anahtar-giris 0|1] [--codex-kapat 0|1]");
            Console.WriteLine("          (anahtar YZLAB_ANAHTAR ortam degiskeninden de okunur)");
            return 2;
        }
        var modelId = Deger("--model", args) ?? m.Codex.DefaultModel;
        var model = m.Codex.Models.FirstOrDefault(x => x.Id == modelId);
        if (model is null)
        {
            Console.WriteLine($"bilinmeyen model: {modelId} — secenekler: {string.Join(", ", m.Codex.Models.Select(x => x.Id))}");
            return 2;
        }
        var claude = (Deger("--claude", args) ?? "0") != "0";
        var anahtarGiris = (Deger("--anahtar-giris", args) ?? "0") != "0";
        var kapat = (Deger("--codex-kapat", args) ?? "0") != "0";
        if (claude) Console.WriteLine("claude dizini: " + k.ClaudeDizini);

        try
        {
            k.KurAsync(anahtar.Trim(), model, s => Console.WriteLine("› " + s), claude, anahtarGiris, kapat)
             .GetAwaiter().GetResult();
            Console.WriteLine("✓ kuruldu: " + k.AyarYolu + (anahtarGiris ? " (anahtarla giris)" : " (ChatGPT girisi korundu)"));
            if (claude) Console.WriteLine("✓ claude code: " + k.ClaudeAyarYolu);
            return 0;
        }
        catch (Exception e)
        {
            Console.WriteLine("✗ " + e.Message);
            return 1;
        }
    }
}

/// Windows makinemiz yok: CI her build'de kosar. macOS SelfTest.swift ile ayni invaryantlar.
internal static class SelfTest
{
    private static int _gecen, _kalan;

    private static void Kontrol(bool kosul, string ad)
    {
        if (kosul) { _gecen++; Console.WriteLine($"  PASS  {ad}"); }
        else { _kalan++; Console.WriteLine($"  FAIL  {ad}"); }
    }

    private static string Oku(string p) => File.Exists(p) ? File.ReadAllText(p) : "";

    public static int Calistir()
    {
        Console.WriteLine("YzlabKurucu — kendi kendini sinama\n");

        // 1) Gomulu manifest
        Manifest gomulu;
        try { gomulu = Manifest.Embedded; }
        catch (Exception e) { Console.WriteLine("FATAL gomulu manifest: " + e.Message); return 1; }
        Kontrol(gomulu.Codex.Models.Count > 0, "gomulu manifest cozuluyor");
        Kontrol(!string.IsNullOrEmpty(gomulu.Codex.ProfileTemplate), "profil sablonu dolu");
        Kontrol(gomulu.Codex.Models.Any(x => x.Id == gomulu.Codex.DefaultModel), "varsayilan model listede var");
        Kontrol(gomulu.Codex.CatalogUrl.StartsWith("https://"), "katalog adresi https");

        // 2) Canli manifest + katalog
        var (canliM, canliMi) = Manifest.LoadAsync().GetAwaiter().GetResult();
        Console.WriteLine(canliMi ? "  bilgi canli manifest CEKILDI" : "  bilgi canli manifest YOK — gomuluye dusuldu");
        var kaynak = canliMi ? canliM : gomulu;
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            var adres = new Kurucu(kaynak).KatalogAdresi("0.153.4");
            Kontrol(!adres.Contains("{{"), "katalog adresinde yer tutucu kalmadi");
            var kat = http.GetStringAsync(adres).GetAwaiter().GetResult();
            using var doc = JsonDocument.Parse(kat);
            var adet = doc.RootElement.GetProperty("models").GetArrayLength();
            Kontrol(adet > 0, $"model katalogu indi ve cozuldu ({adet} model)");
        }
        catch (Exception e)
        {
            if (canliMi) Kontrol(false, "model katalogu indi: " + e.Message);
            else Console.WriteLine("  bilgi model katalogu atlandi (sunucu erisilemez): " + e.Message);
        }

        // 3) Saf yardimcilar
        Kontrol(Kurucu.SurumAyikla("codex-cli 0.153.4") == "0.153.4", "codex surumu ayiklaniyor");
        Kontrol(Kurucu.SurumAyikla("gurultu 1.2.3\ncodex-cli 0.153.4") == "0.153.4", "gurultu icinde codex-cli satiri tercih edildi");
        Kontrol(Kurucu.SurumAyikla("hicbir sey") is null, "surum yoksa null");
        Kontrol(!Kurucu.YetkiReddiMi("tokens used\n8,401\nok"), "401 iceren token sayisi ret sayilmadi");
        Kontrol(!Kurucu.YetkiReddiMi("{\"duration_api_ms\":3401,\"stop_reason\":\"end_turn\"}"), "401 iceren sure ret sayilmadi");
        Kontrol(Kurucu.YetkiReddiMi("401 Unauthorized: API anahtarı geçersiz veya iptal edilmiş, url: x"), "gercek codex 401 yakalandi");
        Kontrol(Kurucu.YetkiReddiMi("error: HTTP 401"), "HTTP 401 yakalandi");
        Kontrol(Kurucu.AkisSatiri("data: {\"type\":\"response.completed\",\"response\":{}}").Durum == "tamam", "akis: completed = tamam");
        Kontrol(Kurucu.AkisSatiri("event: response.completed").Durum == "devam", "akis: event satiri atlandi");
        Kontrol(Kurucu.AkisSatiri("data: {\"type\":\"response.output_text.delta\",\"delta\":\"ok\"}").Durum == "devam", "akis: delta = devam");
        var a1 = Kurucu.AkisSatiri("data: {\"type\": \"error\", \"error\": {\"message\": \"Store must be set to false\"}}");
        Kontrol(a1.Durum == "hata" && a1.Mesaj == "Store must be set to false", "akis: error olayi = hata (mesajiyla)");
        var a2 = Kurucu.AkisSatiri("data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"message\":\"x\"}}}");
        Kontrol(a2.Durum == "hata" && a2.Mesaj == "x", "akis: response.failed = hata");

        // 4) Izole CODEX_HOME: config.toml birlestirme + iki giris modu + geri al
        var gecici = Path.Combine(Path.GetTempPath(), "yzlab-selftest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(gecici);
        Environment.SetEnvironmentVariable("CODEX_HOME", gecici);
        try
        {
            var k = new Kurucu(kaynak);
            Kontrol(k.CodexDizini == gecici, "CODEX_HOME dikkate aliniyor");
            var cfg = Path.Combine(gecici, "config.toml");
            var auth = Path.Combine(gecici, "auth.json");
            const string cfgOnce = "model = \"kendi-modelim\"\nnotify = [\"x\"]\n\n[mcp_servers.foo]\ncommand = \"bar\"\n";
            const string authOnce = "{\"auth_mode\":\"chatgpt\",\"tokens\":{\"id_token\":\"x\"}}";
            File.WriteAllText(cfg, cfgOnce);
            File.WriteAllText(auth, authOnce);
            File.WriteAllText(k.EskiProfilYolu, "eski profil");

            var model = kaynak.Codex.Models[0];
            const string anahtar = "yzk_live_TESTTESTTESTTEST";
            try { k.CodexAyariYaz(anahtar, model, false); Kontrol(true, "codex ayari yazildi (hesap modu)"); }
            catch (Exception e) { Kontrol(false, "codex ayari yazildi (hesap modu): " + e.Message); }

            var y1 = Oku(cfg);
            Kontrol(CodexAyar.Dogrula(y1) is null, "config.toml gecerli (" + (CodexAyar.Dogrula(y1) ?? "ok") + ")");
            Kontrol(y1.Contains("model_provider = \"yapayzekalab\"") && y1.Contains("experimental_bearer_token = \"" + anahtar + "\""),
                    "saglayici + anahtar ana config'e yazildi (masaustu okur)");
            Kontrol(y1.Contains("model = \"" + model.Id + "\"") && !y1.Contains("kendi-modelim"), "model yazildi, eski model yedekte");
            Kontrol(y1.Contains("[mcp_servers.foo]") && y1.Contains("notify = [\"x\"]"), "musterinin diger ayarlari korundu");
            Kontrol(!y1.Contains("{{") && !y1.Contains("[tools]"), "yer tutucu yok, [tools] eklenmedi");
            Kontrol(!y1.Contains(":\\") || y1.Contains(":\\\\"), "katalog yolu TOML icin kacisli");
            Kontrol(!y1.Contains("requires_openai_auth"), "hesap modu: requires_openai_auth YOK");
            Kontrol(Oku(auth) == authOnce, "hesap modu: auth.json DEGISMEDI (ChatGPT girisi durur)");
            Kontrol(File.Exists(k.YedekYolu) && File.Exists(k.AyarAnlikYedekYolu), "yedek json + tam kopya yazildi");
            Kontrol(!File.Exists(k.EskiProfilYolu), "v0.1 profil kalintisi temizlendi");
            Kontrol(k.KuruluMu, "KuruluMu dogru");

            k.CodexAyariYaz(anahtar, model, true);
            using (var d = JsonDocument.Parse(Oku(auth)))
                Kontrol(d.RootElement.GetProperty("auth_mode").GetString() == "apikey"
                        && d.RootElement.GetProperty("OPENAI_API_KEY").GetString() == anahtar, "anahtar modu: auth.json apikey");
            Kontrol(Oku(k.AuthYedekYolu) == authOnce, "anahtar modu: auth.json yedegi birebir");
            var y2 = Oku(cfg);
            Kontrol(y2.Contains("requires_openai_auth = true") && CodexAyar.Dogrula(y2) is null,
                    "anahtar modu: requires_openai_auth eklendi, dosya gecerli");

            k.CodexAyariYaz(anahtar, model, false);
            Kontrol(Oku(auth) == authOnce && !File.Exists(k.AuthYedekYolu), "hesap moduna donus: ChatGPT girisi geri geldi");
            Kontrol(!Oku(cfg).Contains("requires_openai_auth"), "hesap moduna donus: requires_openai_auth kalkti");

            k.CodexAyariYaz(anahtar, model, true);
            k.GeriAl(kisayollar: false);
            Kontrol(CodexAyarTest.Kume(Oku(cfg)).SequenceEqual(CodexAyarTest.Kume(cfgOnce)), "geri al: config.toml onceki satirlar");
            Kontrol(Oku(auth) == authOnce, "geri al: auth.json ayni");
            Kontrol(!File.Exists(k.YedekYolu) && !File.Exists(k.AuthYedekYolu), "geri al: yedekler temizlendi");
            Kontrol(k.GeriAlHatalari.Count == 0, "geri al: hata yok");

            File.Delete(cfg);
            k.CodexAyariYaz(anahtar, model, false);
            Kontrol(CodexAyar.Dogrula(Oku(cfg)) is null, "config.toml yokken gecerli dosya olustu");
            k.GeriAl(kisayollar: false);
            Kontrol(!File.Exists(cfg), "geri al: dosya yoktuysa silindi");
        }
        catch (Exception e) { Kontrol(false, "codex bolumu istisna: " + e.Message); }
        finally
        {
            Environment.SetEnvironmentVariable("CODEX_HOME", null);
            try { Directory.Delete(gecici, true); } catch { }
        }

        // 5) Claude Code settings.json birlestirme + yedek + geri al
        var cdir = Path.Combine(Path.GetTempPath(), "yzlab-selftest-claude-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(cdir);
        Environment.SetEnvironmentVariable("CLAUDE_CONFIG_DIR", cdir);
        try
        {
            var kc = new Kurucu(kaynak);
            Kontrol(kc.ClaudeDizini == cdir, "CLAUDE_CONFIG_DIR dikkate aliniyor");
            var ayar = Path.Combine(cdir, kaynak.Claude.SettingsFile);
            var orijinal = "{\n  \"permissions\": {\"allow\": [\"Bash\"]},\n  \"env\": {\"ANTHROPIC_API_KEY\": \"sk-eski\", \"FOO\": \"bar\"},\n  \"model\": \"x\"\n}\n";
            File.WriteAllText(ayar, orijinal, new UTF8Encoding(false));
            kc.ClaudeAyarYaz("yzk_live_TESTTESTTESTTEST", "gpt-5.6-luna");
            Kontrol(File.ReadAllText(kc.ClaudeYedekYolu) == orijinal, "claude yedek birebir");
            using (var doc = JsonDocument.Parse(File.ReadAllText(ayar)))
            {
                var root = doc.RootElement;
                var env = root.GetProperty("env");
                Kontrol(root.TryGetProperty("permissions", out _) && root.GetProperty("model").GetString() == "x", "claude diger anahtarlar korundu");
                Kontrol(env.GetProperty("FOO").GetString() == "bar", "claude env'deki yabanci anahtar korundu");
                Kontrol(!env.TryGetProperty("ANTHROPIC_API_KEY", out _), "claude kalinti ANTHROPIC_API_KEY silindi");
                Kontrol(env.GetProperty("ANTHROPIC_AUTH_TOKEN").GetString() == "yzk_live_TESTTESTTESTTEST", "claude AUTH_TOKEN yazildi");
                Kontrol(env.GetProperty("ANTHROPIC_BASE_URL").GetString() == kaynak.Claude.BaseUrl, "claude BASE_URL yazildi (kok, /v1 yok)");
                Kontrol(env.GetProperty("ANTHROPIC_MODEL").GetString() == "gpt-5.6-luna", "claude MODEL yazildi");
            }
            kc.ClaudeAyarYaz("yzk_live_IKINCI", "gpt-5.6-sol");
            Kontrol(File.ReadAllText(kc.ClaudeYedekYolu) == orijinal, "yeniden kurmak yedegi ezmedi");
            kc.ClaudeGeriAl(kisayol: false);
            Kontrol(File.ReadAllText(ayar) == orijinal, "claude geri al orijinali birebir geri koydu");
            File.Delete(ayar);
            kc.ClaudeAyarYaz("yzk_live_TESTTESTTESTTEST", "gpt-5.6-luna");
            Kontrol(File.Exists(kc.ClaudeYokIsareti), "claude 'dosya yoktu' isareti");
            kc.ClaudeGeriAl(kisayol: false);
            Kontrol(!File.Exists(ayar), "claude geri al (dosya yoktu) dosyayi sildi");
            File.WriteAllText(ayar, "{bozuk");
            var bozukHata = false;
            try { kc.ClaudeAyarYaz("x", "y"); } catch (KurulumHatasi) { bozukHata = true; }
            Kontrol(bozukHata && File.ReadAllText(ayar) == "{bozuk", "bozuk settings.json → hata, dosya dokunulmadi");
        }
        catch (Exception e) { Kontrol(false, "claude selftest istisna: " + e.Message); }
        finally
        {
            Environment.SetEnvironmentVariable("CLAUDE_CONFIG_DIR", null);
            try { Directory.Delete(cdir, true); } catch { }
        }

        // 5b) config.toml isaretli blok birlestirici
        CodexAyarTest.Calistir(Kontrol);

        // 6) Kisayol COM yolu
        try { Kontrol(Type.GetTypeFromProgID("WScript.Shell") is not null, "WScript.Shell COM erisilebilir"); }
        catch (Exception e) { Kontrol(false, "WScript.Shell: " + e.Message); }

        // 7) Kabuk + stdin kapali
        var r = Kurucu.Calistir("cmd.exe", "/d /s /c \"echo merhaba\"", 15_000);
        Kontrol(r.Kod == 0 && r.Cikti.Contains("merhaba"), "kabuk calisiyor (stdin kapali)");

        Console.WriteLine($"\n{_gecen} gecti, {_kalan} kaldi");
        return _kalan == 0 ? 0 : 1;
    }
}
