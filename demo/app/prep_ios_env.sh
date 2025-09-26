#!/usr/bin/env bash
set -euo pipefail

say(){ printf "\033[1;34m==> %s\033[0m\n" "$*"; }
die(){ printf "\033[1;31m[✗] %s\033[0m\n" "$*"; exit 1; }

IOS_PLATFORM="13.0"
DEVNAME="iPhone 16e Dev"
RUNTIME_LABEL="iOS 26.0"
RUNTIME_ID="com.apple.CoreSimulator.SimRuntime.iOS-26-0"

command -v flutter >/dev/null || die "No encuentro 'flutter' en PATH"
command -v xcrun   >/dev/null || die "No encuentro 'xcrun'"

say "xcodebuild -runFirstLaunch (idempotente)"
sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch >/dev/null 2>&1 || true

say "Verificando runtime ${RUNTIME_LABEL}"
if ! xcrun simctl list runtimes | grep -q "${RUNTIME_LABEL}"; then
  die "No está instalado el runtime ${RUNTIME_LABEL}."
fi

say "flutter clean + pub get"
flutter clean
flutter pub get

# ---------- Ajustes de xcconfig / Podfile ----------
PODFILE="ios/Podfile"
[[ -f "$PODFILE" ]] || die "No existe $PODFILE"

say "Ajustando Podfile (platform :ios, '${IOS_PLATFORM}')"
python3 - "$PODFILE" "$IOS_PLATFORM" <<'PY'
import io,sys,re
pf=sys.argv[1]; ios=sys.argv[2]
txt=open(pf,'r',encoding='utf-8').read()
txt=re.sub(r'^\s*platform\s*:ios.*$', f"platform :ios, '{ios}'", txt, flags=re.M)
if "post_install do |installer|" not in txt:
    txt += """

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |cfg|
      cfg.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = ios
    end
  end
end
"""
open(pf,'w',encoding='utf-8').write(txt)
print("OK")
PY

say "Incluyendo Pods en ios/Flutter/*.xcconfig"
for xc in ios/Flutter/Debug.xcconfig ios/Flutter/Release.xcconfig ios/Flutter/Profile.xcconfig; do
  [[ -f "$xc" ]] || continue
  /usr/bin/sed -E -i '' '/Pods\/Target Support Files\/Pods-Runner\/Pods-Runner\.(debug|release|profile)\.xcconfig/d' "$xc"
  tmp="$(mktemp)"
  case "$xc" in
    *Debug.xcconfig)
      { echo '#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"'; cat "$xc"; } > "$tmp" ;;
    *Release.xcconfig)
      { echo '#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"'; cat "$xc"; } > "$tmp" ;;
    *Profile.xcconfig)
      { echo '#include "Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"'; cat "$xc"; } > "$tmp" ;;
  esac
  mv "$tmp" "$xc"
done

# ---------- Sanear pbxproj para evitar errores de Nanaimo ----------
PYX="ios/Runner.xcodeproj/project.pbxproj"
if [[ -f "$PYX" ]]; then
  say "Saneando $PYX (SUPPORTED_PLATFORMS y diccionarios)"
  python3 - "$PYX" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p,'r',encoding='utf-8').read()
# 1) Normalizar EOL y espacios finales
s = s.replace('\r\n','\n').replace('\r','\n')
s = '\n'.join(l.rstrip() for l in s.split('\n'))
# 2) Corregir SUPPORTED_PLATFORMS -> valor entre comillas
s = re.sub(r"SUPPORTED_PLATFORMS\s*=\s*iphonesimulator iphoneos;", "SUPPORTED_PLATFORMS = \"iphonesimulator iphoneos\";", s)
# 3) Quitar ';' inmediatamente después de '{' en diccionarios (patrón '= {;')
s = re.sub(r"=\s*\{\s*;", "= {", s)
# 4) Asegurar que cada asignación dentro de buildSettings termine en ';'
out = []
brace = 0
in_bs = False
for ln in s.split('\n'):
    if 'buildSettings = {' in ln and not in_bs:
        in_bs = True
        brace = ln.count('{') - ln.count('}')
        out.append(ln)
        continue
    if in_bs:
        brace += ln.count('{') - ln.count('}')
        if '=' in ln and not ln.strip().endswith(';') and not ln.strip().endswith('{') and '/*' not in ln:
            # preservar comentarios de fin de línea
            parts = ln.split('//', 1)
            left = parts[0].rstrip()
            if left and not left.endswith(';'):
                left += ';'
            ln = left + ((' //' + parts[1]) if len(parts)==2 else '')
        if brace <= 0:
            in_bs = False
    out.append(ln)
