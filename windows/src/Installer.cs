using System.Diagnostics;
using System.Text;
using System.Text.Json;

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
                               Action<string> bildir)
    {
        bildir("Anahtar dogrulaniyor…");
        await AnahtariDogrulaAsync(anahtar);

        bildir("Codex aranıyor…");
        await CodexHazirlaAsync(bildir);

        bildir("Model katalogu indiriliyor…");
        await KataloguIndirAsync();

        bildir("Profil yaziliyor…");
        ProfiliYaz(anahtar, model);

        if (kisayol)
        {
            bildir("Kisayol olusturuluyor…");
            KisayolYaz();
        }

        bildir("Dogrulaniyor…");
        Dogrula();
    }

    /// Codex KURULUYSA hic dokunma. Boylece musterinin Codex'i acikken de kurulum
    /// yapilabilir: Windows'ta calisan codex.exe npm guncellemesini EBUSY ile kilitler.
    private async Task CodexHazirlaAsync(Action<string> bildir)
    {
        if (KomutVar("codex")) return;

        if (!KomutVar("npm"))
        {
            bildir("Node.js kuruluyor… (birkac dakika)");
            await NodeKurAsync();
        }

        bildir("Codex CLI kuruluyor… (birkac dakika)");
        var r = Calistir("cmd.exe", $"/d /s /c \"npm install -g {_m.Codex.NpmPackage}\"", 1_200_000);
        if (!KomutVar("codex"))
            throw new KurulumHatasi("Codex kurulamadi: " + Kisalt(r.Cikti));
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

    private async Task KataloguIndirAsync()
    {
        string json;
        using (var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) })
        {
            try { json = await http.GetStringAsync(_m.Codex.CatalogUrl); }
            catch (Exception e) { throw new KurulumHatasi("Model katalogu indirilemedi: " + e.Message); }
        }
        try { using var _ = JsonDocument.Parse(json); }
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
    private void Dogrula()
    {
        var r = Calistir("cmd.exe",
            $"/d /s /c \"codex exec -p {_m.Codex.ProfileName} --skip-git-repo-check ok\"", 120_000);
        var c = r.Cikti;
        if (c.Contains("401") || c.Contains("gecersiz") || c.Contains("geçersiz"))
            throw new KurulumHatasi("Anahtar gecersiz veya iptal edilmis.");
        if (c.Contains("failed to parse model_catalog_json"))
            throw new KurulumHatasi("Model katalogu bozuk indi — tekrar dene.");
        if (!c.Contains("yapayzekalab"))
            throw new KurulumHatasi("Profil yuklenmedi:\n" + Kisalt(c));
    }

    public void GeriAl()
    {
        foreach (var y in new[] { ProfilYolu, KatalogYolu, KisayolYolu })
            try { if (File.Exists(y)) File.Delete(y); } catch { }
    }

    // ── yardimcilar ────────────────────────────────────────────────────────

    public readonly record struct Sonuc(int Kod, string Cikti);

    public static Sonuc Calistir(string dosya, string arg, int msTimeout)
    {
        var psi = new ProcessStartInfo(dosya, arg)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        using var p = Process.Start(psi);
        if (p is null) return new Sonuc(127, "calistirilamadi");

        var sb = new StringBuilder();
        p.OutputDataReceived += (_, e) => { if (e.Data is not null) sb.AppendLine(e.Data); };
        p.ErrorDataReceived += (_, e) => { if (e.Data is not null) sb.AppendLine(e.Data); };
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();

        if (!p.WaitForExit(msTimeout))
        {
            try { p.Kill(true); } catch { }
            return new Sonuc(124, sb + "\n(zaman asimi)");
        }
        return new Sonuc(p.ExitCode, sb.ToString().Trim());
    }

    public static bool KomutVar(string komut) =>
        Calistir("cmd.exe", $"/d /s /c \"where {komut}\"", 15_000).Kod == 0;

    private static string Kisalt(string s) =>
        s.Length <= 300 ? s : s[^300..];
}
