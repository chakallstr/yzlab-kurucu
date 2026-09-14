# yzlab Codex Kurucu — Tasarım

Durum: **2026-09-14 · uçtan uca TAM (mac gerçek makine, win CI gerçek anahtar).** Yayın: GitHub Release `v0.1.0`.
İlk tasarım 2026-09-07; o günkü açık işler aşağıda "Kapanış" bölümünde.

## Amaç
Müşteri anahtarını yapıştırsın, Codex CLI/IDE/masaüstünde yapayzekalab.org üzerinden
çalışsın — **kendi ChatGPT Plus'ı bozulmadan**, yan yana.

Web Codex (chatgpt.com/codex) kapsam DIŞI: sunucu tarafı, istemci ayarı yok.

## Temel ilke: hiçbir şeyi ezme
| Dosya | Biz |
|---|---|
| `~/.codex/config.toml` | dokunma |
| `~/.codex/auth.json` | dokunma (Plus oturumu sağlam) |
| `~/.codex/yzlab.config.toml` | ✅ tek yazdığımız dosya (0600) |
| `~/.codex/yzlab-model-catalog.json` | ✅ ikinci dosya (model metadata) |

Geri alma = bu iki dosyayı + kısayolu sil. ZendiKey'in 200+ satırlık yedek/restore
mekanizmasına ihtiyaç yok.

Codex profil mekaniği (`codex -p <ad>` → `$CODEX_HOME/<ad>.config.toml` taban configin
ÜSTÜNE katmanlanır; 0.153.4'te `--profile <CONFIG_PROFILE_V2>`) bu tasarımı mümkün kılan şey.

## Manifest — beyin sunucuda
`https://yapayzekalab.org/kurulum/codex.json`
Kaynak: `~/yzlab-live/apps/web/public/kurulum/codex.json`

`next.config` içinde `output: 'standalone'` YOK → `next start` `public/`i diskten okur.
**Dosyayı VPS'te düzenlemek anında etki eder — build ve restart GEREKMEZ.**
Model değişimi, `experimental_bearer_token` adının değişmesi, minimum sürüm,
Node indirme adresi: hepsi tek satır. Yeni .exe dağıtmadan.

Kurucuda gömülü varsayılan da var (manifest çekilemezse ona düşer). Gömülü kopya
`scripts/gomulu-manifest-uret.sh` ile codex.json'dan ÜRETİLİR (build.sh her seferinde
yeniler) — elle düzenlenmez.

### Katalog canlı API'den (2026-09-14)
`codex.catalogUrl = https://yapayzekalab.org/v1/models?client_version={{CODEX_VERSION}}`.
Kurucu `{{CODEX_VERSION}}`'ı kurulu `codex --version` ile doldurur (yoksa `minVersion`) ve
isteği **müşterinin anahtarıyla** atar (gateway kademeye göre katalog döner). Yanıt olduğu
gibi `yzlab-model-catalog.json`'a yazılır (`models` dizisi boş değilse).
Sebep: 09-07'deki statik `codex-catalog.json` bir haftada bayatladı (service_tiers,
auto_compact_token_limit, base_instructions, use_responses_lite değişmişti). Canlı yanıtın
ham hâlinin (`data`/`dataStatus` üst anahtarlarıyla) Codex 0.153.4 tarafından kabul edildiği
ölçüldü. Statik dosya artık kullanılmıyor (sunucuda durabilir, zararsız).

### Profil şablonu — çalışma ayarları
Sahip kararı 2026-09-04 (web kitiyle parite): profil `approval_policy = "never"`,
`sandbox_mode = "danger-full-access"`, `model_verbosity = "high"`,
`model_reasoning_summary = "detailed"`, `[tools] web_search = true` içerir. Yalnız
`-p yzlab` oturumlarını etkiler; müşterinin kendi `codex`'i aynen kalır. Canlıda doğrulandı:
`codex exec -p yzlab` başlığı `approval: never · sandbox: danger-full-access` gösteriyor.

## Kurucunun 5 adımı (iki platformda birebir aynı)
1. Anahtar doğrula — `GET /v1/balance` + Bearer. 200=geçerli, 401=net hata mesajı.
2. Codex var mı — `codex --version`. **Varsa dokunma** → müşterinin Codex'i kapatması gerekmez.
   Yoksa Node kur, sonra `npm i -g @openai/codex`.
