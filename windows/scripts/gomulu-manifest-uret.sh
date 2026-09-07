#!/bin/bash
# Canli manifest dosyasindan gomulu C# yedegini uretir. Ikisi ASLA elle ayri duzenlenmez.
set -euo pipefail
SRC="${1:-$HOME/yzlab-live/apps/web/public/kurulum/codex.json}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/src/EmbeddedManifest.cs"
python3 - "$SRC" "$OUT" <<'PY'
import json,sys
src,out=sys.argv[1],sys.argv[2]
raw=json.dumps(json.load(open(src)),ensure_ascii=False,separators=(',',':'))
# C# ham dizesi: """ ... """ (C# 11). Icerikte """ gecmiyor.
assert '"""' not in raw
open(out,'w',encoding='utf-8').write(
'// URETILMIS DOSYA — ELLE DUZENLEME.\n'
'// Kaynak: apps/web/public/kurulum/codex.json\n'
'// Yeniden uret: scripts/gomulu-manifest-uret.sh\n\n'
'namespace YzlabKurucu;\n\n'
'public sealed partial class Manifest\n{\n'
'    public const string EmbeddedJson =\n        """\n        '+raw+'\n        """;\n}\n')
print("uretildi:",out,len(raw),"bayt JSON")
PY
