using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace YzlabKurucu;

public sealed class KurulumHatasi : Exception
{
    public KurulumHatasi(string mesaj) : base(mesaj) { }
}

public sealed class Kurucu
{
    private readonly Manifest _m;
    public Kurucu(Manifest m) { _m = m; }

    /// CODEX_HOME tanimliysa Codex config'i ORADAN okur; %USERPROFILE%\.codex'e
    /// yazmak sessizce hicbir sey yapmaz ve hata da vermez.
    public string CodexDizini
    {
        get
        {
            var h = Environment.GetEnvironmentVariable("CODEX_HOME");
            if (string.IsNullOrWhiteSpace(h))
                h = Environment.GetEnvironmentVariable("CODEX_HOME", EnvironmentVariableTarget.User);
            if (!string.IsNullOrWhiteSpace(h))
                return Environment.ExpandEnvironmentVariables(h.Trim());
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
        }
    }

    public string ProfilYolu => Path.Combine(CodexDizini, _m.Codex.ProfileFile);
    public string KatalogYolu => Path.Combine(CodexDizini, _m.Codex.CatalogFile);
    public string KisayolYolu => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
        "Codex (YapayZekaLab).lnk");

    public bool KuruluMu => File.Exists(ProfilYolu);

    /// Claude Code'un karsiligi CLAUDE_CONFIG_DIR. Masaustu uygulamasi (Code sekmesi) da
    /// ayni dizini okur; profil mekanizmasi yok → settings.json'in `env` blogu.
    public string ClaudeDizini
    {
        get
        {
            var h = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
            if (string.IsNullOrWhiteSpace(h))
                h = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR", EnvironmentVariableTarget.User);
            if (!string.IsNullOrWhiteSpace(h))
                return Environment.ExpandEnvironmentVariables(h.Trim());
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), _m.Claude.ConfigDir);
        }
    }
    public string ClaudeAyarYolu => Path.Combine(ClaudeDizini, _m.Claude.SettingsFile);
    /// Ilk yazimdan onceki settings.json — Geri Al bunu birebir geri koyar.
    public string ClaudeYedekYolu => ClaudeAyarYolu + ".bak-yzlab";
    /// Ilk yazimda settings.json HIC YOKTU isareti — Geri Al dosyayi siler.
    public string ClaudeYokIsareti => ClaudeAyarYolu + ".yok-yzlab";
    public string ClaudeKisayolYolu => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
        "Claude Code (YapayZekaLab).lnk");
    public bool ClaudeKuruluMu => File.Exists(ClaudeYedekYolu) || File.Exists(ClaudeYokIsareti);

    // ── 1. Anahtar dogrulama ───────────────────────────────────────────────

    public async Task<string> AnahtariDogrulaAsync(string anahtar)
    {
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        using var req = new HttpRequestMessage(HttpMethod.Get, _m.Api.ValidateUrl);
        req.Headers.TryAddWithoutValidation("Authorization", _m.Api.AuthPrefix + anahtar);

        HttpResponseMessage resp;
        try { resp = await http.SendAsync(req); }
        catch (Exception e) { throw new KurulumHatasi("Baglanti kurulamadi: " + e.Message); }

        if ((int)resp.StatusCode == 401)
            throw new KurulumHatasi("Anahtar gecersiz veya iptal edilmis. Panelden yeni anahtar olustur.");
        if (!resp.IsSuccessStatusCode)
            throw new KurulumHatasi($"Sunucu {(int)resp.StatusCode} dondu. Birazdan tekrar dene.");

        var govde = await resp.Content.ReadAsStringAsync();
        try
        {
            using var doc = JsonDocument.Parse(govde);
            if (doc.RootElement.TryGetProperty("balance_try", out var b))
                return b.GetString() ?? "—";
        }
        catch { }
        return "—";
    }

    // ── 2..5 tam kurulum ───────────────────────────────────────────────────

    public async Task KurAsync(string anahtar, Manifest.ModelInfo model, bool kisayol,
                               Action<string> bildir, bool claude = true)
    {
        bildir("Anahtar dogrulaniyor…");
        await AnahtariDogrulaAsync(anahtar);

        bildir("Codex aranıyor…");
        await CodexHazirlaAsync(bildir);

        bildir("Model katalogu indiriliyor…");
        await KataloguIndirAsync(anahtar);

        bildir("Profil yaziliyor…");
        ProfiliYaz(anahtar, model);

        if (kisayol)
        {
            bildir("Kisayol olusturuluyor…");
            KisayolYaz();
        }

        bildir("Codex dogrulaniyor…");
        Dogrula();

        if (claude)
        {
            bildir("Claude Code aranıyor…");
            await ClaudeHazirlaAsync(bildir);

            bildir("Claude Code ayari yaziliyor…");
            ClaudeAyarYaz(anahtar, model.Id);

            if (kisayol)
            {
                bildir("Claude Code kisayolu…");
                ClaudeKisayolYaz();
            }

            bildir("Claude Code dogrulaniyor…");
            ClaudeDogrula();
        }
    }

    /// Codex KURULUYSA hic dokunma. Boylece musterinin Codex'i acikken de kurulum
    /// yapilabilir: Windows'ta calisan codex.exe npm guncellemesini EBUSY ile kilitler.
    private async Task NodeHazirlaAsync(Action<string> bildir)
    {
        if (KomutVar("npm")) return;
        bildir("Node.js kuruluyor… (birkac dakika)");
        await NodeKurAsync();
    }

    private async Task CodexHazirlaAsync(Action<string> bildir)
    {
        if (KomutVar("codex")) return;
        await NodeHazirlaAsync(bildir);

        bildir("Codex CLI kuruluyor… (birkac dakika)");
        var r = Calistir("cmd.exe", $"/d /s /c \"npm install -g {_m.Codex.NpmPackage}\"", 1_200_000);
        NpmGlobalBiniPathEkle();
        if (!KomutVar("codex"))
            throw new KurulumHatasi("Codex kurulamadi: " + Kisalt(r.Cikti));
    }

    /// npm'in global bin dizini (Windows'ta prefix'in kendisi: %APPDATA%\npm) yeni kurulan
    /// Node'da/ozel prefix'te surecimizin PATH'inde OLMAYABILIR (CI'da olculdu: "added 2
    /// packages" ama `where codex` bos). npm'e sorup PATH'in basina ekliyoruz; boylece hem
    /// `where codex` hem dogrulamadaki `codex exec` bulur. Kisayol/terminal zaten kayit
    /// defterindeki PATH'i kullanir.
    private static void NpmGlobalBiniPathEkle()
    {
        var r = Calistir("cmd.exe", "/d /s /c \"npm prefix -g\"", 30_000);
        var prefix = r.Cikti.Split('\n').Select(x => x.Trim()).LastOrDefault(x => x.Length > 0);
        if (r.Kod != 0 || string.IsNullOrEmpty(prefix) || !Directory.Exists(prefix)) return;
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        if (!path.Split(';').Any(x => string.Equals(x.TrimEnd('\\'), prefix.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)))
            Environment.SetEnvironmentVariable("PATH", prefix + ";" + path);
    }

    /// ⚠️ winget KULLANMIYORUZ: Windows Server'da hic yok, Win10'da surum surum
    /// degisiyor ve test imkanimiz en zayif oldugu yer orasi. Dogrudan MSI.
    private async Task NodeKurAsync()
    {
        var msi = Path.Combine(Path.GetTempPath(), "node-yzlab.msi");
        using (var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) })
        {
            var bytes = await http.GetByteArrayAsync(_m.Node.Windows.Url);
            await File.WriteAllBytesAsync(msi, bytes);
        }

        // msiexec yonetici hakki ister → UAC istemi cikar (runas).
        var psi = new ProcessStartInfo("msiexec.exe",
            $"/i \"{msi}\" {_m.Node.Windows.SilentArgs}")
        { UseShellExecute = true, Verb = "runas" };

        using var p = Process.Start(psi)
            ?? throw new KurulumHatasi("Node kurulumu baslatilamadi.");
        await p.WaitForExitAsync();
        if (p.ExitCode != 0)
            throw new KurulumHatasi("Node kurulumu reddedildi veya basarisiz (kod " + p.ExitCode + ").");

        // MSI PATH'i degistirir ama bizim surecimiz eski PATH'i tasiyor — tazele.
        var makine = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.Machine) ?? "";
        var kullanici = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? "";
        Environment.SetEnvironmentVariable("PATH", makine + ";" + kullanici);
    }

    // ── Katalog (canli API'den, kurulu Codex surumune gore) ───────────────

    /// Codex/Claude ciktisinda GERCEK yetki reddi var mi? Sayilarin icindeki "401"e kanmaz.
    public static bool YetkiReddiMi(string c)
    {
        if (c.Contains("Unauthorized") || c.Contains("authentication_error") || c.Contains("Invalid API key")
            || c.Contains("invalid_api_key") || c.Contains("gecersiz") || c.Contains("geçersiz")) return true;
        return Regex.IsMatch(c, @"(?i)(http|status|code)\D{0,4}401(\D|$)");
    }

    /// "codex-cli 0.153.4" → "0.153.4". Yoksa null.
    public static string? SurumAyikla(string s)
    {
        // Once "codex-cli x.y.z" satiri; yoksa ilk x.y.z (kabuk gurultusu surum sanilmasin).
        var c = Regex.Match(s ?? "", @"codex-cli\s+(\d+\.\d+\.\d+)");
        if (c.Success) return c.Groups[1].Value;
        var m = Regex.Match(s ?? "", @"\d+\.\d+\.\d+");
        return m.Success ? m.Value : null;
    }

    public string? CodexSurumu() =>
        SurumAyikla(Calistir("cmd.exe", "/d /s /c \"codex --version\"", 20_000).Cikti);

    /// Manifestteki katalog adresi `{{CODEX_VERSION}}` tasiyabilir: gateway kurulu
    /// Codex surumune gore dogru semayi doner. Surum bulunamazsa minimum surum yazilir.
    public string KatalogAdresi(string? surum)
    {
        var v = string.IsNullOrEmpty(surum) ? _m.Codex.MinVersion : surum;
        return _m.Codex.CatalogUrl.Replace("{{CODEX_VERSION}}", Uri.EscapeDataString(v ?? ""));
    }

    private async Task KataloguIndirAsync(string anahtar)
    {
        string json;
        using (var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) })
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, KatalogAdresi(CodexSurumu()));
            // Anahtarla istenir: gateway musterinin kendi kademesine gore katalog verir.
            req.Headers.TryAddWithoutValidation("Authorization", _m.Api.AuthPrefix + anahtar);
            try
            {
                var resp = await http.SendAsync(req);
                if (!resp.IsSuccessStatusCode)
                    throw new Exception($"HTTP {(int)resp.StatusCode}");
                json = await resp.Content.ReadAsStringAsync();
            }
            catch (Exception e) { throw new KurulumHatasi("Model katalogu indirilemedi: " + e.Message); }
        }
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("models", out var ms) || ms.GetArrayLength() == 0)
                throw new Exception("models bos");
        }
        catch { throw new KurulumHatasi("Model katalogu bozuk indi — tekrar dene."); }

        Directory.CreateDirectory(CodexDizini);
        File.WriteAllText(KatalogYolu, json, new UTF8Encoding(false));
    }

    /// SADECE kendi dosyamizi yazar. config.toml ve auth.json'a DOKUNMAZ →
    /// musterinin ChatGPT Plus oturumu bozulmaz.
    private void ProfiliYaz(string anahtar, Manifest.ModelInfo model)
    {
        var icerik = _m.Codex.ProfileTemplate
            .Replace("{{MODEL}}", model.Id)
            .Replace("{{CONTEXT}}", model.ContextWindow.ToString())
            .Replace("{{BASE_URL}}", _m.Api.BaseUrl)
            .Replace("{{CATALOG_PATH}}", KatalogYolu.Replace("\\", "\\\\"))  // TOML kacisi
            .Replace("{{TOKEN_FIELD}}", _m.Codex.TokenField)
            .Replace("{{TOKEN}}", anahtar);

        Directory.CreateDirectory(CodexDizini);
        File.WriteAllText(ProfilYolu, icerik, new UTF8Encoding(false));
    }

    private void KisayolYaz()
    {
        // WScript.Shell COM: ek paket gerektirmez.
        var tip = Type.GetTypeFromProgID("WScript.Shell");
        if (tip is null) return;
        dynamic? kabuk = Activator.CreateInstance(tip);
        if (kabuk is null) return;
        dynamic k = kabuk.CreateShortcut(KisayolYolu);
        k.TargetPath = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        k.Arguments = $"/k codex -p {_m.Codex.ProfileName}";
        k.Description = "Codex — YapayZekaLab uzerinden";
        k.WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        k.Save();
    }

    /// Profilin gercekten yuklendigini ve BIZE gittigini kanitlar.
    ///
    /// IZOLE calisir: gecici bir CODEX_HOME'a yalniz bizim profil kopyalanir (katalog
    /// yolu gercek dosyaya bakar). Sebep: `codex exec` calistigi dizin icin config.toml'a
    /// `[projects.*] trust_level` YAZAR (0.153'te olculdu) — musterinin config.toml'una
    /// dokunmama sozunu bozmamak ve musterinin MCP sunucularini bosuna baslatmamak icin.
    private void Dogrula()
    {
        var gecici = Path.Combine(Path.GetTempPath(), "yzlab-dogrula-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(gecici);
        try
        {
            File.Copy(ProfilYolu, Path.Combine(gecici, _m.Codex.ProfileFile), overwrite: true);
            var r = Calistir("cmd.exe",
                $"/d /s /c \"codex exec -p {_m.Codex.ProfileName} --skip-git-repo-check -C \"{gecici}\" ok\"",
                120_000, new() { ["CODEX_HOME"] = gecici });
            var c = r.Cikti;
            // ⚠️ Duz "401" arama YANLIS POZITIF verir (token sayisi 8,401, sure 3401ms).
            if (YetkiReddiMi(c))
                throw new KurulumHatasi("Anahtar gecersiz veya iptal edilmis.");
            if (c.Contains("failed to parse model_catalog_json"))
                throw new KurulumHatasi("Model katalogu bozuk indi — tekrar dene.");
            if (!c.Contains("yapayzekalab"))
                throw new KurulumHatasi("Profil yuklenmedi:\n" + Kisalt(c));
            // Izolasyon KANITI: codex exec trust kaydini calistigi CODEX_HOME'un config.toml'una
            // yazar; gecici dizinde yoksa exec baska bir CODEX_HOME'da kostu demektir.
            if (!File.Exists(Path.Combine(gecici, "config.toml")))
                throw new KurulumHatasi("Dogrulama izole kosmadi (CODEX_HOME ezildi?).");
        }
        finally
        {
            try { Directory.Delete(gecici, true); } catch { }
        }
    }

    // ── Claude Code (terminal + Claude masaustu uygulamasi) ───────────────

    private async Task ClaudeHazirlaAsync(Action<string> bildir)
    {
        if (KomutVar("claude")) return;
        await NodeHazirlaAsync(bildir);
        bildir("Claude Code kuruluyor… (birkac dakika)");
        var r = Calistir("cmd.exe", $"/d /s /c \"npm install -g {_m.Claude.NpmPackage}\"", 1_200_000);
        NpmGlobalBiniPathEkle();
        if (!KomutVar("claude"))
            throw new KurulumHatasi("Claude Code kurulamadi: " + Kisalt(r.Cikti));
    }

    /// settings.json'in YALNIZ `env` blogunu duzenler; diger her anahtar (permissions,
    /// hooks, model…) aynen kalir. Ilk yazimdan once birebir yedek alinir (Geri Al bunu
    /// geri koyar). Kalinti: env'de ANTHROPIC_API_KEY kalirsa AUTH_TOKEN'i EZER → silinir.
    public void ClaudeAyarYaz(string anahtar, string modelId)
    {
        Directory.CreateDirectory(ClaudeDizini);
        JsonObject obj;
        if (File.Exists(ClaudeAyarYolu))
        {
            var ham = File.ReadAllText(ClaudeAyarYolu, Encoding.UTF8);
            if (string.IsNullOrWhiteSpace(ham)) obj = new JsonObject();
            else
            {
                try { obj = JsonNode.Parse(ham) as JsonObject ?? throw new Exception("nesne degil"); }
                catch { throw new KurulumHatasi($"{ClaudeAyarYolu} gecerli JSON degil — elle duzelt, sonra tekrar dene."); }
            }
            // Yedek YALNIZ ilk kurulumda alinir: yeniden kurmak yedegi ezmesin.
            if (!ClaudeKuruluMu) File.Copy(ClaudeAyarYolu, ClaudeYedekYolu, overwrite: false);
        }
        else
        {
            obj = new JsonObject();
            if (!ClaudeKuruluMu) File.WriteAllText(ClaudeYokIsareti, "");
        }

        var env = obj["env"] as JsonObject ?? new JsonObject();
        foreach (var k in _m.Claude.RemoveEnvKeys) env.Remove(k);
        foreach (var (k, v) in _m.Claude.EnvTemplate)
            env[k] = v.Replace("{{BASE_URL}}", _m.Claude.BaseUrl)
                      .Replace("{{TOKEN}}", anahtar)
                      .Replace("{{MODEL}}", modelId)
                      .Replace("{{SMALL_MODEL}}", _m.Claude.SmallFastModel);
        obj["env"] = env;

        var json = obj.ToJsonString(new JsonSerializerOptions
        {
            WriteIndented = true,
            Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        });
        File.WriteAllText(ClaudeAyarYolu, json + "\n", new UTF8Encoding(false));
    }

    private void ClaudeKisayolYaz()
    {
        var tip = Type.GetTypeFromProgID("WScript.Shell");
        if (tip is null) return;
        dynamic? kabuk = Activator.CreateInstance(tip);
        if (kabuk is null) return;
        dynamic k = kabuk.CreateShortcut(ClaudeKisayolYolu);
        k.TargetPath = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        k.Arguments = $"/k {_m.Claude.LaunchCommand}";
        k.Description = "Claude Code — YapayZekaLab uzerinden";
        k.WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        k.Save();
    }

    /// settings.json'daki env ile Claude Code'un gercekten BIZE gittigini kanitlar.
    /// IZOLE: gecici CLAUDE_CONFIG_DIR'a yalniz settings.json kopyalanir — musterinin
    /// oturum/proje kayitlarina (.claude.json, projects/) dokunulmaz.
    private void ClaudeDogrula()
    {
        var gecici = Path.Combine(Path.GetTempPath(), "yzlab-claude-dogrula-" + Guid.NewGuid().ToString("N"));
        var cfg = Path.Combine(gecici, "cfg");
        Directory.CreateDirectory(cfg);
        try
        {
            File.Copy(ClaudeAyarYolu, Path.Combine(cfg, _m.Claude.SettingsFile), overwrite: true);
            var r = Calistir("cmd.exe",
                $"/d /s /c \"{_m.Claude.LaunchCommand} -p \"Sadece ok yaz\" --output-format json\"",
                180_000, new() { ["CLAUDE_CONFIG_DIR"] = cfg }, gecici);
            var c = r.Cikti;
            if (c.Contains("requires git-bash") || c.Contains("Git Bash"))
                throw new KurulumHatasi("Claude Code Windows'ta Git for Windows ister: git-scm.com'dan kur, sonra Yeniden Kur.");
            if (YetkiReddiMi(c))
                throw new KurulumHatasi("Anahtar gecersiz veya iptal edilmis.");
            if (!(c.Contains("\"stop_reason\"") || c.Contains("\"result\"")) || c.Contains("\"is_error\":true"))
                throw new KurulumHatasi("Claude Code dogrulama yaniti beklenmedik:\n" + Kisalt(c));
            // Izolasyon kaniti: claude, CLAUDE_CONFIG_DIR'a .claude.json / projects yazar.
            if (!File.Exists(Path.Combine(cfg, ".claude.json")) && !Directory.Exists(Path.Combine(cfg, "projects")))
                throw new KurulumHatasi("Claude Code dogrulama izole kosmadi (CLAUDE_CONFIG_DIR ezildi?).");
        }
        finally
        {
            try { Directory.Delete(gecici, true); } catch { }
        }
    }

    /// Geri alma sirasinda yutulan hatalar (musteriye ve CLI'a gosterilir; sessiz kalmasin).
    public List<string> GeriAlHatalari { get; } = new();

    public void ClaudeGeriAl(bool kisayol = true)
    {
        try
        {
            if (File.Exists(ClaudeYedekYolu))
            {
                // Yedegi ONCE yerine kopyala, sonra yedegi sil: arada hata olursa dosya kaybolmaz.
                File.Copy(ClaudeYedekYolu, ClaudeAyarYolu, overwrite: true);
                File.Delete(ClaudeYedekYolu);
            }
            else if (File.Exists(ClaudeYokIsareti))
            {
                if (File.Exists(ClaudeAyarYolu)) File.Delete(ClaudeAyarYolu);
                File.Delete(ClaudeYokIsareti);
            }
        }
        catch (Exception e) { GeriAlHatalari.Add("claude settings: " + e.Message); }
        if (!kisayol) return;
        try { if (File.Exists(ClaudeKisayolYolu)) File.Delete(ClaudeKisayolYolu); }
        catch (Exception e) { GeriAlHatalari.Add("claude kisayol: " + e.Message); }
    }

    /// `kisayollar: false` → yalniz CODEX_HOME/CLAUDE_CONFIG_DIR icindekiler; masaustu
    /// kisayollari (profil dizinine bagli, izole edilemez) dokunulmaz. --selftest bunu kullanir.
    public void GeriAl(bool kisayollar = true)
    {
        GeriAlHatalari.Clear();
        var hedefler = new List<string> { ProfilYolu, KatalogYolu };
        if (kisayollar) hedefler.Add(KisayolYolu);
        foreach (var y in hedefler)
            try { if (File.Exists(y)) File.Delete(y); }
            catch (Exception e) { GeriAlHatalari.Add(Path.GetFileName(y) + ": " + e.Message); }
        ClaudeGeriAl(kisayollar);
    }

    // ── yardimcilar ────────────────────────────────────────────────────────

    public readonly record struct Sonuc(int Kod, string Cikti);

    public static Sonuc Calistir(string dosya, string arg, int msTimeout,
                                 Dictionary<string, string>? env = null, string? calismaDizini = null)
    {
        var psi = new ProcessStartInfo(dosya, arg)
        {
            WorkingDirectory = calismaDizini ?? "",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            // ⚠️ stdin KAPALI olmali: `codex exec` stdin bir boru/terminal ise
            // "Reading additional input from stdin..." deyip EOF bekler ve ASILI KALIR.
            RedirectStandardInput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        if (env is not null)
            foreach (var (k, v) in env) psi.Environment[k] = v;

        using var p = Process.Start(psi);
        if (p is null) return new Sonuc(127, "calistirilamadi");
        p.StandardInput.Close();

        var sb = new StringBuilder();
        p.OutputDataReceived += (_, e) => { if (e.Data is not null) lock (sb) sb.AppendLine(e.Data); };
        p.ErrorDataReceived += (_, e) => { if (e.Data is not null) lock (sb) sb.AppendLine(e.Data); };
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();

        if (!p.WaitForExit(msTimeout))
        {
            try { p.Kill(true); } catch { }
            lock (sb) return new Sonuc(124, sb + "\n(zaman asimi)");
        }
        p.WaitForExit(); // async okuma tamponlari bosalsin
        lock (sb) return new Sonuc(p.ExitCode, sb.ToString().Trim());
    }

    public static bool KomutVar(string komut) =>
        Calistir("cmd.exe", $"/d /s /c \"where {komut}\"", 15_000).Kod == 0;

    private static string Kisalt(string s) =>
        s.Length <= 300 ? s : s[^300..];
}
