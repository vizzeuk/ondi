#!/bin/zsh
# Builds "Ondi.app" into ./build (and optionally copies it to /Applications with --install).
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NXBiblioteca"

# The icon is drawn from the logo's geometry (Sources/NXBiblioteca/LogoGeometry.swift); redrawn when either file changes.
if [[ ! -f Resources/AppIcon.icns || scripts/make_icon.swift -nt Resources/AppIcon.icns || Sources/NXBiblioteca/LogoGeometry.swift -nt Resources/AppIcon.icns ]]; then
  TMP="$(mktemp -d)"
  cp scripts/make_icon.swift "$TMP/main.swift"
  swiftc -O "$TMP/main.swift" Sources/NXBiblioteca/LogoGeometry.swift -o "$TMP/make_icon"
  "$TMP/make_icon" "$TMP/AppIcon.iconset"
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$TMP"
fi

APP="build/Ondi.app"
rm -rf "build/NX Biblioteca.app"   # the app's first name
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NXBiblioteca"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp patches/nxnative-keymap.patch "$APP/Contents/Resources/"   # DM_KEYMAP for the engine (Controles › Agregar soporte de teclas)
# Languages: Spanish is the source (the keys); each Resources/<lang>.lproj holds a translation
for L in Resources/*.lproj(N); do cp -R "$L" "$APP/Contents/Resources/"; done
mkdir -p "$APP/Contents/Resources/es.lproj"   # so macOS lists Spanish as a language of the app
mkdir -p "$APP/Contents/Resources/Licenses"
cp LICENSE NOTICE.md "$APP/Contents/Resources/Licenses/"   # credits travel with the app, without a screen for them
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Ondi.app"
  cp -R "$APP" /Applications/
  echo "Instalada en /Applications/Ondi.app"
else
  echo "Lista: $PWD/$APP"
fi
