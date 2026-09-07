using System.Text.Json;

namespace YzlabKurucu;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--selftest")
            return SelfTest.Calistir();

        ApplicationConfiguration.Initialize();
        var (m, canli) = Manifest.LoadAsync().GetAwaiter().GetResult();
        Application.Run(new MainForm(m, canli));
        return 0;
    }
}

/// Windows makinemiz olmadigi icin TEK dogrulama yolumuz bu: CI her build'de kosar.
/// GUI'yi test edemez ama kurulum mantiginin invaryantlarini test eder.
internal static class SelfTest
{
    private static int _gecen, _kalan;

    private static void Kontrol(bool kosul, string ad)
    {
        if (kosul) { _gecen++; Console.WriteLine($"  PASS  {ad}"); }
        else { _kalan++; Console.WriteLine($"  FAIL  {ad}"); }
    }

    public static int Calistir()
    {
        Console.WriteLine("YzlabKurucu — kendi kendini sinama\n");

        // 1) Gomulu manifest bozulmadan derlendi mi?
        Manifest gomulu;
        try { gomulu = Manifest.Embedded; }
        catch (Exception e) { Console.WriteLine("FATAL gomulu manifest: " + e.Message); return 1; }
        Kontrol(gomulu.Codex.Models.Count > 0, "gomulu manifest cozuluyor");
        Kontrol(!string.IsNullOrEmpty(gomulu.Codex.ProfileTemplate), "profil sablonu dolu");
        Kontrol(gomulu.Codex.Models.Any(x => x.Id == gomulu.Codex.DefaultModel),
                "varsayilan model listede var");

        // 2) Canli manifest ve katalog gercekten cekilebiliyor mu?
        var (canliM, canliMi) = Manifest.LoadAsync().GetAwaiter().GetResult();
        Console.WriteLine(canliMi ? "  bilgi canli manifest CEKILDI"
                                  : "  bilgi canli manifest YOK — gomuluye dusuldu");
        var kaynak = canliMi ? canliM : gomulu;

        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            var kat = http.GetStringAsync(kaynak.Codex.CatalogUrl).GetAwaiter().GetResult();
            using var doc = JsonDocument.Parse(kat);
            var adet = doc.RootElement.GetProperty("models").GetArrayLength();
            Kontrol(adet > 0, $"model katalogu indi ve cozuldu ({adet} model)");
        }
        catch (Exception e) { Kontrol(false, "model katalogu indi: " + e.Message); }

        // 3) Izole bir CODEX_HOME kurup gercek yazma yolunu calistir.
        var gecici = Path.Combine(Path.GetTempPath(), "yzlab-selftest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(gecici);
        Environment.SetEnvironmentVariable("CODEX_HOME", gecici);
        try
        {
            var k = new Kurucu(kaynak);
            Kontrol(k.CodexDizini == gecici, "CODEX_HOME dikkate aliniyor");

            // ⚠️ EN ONEMLI INVARYANT: musterinin mevcut dosyalarina DOKUNMAMALIYIZ.
            var cfg = Path.Combine(gecici, "config.toml");
            var auth = Path.Combine(gecici, "auth.json");
            File.WriteAllText(cfg, "model = \"kendi-modelim\"\n");
            File.WriteAllText(auth, "{\"auth_mode\":\"chatgpt\"}");
            var cfgOnce = File.ReadAllText(cfg);
            var authOnce = File.ReadAllText(auth);

            var model = kaynak.Codex.Models[0];
            typeof(Kurucu).GetMethod("ProfiliYaz",
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!
                .Invoke(k, new object[] { "yzk_live_TESTTESTTESTTEST", model });

            Kontrol(File.ReadAllText(cfg) == cfgOnce, "config.toml DEGISMEDI");
            Kontrol(File.ReadAllText(auth) == authOnce, "auth.json DEGISMEDI");
            Kontrol(File.Exists(k.ProfilYolu), "profil dosyasi yazildi");

            var profil = File.ReadAllText(k.ProfilYolu);
            Kontrol(!profil.Contains("{{"), "sablonda doldurulmamis yer tutucu YOK");
            Kontrol(profil.Contains(model.Id), "model yazildi");
            Kontrol(profil.Contains("yzk_live_TESTTESTTESTTEST"), "anahtar yazildi");
            Kontrol(profil.Contains(kaynak.Api.BaseUrl), "base_url yazildi");
            Kontrol(profil.Contains(kaynak.Codex.TokenField), "token alani yazildi");
            // Windows yolu TOML'da \\ olarak kacilmali, yoksa Codex parse edemez.
            Kontrol(!profil.Contains(":\\") || profil.Contains(":\\\\"),
                    "katalog yolu TOML icin kacisli");

            k.GeriAl();
            Kontrol(!File.Exists(k.ProfilYolu), "geri al profili sildi");
            Kontrol(File.Exists(cfg) && File.Exists(auth), "geri al musterinin dosyalarina dokunmadi");
        }
        finally
        {
            Environment.SetEnvironmentVariable("CODEX_HOME", null);
            try { Directory.Delete(gecici, true); } catch { }
        }

        // 4) Kisayol COM yolu bu makinede calisiyor mu?
        try
        {
            var tip = Type.GetTypeFromProgID("WScript.Shell");
            Kontrol(tip is not null, "WScript.Shell COM erisilebilir");
        }
        catch (Exception e) { Kontrol(false, "WScript.Shell: " + e.Message); }

        Console.WriteLine($"\n{_gecen} gecti, {_kalan} kaldi");
        return _kalan == 0 ? 0 : 1;
    }
}
