using System.ComponentModel;

namespace YzlabKurucu;

public sealed class MainForm : Form
{
    private readonly Manifest _m;
    private readonly Kurucu _k;
    private readonly bool _canli;

    private readonly TextBox _anahtar = new();
    private readonly ComboBox _model = new();
    private readonly CheckBox _kisayol = new();
    private readonly Label _durum = new();
    private readonly Button _kur = new();
    private readonly Button _geriAl = new();

    private CancellationTokenSource? _dogrulama;
    private bool _anahtarGecerli;
    private bool _mesgul;

    public MainForm(Manifest m, bool canli)
    {
        _m = m; _canli = canli; _k = new Kurucu(m);
        KurArayuz();
    }

    private void KurArayuz()
    {
        Text = "YapayZekaLab Codex Kurulumu";
        ClientSize = new Size(460, 470);
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(250, 250, 250);
        Font = new Font("Segoe UI", 9F);

        int y = 22;
        Label Baslik(string s, float boyut, FontStyle st, Color c, int ust)
        {
            var l = new Label { Text = s, AutoSize = true, ForeColor = c,
                Font = new Font("Segoe UI", boyut, st), Location = new Point(26, ust) };
            Controls.Add(l); return l;
        }

        Baslik("YapayZekaLab", 16F, FontStyle.Bold, Color.FromArgb(25, 25, 25), y); y += 30;
        Baslik("Codex Kurulumu", 10.5F, FontStyle.Regular, Color.Gray, y); y += 34;

        Baslik("API anahtarin", 8.5F, FontStyle.Bold, Color.Gray, y); y += 20;
        _anahtar.Location = new Point(26, y);
        _anahtar.Size = new Size(408, 26);
        _anahtar.UseSystemPasswordChar = true;
        _anahtar.PlaceholderText = _m.Api.KeyPrefix + "…";
        _anahtar.TextChanged += AnahtarDegisti;
        Controls.Add(_anahtar); y += 32;

        _durum.Location = new Point(26, y);
        _durum.Size = new Size(408, 34);
        _durum.ForeColor = Color.Gray;
        _durum.Font = new Font("Segoe UI", 8.25F);
        _durum.Text = "Panelinden kopyalayip yapistir.";
        Controls.Add(_durum); y += 42;

        Baslik("Model", 8.5F, FontStyle.Bold, Color.Gray, y); y += 20;
        _model.Location = new Point(26, y);
        _model.Size = new Size(408, 26);
        _model.DropDownStyle = ComboBoxStyle.DropDownList;
        foreach (var mm in _m.Codex.Models) _model.Items.Add(mm);
        _model.SelectedIndex = Math.Max(0,
            _m.Codex.Models.FindIndex(x => x.Id == _m.Codex.DefaultModel));
        Controls.Add(_model); y += 30;

        Baslik($"Sonradan degistirebilirsin: {_m.Codex.ProfileFile} icindeki model satiri.",
               8.25F, FontStyle.Regular, Color.Gray, y); y += 30;

        _kisayol.Text = "Masaustune kisayol ekle";
        _kisayol.Checked = true;
        _kisayol.AutoSize = true;
        _kisayol.Location = new Point(24, y);
        Controls.Add(_kisayol); y += 34;

        Controls.Add(new Label { BorderStyle = BorderStyle.Fixed3D,
            Location = new Point(26, y), Size = new Size(408, 2) }); y += 14;

        Baslik("🔒 ChatGPT Plus ayarlarina dokunulmaz", 9F, FontStyle.Bold,
               Color.FromArgb(25, 25, 25), y); y += 22;
        var guvence = new Label {
            Text = "Kurulum ayri bir profil dosyasi olusturur. Mevcut config.toml ve "
                 + "auth.json aynen kalir; codex eskisi gibi, "
                 + $"codex -p {_m.Codex.ProfileName} bizim uzerimizden calisir.",
            Location = new Point(26, y), Size = new Size(408, 46),
            ForeColor = Color.Gray, Font = new Font("Segoe UI", 8.25F) };
        Controls.Add(guvence); y += 48;

        if (!_canli)
        {
            Baslik("Sunucuya ulasilamadi — gomulu ayarlar kullaniliyor.",
                   8.25F, FontStyle.Regular, Color.DarkOrange, y);
        }

        _kur.Text = _k.KuruluMu ? "Yeniden Kur" : "Kur";
        _kur.Size = new Size(110, 32);
        _kur.Location = new Point(324, 412);
        _kur.Enabled = false;
        _kur.Click += async (_, __) => await KurulumuBaslat();
        Controls.Add(_kur);
        AcceptButton = _kur;

        _geriAl.Text = "Geri Al";
        _geriAl.Size = new Size(90, 32);
        _geriAl.Location = new Point(26, 412);
        _geriAl.Visible = _k.KuruluMu;
        _geriAl.Click += (_, __) =>
        {
            _k.GeriAl();
            _geriAl.Visible = false;
            _kur.Text = "Kur";
            Durum("Geri alindi. Codex ayarlarin kurulumdan onceki haline dondu.", Color.Gray);
        };
        Controls.Add(_geriAl);
    }

    private void Durum(string s, Color c) { _durum.Text = s; _durum.ForeColor = c; }

    private void Mesgul(bool m)
    {
        _mesgul = m;
        _anahtar.Enabled = _model.Enabled = _kisayol.Enabled = !m;
        _kur.Enabled = !m && _anahtarGecerli;
        _geriAl.Enabled = !m;
        Cursor = m ? Cursors.WaitCursor : Cursors.Default;
    }

    private async void AnahtarDegisti(object? s, EventArgs e)
    {
        _dogrulama?.Cancel();
        _anahtarGecerli = false;
        _kur.Enabled = false;

        var temiz = _anahtar.Text.Trim();
        if (temiz.Length < 20) { Durum("Panelinden kopyalayip yapistir.", Color.Gray); return; }

        Durum("Kontrol ediliyor…", Color.Gray);
        var cts = new CancellationTokenSource();
        _dogrulama = cts;
        try
        {
            // Yapistirma sirasinda her karakterde istek atmamak icin kisa bekleme.
            await Task.Delay(500, cts.Token);
            var bakiye = await _k.AnahtariDogrulaAsync(temiz);
            if (cts.IsCancellationRequested) return;
            _anahtarGecerli = true;
            _kur.Enabled = !_mesgul;
            Durum($"✓ Anahtar gecerli · bakiye ₺{bakiye}", Color.SeaGreen);
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            if (!cts.IsCancellationRequested) Durum("⚠ " + ex.Message, Color.DarkOrange);
        }
    }

    private async Task KurulumuBaslat()
    {
        Mesgul(true);
        try
        {
            var model = (Manifest.ModelInfo)_model.SelectedItem!;
            await _k.KurAsync(_anahtar.Text.Trim(), model, _kisayol.Checked,
                              s => Durum(s, Color.Gray));
            Durum($"✓ Kuruldu. Masaustundeki kisayoldan veya "
                + $"codex -p {_m.Codex.ProfileName} ile calistir.", Color.SeaGreen);
            _geriAl.Visible = true;
            _kur.Text = "Yeniden Kur";
        }
        catch (Exception ex)
        {
            Durum("⚠ " + ex.Message, Color.DarkOrange);
        }
        finally { Mesgul(false); }
    }
}
