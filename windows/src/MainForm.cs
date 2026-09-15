namespace YzlabKurucu;

public sealed class MainForm : Form
{
    private readonly Manifest _m;
    private readonly Kurucu _k;
    private readonly bool _canli;

    private readonly TextBox _anahtar = new();
    private readonly ComboBox _model = new();
    private readonly CheckBox _anahtarGiris = new();
    private readonly CheckBox _claude = new();
    private readonly Label _durum = new();
    private readonly ProgressBar _ilerleme = new();
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
        ClientSize = new Size(480, 600);
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
        Baslik("Codex masaustu kurulumu", 10.5F, FontStyle.Regular, Color.Gray, y); y += 34;

        Baslik("API anahtarin", 8.5F, FontStyle.Bold, Color.Gray, y); y += 20;
        _anahtar.Location = new Point(26, y);
        _anahtar.Size = new Size(428, 26);
        _anahtar.UseSystemPasswordChar = true;
        _anahtar.PlaceholderText = _m.Api.KeyPrefix + "…";
        _anahtar.TextChanged += AnahtarDegisti;
        Controls.Add(_anahtar); y += 32;

        _durum.Location = new Point(26, y);
        _durum.Size = new Size(428, 48);
        _durum.ForeColor = Color.Gray;
        _durum.Font = new Font("Segoe UI", 8.25F);
        _durum.Text = "Panelinden kopyalayip yapistir.";
        Controls.Add(_durum); y += 54;

        Baslik("Model", 8.5F, FontStyle.Bold, Color.Gray, y); y += 20;
        _model.Location = new Point(26, y);
        _model.Size = new Size(428, 26);
        _model.DropDownStyle = ComboBoxStyle.DropDownList;
        foreach (var mm in _m.Codex.Models) _model.Items.Add(mm);
        _model.SelectedIndex = Math.Max(0, _m.Codex.Models.FindIndex(x => x.Id == _m.Codex.DefaultModel));
        Controls.Add(_model); y += 40;

        _anahtarGiris.Text = "ChatGPT hesabim yerine yalniz anahtarla gir";
        _anahtarGiris.Checked = false;
        _anahtarGiris.AutoSize = true;
        _anahtarGiris.Location = new Point(24, y);
        Controls.Add(_anahtarGiris); y += 22;
        Controls.Add(new Label {
            Text = "Codex'te hala \"hakkiniz yok / usage limit\" cikiyorsa isaretle. Geri Al hesabini geri getirir.",
            Location = new Point(42, y), Size = new Size(412, 32),
            ForeColor = Color.Gray, Font = new Font("Segoe UI", 8.25F) });
        y += 36;

        _claude.Text = "Claude Code'u da bagla (terminal + Claude masaustu)";
        _claude.Checked = false;
        _claude.AutoSize = true;
        _claude.Location = new Point(24, y);
        Controls.Add(_claude); y += 34;

        Controls.Add(new Label { BorderStyle = BorderStyle.Fixed3D,
            Location = new Point(26, y), Size = new Size(428, 2) }); y += 14;

        Baslik("🔒 Mevcut ayarlarin korunur", 9F, FontStyle.Bold, Color.FromArgb(25, 25, 25), y); y += 22;
        Controls.Add(new Label {
            Text = "Codex'in config.toml dosyasina isaretli bir blok eklenir, onceki hali saklanir. "
                 + "ChatGPT girisin durur. Codex aciksa kapatilip kurulumdan sonra yeniden acilir. "
                 + "Geri Al her seyi birebir geri koyar.",
            Location = new Point(26, y), Size = new Size(428, 64),
            ForeColor = Color.Gray, Font = new Font("Segoe UI", 8.25F) });
        y += 66;

        if (!_canli)
            Baslik("Sunucuya ulasilamadi — gomulu ayarlar kullaniliyor.", 8.25F, FontStyle.Regular, Color.DarkOrange, y);