3. `yzlab.config.toml` + `yzlab-model-catalog.json` yaz.
4. Kısayol — Win: masaüstü `.lnk` → `cmd /k codex -p yzlab`. Mac: `~/.local/bin/yzlab-codex`.
5. Canlı test — profil ile küçük istek; 200 ise "Kuruldu ✓".
Ek: tek "Geri Al" butonu.

### Doğrulama İZOLE çalışır (2026-09-14)
`codex exec`, çalıştığı dizin için **config.toml'a `[projects.<dizin>] trust_level="trusted"`
yazıyor** (0.153.4'te ölçüldü; `--skip-git-repo-check`, `-C`, git-dizini fark etmiyor).
"config.toml'a dokunmuyoruz" sözünü bozmamak ve müşterinin MCP sunucularını boşuna
başlatmamak için doğrulama **geçici bir CODEX_HOME**'da koşar: oraya yalnız profil kopyalanır
(katalog yolu gerçek dosyaya bakar), `CODEX_HOME=<geçici> codex exec -p yzlab -C <geçici> ok`.
Kanıtlanan: anahtar + katalog + şablon + sağlayıcı. Kanıtlanmayan: gerçek CODEX_HOME'un
seçimi — onu selftest'in `CODEX_HOME dikkate aliniyor` kontrolü ve CI'daki bağımsız
`codex exec` (gerçek CODEX_HOME ile) kapatıyor.

### ⚠️ stdin KAPALI olmalı
`codex exec` stdin bir boru/terminal ise "Reading additional input from stdin..." deyip EOF
bekler ve **asılı kalır** (bu Mac'te 3 dk bekledi). Mac: `Process.standardInput = nullDevice`,
Win: `RedirectStandardInput` + hemen kapat. CI betiğinde de `< NUL`.

### ⚠️ CODEX_HOME sondası yalnız stdout okur
GUI uygulaması kullanıcının `.zprofile`'ini görmez; `zsh -lc 'echo $CODEX_HOME'` ile sorulur.
Login kabuğu stderr'e gürültü basarsa (bozuk .zprofile, nvm uyarısı) o metin YOL sanılıyordu
→ profil çöp dizine yazılır, doğrulama "no such file" der. Artık yalnız stdout okunur ve değer
`/` ya da `~` ile başlamalı. **`NSHomeDirectory()` HOME env'ini YOK SAYAR** (passwd home):
sahte HOME ile test yapılmaz, CODEX_HOME açıkça verilir.

## Komut satırı modları (2026-09-14, iki platform)
| mod | ne |
|---|---|
| `--selftest` | 21 (mac) / 22 (win) invaryant: gömülü manifest, CODEX_HOME, dokunmama, geri al, sürüm ayıklama, katalog adresi |
| `--kur [--anahtar K] [--model id] [--kisayol 0/1]` | başsız kurulum; anahtar `YZLAB_ANAHTAR` env'den de okunur (loglara düşmesin) |
| `--geri-al` | kurulumu siler |
Çıkış kodu: 0 başarı · 1 hata · 2 kullanım. Mac: `main.swift` giriş, pencere modu `YzlabKurucuApp.main()`.
DEBUG derlemede test kancaları: `YZLAB_MANIFEST_URL` (manifest adresi), `YZLAB_LOGIN_PATH`
(PATH daralt + login-dışı kabuk → "codex yok" yolu test edilebilir). RELEASE'de derlenmez.

## Platformlar
| | Windows | macOS |
|---|---|---|
| Teknoloji | C# WinForms, .NET 8 self-contained tek .exe | SwiftUI universal |
| Derleme | GitHub Actions `windows-latest` | Mac mini yerel (Xcode 26.6) |
| İmza | yok → SmartScreen ("Daha fazla bilgi → Yine de çalıştır") | ✅ Developer ID `Ufuk Ince (6VNK7BFS8H)` + notarize → uyarı YOK |

Dağıtım: GitHub Releases (VPS diskine dokunmaz — disk zaten sıkışık).
`/kurulum` sayfası: `KurucuIndir.tsx` şeridi — tarayıcıdan OS algılar, algılananın düğmesi
öne çıkar, SmartScreen + notarize + geri alma notu, 7 dilde (`kurulum.app*` anahtarları).

## ⚠️ winget'e BAĞLANMA
Windows Server'da winget yok, Win10'da sürüm sürüm değişiyor ve bizim test imkânımız
en zayıf olduğu yer orası. **Node'u nodejs.org MSI'ından `/quiet /norestart` ile kur.**
winget yalnız yedek yol. Bu, test edilemeyen en büyük riski tasarımdan siliyor.

## Test durumu (2026-09-14)
**macOS (bu makine, DEBUG ikili, gerçek anahtar):**
- `--selftest` 21/21.
- E2E A (codex var): kur → profil 0600 + katalog 219 KB (canlı API) + config/auth DEĞİŞMEDİ →
  bağımsız `codex exec -p yzlab` (gerçek CODEX_HOME): `provider: yapayzekalab · approval: never` → geri al ✓.
- E2E B (codex YOK, izole npm prefix + daraltılmış PATH): `npm i -g` ile 0.154.0 kuruldu → katalog
  `client_version=0.154.0` → profil → doğrulama ✓. Node yokken (.pkg + admin şifresi) yolu
  ELLE test edilmedi (bu makinede Node var; yıkıcı).
- Betikler: scratchpad `e2e-mac.sh` / `e2e-mac-B.sh`.

**Windows (GitHub Actions, gerçek anahtar `YZLAB_TEST_KEY` secret):**
- `derle-ve-sina`: selftest 22 kontrol.
- `uctan-uca`: runner'da codex YOK → kurucu npm ile kurar → profil/katalog/kısayol → config/auth
  değişmedi → bağımsız `codex exec` (`provider: yapayzekalab`, `approval: never`) → `--geri-al`.
- `node-yokken` (bilgi, `continue-on-error`): runner Node'u kaldırılıp MSI yolu denenir.
  Runner ortamı müşteri PC'sinden farklı (UAC yok) → kırmızı olursa release'i durdurmaz, oku.
- Windows makinesi YOK. Mac mini'de VM de yok (disk). GUI (WinForms) hiç görülmedi; mantık
  `Kurucu` sınıfında ve başsız modla aynı.

## ⚠️ Derleme tuzağı — Xcode exFAT diskte
Xcode `/Volumes/KIOXIA` (**exFAT**) üzerinde. exFAT xattr tutamadığı için macOS AppleDouble
`._*` dosyaları yazmış — yalnız SDK `usr/include` altında **3.664 tane**. Clang bunları gerçek
başlık sanıp modülü kırıyor: `error: source file is not valid UTF-8`.
**Çözüm (Xcode'a DOKUNMADAN):** `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk`
+ iki mimariyi AYRI derle (`--triple arm64-apple-macosx13.0` / `x86_64-…`) + `lipo`.
`scripts/build.sh` ikisini de yapıyor. Release: `NOTARIZE=1 ./scripts/build.sh`
(profil `yzlab-notary` Keychain'de).

## ⚠️ CI tuzağı — WinExe çıkış kodu okunmaz
`.exe` WinForms (WinExe alt sistemi) olduğu için PowerShell onu **beklemez** ve
`$LASTEXITCODE`'u okumaz. Doğrusu: `Start-Process -NoNewWindow -Wait -PassThru` + `ExitCode`'u
elle kontrol et. Console çıktısı bu yolla loga DÜŞÜYOR (PASS/FAIL satırları görünür).

## Kapanış — 09-07 açık işleri
1. ~~`codex-catalog.json`~~ → yerini canlı API aldı (yukarıda).
2. ~~macOS kurucu~~ ✅ universal, imzalı, notarize.
3. ~~macOS notarize~~ ✅.
4. ~~Windows kurucu~~ ✅ CI'da derlenir + gerçek anahtarla uçtan uca.
5. ~~`/kurulum` sayfası~~ ✅ `KurucuIndir.tsx` (deploy ayrı onay).
6. ~~Manifest + katalog canlıya~~ ✅ manifest canlı; katalog statikten API'ye geçti.
7. ~~GitHub Release~~ ✅ `v0.1.0` (indirme adresleri `releases/latest/download/…`).
8. ~~Gerçek anahtarla uçtan uca~~ ✅ mac yerel + win CI.
9. ~~`/v1/balance` tier~~ → GEREKSİZ: 09-10 boyama sonrası GENEL = BALLS = 450k
   (`ballsTierContextWindow` manifestten kaldırıldı). Kademe yeniden ayrışırsa katalog zaten
   anahtarla istendiği için gateway doğru pencereyi döner; şablondaki
   `model_context_window` satırı Codex tarafından `max_context_window`'a kelepçelenir.

## Depo
https://github.com/chakallstr/yzlab-kurucu (public) · CI: `.github/workflows/windows.yml`
· secret: `YZLAB_TEST_KEY` (sahibin anahtarı; döndürülürse secret'ı da güncelle).
