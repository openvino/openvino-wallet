#!/usr/bin/env bash
set -euo pipefail

DEVICE_NAME_DEFAULT="iPhone 16"   # Cambialo si preferís otro por defecto
DEVICE_NAME="${1:-$DEVICE_NAME_DEFAULT}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$ROOT"

echo "==> 1) Seleccionar Xcode correcto"
sudo xcode-select -s /Applications/Xcode.app

echo "==> 2) Inicializar herramientas Xcode (si hace falta)"
sudo xcodebuild -runFirstLaunch || true

echo "==> 3) Limpieza Flutter y CocoaPods"
flutter clean

# Borrar workspace y Pods para forzar regeneración
rm -rf ios/Runner.xcworkspace ios/Pods || true

# Deintegrate (por si había residuos de Pods en el .xcodeproj)
( cd ios && pod deintegrate || true )

echo "==> 4) Reinstalar Pods (recrea Runner.xcworkspace)"
( cd ios && pod install )

echo "==> 5) Asegurar includes de Pods en los .xcconfig"
# Inserta la línea include si falta (Debug/Release/Profile)
insert_if_missing () {
  local file="$1" ; local inc="$2"
  if [ -f "$file" ] && ! grep -qF "$inc" "$file"; then
    # Poner include de Pods ARRIBA de todo (antes que Generated.xcconfig)
    printf '%s\n%s' "$inc" "$(cat "$file")" > "$file"
    echo "   + insertado include en $file"
  fi
}

insert_if_missing "ios/Flutter/Debug.xcconfig"   '#include "../Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"'
insert_if_missing "ios/Flutter/Release.xcconfig" '#include "../Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"'
insert_if_missing "ios/Flutter/Profile.xcconfig" '#include "../Pods/Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig"'

# Asegurar que Generated.xcconfig esté incluido (normalmente ya está)
for f in ios/Flutter/{Debug,Release,Profile}.xcconfig; do
  grep -qF 'Generated.xcconfig' "$f" || echo '#include "Generated.xcconfig"' >> "$f"
done

echo "==> 6) Limpiar DerivedData (por las dudas)"
rm -rf ~/Library/Developer/Xcode/DerivedData/* || true

echo "==> 7) Mostrar simuladores disponibles (recorte)"
xcrun simctl list devices | sed -n '1,120p' || true

echo "==> 8) Bootear/abrir simulador ($DEVICE_NAME)"
# Si hay varios con el mismo nombre, tomá el primero
UDID="$(xcrun simctl list devices | awk -v dn="$DEVICE_NAME" -F '[()]' '
  tolower($0) ~ tolower(dn) && $0 ~ /Shutdown|Booted/ { print $(NF-1); exit }')"

if [ -z "${UDID:-}" ]; then
  echo "No encontré UDID para '$DEVICE_NAME'. Probá con otro nombre (p.ej: 'iPhone 16 Pro')."
  exit 1
fi

xcrun simctl boot "$UDID" || true
open -a Simulator --args -CurrentDeviceUDID "$UDID"

echo "==> 9) Ver que Xcode vea el destino"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -showdestinations | grep -n "iOS Simulator" | sed -n '1,30p' || true

echo "==> 10) Build iOS (simulador) con Flutter"
flutter pub get
( cd ios && pod install )
flutter run -d "$UDID"
