#!/usr/bin/env bash
set -euo pipefail
say(){ printf "\033[1;34m==> %s\033[0m\n" "$*"; }
die(){ printf "\033[1;31m[✗] %s\033[0m\n" "$*"; exit 1; }

RUNTIME_ID="com.apple.CoreSimulator.SimRuntime.iOS-26-0"
SCHEME="Runner"
WORKSPACE="ios/Runner.xcworkspace"

[[ -f ".ios_sim_uuid" ]] || die "No existe .ios_sim_uuid. Corré ./prep_ios_env.sh primero."
UDID="$(cat .ios_sim_uuid)"

say "Abriendo/booteando simulador ${UDID}"
open -ga Simulator || true
xcrun simctl bootstatus "${UDID}" -b

say "Verificando que Xcode publique el simulador arm64"
# Necesitamos ver el UDID en -showdestinations o, al menos, cualquier iPhone arm64 en iOS 26.0
OUT="$(/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -workspace "${WORKSPACE}" -scheme "${SCHEME}" -showdestinations 2>/dev/null || true)"

if ! grep -q "OS:26.0" <<<"$OUT"; then
  die "Xcode no está publicando destinos iOS 26.0. Revisá ARCHS/EXCLUDED_ARCHS en Runner y los includes de Pods."
fi

# Si no aparece el UDID puntual (a veces tarda), igual dejamos que flutter lo apunte por id
say "Lanzando Flutter en ${UDID}"
flutter run -d "${UDID}"
