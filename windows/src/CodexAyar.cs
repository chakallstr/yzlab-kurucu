using System.Text.Json.Serialization;

namespace YzlabKurucu;

/// Codex `config.toml`'a YapayZekaLab yonlendirmesini ISARETLI bloklarla ekler / kaldirir.
///
/// NEDEN PROFIL DEGIL: Codex MASAUSTU uygulamasi `-p yzlab` profilini okumaz (2026-09-15 musteri
/// kamer5561: kurucu "Kuruldu" dedi ama masaustu kendi ChatGPT hesabiyla gitti → "hakkiniz yok").
/// Sahibin CALISAN masaustu kurulumu ana config.toml'da model_provider + [model_providers.yapayzekalab]
/// (experimental_bearer_token) kullaniyor; auth.json'daki ChatGPT girisi duruyor.
///
/// Saf metin islemi. macOS karsiligi `CodexAyar.swift` BIREBIR ayni kurallar.
public static class CodexAyar
{
    public const string UstBas = "# >>> YapayZekaLab kurucu: ust ayarlar (Geri Al kaldirir; elle degistirme)";
    public const string UstSon = "# <<< YapayZekaLab kurucu: ust ayarlar";
    public const string SagBas = "# >>> YapayZekaLab kurucu: saglayici";
    public const string SagSon = "# <<< YapayZekaLab kurucu: saglayici";
    public const string Saglayici = "yapayzekalab";

    /// Kurulumdan ONCE dosyada olup bizim kaldirdigimiz seyler. Geri Al bunlari geri koyar.
    public sealed class Yedek
    {
        [JsonPropertyName("dosyaYoktu")] public bool DosyaYoktu { get; set; }
        [JsonPropertyName("ustSatirlar")] public List<string> UstSatirlar { get; set; } = new();
        [JsonPropertyName("saglayiciBlogu")] public List<string> SaglayiciBlogu { get; set; } = new();
        [JsonPropertyName("yonetilenAnahtarlar")] public List<string> YonetilenAnahtarlar { get; set; } = new();
    }

    public sealed record Sablon(List<string> UstSatirlar, List<string> Anahtarlar, List<string> SaglayiciSatirlar);

    // ── Satir yardimcilari ────────────────────────────────────────────────

    public static (List<string> Satirlar, string Nl) SatirlaraAyir(string? metin)
    {
        var s = metin ?? "";
        if (s.Length > 0 && s[0] == '﻿') s = s[1..];
        var nl = s.Contains("\r\n") ? "\r\n" : "\n";
        var parca = s.Replace("\r\n", "\n").Split('\n').ToList();
        if (parca.Count > 0 && parca[^1] == "") parca.RemoveAt(parca.Count - 1);
        return (parca, nl);
    }

    public static bool BosMu(string l) => string.IsNullOrWhiteSpace(l);
    public static bool BasliMi(string l) => l.TrimStart().StartsWith('[');

    public static string? Anahtar(string l)
    {
        var t = l.Trim();
        if (t.Length == 0 || t[0] == '#' || t[0] == '[') return null;
        var e = t.IndexOf('=');
        if (e <= 0) return null;
        var k = t[..e].Trim();
        if (k.Length >= 2 && ((k[0] == '"' && k[^1] == '"') || (k[0] == '\'' && k[^1] == '\'')))
            k = k[1..^1];
        return k.Length == 0 ? null : k;
    }

    public static string? BaslikAdi(string l)
    {
        var t = l.Trim();
        if (!t.StartsWith('[')) return null;
        var kapa = t.LastIndexOf(']');
        if (kapa < 0) return null;
        var ic = t[..(kapa + 1)].Trim('[', ']');
        return ic.Replace(" ", "").Replace("\"", "").Replace("'", "");
    }

    public static bool SaglayiciBasligiMi(string l)
    {
        var ad = BaslikAdi(l);
        if (ad is null) return false;
        return ad == "model_providers." + Saglayici || ad.StartsWith("model_providers." + Saglayici + ".");
    }

    public static List<string> IsaretlileriSil(List<string> L)
    {
        var outL = new List<string>();
        var i = 0;
        while (i < L.Count)
        {
            var t = L[i].Trim();
            if (t == UstBas || t == SagBas)
            {
                var son = t == UstBas ? UstSon : SagSon;
                var j = -1;
                for (var x = i + 1; x < L.Count; x++) if (L[x].Trim() == son) { j = x; break; }
                i = j >= 0 ? j + 1 : i + 1;
                continue;
            }
            if (t == UstSon || t == SagSon) { i++; continue; }
            outL.Add(L[i]);
            i++;
        }
        return outL;
    }

    public static (List<string> Ust, List<string> Kalan, List<string> YUst, List<string> YSag)
        Ayikla(List<string> L, HashSet<string> anahtarlar)
    {
        var ilk = L.FindIndex(BasliMi);
        if (ilk < 0) ilk = L.Count;
        var ust = new List<string>(); var yUst = new List<string>();
        for (var i = 0; i < ilk; i++)
        {
            var k = Anahtar(L[i]);
            if (k is not null && anahtarlar.Contains(k)) yUst.Add(L[i]); else ust.Add(L[i]);
        }
        var kalan = new List<string>(); var ySag = new List<string>();
        var siliyor = false;
        for (var i = ilk; i < L.Count; i++)
        {
            if (BasliMi(L[i])) siliyor = SaglayiciBasligiMi(L[i]);
            if (siliyor) ySag.Add(L[i]); else kalan.Add(L[i]);
        }
        while (ySag.Count > 0 && BosMu(ySag[^1])) ySag.RemoveAt(ySag.Count - 1);
        while (ust.Count > 0 && BosMu(ust[0])) ust.RemoveAt(0);
        return (ust, kalan, yUst, ySag);
    }

