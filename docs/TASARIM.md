# yzlab Codex + Claude Code Kurucu — Tasarım

Durum: **2026-09-15 · v0.2.0 — HEDEF CODEX MASAÜSTÜ.** Aşağıdaki "profil (`-p yzlab`)" anlatımları v0.1.x
TARİHÇESİDİR; masaüstü o profili okumadığı için bırakıldı.

## v0.2.0 — neden ve ne değişti (müşteri kamer5561, 2026-09-15)
- **Olay:** müşteri kurucuyu çalıştırdı, "Kuruldu" gördü; Codex masaüstünde yazınca "hakkınız yok". Paketi sağlamdı
  (30 haktan 2,5). Kurucunun doğrulama isteği 11:04'te bize geldi, **sonra masaüstünden tek istek gelmedi** →
  masaüstü kendi ChatGPT hesabıyla OpenAI'ye gitti.
- **Kök:** v0.1.x yalnız `$CODEX_HOME/yzlab.config.toml` profilini yazıyordu; bu yalnız `codex -p yzlab` ile okunur.
  **Codex masaüstü (`ChatGPT.app`, bundle `com.openai.codex`, içinde codex-cli 0.154.0-alpha) profili OKUMAZ.**
  Sahibin çalışan masaüstü kurulumu ana `config.toml`'da top-level `model_provider = "yapayzekalab"` +
  `[model_providers.yapayzekalab]` (`experimental_bearer_token`), auth.json'da ChatGPT girişi → bu kanıtlı model.
- **Yeni yazıcı `CodexAyar` (mac+win, saf, 20 test):** ana config.toml'a İŞARETLİ iki blok —
  `# >>> YapayZekaLab kurucu: ust ayarlar` (dosyanın en başı; manifest şablonunun üst anahtarları) ve
  `# >>> YapayZekaLab kurucu: saglayici` (sonda). Kurulumdan önce aynı üst anahtarlar ve eski
  `[model_providers.yapayzekalab*]` tabloları ayıklanıp `yzlab-kurucu-yedek.json`'a konur (tekrar eden anahtar/tablo
  Codex'i AÇILMAZ yapar; `dogrula` yazmadan önce kontrol eder). `[tools]` gibi diğer şablon tabloları ALINMAZ
  (müşterinin tablosuyla çakışır). Geri Al: işaretli blokları + yönetilen anahtarları kaldırır, yedektekileri geri
  koyar; kurulumdan SONRA Codex'in eklediği `[projects.*]` korunur. İlk kurulumda `config.toml.bak-yzlab` tam kopya.
- **Giriş modları:** varsayılan **ChatGPT girişi durur** (auth.json'a dokunulmaz). Masaüstü uygulamasında hesap
  limitine bağlı "You've hit your usage limit" afişleri var (app.asar: `rateLimitStatus`, `usage_limit_reached`);
  müşterinin ChatGPT hesabında hak yoksa gönderimi engelleyebilir → **"ChatGPT hesabım yerine yalnız anahtarla gir"**
  seçeneği: auth.json → `{"auth_mode":"apikey","OPENAI_API_KEY":…}` (+ sağlayıcıya `requires_openai_auth = true`,
  web kitiyle birebir), önce `auth.json.bak-yzlab`. Hesap moduna dönünce/Geri Al'da auth.json birebir geri gelir.
- **Hız / donma:** Node, Codex CLI ve (varsayılan) Claude Code artık KURULMAZ — masaüstü kendi codex'ini taşır.
  Doğrulama doğrudan HTTPS `POST /v1/responses`, **Codex biçiminde** (`store:false`, `stream:true`, liste `input`,
  `instructions`) — bazı bacaklar string input'u ("Input must be a list") ve store'suz isteği ("Store must be set to
  false") REDDEDİYOR (ölçüldü). İlk terminal SSE olayı kazanır (gateway bazen completed'dan sonra bir failed daha
  yolluyor — ölçüldü). Önce luna 3 deneme; 402/403 ise seçilen modelle 3 deneme. **Mac E2E: kurulum 3 sn.**
  mac: dizin sondası artık `zsh -l` değil (her ekran çiziminde çalışıyordu) — env → `launchctl getenv` → ~/.codex;
  env'de CODEX_HOME varsa YALNIZ o (testler sahibin launchctl dizinine yazmasın).
- **Codex açıkken:** kurmadan önce sorulur (mac NSAlert / win MessageBox) → kapatılır, kurulumdan sonra yeniden
  açılır (açıkken yazılan ayarı uygulama çıkışta ezebilir; ayar yalnız açılışta okunur). Win: pencereli süreçler
  (`Codex`, `ChatGPT`), CloseMainWindow → 10 sn → aynı exe yolundaki süreçler Kill (tepsiye küçülme). CLI:
  `--codex-kapat 1` yoksa hata. DEBUG: `YZLAB_CODEX_KONTROL=kapali`.
- **CLI:** `--kur --anahtar K [--model] [--claude 0|1] [--anahtar-giris 0|1] [--codex-kapat 0|1]`, `--geri-al`,
  `--selftest` (mac 76). Katalog `client_version` = npm `@openai/codex` latest (yoksa manifest min).
- **Kanıt:** mac E2E v2 (scratchpad `e2e-mac-v2.sh`): hesap modu → PROFİLSİZ `codex exec` `provider: yapayzekalab`;
  anahtar modu → aynı; geri al → auth.json birebir, config.toml önceki hâli. Win CI `uctan-uca` aynısını yapar.
- **Sonuçlar:** mac selftest 80/80 · mac gerçek pencere (anahtar panodan, Kur → 3 sn, Geri Al birebir) · win CI selftest
  81/81 · win uçtan uca temiz runner'da (codex + claude yokken, Claude dahil) 33 sn.
- ⚠️ **Codex 0.154 config.toml'u yeniden yazarken YORUM ve BOŞ satırları siliyor** (Windows CI'da ölçüldü) → işaret
  yorumları kaybolur. Geri al / yeniden kur işarete değil anahtar + tablo adına dayandığı için çalışır (4 simülasyon testi);
  CI karşılaştırmaları anlamsal (yorum/boş satır/`[projects.*]` hariç, sıralı satırlar).
