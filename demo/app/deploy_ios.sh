#!/usr/bin/env bash
# Deploy iOS (simulador o device real) con backup/restore y pasos determinísticos
# Uso:
#   ./deploy_ios.sh --sim "iPhone 16"
#   ./deploy_ios.sh --udid 5B15D6DA-349F-4CD7-BA54-F986DE432897
#   ./deploy_ios.sh --build-only
#   ./deploy_ios.sh --restore backups/archivo.tgz
# Opciones: --skip-clean --skip-pods

set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$APP_ROOT/ios"
BACKUP_DIR="$APP_ROOT/backups"
mkdir -p "$BACKUP_DIR"

DEVICE_MODE="sim"  # sim | udid
DEVICE_NAME=""
DEVICE_UDID=""
SKIP_CLEAN="0"
SKIP_PODS="0"
BUILD_ONLY="0"
RESTORE_FILE=""

usage(){ cat <<USAGE
Uso:
  $0 --sim "iPhone 16" | --udid <UDID> [--skip-clean] [--skip-pods] [--build-only]
  $0 --restore <backup.tgz>
USAGE
}
log(){ echo -e "\n==> $*\n"; }
die(){ echo "[ERROR] $*" >&2; exit 1; }
warn(){ echo "[WARN]  $*" >&2; }

close_xcode(){
  # Evita que Xcode tenga abierto el workspace mientras lo regeneramos
  osascript >/dev/null 2>&1 <<'OSA' || true
  tell application "Xcode" to quit
OSA
}
ensure_tools(){
  command -v flutter >/dev/null 2>&1 || die "Flutter no está en PATH."
  command -v pod     >/dev/null 2>&1 || die "CocoaPods no está en PATH."
  [[ -d /Applications/Xcode.app ]] || die "Instala Xcode."
  if [[ "$(xcode-select -p)" != "/Applications/Xcode.app/Contents/Developer" ]]; then
    sudo xcode-select -s /Applications/Xcode.app
  fi
}
backup_now(){
  local ts out
  ts=$(date +%F_%H%M%S)
  out="$BACKUP_DIR/deploy_${ts}.tgz"
  log "Creando backup: $out"
  (cd "$APP_ROOT" && tar -czf "$out" --exclude='build' --exclude='.dart_tool' --exclude='DerivedData' .)
  echo "$out"
}
restore_backup(){
  local f="$1"; [[ -f "$f" ]] || die "No existe backup $f"
  log "Restaurando backup $f"
  (cd "$APP_ROOT/.." && tar -xzf "$f")
}
boot_sim_by_udid(){
  local udid="$1" line
  line=$(xcrun simctl list devices | grep -F "$udid" || true)
  [[ -n "$line" ]] || return 1
  if ! xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1; then
    xcrun simctl boot "$udid" || true
    xcrun simctl bootstatus "$udid" -b || true
  fi
  echo "$udid"
}
boot_sim_by_name(){
  local name="$1" line udid
  # Extrae SOLO el UDID (nunca el estado). Ejemplo de línea:
  #   iPhone 16 (5B15...E432897) (Shutdown)
  line=$(xcrun simctl list devices | sed -n "s/.*${name} (\\([A-F0-9-]\\{36\\}\\)) (\\(Booted\\|Shutdown\\)).*/\\1/p" | head -n1) || true
  [[ -n "$line" ]] || die "No encontré simulador llamado '$name'. Descarga el runtime en Xcode > Settings > Platforms."
  udid="$line"
  boot_sim_by_udid "$udid" >/dev/null
  echo "$udid"
}
fix_xcconfig_includes(){
  for cfg in Debug Release Profile; do
    local cfg_file="$IOS_DIR/Flutter/$cfg.xcconfig"
    [[ -f "$cfg_file" ]] || continue
    grep -q 'Generated.xcconfig' "$cfg_file" || echo '#include "Generated.xcconfig"' >> "$cfg_file"
  done
}

main(){
  ensure_tools

  # Args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --sim) DEVICE_MODE="sim";  DEVICE_NAME="${2:-}"; shift 2;;
      --udid) DEVICE_MODE="udid"; DEVICE_UDID="${2:-}"; shift 2;;
      --build-only) BUILD_ONLY="1"; shift 1;;
      --restore) RESTORE_FILE="${2:-}"; shift 2;;
      --skip-clean) SKIP_CLEAN="1"; shift 1;;
      --skip-pods) SKIP_PODS="1"; shift 1;;
      -h|--help) usage; exit 0;;
      *) warn "Argumento ignorado: $1"; shift 1;;
    esac
  done

  if [[ -n "$RESTORE_FILE" ]]; then
    restore_backup "$RESTORE_FILE"; exit 0
  fi

  close_xcode
  backup_now; log "Backup OK ->"

  [[ "$SKIP_CLEAN" == "1" ]] || { log "flutter clean"; (cd "$APP_ROOT" && flutter clean); }

  log "flutter pub get (genera ios/Flutter/Generated.xcconfig)"
  (cd "$APP_ROOT" && flutter pub get)
  [[ -f "$IOS_DIR/Flutter/Generated.xcconfig" ]] || die "No se generó ios/Flutter/Generated.xcconfig"

  if [[ "$SKIP_PODS" != "1" ]]; then
    log "Reinstalando CocoaPods"
    pushd "$IOS_DIR" >/dev/null
      rm -rf Pods Podfile.lock Runner.xcworkspace
      pod deintegrate || true
      pod install
    popd >/dev/null
  fi

  fix_xcconfig_includes

  if [[ "$BUILD_ONLY" == "1" ]]; then
    log "Compilando para simulador (artefacto)…"
    (cd "$APP_ROOT" && flutter build ios --simulator)
    exit 0
  fi

  local target_udid=""
  case "$DEVICE_MODE" in
    sim)
      [[ -n "$DEVICE_NAME" ]] || die "Usa --sim \"iPhone 16\" (o similar)"
      target_udid="$(boot_sim_by_name "$DEVICE_NAME")"
      ;;
    udid)
      [[ -n "$DEVICE_UDID" ]] || die "Falta --udid <UDID>"
      target_udid="$(boot_sim_by_udid "$DEVICE_UDID")" || die "UDID no válido: $DEVICE_UDID"
      ;;
    *) die "Modo de device no soportado";;
  esac

  log "Abriendo Simulator ($target_udid)"
  open -a Simulator --args -CurrentDeviceUDID "$target_udid" || true

  log "flutter run -d $target_udid"
  (cd "$APP_ROOT" && flutter run -d "$target_udid")
}

main "$@"
