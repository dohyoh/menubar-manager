# MenuBarManager

macOS 메뉴바에 표시할 앱을 고르고, 숨긴 앱을 클릭 한 번으로 펼쳐 보고, 아이콘 순서를 정리하는 메뉴바 상주 앱입니다.

- 메뉴바 아이콘 **좌클릭**: 숨긴 앱 펼치기 ↔ 숨기기
- 메뉴바 아이콘 **우클릭**: 숨기기 스위치 · 설정 · 정보 · 종료
- **설정**: 앱별·시스템 아이콘(Wi-Fi, 배터리) 표시 여부, 순서 조정, 로그인 시 실행, 자동으로 다시 숨기기, 전역 단축키, 설정 백업

## 요구 사항

- 앱은 macOS 15 이상에서 실행됩니다.
- **숨김 기능은 macOS 27에서 확인했습니다.** 필요한 시스템 기능이 없는 버전에서는 숨김을 켜지 않고 그 이유를 알려 줍니다.
- 순서 조정과 일부 편의 기능은 손쉬운 사용(접근성) 권한이 필요합니다. 숨기기·펼치기는 권한 없이 동작합니다.

## 설치

1. [Releases](https://github.com/dohyoh/menubar-manager/releases)에서 `MenuBarManager-<버전>.zip`을 받아 압축을 풉니다.
2. `MenuBarManager.app`을 **응용 프로그램 폴더**로 옮깁니다. 다른 위치에서는 숨김 기능이 동작하지 않습니다.
3. 앱을 엽니다.

이 앱은 Apple의 공증을 받지 않았습니다. 처음 열 때 macOS가 실행을 막으면 다음 중 하나로 풉니다.

- 시스템 설정 > 개인정보 보호 및 보안 > 아래쪽의 "그래도 열기"
- 또는 터미널에서:

  ```bash
  xattr -dr com.apple.quarantine /Applications/MenuBarManager.app
  ```

새 버전으로 바꾸면 손쉬운 사용 권한을 다시 허용해야 합니다.

## 알아 둘 점

- 응용 프로그램 폴더 밖에 있는 앱과, 제어 센터에서 메뉴바로 꺼낸 항목(타이머 등)은 숨김 중에는 표시되지 않습니다.
- 숨김 중에도 시계를 누르면 알림 센터가 열립니다. 트랙패드를 쓸어서 여는 경우에는 먼저 펼쳐야 합니다.
- 앱을 종료하면 숨긴 아이콘은 모두 돌아옵니다.
- 숨김은 macOS의 비공개 기능을 사용합니다. macOS 업데이트로 동작이 바뀔 수 있고, Mac App Store에는 올릴 수 없습니다.
- 네트워크 통신을 하지 않습니다. 설정은 `~/Library/Application Support/MenuBarManager/state.json`에만 저장됩니다.

## 직접 빌드

Xcode와 [XcodeGen](https://github.com/yonaskolb/XcodeGen)이 필요합니다.

```bash
./scripts/bootstrap.sh
```

```bash
CONFIG=Release ./scripts/build.sh install
```

단위 테스트:

```bash
swift test --package-path Packages/MenuBarKit
```

## 문서

- 한눈에 보기: [docs/overview.html](docs/overview.html)
- 문서 지도와 현재 상태: [docs/README.md](docs/README.md)
- 변경 이력: [docs/CHANGELOG.md](docs/CHANGELOG.md)
