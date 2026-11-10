#!/bin/zsh
# 배포용 압축 파일을 만든다: build/release/MenuBarManager-<버전>.zip
#   ./scripts/release.sh
#
# 버전은 project.yml 의 MARKETING_VERSION 을 쓴다.
# 배포 파일은 임시(ad-hoc) 서명으로 만든다 — 개발용 인증서에는 개발자 이름이 들어 있고,
# Developer ID 인증서가 없어 공증은 하지 않는다 (docs/adr/0011-unnotarized-release.md).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -nE 's/.*MARKETING_VERSION: "(.*)".*/\1/p' project.yml)"
APP="build/DerivedData/Build/Products/Release/MenuBarManager.app"
OUT="build/release"
ZIP="$OUT/MenuBarManager-$VERSION.zip"

CONFIG=Release CODESIGN_IDENTITY="-" ./scripts/build.sh
# 이전 빌드에서 고정 인증서로 서명된 결과물이 남아 있을 수 있으므로, 묶음 전체를 임시 서명으로 다시 봉인한다.
codesign --force --deep --options runtime --sign - "$APP"
codesign --verify --deep --strict "$APP"

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
  echo "버전이 맞지 않습니다: 빌드 $BUILT_VERSION, project.yml $VERSION" >&2
  exit 1
fi

mkdir -p "$OUT"
rm -f "$ZIP"
# 확장 속성은 넣지 않는다 (코드 서명은 묶음 안의 파일에 들어 있다).
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
echo "release $ZIP"
shasum -a 256 "$ZIP"
