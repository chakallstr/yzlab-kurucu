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

/// Kurulumun beyni. v0.2 (2026-09-15) — HEDEF CODEX MASAUSTU (macOS Installer.swift ile birebir):
/// - Ayar ana config.toml'a isaretli bloklarla yazilir (CodexAyar). Profil YAZILMAZ — masaustu okumuyordu.
/// - Node / Codex CLI KURULMAZ. Dogrulama dogrudan HTTPS, Codex bicimiyle.
/// - Varsayilan ChatGPT girisi DURUR; `anahtarGiris` → auth.json anahtar modu (yedekli).
/// - Codex aciksa izinle kapatilir, kurulumdan sonra yeniden acilir.
public sealed class Kurucu
{
    private readonly Manifest _m;
    public Kurucu(Manifest m) { _m = m; }

    public List<string> GeriAlHatalari { get; } = new();

    // ── Dizinler ───────────────────────────────────────────────────────────

    /// CODEX_HOME tanimliysa Codex config'i ORADAN okur.
    public string CodexDizini
    {
        get
        {
            var h = Environment.GetEnvironmentVariable("CODEX_HOME");
            if (string.IsNullOrWhiteSpace(h))
                h = Environment.GetEnvironmentVariable("CODEX_HOME", EnvironmentVariableTarget.User);
            if (!string.IsNullOrWhiteSpace(h))
                return Environment.ExpandEnvironmentVariables(h.Trim());
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
        }
    }

    public string AyarYolu => Path.Combine(CodexDizini, "config.toml");
    public string YedekYolu => Path.Combine(CodexDizini, "yzlab-kurucu-yedek.json");
    public string AyarAnlikYedekYolu => Path.Combine(CodexDizini, "config.toml.bak-yzlab");
    public string AuthYolu => Path.Combine(CodexDizini, "auth.json");
    public string AuthYedekYolu => Path.Combine(CodexDizini, "auth.json.bak-yzlab");
    public string AuthYokIsareti => Path.Combine(CodexDizini, "auth.json.yok-yzlab");
    public string KatalogYolu => Path.Combine(CodexDizini, _m.Codex.CatalogFile);
    /// v0.1.x kalintilari: profil dosyasi + `codex -p yzlab` masaustu kisayolu (artik calismaz).
    public string EskiProfilYolu => Path.Combine(CodexDizini, _m.Codex.ProfileFile);
    public string EskiKisayolYolu => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Codex (YapayZekaLab).lnk");

