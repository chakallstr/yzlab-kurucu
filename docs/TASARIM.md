# yzlab Codex Kurucu — Tasarım

Durum: 2026-09-07 · Madde 1 (manifest) bitti ve canlı Codex ile doğrulandı.

## Amaç
Müşteri anahtarını yapıştırsın, Codex CLI/IDE/masaüstünde yapayzekalab.org üzerinden
çalışsın — **kendi ChatGPT Plus'ı bozulmadan**, yan yana.

Web Codex (chatgpt.com/codex) kapsam DIŞI: sunucu tarafı, istemci ayarı yok.

## Temel ilke: hiçbir şeyi ezme
| Dosya | Biz |
|---|---|
| `~/.codex/config.toml` | dokunma |
| `~/.codex/auth.json` | dokunma (Plus oturumu sağlam) |
| `~/.codex/yzlab.config.toml` | ✅ tek yazdığımız dosya |
| `~/.codex/yzlab-model-catalog.json` | ✅ ikinci dosya (model metadata) |

Geri alma = bu iki dosyayı + kısayolu sil. ZendiKey'in 200+ satırlık yedek/restore
mekanizmasına ihtiyaç yok.

Codex profil mekaniği (`codex -p <ad>` → `$CODEX_HOME/<ad>.config.toml` taban configin
ÜSTÜNE katmanlanır) bu tasarımı mümkün kılan şey.

## Manifest — beyin sunucuda
`https://yapayzekalab.org/kurulum/codex.json`
Kaynak: `~/yzlab-live/apps/web/public/kurulum/codex.json`

`next.config` içinde `output: 'standalone'` YOK → `next start` `public/`i diskten okur.
**Dosyayı VPS'te düzenlemek anında etki eder — build ve restart GEREKMEZ.**
Model değişimi, `experimental_bearer_token` adının değişmesi, minimum sürüm,
Node indirme adresi: hepsi tek satır. Yeni .exe dağıtmadan.

Kurucuda gömülü varsayılan da var (manifest çekilemezse ona düşer).

## Kurucunun 5 adımı (iki platformda birebir aynı)
1. Anahtar doğrula — `GET /v1/balance` + Bearer. 200=geçerli, 401=net hata mesajı.
2. Codex var mı — `codex --version`. **Varsa dokunma** → müşterinin Codex'i kapatması gerekmez.
   Yoksa Node kur, sonra `npm i -g @openai/codex`.
3. `yzlab.config.toml` + `yzlab-model-catalog.json` yaz.
4. Kısayol — Win: `.lnk` → `cmd /k codex -p yzlab`. Mac: `~/.local/bin/yzlab-codex`.
5. Canlı test — profil ile küçük istek; 200 ise "Kuruldu ✓".
Ek: tek "Geri Al" butonu.

## Platformlar
| | Windows | macOS |
|---|---|---|
| Teknoloji | C# WinForms, .NET 8 self-contained tek .exe | SwiftUI universal |
| Derleme | GitHub Actions `windows-latest` | Mac mini yerel (Xcode 26.6) |
| İmza | yok → SmartScreen | ✅ Developer ID `Ufuk Ince (6VNK7BFS8H)` + notarize → uyarı YOK |

Dağıtım: GitHub Releases (VPS diskine dokunmaz — disk zaten sıkışık).

## ⚠️ winget'e BAĞLANMA
Windows Server'da winget yok, Win10'da sürüm sürüm değişiyor ve bizim test imkânımız
en zayıf olduğu yer orası. **Node'u nodejs.org MSI'ından `/quiet /norestart` ile kur.**
winget yalnız yedek yol. Bu, test edilemeyen en büyük riski tasarımdan siliyor.

## Doğrulanmış bulgular (2026-09-07, bu makinede ölçüldü)
- `codex -p yzlabtest` → `provider: yapayzekalab`, sahte anahtar → bizim 401'imiz:
  `401 Unauthorized: API anahtarı geçersiz veya iptal edilmiş, url: .../v1/responses`
  Taban config ve auth.json etkilenmedi. **Çekirdek tasarım çalışıyor.**
