#!/bin/zsh
# M0 검증용 앱 빌드. 결과물: Spikes/MenuBarSpike/build/MenuBarSpike.app
# 사용: ./build.sh          빌드만
#       ./build.sh install  빌드 후 /Applications 에 설치 (숨김 검증에 필요)
# 서명 인증서를 고정해야 접근성 권한이 재빌드 후에도 유지됩니다.
#   CODESIGN_IDENTITY 환경 변수로 지정하거나, 없으면 첫 번째 유효한 인증서를 사용합니다.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MenuBarSpike.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.menubarmanager.spike</string>
  <key>CFBundleName</key><string>MenuBarSpike</string>
  <key>CFBundleDisplayName</key><string>MenuBarSpike</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleExecutable</key><string>MenuBarSpike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

clang -fobjc-arc -O1 -Wno-deprecated-declarations -framework AppKit -framework ApplicationServices SpikeApp.m SettingsWindow.m InfoWindow.m -o "$APP/Contents/MacOS/MenuBarSpike"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk 'NR==1 && /^ *1\)/ {print $2}')}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "signed with identity $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "WARNING: 인증서가 없어 임시(ad-hoc) 서명했습니다. 재빌드마다 접근성 권한을 다시 줘야 합니다."
fi
echo "built $APP"

# macOS 27: 앱이 /Applications 에 있어야 MenuBarAgent 가 메뉴바 아이콘을 번들 ID 와 연결한다.
# 다른 위치에서 실행하면 허용 목록에 넣어도 숨겨진다 (docs/architecture/platform-notes.md 참고).
if [[ "${1:-}" == "install" ]]; then
  pkill -f "/Applications/MenuBarSpike.app/Contents/MacOS/MenuBarSpike" 2>/dev/null || true
  rm -rf /Applications/MenuBarSpike.app
  cp -R "$APP" /Applications/MenuBarSpike.app
  echo "installed /Applications/MenuBarSpike.app"
fi
