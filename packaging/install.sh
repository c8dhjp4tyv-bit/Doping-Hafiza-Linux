#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

UPDATE_OWNER=${DOPING_UPDATE_OWNER:-c8dhjp4tyv-bit}
UPDATE_REPO=${DOPING_UPDATE_REPO:-Doping-Hafiza-Linux}
PRODUCT_NAME='Doping Hafıza'
APP_NAME='doping-hafiza'
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

MODE=user
PREFIX_OVERRIDE=''
APPIMAGE_INPUT=''
UNINSTALL=0
AUTOSTART=0
NO_DESKTOP=0
DOWNLOAD_DIR=''

usage() {
  cat <<'EOF'
Kullanım: ./install.sh [seçenekler]

Seçenekler:
  --appimage PATH   Kurulacak AppImage dosyasını belirtir
  --prefix PATH     Hedef uygulama dizinini belirtir
  --system          Sistem geneli kurulum (/opt, /usr/local/bin)
  --user            Kullanıcı kurulumu (varsayılan, otomatik güncelleme için önerilir)
  --autostart       Oturum açıldığında uygulamayı başlatan XDG kaydı oluşturur
  --no-desktop      Menü/görev çubuğu için .desktop kaydı oluşturmaz
  --uninstall       Bu kurulumun dosyalarını kaldırır
  -h, --help        Bu yardımı gösterir

AppImage aynı klasörde bulunmuyorsa, son GitHub Release içinden otomatik indirilir.
EOF
}

die() {
  printf 'install.sh: HATA: %s\n' "$*" >&2
  exit 1
}

fetch_url() {
  local url=$1
  local destination=$2
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --retry 3 --connect-timeout 20 --max-time 900 -o "$destination" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget --tries=3 --timeout=30 -O "$destination" "$url"
  else
    die 'curl veya wget gerekli'
  fi
}

desktop_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value// /\\ }
  value=${value//$'\t'/\\t}
  value=${value//"/\\"}
  printf '%s' "$value"
}

while (($# > 0)); do
  case "$1" in
    --appimage)
      (($# >= 2)) || die '--appimage bir yol bekler'
      APPIMAGE_INPUT=$2
      shift 2
      ;;
    --prefix)
      (($# >= 2)) || die '--prefix bir yol bekler'
      PREFIX_OVERRIDE=$2
      shift 2
      ;;
    --system)
      MODE=system
      shift
      ;;
    --user)
      MODE=user
      shift
      ;;
    --autostart)
      AUTOSTART=1
      shift
      ;;
    --no-desktop)
      NO_DESKTOP=1
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "bilinmeyen seçenek: $1"
      ;;
  esac
done

if [[ "$MODE" == system ]]; then
  ((EUID == 0)) || die '--system için root yetkisi gerekir (sudo ./install.sh --system)'
  PREFIX=${PREFIX_OVERRIDE:-/opt/doping-hafiza}
  BIN_DIR=/usr/local/bin
  DATA_HOME=/usr/share
  CONFIG_HOME=/etc/xdg
else
  ((EUID != 0)) || die 'root ile kullanıcı kurulumu yapılamaz; --system kullanın'
  PREFIX=${PREFIX_OVERRIDE:-${XDG_DATA_HOME:-$HOME/.local/share}/doping-hafiza}
  BIN_DIR=${XDG_BIN_HOME:-$HOME/.local/bin}
  DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
  CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
fi

case "$PREFIX" in
  /*) ;;
  *) die '--prefix mutlak bir yol olmalıdır' ;;
esac
[[ "$PREFIX" != / && -n "$PREFIX" ]] || die 'güvenli olmayan prefix'

DESKTOP_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor"
AUTOSTART_DIR="$CONFIG_HOME/autostart"
APPIMAGE_DEST="$PREFIX/$APP_NAME.AppImage"
BIN_DEST="$BIN_DIR/$APP_NAME"
DESKTOP_DEST="$DESKTOP_DIR/$APP_NAME.desktop"
AUTOSTART_DEST="$AUTOSTART_DIR/$APP_NAME.desktop"

if [[ "$UNINSTALL" == 1 ]]; then
  if [[ -L "$BIN_DEST" && "$(readlink -- "$BIN_DEST")" == "$APPIMAGE_DEST" ]]; then
    rm -f "$BIN_DEST"
  fi
  rm -f "$DESKTOP_DEST" "$AUTOSTART_DEST"
  rm -f "$ICON_DIR/256x256/apps/$APP_NAME.png" "$ICON_DIR/scalable/apps/$APP_NAME.svg"
  rm -f "$PREFIX/$APP_NAME.png" "$PREFIX/$APP_NAME.svg" "$APPIMAGE_DEST"
  rmdir "$PREFIX" 2>/dev/null || true
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  fi
  printf '%s kaldırıldı (%s).\n' "$PRODUCT_NAME" "$MODE"
  exit 0
fi

case "$(uname -m)" in
  x86_64|amd64) ;;
  *) die 'şu an yalnızca x86_64 AppImage yayımlanıyor' ;;
esac

if [[ -n "$APPIMAGE_INPUT" ]]; then
  [[ -f "$APPIMAGE_INPUT" ]] || die "AppImage bulunamadı: $APPIMAGE_INPUT"
  APPIMAGE_SOURCE=$(CDPATH= cd -- "$(dirname -- "$APPIMAGE_INPUT")" && pwd)/$(basename -- "$APPIMAGE_INPUT")
else
  candidates=("$SCRIPT_DIR"/doping-hafiza-*.AppImage)
  if ((${#candidates[@]} == 1)); then
    APPIMAGE_SOURCE=${candidates[0]}
  elif ((${#candidates[@]} > 1)); then
    die 'birden fazla AppImage bulundu; --appimage ile seçim yapın'
  else
    DOWNLOAD_DIR=$(mktemp -d)
    trap 'rm -rf "$DOWNLOAD_DIR"' EXIT
    release_json="$DOWNLOAD_DIR/release.json"
    release_api="https://api.github.com/repos/$UPDATE_OWNER/$UPDATE_REPO/releases/latest"
    fetch_url "$release_api" "$release_json"
    appimage_url=$(sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*doping-hafiza-[^"]*\.AppImage\)".*/\1/p' "$release_json" | head -n 1)
    [[ -n "$appimage_url" ]] || die 'son release içinde AppImage bulunamadı'
    APPIMAGE_SOURCE="$DOWNLOAD_DIR/$APP_NAME.AppImage"
    fetch_url "$appimage_url" "$APPIMAGE_SOURCE"
    icon_url="https://github.com/$UPDATE_OWNER/$UPDATE_REPO/releases/latest/download/doping-hafiza.png"
    fetch_url "$icon_url" "$DOWNLOAD_DIR/doping-hafiza.png" >/dev/null 2>&1 || true
    if [[ ! -s "$DOWNLOAD_DIR/doping-hafiza.png" ]]; then
      icon_url="https://github.com/$UPDATE_OWNER/$UPDATE_REPO/releases/latest/download/doping-hafiza.svg"
      fetch_url "$icon_url" "$DOWNLOAD_DIR/doping-hafiza.svg" >/dev/null 2>&1 || true
    fi
  fi
fi

[[ -s "$APPIMAGE_SOURCE" ]] || die 'AppImage boş'
file "$APPIMAGE_SOURCE" | grep -Eq 'ELF|AppImage' || die 'geçerli bir AppImage değil'
APPIMAGE_SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$APPIMAGE_SOURCE")" && pwd)

