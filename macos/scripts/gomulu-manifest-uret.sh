#!/bin/bash
# Canli manifest dosyasindan gomulu yedegi uretir. Ikisi ASLA elle ayri duzenlenmez.
set -euo pipefail
SRC="${1:-$HOME/yzlab-live/apps/web/public/kurulum/codex.json}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/Sources/YzlabKurucu/EmbeddedManifest.swift"
python3 - "$SRC" "$OUT" <<'PY'
import json,sys
src,out=sys.argv[1],sys.argv[2]
raw=json.dumps(json.load(open(src)),ensure_ascii=False,separators=(',',':'))
body='\n'.join('    '+l for l in ('"""\n'+raw.replace('\\','\\\\')+'\n"""').split('\n'))
open(out,'w').write(
'// URETILMIS DOSYA — ELLE DUZENLEME.\n'
'// Kaynak: apps/web/public/kurulum/codex.json\n'
'// Yeniden uret: scripts/gomulu-manifest-uret.sh\n\n'
'extension Manifest {\n    static let embeddedJson =\n'+body+'\n}\n')
print("uretildi:",out,len(raw),"bayt JSON")
PY