- ⚠️ `model_catalog_json` ŞART. Yoksa: `warning: Model metadata for <model> not found
  ... can degrade performance`. **Müşteri kataloğu YAZILDI ve doğrulandı** (uyarı kalktı).
- ⚠️ Katalog şeması KATI: alan-seçmeli (allowlist) kısaltma ÇÖKÜYOR →
  `failed to parse model_catalog_json: missing field experimental_supported_tools`.
  Doğru yol: tam kaydı al, sadece şişkin alanları AT
  (`model_messages` 16,6 KB + `availability_nux` + `upgrade`).
  Sonuç: 328 KB → **87 KB**, uyarı yok. `base_instructions` (16 KB/model) TUTULDU —
  model davranışını o belirliyor.
- `/v1/models` anahtarsız 200, **14 modelin hepsi public** (`gpt-6-astra` dahil).
  Yine de kurucu listeyi manifest'ten alır: `/v1/models` bağlam penceresi ve
  sıralama bilgisi vermiyor.
- ⚠️ `/v1/balance` **tier DÖNDÜRMÜYOR** (`balance_usd/try, rate, payg_enabled`).
  Kurucu GENEL/BALLS ayrımını yapamıyor → katalog **450k (GENEL)** ile gidiyor.
  BALLS müşterisi 750k yerine 450k alır. Düzeltme: `/v1/balance`'a `tier` eklenirse
  kurucu otomatik 750k yazar. Küçük iş, canlı ödeme ucu → ayrı onay.
- `/v1/balance` anahtarsız 401 → anahtar doğrulama ucu olarak birebir uygun.

## ⚠️ Derleme tuzağı — Xcode exFAT diskte
Xcode `/Volumes/KIOXIA` (**exFAT**) üzerinde. exFAT xattr tutamadığı için macOS
AppleDouble `._*` dosyaları yazmış — yalnız SDK `usr/include` altında **3.664 tane**.
Clang bunları gerçek başlık sanıp modülü kırıyor:
`error: source file is not valid UTF-8` → `could not build Objective-C module 'Darwin'`.

**Çözüm (Xcode'a DOKUNMADAN):**
1. `export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk` (dahili disk)
2. ⚠️ `swift build --arch arm64 --arch x86_64` SDKROOT'u **YOK SAYAR**, Xcode'un bozuk
   SDK'sına döner. Universal binary için iki mimariyi AYRI derle
   (`--triple arm64-apple-macosx13.0` / `--triple x86_64-apple-macosx13.0`) + `lipo -create`.

`scripts/build.sh` ikisini de yapıyor.

## Açık işler
1. ~~`codex-catalog.json`~~ ✅ bitti (87 KB, 5 model, doğrulandı)
2. ~~macOS kurucu~~ ✅ BİTTİ — universal, imzalı, NOTARIZE EDİLDİ, `spctl: accepted` (app+dmg)
3. ~~macOS notarize~~ ✅ profil `yzlab-notary` Keychain'de; `NOTARIZE=1 ./scripts/build.sh`
4. Windows kurucu (C# + CI)  ← SIRADAKİ
5. `/kurulum` sayfası: OS algıla, 2 buton, SmartScreen anlatımı
6. (ops) `/v1/balance`'a `tier` ekle → BALLS için otomatik 750k

## Test durumu
- Windows makinesi YOK. Mac mini'de yerel VM de YOK: **disk 96% dolu, 7,5 GB boş**
  (Win11 ARM VM ~50 GB ister). Bkz. `project_macmini_disk_full_icloud`.
- Plan: GitHub Actions `windows-latest` (ücretsiz, her build'de mantık testi)
  + gerekirse netlen Windows Server 2025 Evaluation (`os_version_id: 22`) saatlik kiralık.
  ⚠️ Server'da winget yok → zaten winget'e bağlanmıyoruz.

## ⚠️ Deploy notu
Manifest `public/` altında STATİK; rota eklemiyoruz, `.next/types` bayat-rota tuzağı
(`yzlab-api-sekmesi-ve-rota-tuzaklari` TUZAK 2) bu dosya için geçerli DEĞİL.
Yine de canlıya çıkmak AÇIK ONAY ister.
