#!/bin/zsh
# README·사용 안내서에 쓰는 그림 중 "그린 그림"을 다시 만든다 → docs/images/
#   ./scripts/readme-images/make.sh
# 만드는 것: menubar-before-after.png, settings-menubar-en.png, settings-menubar-ko.png (앱 목록은 예시 앱)
# 만들지 않는 것: settings-general-*.png, menu-*.png — 실제 화면 캡처다.
#   Debug 빌드를 `-automationDir <폴더> -AppleLanguages "(en)"` 으로 실행해 `settings general`, `menushot` 명령으로 띄우고
#   `screencapture -x -o -l <창 번호>` 로 찍는다 (CLAUDE.md 의 자동 검증 방법 참고).
#   찍은 파일에는 모니터 색 프로파일 등의 메타데이터가 들어 있으므로 `swiftc strip.swift -o strip && ./strip <png>…` 로 지운 뒤 넣는다.
#   화면에 사용자의 앱 목록이 보이는 탭(메뉴바 관리)은 찍어서 올리지 않는다.
set -euo pipefail
cd "$(dirname "$0")"
OUT="../../docs/images"
WORK="../../build/readme-images"
mkdir -p "$WORK" "$OUT"

swiftc -O sym.swift -o "$WORK/sym"
swiftc -O snap.swift -o "$WORK/snap"
"$WORK/sym" curtains.closed curtains.open wifi battery.100percent switch.2 cloud.fill music.note paperplane.fill \
  doc.on.clipboard.fill rectangle.split.2x1.fill bolt.fill moon.fill cursorarrow.click.2 > "$WORK/syms.json"
python3 gen.py "$WORK"
"$WORK/snap" "$WORK/hero.html" "$OUT/menubar-before-after.png" 860
"$WORK/snap" "$WORK/settings-menubar-en.html" "$OUT/settings-menubar-en.png" 580
"$WORK/snap" "$WORK/settings-menubar-ko.html" "$OUT/settings-menubar-ko.png" 580