        _ilerleme.Style = ProgressBarStyle.Marquee;
        _ilerleme.MarqueeAnimationSpeed = 30;
        _ilerleme.Location = new Point(130, 551);
        _ilerleme.Size = new Size(200, 10);
        _ilerleme.Visible = false;
        Controls.Add(_ilerleme);

        _kur.Text = _k.KuruluMu ? "Yeniden Kur" : "Kur";
        _kur.Size = new Size(110, 32);
        _kur.Location = new Point(344, 540);
        _kur.Enabled = false;
        _kur.Click += async (_, __) => await KurulumuBaslat();
        Controls.Add(_kur);
        AcceptButton = _kur;

        _geriAl.Text = "Geri Al";
        _geriAl.Size = new Size(90, 32);
        _geriAl.Location = new Point(26, 540);
        _geriAl.Visible = _k.KuruluMu || _k.ClaudeKuruluMu;
        _geriAl.Click += (_, __) =>
        {
            _k.GeriAl();
            _geriAl.Visible = _k.KuruluMu || _k.ClaudeKuruluMu;
            _kur.Text = "Kur";
            if (_k.GeriAlHatalari.Count > 0)
                Durum("⚠ Geri alma eksik kaldi: " + string.Join("; ", _k.GeriAlHatalari), Color.DarkOrange);
            else
                Durum("Geri alindi. Codex ve Claude Code ayarlarin kurulumdan onceki haline dondu.", Color.Gray);
        };
        Controls.Add(_geriAl);

        PanodanAnahtar();
    }

    /// TEK TIK: panoda `yzk_live_…` varsa alana kendiliginden girer.
    private void PanodanAnahtar()
    {
        try
        {
            if (!Clipboard.ContainsText()) return;
            var s = Clipboard.GetText().Trim();
            if (s.StartsWith(_m.Api.KeyPrefix) && s.Length >= 20 && s.Length <= 200
                && !s.Contains(' ') && !s.Contains('\n'))
                _anahtar.Text = s;
        }
        catch { }
    }

    private void Durum(string s, Color c) { _durum.Text = s; _durum.ForeColor = c; }

    /// Bekleme imleci YOK (pencere "donmus" gibi gorunuyordu); yerine donen ilerleme cubugu.
    private void Mesgul(bool m)
    {
        _mesgul = m;
        _anahtar.Enabled = _model.Enabled = _anahtarGiris.Enabled = _claude.Enabled = !m;
        _kur.Enabled = !m && _anahtarGecerli;
        _geriAl.Enabled = !m;
        _ilerleme.Visible = m;
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
        var kapatIzni = false;
        if (Kurucu.AcikCodexUygulamalari().Count > 0)
        {
            var c = MessageBox.Show(this,
                "Codex acik. Ayarin gecmesi icin Codex kapatilacak ve kurulum bitince yeniden acilacak.",
                "Codex acik", MessageBoxButtons.OKCancel, MessageBoxIcon.Information);
            if (c != DialogResult.OK) return;
            kapatIzni = true;
        }

        Mesgul(true);
        try
        {
            var model = (Manifest.ModelInfo)_model.SelectedItem!;
            var anahtar = _anahtar.Text.Trim();
            var claude = _claude.Checked;
            var giris = _anahtarGiris.Checked;
            // Kurulum ARKA PLAN is parcaciginda (UI donmasin); durum metni Invoke ile tasinir.
            await Task.Run(() => _k.KurAsync(anahtar, model,
                s => { try { BeginInvoke(() => Durum(s, Color.Gray)); } catch { } },
                claude, giris, kapatIzni));
            Durum(claude
                ? "✓ Kuruldu. Codex'i ac ve yaz. Claude Code: yeni terminalde claude."
                : "✓ Kuruldu. Codex'i ac ve yaz — istekler YapayZekaLab'dan gecer.", Color.SeaGreen);
            _geriAl.Visible = true;
            _kur.Text = "Yeniden Kur";
        }
        catch (Exception ex)
        {
            Durum("⚠ " + ex.Message, Color.DarkOrange);
            _geriAl.Visible = _k.KuruluMu || _k.ClaudeKuruluMu;
        }
        finally { Mesgul(false); }
    }
}
