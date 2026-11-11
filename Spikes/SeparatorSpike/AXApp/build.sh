#!/bin/zsh
# 검증용 앱을 build/SeparatorSpike.app 으로 만든다 (임시 서명). 설치하지 않는다.
#   ./build.sh          빌드
#   ./build.sh run      빌드 후 실행 (명령 폴더: ~/Library/Logs/SeparatorSpike)
# 임시 서명이라 다시 빌드하면 접근성 권한을 다시 허용해야 한다.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release 2>&1 | tail -3
APP="build/SeparatorSpike.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SeparatorSpikeApp "$APP/Contents/MacOS/SeparatorSpike"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.menubarmanager.separatorspike</string>
  <key>CFBundleName</key><string>SeparatorSpike</string>
  <key>CFBundleExecutable</key><string>SeparatorSpike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "built $PWD/$APP"
if [[ "${1:-}" == "run" ]]; then open -n "$APP"; echo "launched"; fi