    // ── Sablon ────────────────────────────────────────────────────────────

    /// Doldurulmus profil sablonunu ust anahtarlara + saglayici tablosuna ayirir.
    /// [tools] gibi DIGER tablolar ALINMAZ: musterinin kendi tablosuyla cakisip TOML'u bozar.
    public static Sablon SablonuAyir(string dolu)
    {
        var L = SatirlaraAyir(dolu).Satirlar;
        var ust = new List<string>(); var anah = new List<string>(); var sag = new List<string>();
        bool baslikGoruldu = false, saglayicida = false;
        foreach (var l in L)
        {
            if (BasliMi(l))
            {
                baslikGoruldu = true;
                saglayicida = SaglayiciBasligiMi(l);
                if (saglayicida) sag.Add(l.Trim());
                continue;
            }
            var t = l.Trim();
            if (!baslikGoruldu)
            {
                var k = Anahtar(l);
                if (k is not null) { ust.Add(t); anah.Add(k); }
            }
            else if (saglayicida && t.Length > 0 && t[0] != '#')
            {
                sag.Add(t);
            }
        }
        return new Sablon(ust, anah, sag);
    }

    // ── Uygula / Geri al / Dogrula ────────────────────────────────────────

    public static (string Metin, Yedek Yedek) Uygula(string? mevcut, Sablon sablon)
    {
        var (ham, nl) = SatirlaraAyir(mevcut);
        var a = Ayikla(IsaretlileriSil(ham), new HashSet<string>(sablon.Anahtarlar));
        var outL = new List<string> { UstBas };
        outL.AddRange(sablon.UstSatirlar);
        outL.Add(UstSon);
        var govde = a.Ust.Concat(a.Kalan).ToList();
        if (govde.Count > 0) { outL.Add(""); outL.AddRange(govde); }
        while (outL.Count > 0 && BosMu(outL[^1])) outL.RemoveAt(outL.Count - 1);
        outL.Add(""); outL.Add(SagBas); outL.AddRange(sablon.SaglayiciSatirlar); outL.Add(SagSon);
        var yedek = new Yedek
        {
            DosyaYoktu = mevcut is null,
            UstSatirlar = a.YUst,
            SaglayiciBlogu = a.YSag,
            YonetilenAnahtarlar = sablon.Anahtarlar.ToList(),
        };
        return (string.Join(nl, outL) + nl, yedek);
    }

    /// null → dosya kurulumdan once YOKTU ve geriye bir sey kalmadi (sil).
    public static string? GeriAl(string? mevcut, Yedek yedek)
    {
        var (ham, nl) = SatirlaraAyir(mevcut);
        var a = Ayikla(IsaretlileriSil(ham), new HashSet<string>(yedek.YonetilenAnahtarlar));
        var govde = a.Ust.Concat(a.Kalan).ToList();
        while (govde.Count > 0 && BosMu(govde[0])) govde.RemoveAt(0);
        var outL = new List<string>(yedek.UstSatirlar);
        if (outL.Count > 0 && govde.Count > 0 && BasliMi(govde[0])) outL.Add("");
        outL.AddRange(govde);
        while (outL.Count > 0 && BosMu(outL[^1])) outL.RemoveAt(outL.Count - 1);
        if (yedek.SaglayiciBlogu.Count > 0)
        {
            if (outL.Count > 0) outL.Add("");
            outL.AddRange(yedek.SaglayiciBlogu);
        }
        if (outL.All(BosMu)) return yedek.DosyaYoktu ? null : "";
        return string.Join(nl, outL) + nl;
    }

    /// Codex'i ACILMAZ yapacak hatalari yakalar. null = sorun yok.
    public static string? Dogrula(string metin)
    {
        var L = SatirlaraAyir(metin).Satirlar;
        var ilk = L.FindIndex(BasliMi);
        if (ilk < 0) ilk = L.Count;
        var gorulen = new HashSet<string>();
        for (var i = 0; i < ilk; i++)
        {
            var k = Anahtar(L[i]);
            if (k is null) continue;
            if (!gorulen.Add(k)) return "config.toml'da ayni ust anahtar iki kez: " + k;
        }
        var basliklar = new HashSet<string>();
        for (var i = ilk; i < L.Count; i++)
        {
            if (!BasliMi(L[i]) || L[i].TrimStart().StartsWith("[[")) continue;
            var ad = BaslikAdi(L[i]);
            if (ad is null) continue;
            if (!basliklar.Add(ad)) return "config.toml'da ayni tablo iki kez: [" + ad + "]";
        }
        if (!basliklar.Contains("model_providers." + Saglayici)) return "saglayici tablosu yazilamadi";
        string? saglayiciSatiri = null;
        for (var i = 0; i < ilk; i++) if (Anahtar(L[i]) == "model_provider") { saglayiciSatiri = L[i]; break; }
        if (saglayiciSatiri is null || !saglayiciSatiri.Contains("\"" + Saglayici + "\""))
            return "model_provider yapayzekalab degil";
        return null;
    }
}