if [[ -e "$BIN_DEST" && ! -L "$BIN_DEST" ]]; then
  die "normal dosya korunuyor, üzerine yazılmadı: $BIN_DEST"
fi
install -d "$PREFIX" "$BIN_DIR"
install -m 0755 "$APPIMAGE_SOURCE" "$APPIMAGE_DEST"
ln -sfn "$APPIMAGE_DEST" "$BIN_DEST"

ICON_SOURCE=''
for icon_candidate in \
  "$APPIMAGE_SOURCE_DIR/doping-hafiza.png" \
  "${DOWNLOAD_DIR:-$SCRIPT_DIR}/doping-hafiza.png" \
  "$SCRIPT_DIR/doping-hafiza.png" \
  "$APPIMAGE_SOURCE_DIR/doping-hafiza.svg" \
  "${DOWNLOAD_DIR:-$SCRIPT_DIR}/doping-hafiza.svg" \
  "$SCRIPT_DIR/doping-hafiza.svg"; do
  if [[ -s "$icon_candidate" ]]; then
    ICON_SOURCE=$icon_candidate
    break
  fi
done

write_desktop() {
  local destination=$1
  local exec_value
  exec_value=$(desktop_escape "$APPIMAGE_DEST")
  install -d "$(dirname "$destination")"
  {
    printf '%s\n' '[Desktop Entry]'
    printf 'Name=%s\n' "$PRODUCT_NAME"
    printf '%s\n' 'Comment=Doping Hafıza eğitim uygulaması'
    printf 'Exec=%s %%U\n' "$exec_value"
    printf '%s\n' 'Terminal=false' 'Type=Application' 'Icon=doping-hafiza' 'StartupWMClass=doping-hafiza' 'Categories=Education;'
  } > "$destination"
  chmod 0644 "$destination"
}

if [[ "$NO_DESKTOP" == 0 ]]; then
  if [[ "$ICON_SOURCE" == *.png ]]; then
    install -D -m 0644 "$ICON_SOURCE" "$PREFIX/$APP_NAME.png"
    install -D -m 0644 "$ICON_SOURCE" "$ICON_DIR/256x256/apps/$APP_NAME.png"
  elif [[ "$ICON_SOURCE" == *.svg ]]; then
    install -D -m 0644 "$ICON_SOURCE" "$PREFIX/$APP_NAME.svg"
    install -D -m 0644 "$ICON_SOURCE" "$ICON_DIR/scalable/apps/$APP_NAME.svg"
  fi
  write_desktop "$DESKTOP_DEST"
  if [[ "$AUTOSTART" == 1 ]]; then
    write_desktop "$AUTOSTART_DEST"
  fi
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  fi
fi

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  distro=${PRETTY_NAME:-${ID:-unknown}}
else
  distro=unknown
fi

printf '%s kuruldu (%s, %s).\n' "$PRODUCT_NAME" "$MODE" "$distro"
printf 'Başlatma: %s\n' "$BIN_DEST"
if [[ "$MODE" == user ]]; then
  printf '%s\n' 'Kullanıcı kurulumu yazılabilir olduğundan GitHub Releases otomatik güncellemeleri kullanılabilir.'
else
  printf '%s\n' 'Sistem kurulumu root yazma izni ister; otomatik güncelleme için kullanıcı kurulumu önerilir.'
fi
printf '%s\n' 'GUI uygulaması için systemd servisi kurulmadı; .desktop kaydı uygulama menüsü/görev çubuğu entegrasyonunu sağlar.'
