#!/bin/zsh
# 처음 받았을 때 한 번 실행: 도구 확인 + Xcode 프로젝트 생성
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null; then
  echo "xcodegen 이 없습니다. 설치: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate
echo "생성 완료: MenuBarManager.xcodeproj"
echo "다음: ./scripts/build.sh install"
