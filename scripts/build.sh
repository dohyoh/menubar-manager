#!/bin/zsh
# 명령줄 빌드.
#   ./scripts/build.sh            빌드만
#   ./scripts/build.sh install    빌드 후 /Applications 에 설치 (숨김 동작 확인에 필요 — docs/adr/0010-install-location.md)
#   ./scripts/build.sh run        설치 후 실행
# 환경 변수:
#   CONFIG=Release                기본 Debug. Debug 빌드에는 자동 검증용 명령 채널이 들어 있으므로
#                                 평소에 쓰는 앱은 Release 로 설치한다 (CONFIG=Release ./scripts/build.sh install).
#   CODESIGN_IDENTITY="<이름/해시>" 기본: 키체인의 첫 번째 유효한 서명 인증서. 없으면 임시 서명.
#                                 고정 인증서로 서명해야 접근성 권한이 재빌드 후에도 유지된다.
#                                 임시 서명을 강제하려면 CODESIGN_IDENTITY="-"
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-Debug}"
DEFAULT_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/^ *1\)/ {print $2}')"
IDENTITY="${CODESIGN_IDENTITY:-${DEFAULT_IDENTITY:--}}"
DERIVED="build/DerivedData"
APP="$DERIVED/Build/Products/$CONFIG/MenuBarManager.app"
INSTALLED="/Applications/MenuBarManager.app"

xcodegen generate --quiet
# 빌드는 항상 임시 서명으로 한다. 고정 인증서를 지정했으면 완성된 앱을 그 인증서로 다시 서명한다.
# (패키지의 리소스 번들까지 Xcode 가 서명하게 하면 개발 팀 설정을 요구해서, 이 방식이 더 단순하다.)
xcodebuild -project MenuBarManager.xcodeproj -scheme MenuBarManager -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY="-" build -quiet
if [[ "$IDENTITY" != "-" ]]; then
  # 키체인이 키 접근을 물으면 여기서 멈춘다. 확인 창에서 "항상 허용"을 선택하면 다음부터 묻지 않는다.
  # --options runtime: 강화된 런타임. 다른 프로세스가 라이브러리를 끼워 넣어 이 앱의 접근성 권한을 빌려 쓰지 못하게 한다.
  codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
  echo "signed with fixed identity"
fi
echo "built $APP"

case "${1:-}" in
  install|run)
    pkill -f "$INSTALLED/Contents/MacOS/MenuBarManager" 2>/dev/null || true
    rm -rf "$INSTALLED"
    cp -R "$APP" "$INSTALLED"
    echo "installed $INSTALLED"
    if [[ "$1" == "run" ]]; then open -n "$INSTALLED"; echo "launched"; fi
    ;;
esac
