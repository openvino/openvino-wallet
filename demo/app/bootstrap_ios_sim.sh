#!/usr/bin/env bash
# bootstrap_ios_sim.sh — repo fresco → app Flutter en simulador iOS (Xcode 16 / iOS 26)
# Fixes clave:
#  - export DEVELOPER_DIR para que Flutter/Pods usen el mismo Xcode.
#  - Warmup de destino por nombre+OS (Xcode -showdestinations) y fallback inteligente.
#  - Includes de Pods en xcconfig + limpiar EXCLUDED_ARCHS.
#  - Evitamos usar el UUID recién creado si Xcode no lo publica.

set -euo pipefail

say()  { echo -e "\033[1;34m==> $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
die()  { echo -e "\033[1;31m[✗] $*\033[0m"; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Falta comando: $1"; }

# ===== Config =====
APP_PATH="${APP_PATH:-.}"
IOS_PLATFORM="${IOS_PLATFORM:-13.0}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 16e}"
PREFERRED_OS_MAJOR="${PREFERRED_OS_MAJOR:-26}"   # preferimos iOS 26.*
AUTO_DOWNLOAD_RUNTIME="${AUTO_DOWNLOAD_RUNTIME:-1}"
RUNTIME_WAIT_TRIES="${RUNTIME_WAIT_TRIES:-20}"
RUNTIME_WAIT_SECS="${RUNTIME_WAIT_SECS:-2}"

need xcrun; need pod; need flutter
if command -v /usr/bin/python3 >/dev/null 2>&1; then PY=/usr/bin/python3; else need python3; PY=python3; fi

# ===== Xcode / licencia / runtime =====
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
say "Seleccionando Xcode.app y preparando entorno"
sudo xcode-select -s "$DEVELOPER_DIR" >/dev/null 2>&1 || true
sudo xcodebuild -license accept >/dev/null 2>&1 || true
sudo xcodebuild -runFirstLaunch >/dev/null 2>&1 || true

get_ios_runtime(){  # devuelve p.ej. com.apple.CoreSimulator.SimRuntime.iOS-26-0
  local json out
  json="$(xcrun simctl list -j runtimes 2>/dev/null || true)"
  [[ -n "$json" ]] || { echo ""; return 0; }
  out="$("$PY" - <<'PY' <<<"$json" 2>/dev/null
import json,sys
try: d=json.load(sys.stdin)
except: print(""); sys.exit(0)
ios=[r for r in d.get("runtimes",[]) if r.get("name","").startswith("iOS") and (r.get("isAvailable") or str(r.get("availability","")).endswith("available"))]
def ident(r):
  i=r.get("identifier")
  if i: return i
  v=str(r.get("version","")).replace(".","-")
  return f"com.apple.CoreSimulator.SimRuntime.iOS-{v}" if v else ""
# preferir la mayor versión
ios_sorted=sorted(ios, key=lambda r: r.get("version","0"))
print(ident(ios_sorted[-1]) if ios_sorted else "")
PY
)"
  echo "$out"
}

if [[ -z "$(get_ios_runtime)" && "$AUTO_DOWNLOAD_RUNTIME" == "1" ]]; then
  warn "No hay runtimes iOS. Descargando con Xcode (puede demorar)…"
  xcodebuild -downloadPlatform iOS || warn "Descarga de runtime iOS falló (podés bajarlo en Xcode → Settings → Platforms)"
fi

RUNTIME="$(get_ios_runtime || true)"
if [[ -z "$RUNTIME" ]] && xcrun simctl list runtimes | grep -q '^iOS '"$PREFERRED_OS_MAJOR"'\.'; then
  RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-${PREFERRED_OS_MAJOR}-0"
fi
[[ -n "$RUNTIME" ]] || die "No hay runtimes iOS instalados. Abrí Xcode → Settings → Platforms y bajá iOS."

say "Runtime iOS detectado: $RUNTIME"

# ===== Navegar a la app =====
cd "$APP_PATH"
[[ -f pubspec.yaml ]] || die "No hay pubspec.yaml en $PWD"

# ===== Helpers iOS/Flutter =====
ensure_valid_logo(){
  local p="lib/assets/images/logo.png"
  mkdir -p "lib/assets/images"
  if [[ ! -f "$p" ]] || ! file "$p" 2>/dev/null | grep -q "PNG image data"; then
    say "Asegurando assets válidos (logo)"
"$PY" - <<'PY'
import base64, pathlib
png=b'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII='
pathlib.Path("lib/assets/images").mkdir(parents=True, exist_ok=True)
pathlib.Path("lib/assets/images/logo.png").write_bytes(base64.b64decode(png))
PY
  fi
}

normalize_podfile(){
  local PODFILE="ios/Podfile"
  [[ -f "$PODFILE" ]] || die "No existe $PODFILE"
  say "Normalizando Podfile (platform :ios, '${IOS_PLATFORM}')"
  cp "$PODFILE" "${PODFILE}.bak.$(date +%Y%m%d%H%M%S)"
  if ! grep -qE "^platform :ios" "$PODFILE"; then
    { echo "platform :ios, '${IOS_PLATFORM}'"; cat "$PODFILE"; } > "${PODFILE}.tmp" && mv "${PODFILE}.tmp" "$PODFILE"
  else
    /usr/bin/sed -E -i '' -e "s/^platform :ios, *'[0-9.]+'$/platform :ios, '${IOS_PLATFORM}'/" "$PODFILE" || true
  fi
  awk 'BEGIN{seen=0} /^platform :ios/{ if(seen==1) next; seen=1 } {print}' "$PODFILE" > "${PODFILE}.tmp" && mv "${PODFILE}.tmp" "$PODFILE"

  if ! grep -q "post_install do |installer|" "$PODFILE"; then
cat >> "$PODFILE" <<'RUBY'

post_install do |installer|
  installer.generated_projects.each do |project|
    project.targets.each do |t|
      t.build_configurations.each do |c|
        c.build_settings["EXCLUDED_ARCHS[sdk=iphonesimulator*]"] = ""
      end
    end
  end
end
RUBY
  fi
}

xcconfig_include_pods(){
  say "Insertando includes de Pods en xcconfig (Runner: Debug/Release/Profile)"
  local DBG="ios/Flutter/Debug.xcconfig" REL="ios/Flutter/Release.xcconfig" PRO="ios/Flutter/Profile.xcconfig"
  [[ -f "$DBG" && -f "$REL" ]] || die "Faltan ios/Flutter/Debug/Release.xcconfig"
  [[ -f "$PRO" ]] || cp "$REL" "$PRO"
  grep -q 'Pods-Runner.debug.xcconfig'   "$DBG" || echo '#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"'   >> "$DBG"
  grep -q 'Pods-Runner.release.xcconfig'  "$REL" || echo '#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"'  >> "$REL"
  grep -q 'Pods-Runner.profile.xcconfig'  "$PRO" || echo '#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"'  >> "$PRO"
}

fix_excluded_archs(){
  say "Limpiando EXCLUDED_ARCHS para iphonesimulator (arm64)"
  /usr/bin/sed -E -i '' 's/^EXCLUDED_ARCHS\[sdk=iphonesimulator\*\].*$//' ios/Runner.xcodeproj/project.pbxproj 2>/dev/null || true
  if [[ -d ios/Pods ]]; then
    while IFS= read -r -d '' f; do
      /usr/bin/sed -E -i '' 's/^EXCLUDED_ARCHS\[sdk=iphonesimulator\*\].*$//' "$f" || true
    done < <(find ios/Pods -type f -name "*.xcconfig" -print0 2>/dev/null)
  fi
}

# ===== Flutter + Pods =====
say "flutter clean + flutter pub get"
flutter clean
flutter pub get
ensure_valid_logo

say "Normalizando iOS (Podfile/xcconfig/archs)"
normalize_podfile
xcconfig_include_pods
fix_excluded_archs

say "Instalando Pods iOS"
pushd ios >/dev/null
pod deintegrate >/dev/null 2>&1 || true
pod install --repo-update
popd >/dev/null

say "Limpiando DerivedData"
rm -rf ~/Library/Developer/Xcode/DerivedData/* || true

# ===== Simuladores publicados por Xcode =====
pick_published_sim(){  # imprime: UUID \n NAME \n OS
  "$PY" - <<'PY'
import re,subprocess,os,sys
PREF_OS=str(os.environ.get("PREFERRED_OS_MAJOR","26"))
DEV=os.environ.get("DEVICE_NAME","iPhone 16e")
def parse(txt):
  sims=[]
  for ln in txt.splitlines():
    m=re.search(r'\{ *platform:iOS Simulator[^}]*\}', ln)
    if not m: continue
    blob=m.group(0)
    gid=lambda k: (re.search(rf'{k}:(\S+)', blob) or [None,""])[1].strip(",}")
    name=(re.search(r'name:([^}]+)\}', blob) or [None,""])[1].strip(" }")
    sims.append({"raw":blob,"arch":gid("arch"),"id":gid("id"),"os":gid("OS"),"name":name})
  return sims
try:
  txt=subprocess.check_output(["xcodebuild","-workspace","ios/Runner.xcworkspace","-scheme","Runner","-showdestinations"],stderr=subprocess.STDOUT).decode(errors="ignore")
except Exception:
  print(""); sys.exit(0)
sims=parse(txt)

# candidato ideal: iPhone con OS que empieza con PREF_OS (26) y con nombre exacto si existe
pref=[s for s in sims if s["name"].startswith("iPhone") and s["os"].startswith(PREF_OS+".")]
for s in pref:
  if s["name"]==DEV and s["id"]: print(s["id"]); print(s["name"]); print(s["os"]); sys.exit(0)
if pref:
  s=pref[0]; print(s["id"]); print(s["name"]); print(s["os"]); sys.exit(0)

# si no hay 26.*, tomar cualquier iPhone publicado
for s in sims:
  if s["name"].startswith("iPhone") and s["id"]:
    print(s["id"]); print(s["name"]); print(s["os"]); sys.exit(0)

print("")
PY
}

say "Consultando destinos de Xcode…"
PUB_INFO="$(pick_published_sim || true)"
if [[ -z "$PUB_INFO" ]]; then
  warn "Xcode aún no publica un iPhone utilizable; abro iOS Simulator genérico y reintento."
  open -a Simulator || true
  sleep 2
  PUB_INFO="$(pick_published_sim || true)"
fi
[[ -n "$PUB_INFO" ]] || die "Xcode no publica ningún iOS Simulator utilizable para Runner."

PUB_UUID="$(echo "$PUB_INFO" | sed -n '1p')"
PUB_NAME="$(echo "$PUB_INFO" | sed -n '2p')"
PUB_OS="$(echo  "$PUB_INFO" | sed -n '3p')"
say "Usando simulador publicado por Xcode: $PUB_NAME ($PUB_UUID) — iOS $PUB_OS"

# ===== Warmup destino por nombre+OS =====
say "Calentando destino por nombre+OS en Xcode…"
if ! xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination "platform=iOS Simulator,name=$PUB_NAME,OS=$PUB_OS" \
  -showBuildSettings >/dev/null 2>&1; then
  warn "Xcode aún no acepta name+OS; abro Simulator y reintento"
  open -a Simulator --args -CurrentDeviceUDID "$PUB_UUID" || true
  sleep 2
  xcrun simctl bootstatus "$PUB_UUID" -b || true
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
    -destination "platform=iOS Simulator,name=$PUB_NAME,OS=$PUB_OS" \
    -showBuildSettings >/dev/null 2>&1 || warn "Warmup name+OS no crítico"
fi

# ===== Lanzar app =====
say "Abriendo/esperando Simulator con UUID=$PUB_UUID"
open -a Simulator --args -CurrentDeviceUDID "$PUB_UUID" || true
xcrun simctl bootstatus "$PUB_UUID" -b || true

say "Lanzando la app (preferencia UUID; fallback por nombre)…"
if ! flutter run -d "$PUB_UUID"; then
  warn "Flutter no pudo con UUID; probando por nombre: $PUB_NAME"
  flutter run -d "$PUB_NAME"
fi