# 5) Corregir productRefGroup line inside PBXProject "Runner" block
def fix_productRefGroup_and_targets(lines):
    in_pbxproject = False
    in_targets_array = False
    pbxproject_indent = None
    fixed_lines = []
    for line in lines:
        # Detect start of PBXProject "Runner" block by presence of comment with "Build configuration list for PBXProject \"Runner\""
        if '/* Begin PBXProject section */' in line:
            in_pbxproject = True
        if in_pbxproject:
            # Fix productRefGroup line
            if 'productRefGroup = 97C146EF1CF9000F007C117D /* Products */' in line and not line.strip().endswith(';'):
                line = line.rstrip() + ';'
            # Detect targets array closing line
            if re.match(r'^\s*\);\s*}\s*$', line):
                line = re.sub(r'\);\s*}', ');              };', line)
                in_pbxproject = False  # Assuming only one PBXProject block to fix
        fixed_lines.append(line)
    return fixed_lines

out = fix_productRefGroup_and_targets(out)

open(p,'w',encoding='utf-8').write('\n'.join(out))
print('OK: pbxproj saneado')
PY
fi

# ---------- Arreglar Runner para simulador arm64 y base configs ----------
PBX="ios/Runner.xcodeproj/project.pbxproj"
[[ -f "$PBX" ]] || die "No existe $PBX"

say "Ajustando Runner.xcodeproj con Ruby/xcodeproj (ARCHS + BaseConfiguration)"
/usr/bin/ruby - <<'RUBY'
require 'xcodeproj'
proj = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = proj.targets.find { |t| t.name == 'Runner' }
raise 'Target Runner no encontrado' unless runner

# Ubicar xcconfigs de Pods-Runner
pod_cfg = {
  'Debug'   => 'Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig',
  'Release' => 'Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig',
  'Profile' => 'Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig'
}

runner.build_configurations.each do |cfg|
  s = cfg.build_settings
  s['ARCHS'] = 'arm64'
  s['ONLY_ACTIVE_ARCH'] = 'NO'
  s.delete('VALID_ARCHS')
  s.delete('EXCLUDED_ARCHS[sdk=iphonesimulator*]')
  s.delete('EXCLUDED_ARCHS')
  # BaseConfiguration con Pods-Runner.* para eliminar el warning y enlazar correctamente
  if File.exist?("ios/#{pod_cfg[cfg.name]}")
    cfg.base_configuration_reference = proj.files.find { |f| f.path == pod_cfg[cfg.name] } || proj.new_file(pod_cfg[cfg.name])
  end
end

proj.save
RUBY

# ---------- Pods ----------
say "pod deintegrate + pod install"
(
  cd ios
  pod deintegrate >/dev/null 2>&1 || true
  pod install
)

# ---------- Limpiar DerivedData y build ----------
say "Limpiando DerivedData y build/ios"
rm -rf ~/Library/Developer/Xcode/DerivedData/* build/ios || true

# ---------- Crear/bootea simulador arm64 iOS 26 ----------
say "Buscando device type iPhone (arm64)"
DEVTYPE="$(xcrun simctl list devicetypes | awk -F'[()]' '/iPhone 16e|iPhone 17|iPhone 16/{print $2; exit}')"
[[ -n "${DEVTYPE:-}" ]] || die "No encontré un device type iPhone."

say "Buscando simulador '${DEVNAME}'"
DEVICES_JSON="$(xcrun simctl list -j devices "${RUNTIME_ID}" 2>/dev/null || echo '{}')"
UDID="$(printf '%s' "$DEVICES_JSON" | python3 - "$DEVNAME" "$RUNTIME_ID" <<'PY'
import sys, json
name = sys.argv[1]
runtime_id = sys.argv[2]
try:
    data = json.load(sys.stdin)
except Exception:
    data = {"devices": {}}
for dev in data.get("devices", {}).get(runtime_id, []):
    if dev.get("name") == name:
        print(dev.get("udid", ""))
        break
PY
)"

# eliminar simuladores auto-* que estorban
xcrun simctl list devices | awk -F '[()]' '/\(auto-/{print $2}' | while read -r old; do
  xcrun simctl delete "$old" >/dev/null 2>&1 || true
done

if [[ -z "${UDID}" ]]; then
  say "No existe. Creando '${DEVNAME}'…"
  UDID="$(xcrun simctl create "${DEVNAME}" "${DEVTYPE}" "${RUNTIME_ID}")"
fi

echo "${UDID}" > .ios_sim_uuid

# Reiniciar CoreSimulatorService y boot explícito
pkill -9 -x com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true
open -ga Simulator || true
xcrun simctl boot "${UDID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${UDID}" -b

# Forzar que Xcode publique destinos del workspace/scheme Runner
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -resolvePackageDependencies >/dev/null 2>&1 || true
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -showdestinations >/dev/null 2>&1 || true

say "Simulador ${UDID} listo (booted)"