    public string ClaudeDizini
    {
        get
        {
            var h = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
            if (string.IsNullOrWhiteSpace(h))
                h = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR", EnvironmentVariableTarget.User);
            if (!string.IsNullOrWhiteSpace(h))
                return Environment.ExpandEnvironmentVariables(h.Trim());
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), _m.Claude.ConfigDir);
        }
    }
    public string ClaudeAyarYolu => Path.Combine(ClaudeDizini, _m.Claude.SettingsFile);
    public string ClaudeYedekYolu => ClaudeAyarYolu + ".bak-yzlab";
    public string ClaudeYokIsareti => ClaudeAyarYolu + ".yok-yzlab";
    public string ClaudeKisayolYolu => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Claude Code (YapayZekaLab).lnk");

    public bool KuruluMu => File.Exists(YedekYolu) || File.Exists(EskiProfilYolu)
                            || File.Exists(AuthYedekYolu) || File.Exists(AuthYokIsareti);
    public bool ClaudeKuruluMu => File.Exists(ClaudeYedekYolu) || File.Exists(ClaudeYokIsareti);

    /// Dogrulama HER ZAMAN en hizli/ucuz modelle (2026-09-15: astra ile "ok" 36-61 sn surdu).
    public string DogrulamaModeli => string.IsNullOrWhiteSpace(_m.Claude.SmallFastModel)
        ? "gpt-5.6-luna" : _m.Claude.SmallFastModel;

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

    // ── 2. Tam kurulum ─────────────────────────────────────────────────────

    public async Task KurAsync(string anahtar, Manifest.ModelInfo model, Action<string> bildir,
                               bool claude = false, bool anahtarGiris = false, bool codexKapatIzni = false)
    {
        bildir("Anahtar dogrulaniyor…");
        await AnahtariDogrulaAsync(anahtar);

        bildir("Codex uygulamasi kontrol ediliyor…");
        var yenidenAc = new List<string>();
        if (AcikCodexUygulamalari().Count > 0)
        {
            if (!codexKapatIzni) throw new KurulumHatasi("Codex uygulamasi acik. Kapatip tekrar Kur'a bas.");
            bildir("Codex kapatiliyor…");
            yenidenAc = await CodexUygulamasiniKapatAsync();
        }

        try
        {
            bildir("Model katalogu indiriliyor…");
            var surum = await CodexSurumuBulAsync();
            await KataloguIndirAsync(anahtar, surum);

            bildir("Codex ayari yaziliyor…");
            CodexAyariYaz(anahtar, model, anahtarGiris);

            bildir("Baglanti test ediliyor…");
            await BaglantiyiDogrulaAsync(anahtar, model.Id);

            if (claude)
            {
                bildir("Claude Code aranıyor…");
                await ClaudeHazirlaAsync(bildir);
                bildir("Claude Code ayari yaziliyor…");
                ClaudeAyarYaz(anahtar, model.Id);
                bildir("Claude Code kisayolu…");
                ClaudeKisayolYaz();
                bildir("Claude Code dogrulaniyor…");
                ClaudeDogrula();
            }
        }
        catch
        {
            CodexUygulamasiniAc(yenidenAc);
            throw;
        }

        if (yenidenAc.Count > 0)
        {
            bildir("Codex yeniden aciliyor…");
            CodexUygulamasiniAc(yenidenAc);
        }
    }

    // ── Codex masaustu uygulamasi (acik mi / kapat / ac) ───────────────────

    public static readonly string[] MasaustuSurecAdlari = { "Codex", "ChatGPT" };

    /// Yalniz PENCERESI olan surecler: ayni adli `codex` CLI oturumlari (konsol) dokunulmaz.
    public static List<Process> AcikCodexUygulamalari()
    {
        var l = new List<Process>();
        foreach (var ad in MasaustuSurecAdlari)
            foreach (var p in Process.GetProcessesByName(ad))
                try { if (p.MainWindowHandle != IntPtr.Zero) l.Add(p); } catch { }
        return l;
    }

    public async Task<List<string>> CodexUygulamasiniKapatAsync()
    {
        var yollar = new List<string>();
        foreach (var p in AcikCodexUygulamalari())
        {
            try { var f = p.MainModule?.FileName; if (!string.IsNullOrEmpty(f) && !yollar.Contains(f)) yollar.Add(f); } catch { }
            try { p.CloseMainWindow(); } catch { }
        }
        for (var i = 0; i < 20; i++)
        {
            if (AyniYoldakiSurecler(yollar).Count == 0 && AcikCodexUygulamalari().Count == 0) return yollar;
            await Task.Delay(500);
        }
        // Electron uygulamasi tepsiye kucelip arka planda kalabilir (config.toml'u sonra ezer):
        // kullanici "Kapat ve kur" dedigi icin ayni yoldaki surecleri sonlandir.
        foreach (var p in AyniYoldakiSurecler(yollar).Concat(AcikCodexUygulamalari()))
            try { p.Kill(true); } catch { }
        for (var i = 0; i < 20; i++)
        {
            if (AyniYoldakiSurecler(yollar).Count == 0 && AcikCodexUygulamalari().Count == 0) return yollar;
            await Task.Delay(500);
        }
        throw new KurulumHatasi("Codex kapanmadi. Elle kapatip tekrar Kur'a bas.");
    }

    private static List<Process> AyniYoldakiSurecler(List<string> yollar)
    {
        var l = new List<Process>();
        if (yollar.Count == 0) return l;
        foreach (var ad in MasaustuSurecAdlari)
            foreach (var p in Process.GetProcessesByName(ad))
                try { var f = p.MainModule?.FileName; if (f is not null && yollar.Contains(f)) l.Add(p); } catch { }
        return l;
    }

    public static void CodexUygulamasiniAc(List<string> yollar)
    {
        foreach (var y in yollar)
            try { Process.Start(new ProcessStartInfo(y) { UseShellExecute = true }); } catch { }
    }

    // ── Katalog ────────────────────────────────────────────────────────────

    /// "codex-cli 0.153.4" → "0.153.4". Once "codex-cli x.y.z" satiri; yoksa ilk x.y.z.
    public static string? SurumAyikla(string s)
    {
        var c = Regex.Match(s ?? "", @"codex-cli\s+(\d+\.\d+\.\d+)");
        if (c.Success) return c.Groups[1].Value;
        var m = Regex.Match(s ?? "", @"\d+\.\d+\.\d+");
        return m.Success ? m.Value : null;
    }

    /// Masaustu kendi codex'ini tasir: npm'deki son surum; ulasilamazsa manifestteki minimum.
    public async Task<string> CodexSurumuBulAsync()
    {
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            var js = await http.GetStringAsync("https://registry.npmjs.org/@openai/codex/latest");
            using var doc = JsonDocument.Parse(js);
            var v = SurumAyikla(doc.RootElement.GetProperty("version").GetString() ?? "");
            if (v is not null) return v;
        }
        catch { }
        return _m.Codex.MinVersion;
    }

    public string KatalogAdresi(string? surum)
    {
        var v = string.IsNullOrEmpty(surum) ? _m.Codex.MinVersion : surum;
        return _m.Codex.CatalogUrl.Replace("{{CODEX_VERSION}}", Uri.EscapeDataString(v ?? ""));
    }

    private async Task KataloguIndirAsync(string anahtar, string surum)
    {
        string json;
        using (var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) })
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, KatalogAdresi(surum));
            req.Headers.TryAddWithoutValidation("Authorization", _m.Api.AuthPrefix + anahtar);
            try
            {
                var resp = await http.SendAsync(req);
                if (!resp.IsSuccessStatusCode) throw new Exception($"HTTP {(int)resp.StatusCode}");
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
        AtomikYaz(KatalogYolu, json);
    }

    // ── config.toml + auth.json ────────────────────────────────────────────

    public static string TomlKacis(string s) => s.Replace("\\", "\\\\").Replace("\"", "\\\"");

    private static void AtomikYaz(string yol, string metin)
    {
        var tmp = yol + ".yzlab-tmp";
        File.WriteAllText(tmp, metin, new UTF8Encoding(false));
        File.Move(tmp, yol, overwrite: true);
    }

    public CodexAyar.Sablon Sablon(string anahtar, Manifest.ModelInfo model, bool anahtarGiris)
    {
        var dolu = _m.Codex.ProfileTemplate
            .Replace("{{MODEL}}", model.Id)
            .Replace("{{CONTEXT}}", model.ContextWindow.ToString())
            .Replace("{{BASE_URL}}", _m.Api.BaseUrl)
            .Replace("{{CATALOG_PATH}}", TomlKacis(KatalogYolu))
            .Replace("{{TOKEN_FIELD}}", _m.Codex.TokenField)
            .Replace("{{TOKEN}}", TomlKacis(anahtar));
        var s = CodexAyar.SablonuAyir(dolu);
        // Anahtar modunda web kitiyle birebir (canlida calisan "normal kurulum").
        if (anahtarGiris) s.SaglayiciSatirlar.Add("requires_openai_auth = true");
        return s;
    }

    public void CodexAyariYaz(string anahtar, Manifest.ModelInfo model, bool anahtarGiris)
    {
        Directory.CreateDirectory(CodexDizini);

        string? mevcut = null;
        if (File.Exists(AyarYolu))
        {
            try { mevcut = File.ReadAllText(AyarYolu, new UTF8Encoding(false, true)); }
            catch (DecoderFallbackException) { throw new KurulumHatasi("Codex ayarlanamadi: config.toml okunamadi (UTF-8 degil)."); }
            if (!File.Exists(AyarAnlikYedekYolu)) try { File.Copy(AyarYolu, AyarAnlikYedekYolu); } catch { }
        }

        var (yeni, buSeferki) = CodexAyar.Uygula(mevcut, Sablon(anahtar, model, anahtarGiris));
        var hata = CodexAyar.Dogrula(yeni);
        if (hata is not null) throw new KurulumHatasi("Codex ayarlanamadi: " + hata);

        // ILK kurulumun yedegi korunur.
        var yedek = buSeferki;
        if (File.Exists(YedekYolu))
        {
            try
            {
                var eski = JsonSerializer.Deserialize<CodexAyar.Yedek>(File.ReadAllText(YedekYolu));
                if (eski is not null)
                {
                    eski.YonetilenAnahtarlar = eski.YonetilenAnahtarlar.Union(buSeferki.YonetilenAnahtarlar)
                        .OrderBy(x => x, StringComparer.Ordinal).ToList();
                    yedek = eski;
                }
            }
            catch { }
        }
        AtomikYaz(YedekYolu, JsonSerializer.Serialize(yedek));
        AtomikYaz(AyarYolu, yeni);

        if (anahtarGiris)
        {
            if (!File.Exists(AuthYedekYolu) && !File.Exists(AuthYokIsareti))
            {
                if (File.Exists(AuthYolu)) File.Copy(AuthYolu, AuthYedekYolu);
                else File.WriteAllText(AuthYokIsareti, "");
            }
            var icerik = new Dictionary<string, string> { ["auth_mode"] = "apikey", ["OPENAI_API_KEY"] = anahtar };
            AtomikYaz(AuthYolu, JsonSerializer.Serialize(icerik, new JsonSerializerOptions { WriteIndented = true }) + "\n");
        }
        else
        {
            AuthGeriKoy();   // mod degisti: ChatGPT girisi geri gelsin
        }

        if (File.Exists(EskiProfilYolu)) try { File.Delete(EskiProfilYolu); } catch { }
        if (File.Exists(EskiKisayolYolu)) try { File.Delete(EskiKisayolYolu); } catch { }
    }

    private void AuthGeriKoy()
    {
        if (File.Exists(AuthYedekYolu))
        {
            File.Copy(AuthYedekYolu, AuthYolu, overwrite: true);
            File.Delete(AuthYedekYolu);
        }
        else if (File.Exists(AuthYokIsareti))
        {
            if (File.Exists(AuthYolu)) File.Delete(AuthYolu);
            File.Delete(AuthYokIsareti);
        }
    }

    // ── Baglanti testi (Codex biciminde, CLI'siz) ──────────────────────────

    /// Tek SSE satiri. Ilk TERMINAL olay kazanir: response.completed → tamam; response.failed/error → hata.
    public static (string Durum, string Mesaj) AkisSatiri(string satir)
    {
        if (!satir.StartsWith("data:")) return ("devam", "");
        try
        {
            using var doc = JsonDocument.Parse(satir[5..].Trim());
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("type", out var tipE)
                || tipE.ValueKind != JsonValueKind.String) return ("devam", "");
            var tip = tipE.GetString();
            if (tip == "response.completed") return ("tamam", "");
            if (tip == "response.failed" || tip == "error")
            {
                string mesaj = tip!;
                if (root.TryGetProperty("response", out var r) && r.ValueKind == JsonValueKind.Object
                    && r.TryGetProperty("error", out var e1) && e1.ValueKind == JsonValueKind.Object
                    && e1.TryGetProperty("message", out var m1) && m1.ValueKind == JsonValueKind.String)
                    mesaj = m1.GetString()!;
                else if (root.TryGetProperty("error", out var e2) && e2.ValueKind == JsonValueKind.Object
                    && e2.TryGetProperty("message", out var m2) && m2.ValueKind == JsonValueKind.String)
                    mesaj = m2.GetString()!;
                return ("hata", mesaj);
            }
        }
        catch { }
        return ("devam", "");
    }

    private async Task<(string Tur, string Mesaj)> TekIstekAsync(string anahtar, string model)
    {
        var govde = new Dictionary<string, object>
        {
            ["model"] = model,
            ["instructions"] = "Kisa cevap ver.",
            ["input"] = new object[]
            {
                new Dictionary<string, object>
                {
                    ["type"] = "message", ["role"] = "user",
                    ["content"] = new object[] { new Dictionary<string, object> { ["type"] = "input_text", ["text"] = "Sadece ok yaz" } },
                },
            },
            ["store"] = false,
            ["stream"] = true,
            ["reasoning"] = new Dictionary<string, object> { ["effort"] = "low" },
        };
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(90));
            using var http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
            using var req = new HttpRequestMessage(HttpMethod.Post, _m.Api.BaseUrl.TrimEnd('/') + "/responses");
            req.Headers.TryAddWithoutValidation("Authorization", _m.Api.AuthPrefix + anahtar);
            req.Headers.TryAddWithoutValidation("Accept", "text/event-stream");
            req.Content = new StringContent(JsonSerializer.Serialize(govde), Encoding.UTF8, "application/json");
            using var resp = await http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cts.Token);
            var kod = (int)resp.StatusCode;
            if (kod == 401) return ("yetkisiz", "");
            if (kod == 402 || kod == 403) return ("hakYok", "HTTP " + kod);
            if (kod != 200) return ("gecici", "HTTP " + kod);
            using var st = await resp.Content.ReadAsStreamAsync(cts.Token);
            using var rd = new StreamReader(st, Encoding.UTF8);
            var sayac = 0;
            while (true)
            {
                var l = await rd.ReadLineAsync(cts.Token);
                if (l is null) break;
                if (++sayac > 20000) return ("gecici", "akis cok uzun");
                var (d, m) = AkisSatiri(l);
                if (d == "tamam") return ("basarili", "");
                if (d == "hata") return ("gecici", m);
            }
            return ("gecici", "akis tamamlanmadi");
        }
        catch (Exception e) { return ("gecici", e.Message); }
    }

    /// Once hizli model (3 deneme); paket o modeli kapsamiyorsa secilen modelle (3 deneme).
    public async Task BaglantiyiDogrulaAsync(string anahtar, string secilenModel)
    {
        var modeller = new List<string> { DogrulamaModeli };
        if (secilenModel != DogrulamaModeli) modeller.Add(secilenModel);
        var sonHata = "bilinmeyen";
        var hakYok = false;
        foreach (var model in modeller)
        {
            hakYok = false;
            for (var deneme = 1; deneme <= 3; deneme++)
            {
                var (tur, m) = await TekIstekAsync(anahtar, model);
                if (tur == "basarili") return;
                if (tur == "yetkisiz") throw new KurulumHatasi("Anahtar gecersiz veya iptal edilmis. Panelden yeni anahtar olustur.");
                sonHata = model + ": " + m;
                if (tur == "hakYok") { hakYok = true; break; }
                if (deneme < 3) await Task.Delay(1500);
            }
        }
        throw new KurulumHatasi(hakYok
            ? "Anahtar gecerli ama istek reddedildi (" + sonHata + "). Panelden paketini/bakiyeni kontrol et."
            : "Baglanti test edilemedi: " + sonHata);
    }

    // ── Node / npm (yalniz Claude Code icin) ───────────────────────────────

    private async Task NodeHazirlaAsync(Action<string> bildir)
    {
        if (KomutVar("npm")) return;
        bildir("Node.js kuruluyor… (birkac dakika)");
        await NodeKurAsync();
    }

    /// ⚠️ winget KULLANMIYORUZ: Windows Server'da hic yok. Dogrudan MSI.
    private async Task NodeKurAsync()
    {
        var msi = Path.Combine(Path.GetTempPath(), "node-yzlab.msi");
        using (var http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) })
        {
            var bytes = await http.GetByteArrayAsync(_m.Node.Windows.Url);
            await File.WriteAllBytesAsync(msi, bytes);
        }
        var psi = new ProcessStartInfo("msiexec.exe", $"/i \"{msi}\" {_m.Node.Windows.SilentArgs}")
        { UseShellExecute = true, Verb = "runas" };
        using var p = Process.Start(psi) ?? throw new KurulumHatasi("Node kurulumu baslatilamadi.");
        await p.WaitForExitAsync();
        if (p.ExitCode != 0)
            throw new KurulumHatasi("Node kurulumu reddedildi veya basarisiz (kod " + p.ExitCode + ").");
        var makine = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.Machine) ?? "";
        var kullanici = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? "";
        Environment.SetEnvironmentVariable("PATH", makine + ";" + kullanici);
    }

    /// npm'in global bin dizini yeni kurulan Node'da surecimizin PATH'inde olmayabilir → ekle.
    private static void NpmGlobalBiniPathEkle()
    {
        var r = Calistir("cmd.exe", "/d /s /c \"npm prefix -g\"", 30_000);
        var prefix = r.Cikti.Split('\n').Select(x => x.Trim()).LastOrDefault(x => x.Length > 0);
        if (r.Kod != 0 || string.IsNullOrEmpty(prefix) || !Directory.Exists(prefix)) return;
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        if (!path.Split(';').Any(x => string.Equals(x.TrimEnd('\\'), prefix.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)))
            Environment.SetEnvironmentVariable("PATH", prefix + ";" + path);
    }

    /// Codex/Claude ciktisinda GERCEK yetki reddi var mi? Sayilarin icindeki "401"e kanmaz.
    public static bool YetkiReddiMi(string c)
    {
        if (c.Contains("Unauthorized") || c.Contains("authentication_error") || c.Contains("Invalid API key")
            || c.Contains("invalid_api_key") || c.Contains("gecersiz") || c.Contains("geçersiz")) return true;
        return Regex.IsMatch(c, @"(?i)(http|status|code)\D{0,4}401(\D|$)");
    }

    // ── Claude Code (istege bagli) ─────────────────────────────────────────

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

    /// settings.json'in YALNIZ `env` blogu; diger anahtarlar kalir. Ilk yazimdan once birebir yedek.
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

    /// settings.json'daki env ile Claude Code'un BIZE gittigini kanitlar. IZOLE (gecici CLAUDE_CONFIG_DIR).
    private void ClaudeDogrula()
    {
        var gecici = Path.Combine(Path.GetTempPath(), "yzlab-claude-dogrula-" + Guid.NewGuid().ToString("N"));
        var cfg = Path.Combine(gecici, "cfg");
        Directory.CreateDirectory(cfg);
        try
        {
            File.Copy(ClaudeAyarYolu, Path.Combine(cfg, _m.Claude.SettingsFile), overwrite: true);
            var r = Calistir("cmd.exe",
                $"/d /s /c \"{_m.Claude.LaunchCommand} -p \"Sadece ok yaz\" --model {DogrulamaModeli} --output-format json\"",
                180_000, new() { ["CLAUDE_CONFIG_DIR"] = cfg }, gecici);
            var c = r.Cikti;
            if (c.Contains("requires git-bash") || c.Contains("Git Bash"))
                throw new KurulumHatasi("Claude Code Windows'ta Git for Windows ister: git-scm.com'dan kur, sonra Yeniden Kur.");
            if (YetkiReddiMi(c))
                throw new KurulumHatasi("Anahtar gecersiz veya iptal edilmis.");
            if (!(c.Contains("\"stop_reason\"") || c.Contains("\"result\"")) || c.Contains("\"is_error\":true"))
                throw new KurulumHatasi("Claude Code dogrulama yaniti beklenmedik:\n" + Kisalt(c));
            if (!File.Exists(Path.Combine(cfg, ".claude.json")) && !Directory.Exists(Path.Combine(cfg, "projects")))
                throw new KurulumHatasi("Claude Code dogrulama izole kosmadi (CLAUDE_CONFIG_DIR ezildi?).");
        }
        finally
        {
            try { Directory.Delete(gecici, true); } catch { }
        }
    }

    // ── Geri al ────────────────────────────────────────────────────────────

    /// `kisayollar: false` → masaustu kisayollarina dokunulmaz (--selftest bunu kullanir).
    public void GeriAl(bool kisayollar = true)
    {
        GeriAlHatalari.Clear();
        if (File.Exists(YedekYolu))
        {
            try
            {
                var yedek = JsonSerializer.Deserialize<CodexAyar.Yedek>(File.ReadAllText(YedekYolu))
                            ?? throw new Exception("yedek bozuk");
                string? mevcut = File.Exists(AyarYolu) ? File.ReadAllText(AyarYolu) : null;
                var eski = CodexAyar.GeriAl(mevcut, yedek);
                if (eski is not null) AtomikYaz(AyarYolu, eski);
                else if (File.Exists(AyarYolu)) File.Delete(AyarYolu);
                File.Delete(YedekYolu);
            }
            catch (Exception e) { GeriAlHatalari.Add("config.toml: " + e.Message); }
        }
        try { AuthGeriKoy(); } catch (Exception e) { GeriAlHatalari.Add("auth.json: " + e.Message); }

        var hedefler = new List<string> { KatalogYolu, EskiProfilYolu };
        if (kisayollar) hedefler.Add(EskiKisayolYolu);
        foreach (var y in hedefler)
            try { if (File.Exists(y)) File.Delete(y); }
            catch (Exception e) { GeriAlHatalari.Add(Path.GetFileName(y) + ": " + e.Message); }

        ClaudeGeriAl(kisayollar);
    }

    public void ClaudeGeriAl(bool kisayol = true)
    {
        try
        {
            if (File.Exists(ClaudeYedekYolu))
            {
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
            // ⚠️ stdin KAPALI olmali: claude -p / codex exec boru stdin'de ASILI KALIR.
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
        p.WaitForExit();
        lock (sb) return new Sonuc(p.ExitCode, sb.ToString().Trim());
    }

    public static bool KomutVar(string komut) =>
        Calistir("cmd.exe", $"/d /s /c \"where {komut}\"", 15_000).Kod == 0;

    private static string Kisalt(string s) => s.Length <= 300 ? s : s[^300..];
}
