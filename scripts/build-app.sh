#!/usr/bin/env bash
# Builds build/Dockyard.app (web UI + Swift host).
set -euo pipefail
cd "$(dirname "$0")/.."

(cd web && { [ -d node_modules ] || npm install; } && npm run build)
swift build -c release

APP=build/Dockyard.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Dockyard" "$APP/Contents/MacOS/Dockyard"
cp -R web/dist "$APP/Contents/Resources/web"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.dockyard</string>
  <key>CFBundleName</key><string>Dockyard</string>
  <key>CFBundleExecutable</key><string>Dockyard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Sign with the local dev certificate if it exists (see setup-dev-cert.sh) so macOS keeps
# permissions like Accessibility across rebuilds. Otherwise fall back to an ad-hoc signature.
IDENTITY="Dockyard Local Dev"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "Signed with \"$IDENTITY\""
else
    codesign --force --sign - "$APP"
    echo "Signed ad-hoc. Run scripts/setup-dev-cert.sh to keep permissions across rebuilds."
fi
echo "Built $APP"
