#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST_DIR=${DIST_DIR:-$ROOT_DIR/dist}
BUILD_ROOT=${BUILD_ROOT:-$ROOT_DIR/.build}
SOURCE_PAGE_URL=${SOURCE_PAGE_URL:-https://teknik.dopinghafiza.com/}
SOURCE_EXE_URL=${SOURCE_EXE_URL:-}
SOURCE_EXE_PATH=${SOURCE_EXE_PATH:-}
ELECTRON_ZIP_PATH=${ELECTRON_ZIP_PATH:-}
# The official executable normally contains an Electron/<version> marker. An
# override is available for an upstream build that omits that marker.
ELECTRON_VERSION_OVERRIDE=${ELECTRON_VERSION_OVERRIDE:-}
APPIMAGE_RUNTIME_PATH=${APPIMAGE_RUNTIME_PATH:-}
APPIMAGE_RUNTIME_URL=${APPIMAGE_RUNTIME_URL:-https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64}
APPIMAGE_RUNTIME_SHA256=${APPIMAGE_RUNTIME_SHA256:-2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d}
UPDATE_OWNER=${DOPING_UPDATE_OWNER:-c8dhjp4tyv-bit}
UPDATE_REPO=${DOPING_UPDATE_REPO:-Doping-Hafiza-Linux}
ASAR_BIN=${ASAR_BIN:-}

log() { printf '[build] %s\n' "$*" >&2; }
die() { printf '[build] ERROR: %s\n' "$*" >&2; exit 1; }
need_command() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

for command_name in curl 7z unzip strings sha256sum sha512sum base64 xxd mksquashfs file node; do
  need_command "$command_name"
done
if command -v magick >/dev/null 2>&1; then
  IMAGE_CMD=magick
elif command -v convert >/dev/null 2>&1; then
  IMAGE_CMD=convert
else
  die 'ImageMagick (magick or convert) is required for the application icon'
fi
if [[ -z "$ASAR_BIN" ]]; then ASAR_BIN=$(command -v asar || true); fi
[[ -n "$ASAR_BIN" ]] || die "asar is required (install @electron/asar@3.4.1)"

mkdir -p "$DIST_DIR" "$BUILD_ROOT"
work_dir=$(mktemp -d "$BUILD_ROOT/run.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT

source_exe="$work_dir/DopingHafiza-Kurulum.exe"
if [[ -n "$SOURCE_EXE_PATH" ]]; then
  [[ -f "$SOURCE_EXE_PATH" ]] || die "SOURCE_EXE_PATH does not exist: $SOURCE_EXE_PATH"
  install -m 0644 "$SOURCE_EXE_PATH" "$source_exe"
else
  if [[ -z "$SOURCE_EXE_URL" ]]; then
    source_page="$work_dir/support.html"
    log "resolving current Windows package from $SOURCE_PAGE_URL"
    curl --fail --location --retry 3 --connect-timeout 20 --max-time 120 --user-agent 'Doping-Hafiza-Linux-CI/1.0' -o "$source_page" "$SOURCE_PAGE_URL"
    SOURCE_EXE_URL=$(grep -Eio 'https?://[^"[:space:]<>]+\.exe([^"[:space:]<>]*)?' "$source_page" | grep -Evi 'win7[-_]?8' | head -n 1 || true)
    [[ -n "$SOURCE_EXE_URL" ]] || die 'the official support page did not expose a current Windows EXE link'
    [[ "$SOURCE_EXE_URL" =~ ^https://([A-Za-z0-9.-]+\.)?(dopinghafiza\.com|dopingtech\.net)/ ]] || die "refusing EXE URL outside the official domains: $SOURCE_EXE_URL"
  fi
  log "downloading official Windows package from $SOURCE_EXE_URL"
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 900 --user-agent 'Doping-Hafiza-Linux-CI/1.0' -o "$source_exe" "$SOURCE_EXE_URL"
fi
[[ -s "$source_exe" ]] || die "downloaded EXE is empty"
file "$source_exe" | grep -Eqi 'PE32|MS-DOS executable' || die "download is not a Windows PE executable"
source_sha256=$(sha256sum "$source_exe" | awk '{print $1}')

nsis_dir="$work_dir/nsis"
mkdir -p "$nsis_dir"
log "extracting x64 NSIS payload"
7z x -y -o"$nsis_dir" "$source_exe" '$PLUGINSDIR/app-64.7z' >/dev/null
app_archive=$(find "$nsis_dir" -type f -name 'app-64.7z' -print -quit)
[[ -n "$app_archive" ]] || die 'the installer did not contain $PLUGINSDIR/app-64.7z'
7z t "$app_archive" >/dev/null

windows_dir="$work_dir/windows-app"
mkdir -p "$windows_dir"
7z x -y -o"$windows_dir" "$app_archive" >/dev/null
windows_asar="$windows_dir/resources/app.asar"
[[ -f "$windows_asar" ]] || die 'resources/app.asar was not found in the x64 payload'
windows_exe=$(find "$windows_dir" -maxdepth 1 -type f -iname '*.exe' -print -quit)
if [[ -z "$windows_exe" ]]; then
  windows_exe=$(find "$windows_dir" -maxdepth 2 -type f -iname '*.exe' -print -quit)
fi
[[ -n "$windows_exe" ]] || die 'the x64 payload did not contain an Electron executable'

asar_tree="$work_dir/app-tree"
"$ASAR_BIN" extract "$windows_asar" "$asar_tree"
package_json="$asar_tree/package.json"
[[ -f "$package_json" ]] || die 'app.asar has no package.json'
app_version=$(node -e 'const fs=require("fs"); const j=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); process.stdout.write(j.version || "")' "$package_json")
[[ "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]] || die "invalid upstream app version: $app_version"
main_relative=$(node -e 'const fs=require("fs"); const j=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); process.stdout.write(j.main || "")' "$package_json")
[[ -n "$main_relative" ]] || die 'app.asar package.json has no main entry'
main_path="$asar_tree/$main_relative"
[[ -f "$main_path" ]] || die "main entry does not exist: $main_relative"

if [[ -n "$ELECTRON_VERSION_OVERRIDE" ]]; then
  electron_version=$ELECTRON_VERSION_OVERRIDE
else
  detected_electron_line=$(strings "$windows_exe" | grep -Eo 'Electron[[:space:]/]+v?[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
  electron_version=$(printf '%s\n' "$detected_electron_line" | sed -E 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')
fi
[[ "$electron_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'could not determine Electron version from the EXE; set ELECTRON_VERSION_OVERRIDE'
log "upstream version=$app_version electron=$electron_version source_sha256=$source_sha256"

patched_main="$main_path.patched"
DOPING_UPDATE_OWNER="$UPDATE_OWNER" DOPING_UPDATE_REPO="$UPDATE_REPO" node "$ROOT_DIR/packaging/patch-updater.js" "$main_path" "$patched_main"
mv "$patched_main" "$main_path"
node --check "$main_path"

electron_zip="$work_dir/electron.zip"
if [[ -n "$ELECTRON_ZIP_PATH" ]]; then
  [[ -f "$ELECTRON_ZIP_PATH" ]] || die "ELECTRON_ZIP_PATH does not exist: $ELECTRON_ZIP_PATH"
  install -m 0644 "$ELECTRON_ZIP_PATH" "$electron_zip"
else
  electron_url="https://github.com/electron/electron/releases/download/v${electron_version}/electron-v${electron_version}-linux-x64.zip"
  log "downloading Electron runtime $electron_version"
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 900 --user-agent 'Doping-Hafiza-Linux-CI/1.0' -o "$electron_zip" "$electron_url"
fi
electron_dir="$work_dir/electron"
mkdir -p "$electron_dir"
unzip -q "$electron_zip" -d "$electron_dir"
electron_bin=$(find "$electron_dir" -type f -name electron -perm -u+x -print -quit)
[[ -n "$electron_bin" ]] || die 'Electron Linux zip did not contain an executable named electron'
runtime_version=$("$electron_bin" --version 2>/dev/null | head -n 1 || true)
runtime_version=${runtime_version#v}
[[ "$runtime_version" == "$electron_version" ]] || die 'Electron runtime version does not match the selected version'
electron_root=$(dirname "$electron_bin")

appdir="$work_dir/AppDir"
mkdir -p "$appdir"
cp -a "$electron_root"/. "$appdir/"
rm -f "$appdir/resources/default_app.asar"
[[ -f "$appdir/electron" ]] || die 'Electron runtime executable was not copied into the AppImage'
mv "$appdir/electron" "$appdir/doping-hafiza"
"$ASAR_BIN" pack "$asar_tree" "$appdir/resources/app.asar"
install -m 0755 "$ROOT_DIR/packaging/AppRun" "$appdir/AppRun"
sed "s/@VERSION@/$app_version/g" "$ROOT_DIR/packaging/doping-hafiza.desktop" > "$appdir/doping-hafiza.desktop"
mkdir -p "$appdir/resources"
printf '%s\n' 'provider: github' "owner: $UPDATE_OWNER" "repo: $UPDATE_REPO" 'releaseType: release' 'tagNamePrefix: v' 'updaterCacheDirName: doping-hafiza-updater' > "$appdir/resources/app-update.yml"

icon_dir="$work_dir/icons"
mkdir -p "$icon_dir"
icon_png=''
if command -v wrestool >/dev/null 2>&1 && command -v icotool >/dev/null 2>&1; then
  if wrestool -x --type=14 --name=1 --language=1033 "$windows_exe" > "$icon_dir/group-icon.bin" 2>"$icon_dir/wrestool.log"; then
    icotool -x -o "$icon_dir" "$icon_dir/group-icon.bin" >/dev/null 2>&1 || true
    icon_png=$(find "$icon_dir" -type f -name '*.png' -printf '%s %p\n' | sort -nr | awk 'NR == 1 { $1=""; sub(/^ /, ""); print }')
  fi
fi
icon_sizes=(16 32 48 64 128 256)
if [[ -n "$icon_png" ]]; then
  for icon_size in "${icon_sizes[@]}"; do
    icon_target="$appdir/usr/share/icons/hicolor/${icon_size}x${icon_size}/apps/doping-hafiza.png"
    mkdir -p "$(dirname "$icon_target")"
    "$IMAGE_CMD" "$icon_png" -background none -resize "${icon_size}x${icon_size}" -gravity center -extent "${icon_size}x${icon_size}" PNG32:"$icon_target"
  done
  cp "$appdir/usr/share/icons/hicolor/256x256/apps/doping-hafiza.png" "$appdir/doping-hafiza.png"
  cp "$appdir/doping-hafiza.png" "$DIST_DIR/doping-hafiza.png"
else
  fallback_svg="$asar_tree/assets/white-logo.svg"
  if [[ -f "$fallback_svg" ]]; then
    install -m 0644 "$fallback_svg" "$appdir/doping-hafiza.svg"
    install -m 0644 "$fallback_svg" "$DIST_DIR/doping-hafiza.svg"
  fi
fi
if [[ -f "$appdir/doping-hafiza.png" ]]; then ln -sfn doping-hafiza.png "$appdir/.DirIcon"; fi
if [[ -f "$appdir/doping-hafiza.svg" ]]; then ln -sfn doping-hafiza.svg "$appdir/.DirIcon"; fi
if command -v desktop-file-validate >/dev/null 2>&1; then desktop-file-validate "$appdir/doping-hafiza.desktop"; fi

runtime_path="$work_dir/runtime-x86_64"
if [[ -n "$APPIMAGE_RUNTIME_PATH" ]]; then
  [[ -f "$APPIMAGE_RUNTIME_PATH" ]] || die "APPIMAGE_RUNTIME_PATH does not exist: $APPIMAGE_RUNTIME_PATH"
  install -m 0755 "$APPIMAGE_RUNTIME_PATH" "$runtime_path"
else
  log 'downloading pinned AppImage type-2 runtime'
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 120 --user-agent 'Doping-Hafiza-Linux-CI/1.0' -o "$runtime_path" "$APPIMAGE_RUNTIME_URL"
fi
if [[ -n "$APPIMAGE_RUNTIME_SHA256" ]]; then
  printf '%s  %s\n' "$APPIMAGE_RUNTIME_SHA256" "$runtime_path" | sha256sum -c - >/dev/null || die 'AppImage runtime checksum mismatch'
fi

squashfs_path="$work_dir/rootfs.squashfs"
log 'building SquashFS payload'
mksquashfs "$appdir" "$squashfs_path" -all-root -noappend -comp gzip -b 131072 -no-xattrs -no-fragments >/dev/null
appimage_name="doping-hafiza-${app_version}-x86_64.AppImage"
appimage_work="$work_dir/$appimage_name"
cat "$runtime_path" "$squashfs_path" > "$appimage_work"
chmod 0755 "$appimage_work"
install -m 0755 "$appimage_work" "$DIST_DIR/$appimage_name"

appimage_path="$DIST_DIR/$appimage_name"
appimage_size=$(stat -c '%s' "$appimage_path")
appimage_sha256=$(sha256sum "$appimage_path" | awk '{print $1}')
appimage_sha512=$(sha512sum "$appimage_path" | awk '{print $1}' | xxd -r -p | base64 | tr -d '\n')
release_date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
printf '%s  %s\n' "$appimage_sha256" "$appimage_name" > "$DIST_DIR/$appimage_name.sha256"
printf '%s  DopingHafiza-Kurulum.exe\n' "$source_sha256" > "$DIST_DIR/source-exe.sha256"
printf '%s\n' "$app_version" > "$DIST_DIR/source-version.txt"
printf '%s\n' "version: $app_version" 'files:' "  - url: $appimage_name" "    sha512: $appimage_sha512" "    size: $appimage_size" "path: $appimage_name" "sha512: $appimage_sha512" "releaseDate: '$release_date'" > "$DIST_DIR/latest-linux.yml"
install -m 0755 "$ROOT_DIR/packaging/install.sh" "$DIST_DIR/install.sh"
sed "s/@VERSION@/$app_version/g" "$ROOT_DIR/packaging/doping-hafiza.desktop" > "$DIST_DIR/doping-hafiza.desktop"
printf '%s\n' "# Doping Hafıza Linux $app_version" '' 'Bu paket, resmi Windows kurulumundan otomatik olarak üretildi.' "Kaynak EXE SHA-256: $source_sha256" "Electron runtime: $electron_version" '' 'Kurulum: ./install.sh' > "$DIST_DIR/release-notes.md"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf '%s\n' "version=$app_version" "electron_version=$electron_version" "appimage=$appimage_name" "source_sha256=$source_sha256" >> "$GITHUB_OUTPUT"
fi
log "built $appimage_name ($appimage_size bytes)"
log "AppImage sha256=$appimage_sha256"
log "artifacts are in $DIST_DIR"