- **Yayın:** `v0.2.0` (latest, 2026-09-15). dmg noterli (universal); exe'yi release olayında CI kendisi ekledi
  (`permissions: contents: write`). `releases/latest/download/YzlabKurucu.{dmg,exe}` ikisi de 200.

## Claude Code (2026-09-15 eklendi) — terminal + Claude masaüstü uygulaması
- **Gateway `/v1/messages` GPT modellerini çeviriyor** (Anthropic sözleşmesi → Codex): canlı 200, araç
  çağrısı (Read) dahil çalıştı. Claude modelleri ölü olduğundan Claude Code de **Codex modelleriyle** koşar
  (`ANTHROPIC_MODEL=gpt-5.6-sol`, küçük model `gpt-5.6-luna`). `[claude-code:unrecognized_model]` stderr satırı zararsız.
- **Profil mekanizması YOK** → tek dosya `~/.claude/settings.json` (veya `CLAUDE_CONFIG_DIR`). Kurucu yalnız `env`
  bloğunu yazar (`ANTHROPIC_BASE_URL` kök, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`),
  `ANTHROPIC_API_KEY` kalıntısını siler (AUTH_TOKEN'ı ezerdi), diğer anahtarlar (permissions/hooks/model) korunur.
  İlk yazımda `settings.json.bak-yzlab` (birebir) ya da `settings.json.yok-yzlab` işareti; **Geri Al birebir geri koyar**;
  yeniden kurmak yedeği EZMEZ. Bozuk JSON → açık hata, dosyaya dokunulmaz.
- **Masaüstü uygulaması kanıtı:** `Claude.app` (1.34493.1) app.asar: Code oturumunu Agent SDK ile spawn eder
  (`pathToClaudeCodeExecutable`, `env:{...process.env}`), Claude Code'un settings/env kodu gömülü (`ANTHROPIC_BASE_URL`,
  `CLAUDE_CONFIG_DIR` ×52, ".claude/settings" ×35, "point CLAUDE_CONFIG_DIR … via Desktop Settings"). CLI ile ölçüm:
  `CLAUDE_CODE_OAUTH_TOKEN=sahte` (uygulamanın verdiği OAuth) + settings.json env → istek **bize** gitti (model gpt-5.6-luna);
  sahte OAuth tek başına → hata. Yani settings.json env, masaüstünün OAuth'unu **yener**.
  ⚠️ Bu Mac'te Claude.app claude.ai'ye giriş yapmamış (login ekranı) → uygulama içinden tıklama testi yapılamadı;
  mekanizma CLI + asar ile kanıtlı. Müşteri kurulumdan sonra uygulamayı yeniden açmalı.
- **Doğrulama izole:** geçici `CLAUDE_CONFIG_DIR` + settings.json kopyası, `claude -p 'Sadece ok yaz' --output-format json`,
  izolasyon izi `.claude.json`/`projects`. Kabuktaki sahte `ANTHROPIC_API_KEY` settings env'i ezmedi (ölçüldü).
- Windows: `claude` npm ile kurulur (`@anthropic-ai/claude-code`); "requires git-bash" çıktısı → müşteriye Git for Windows uyarısı.
- GUI (mac, AX ile sürüldü): anahtar yapıştır → Kur (6 sn) → profil+katalog+settings env+yedek → Geri Al → orijinal birebir.

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

## Manifest — beyin sunucuda (schemaVersion 2, `claude` bloğu)
Canlı manifest gömülüden **eski şemaysa** (`schemaVersion` küçük ya da çözülemiyor) kurucu gömülüyü kullanır ve
"sunucudaki ayar dosyası eski sürüm" der — yeni alanlar (claude) eksik kalmasın diye. Canlıya v2 konana kadar
dağıtılan kurucu gömülü v2 ile çalışır.

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
yazabiliyor** (0.153.4'te ölçüldü; yalnız profil `danger-full-access` iken — read-only sandbox'ta yazmadı).
İzolasyon KANITI bu yüzden trust'a değil, codex'in her koşulda yazdığı durum dosyalarına bakar
(`installation_id`, `sessions/`, `*.sqlite`); yoksa "doğrulama izole koşmadı" hatası.
⚠️ **`CODEX_HOME` komut-önü atama ile verilir** (`CODEX_HOME='…' codex exec …`): `zsh -l` kullanıcının
`.zshenv/.zprofile`'ındaki `export CODEX_HOME=…`i Process env'inden SONRA uygular ve geçici değeri ezerdi
(QA 09-14 ZDOTDIR ile kanıtladı; komut-önü atama tüm profil dosyalarından sonra uygulanır).
"config.toml'a dokunmuyoruz" sözünü bozmamak ve müşterinin MCP sunucularını boşuna
başlatmamak için doğrulama **geçici bir CODEX_HOME**'da koşar: oraya yalnız profil kopyalanır
(katalog yolu gerçek dosyaya bakar), `CODEX_HOME=<geçici> codex exec -p yzlab -C <geçici> ok`.
Kanıtlanan: anahtar + katalog + şablon + sağlayıcı. Kanıtlanmayan: gerçek CODEX_HOME'un
seçimi — onu selftest'in `CODEX_HOME dikkate aliniyor` kontrolü ve CI'daki bağımsız
`codex exec` (gerçek CODEX_HOME ile) kapatıyor.

### ⚠️ Codex'in kendisi config.toml'a `[projects]` yazar (bizim değil)
Profil `danger-full-access` olduğu için müşteri `codex -p yzlab` ile bir dizinde çalışınca **Codex** o dizini
`config.toml`'a `[projects."<dizin>"] trust_level = "trusted"` olarak ekler. Bu kurucunun değil Codex'in
davranışı (kurucunun doğrulaması izole dizinde koşar, config.toml'a dokunmaz). CI'daki bağımsız `codex exec`
gerçek CODEX_HOME'da koştuğu için bu satırı ekler; betik yalnız bu farkı kabul eder, başka fark = kurucu dokundu.

### ⚠️ "401" düz metin araması YANLIŞ POZİTİF
Codex/Claude çıktısında `401` alt dizesi aramak, geçici dizin UUID'sinde (`workdir: …-401…`), token sayısında
(`8.401`) ya da sürede (`3401 ms`) da eşleşiyordu → ~%1 koşuda kurulum "anahtar geçersiz" diye boşuna
reddediliyordu (09-15'te yakalandı). Artık `yetkiReddiMi`/`YetkiReddiMi`: `Unauthorized`, `authentication_error`,
`Invalid API key`, `geçersiz` ya da `HTTP/status/code 401` deseni. Selftest'te 5 kontrol.

### ⚠️ Arayüz donmasın + doğrulama HIZLI modelle (v0.1.2, 2026-09-15 müşteri vakası)
İlk gerçek Windows müşterisi (fordlive49) "Kur'a basınca çok uzun sürüyor, uygulama donuyor" dedi. İki ayrı kök:
1. **Donma:** `KurAsync` WinForms UI thread'inde koşuyordu; içindeki `npm install` / `codex exec` / `claude -p`
   senkron bekliyor → pencere "Yanıt vermiyor". Win: `await Task.Run(...)` + `BeginInvoke` ile durum metni.
   Mac aynı hataya sahipti (`@MainActor` Kurucu içinde senkron `Process` beklemesi): `Kabuk.calistirAsync`
   (`Task.detached`) ile ana aktör bloklanmaz.
2. **Yavaşlık:** doğrulama müşterinin SEÇTİĞİ modelle ("ok") yapılıyordu → gpt-6-astra: 1. deneme kuyrukta 33,5 sn
   bekledi ve 36. sn'de istemci kapattı (`client_closed_request`), 2. deneme 60,5 sn düşündü. Artık doğrulama her
   zaman `manifest.claude.smallFastModel` (gpt-5.6-luna) + `model_reasoning_effort=low`:
   `codex exec -m gpt-5.6-luna -c model_reasoning_effort=low` (tırnaksız da geçerli, 3-11 sn),
   `claude -p … --model gpt-5.6-luna` (settings'teki ANTHROPIC_MODEL'i ezer, 11 sn). Mac E2E toplam 25 sn.
   **Ölçüm (CI, temiz Windows, v0.1.2):** codex npm kurulumu 15 sn · katalog 6 sn · Codex doğrulama 13 sn ·
   Claude Code npm kurulumu 5 sn · Claude doğrulama 11 sn → **toplam 52 sn** (codex+claude ikisi de yokken).
   Bedel: doğrulama istekleri müşterinin PAKETİNDEN düşer (sahipten değil — 09-15'te UsageRecord ile doğrulandı,
   `coveredByPackageId` dolu, costUsd 0); luna ağırlığı düşük olduğu için astra'ya göre çok daha az hak yer.

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
| `--selftest` | 44 (mac) / 45 (win) invaryant: gömülü manifest, CODEX_HOME/CLAUDE_CONFIG_DIR, dokunmama, settings.json birleştirme+yedek, geri al |
| `--kur [--anahtar K] [--model id] [--kisayol 0/1] [--claude 0/1]` | başsız kurulum; anahtar `YZLAB_ANAHTAR` env'den de okunur (loglara düşmesin) |
| `--geri-al` | Codex + Claude Code kurulumunu siler / geri koyar |
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

**macOS Claude Code (09-15):** `e2e-mac-claude.sh`: izole CLAUDE_CONFIG_DIR'da eski settings.json (permissions + ANTHROPIC_API_KEY)
→ kur → yedek birebir, diğer anahtarlar korundu, API_KEY silindi, env 4 anahtar, 0600 → bağımsız `claude -p` (sahte
API_KEY kabukta) `ok` / model gpt-5.6-luna → geri al birebir ✓.

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
5. ~~`/kurulum` sayfası~~ ✅ CANLI 2026-09-15 (`KurucuIndir.tsx` şeridi, 7 dil; BUILD_ID `F0b_RkJgJWtztr3ZqTW3I`).
   Manifest v2 de canlı (kurucu "manifest: canli (sema v2)" alıyor).
6. ~~Manifest + katalog canlıya~~ ✅ manifest canlı; katalog statikten API'ye geçti.
7. ~~GitHub Release~~ ✅ `v0.1.2` yayında (latest; dmg noterli + exe CI'dan; v0.1.1'in yerine). ⚠️ `release: created` olayı
   `gh release create`'te tetiklenmedi (v0.1.0'da exe elle yüklendi) → workflow `published, created`; v0.1.1'de CI kendisi ekledi.
   Yeni sürüm: `SURUM` (build.sh) + csproj `Version` + manifest `installer.latestVersion` → `NOTARIZE=1 build.sh` → `gh release create vX dmg --latest`.
   ⚠️ e2e betikleri sahibin gerçek `~/.local/bin/yzlab-codex`'ini siler (geri-al HOME'a bakar) — testten sonra geri koy; `--selftest` artık dokunmaz.
8. ~~Gerçek anahtarla uçtan uca~~ ✅ mac yerel + win CI.
9. ~~`/v1/balance` tier~~ → GEREKSİZ: 09-10 boyama sonrası GENEL = BALLS = 450k
   (`ballsTierContextWindow` manifestten kaldırıldı). Kademe yeniden ayrışırsa katalog zaten
   anahtarla istendiği için gateway doğru pencereyi döner; şablondaki
   `model_context_window` satırı Codex tarafından `max_context_window`'a kelepçelenir.

## Depo
https://github.com/chakallstr/yzlab-kurucu (public) · CI: `.github/workflows/windows.yml`
· secret: `YZLAB_TEST_KEY` (sahibin anahtarı; döndürülürse secret'ı da güncelle).
