#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
IDENTITY="${SIGN_IDENTITY:-Gaveta DEV}"
swift build -c release --product Bolso
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Bolso.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
./Assets/build-icon.sh
cp Assets/Bolso.icns "$APP/Contents/Resources/Bolso.icns"
cp "$BIN_DIR/Bolso" "$APP/Contents/MacOS/Bolso"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Bolso</string>
<key>CFBundleIdentifier</key><string>dev.personal.Bolso</string>
<key>CFBundleName</key><string>Bolso</string>
<key>CFBundleDisplayName</key><string>Bolso</string>
<key>CFBundleIconFile</key><string>Bolso.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
if [[ "$IDENTITY" != "-" ]] && ! security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\""; then
  echo "Certificado '$IDENTITY' não encontrado. Veja README.md. Bundle gerado, mas não assinado." >&2
  exit 1
fi
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "Pronto: $APP"
if [[ "${1:-}" == "--install" ]]; then
  if pgrep -xq Bolso; then
    # A normal quit lets pending edits cancel the update instead of losing them.
    osascript -e 'quit app id "dev.personal.Bolso"' >/dev/null 2>&1 || true
    for _ in $(seq 50); do pgrep -xq Bolso || break; sleep 0.2; done
    if pgrep -xq Bolso; then
      echo "O Bolso continua aberto (edição pendente?). Saia pelo menu e rode de novo." >&2
      exit 1
    fi
  fi
  ditto "$APP" /Applications/Bolso.app
  open /Applications/Bolso.app
  echo "Instalado e aberto: /Applications/Bolso.app"
fi
