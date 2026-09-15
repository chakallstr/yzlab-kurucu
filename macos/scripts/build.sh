#!/bin/bash
# YzlabKurucu.app uretir, imzalar, (istege bagli) notarize eder ve .dmg paketler.
set -euo pipefail
cd "$(dirname "$0")/.."

AD="YzlabKurucu"
GORUNEN="YapayZekaLab Codex Kurulumu"
BUNDLE_ID="org.yapayzekalab.kurucu"
SURUM="${SURUM:-0.1.2}"
IMZA="${IMZA:-Developer ID Application: Ufuk Ince (6VNK7BFS8H)}"

# ⚠️ Xcode exFAT diskte (KIOXIA); SDK'sinda 3.664 AppleDouble ._* dosyasi var ve
# clang modul derlemesini "source file is not valid UTF-8" ile kiriyor.
# Cozum: dahili diskteki CommandLineTools SDK'sini kullan. Xcode'a DOKUNMA.
if [ -z "${SDKROOT:-}" ]; then
  for s in /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk \
           /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk; do
    [ -d "$s" ] && export SDKROOT="$s" && break
  done
fi
echo "SDKROOT=${SDKROOT:-<varsayilan>}"

echo "› gomulu manifest yenileniyor"
./scripts/gomulu-manifest-uret.sh >/dev/null

# ⚠️ `swift build --arch a --arch b` cok-mimari yolu SDKROOT'u YOK SAYIP Xcode'un
# bozuk SDK'sina donuyor. Iki mimariyi AYRI derleyip lipo ile birlestiriyoruz.
echo "› derleme: arm64"
swift build -c release --triple arm64-apple-macosx13.0
echo "› derleme: x86_64"
swift build -c release --triple x86_64-apple-macosx13.0

APP="build/$AD.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  ".build/arm64-apple-macosx/release/$AD" \
  ".build/x86_64-apple-macosx/release/$AD" \
  -output "$APP/Contents/MacOS/$AD"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$GORUNEN</string>
  <key>CFBundleDisplayName</key><string>$GORUNEN</string>
  <key>CFBundleExecutable</key><string>$AD</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleShortVersionString</key><string>$SURUM</string>
  <key>CFBundleVersion</key><string>$SURUM</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict></plist>
PLIST

echo "› imzalaniyor: $IMZA"
codesign --force --options runtime --timestamp \
         --sign "$IMZA" "$APP" 2>&1 | sed 's/^/   /'
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/   /'

echo "› dmg"
rm -f "build/$AD.dmg"
hdiutil create -quiet -volname "$GORUNEN" -srcfolder "$APP" -ov -format UDZO "build/$AD.dmg"
# .dmg'nin KENDISI de imzalanmali; yoksa spctl "no usable signature" der.
# Sira onemli: imzala -> notarize -> staple. Staple sonrasi imzalamak bileti bozar.
codesign --force --timestamp --sign "$IMZA" "build/$AD.dmg" 2>&1 | sed 's/^/   /' 

# Notarize: Apple'a gonderir, sonra bileti .dmg'ye yapistirir → Gatekeeper uyarisi OLMAZ.
# Once bir kez: xcrun notarytool store-credentials yzlab-notary --apple-id ... --team-id 6VNK7BFS8H
if [ "${NOTARIZE:-0}" = "1" ]; then
  echo "› notarize (birkac dakika)"
  xcrun notarytool submit "build/$AD.dmg" --keychain-profile "${NOTARY_PROFILE:-yzlab-notary}" --wait
  xcrun stapler staple "build/$AD.dmg"
  xcrun stapler validate "build/$AD.dmg"
else
  echo "› notarize ATLANDI (NOTARIZE=1 ile ac). Imzasiz-notarizesiz .dmg baska Mac'te uyari verir."
fi

echo "✓ bitti: build/$AD.app  ve  build/$AD.dmg"
