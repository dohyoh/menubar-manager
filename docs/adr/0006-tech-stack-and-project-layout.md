# ADR-0006: 기술 스택과 프로젝트 구성

- 상태: ✅ 채택 (2026-11-10 사용자가 XcodeGen 설치, 이 구성으로 첫 빌드 성공)
- 날짜: 2026-11-10
- 관련: [project-structure.md](../architecture/project-structure.md)

## 맥락

개발 환경은 처음에 Xcode 26.6 / Swift 6.3.3이었고, 작업 중 Xcode 27.2 / Swift 6.4.2로 업데이트됐습니다 (두 버전 모두에서 빌드 확인). XcodeGen 2.46을 사용합니다. 대부분의 코드는 AI 코딩 도구와 함께 명령줄에서 작성·검증할 예정이라, 텍스트로 다루기 쉬운 구성이 유리합니다.

## 결정

| 항목 | 결정 |
|---|---|
| 언어 | Swift 6 (엄격한 동시성). 비공개 API 브리지만 Objective-C |
| UI | SwiftUI(화면) + AppKit(상태 아이템, 창, 이벤트) |
| 구성 | **얇은 앱 타깃 + 로컬 Swift Package(`Packages/MenuBarKit`)** |
| 프로젝트 파일 | **XcodeGen의 `project.yml`에서 생성.** `.xcodeproj`는 git에 넣지 않음 |
| 테스트 | Swift Testing, `swift test`로 실행 |
| 외부 의존성 | 없이 시작. 필요할 때 ADR 없이 추가 가능한 후보: KeyboardShortcuts, Sparkle |

## 검토한 대안

**UI 프레임워크**

| 대안 | 판단 |
|---|---|
| AppKit만 | 제어는 세밀하지만 목록·설정 UI 작성량이 큼 → 기각 |
| SwiftUI만 (`MenuBarExtra`) | 간단하지만 패널 위치·크기, 드래그 정렬, 이벤트 처리 제어가 부족 → 기각 |
| **SwiftUI + AppKit** | 화면은 빠르게, 시스템 접점은 정확하게 → **채택** |
| Electron/Tauri 등 | 접근성·이벤트·비공개 API 접근이 번거롭고 무거움 → 기각 |

**프로젝트 구성**

| 대안 | 장점 | 단점 | 판단 |
|---|---|---|---|
| Xcode에서 만든 `.xcodeproj`를 그대로 관리 | 도구 불필요 | `pbxproj`가 텍스트 도구로 다루기 어렵고 충돌이 잦음 | 차선 |
| SwiftPM만 + 스크립트로 `.app` 조립 | 도구 불필요, 전부 텍스트 | Info.plist·entitlements·서명·에셋을 직접 처리해야 함. Xcode 디버깅·미리보기 불편 | 기각 |
| **XcodeGen + 로컬 Package** | 선언적 YAML, 재생성 가능, 로직은 Package라 `swift test` 가능 | 도구 설치 1개 필요 (`brew install xcodegen`) | **채택 제안** |
| Tuist | 기능 풍부 | 이 규모에는 과함 | 기각 |

## 결과

- 대부분의 코드가 `Packages/MenuBarKit`에 있어 Xcode를 열지 않고도 빌드·테스트할 수 있습니다.
- 모듈 경계(누가 누구를 import할 수 있는지)를 `Package.swift`의 타깃 의존성으로 강제합니다.
- 새로 받은 사람은 `./scripts/bootstrap.sh` 한 번으로 프로젝트를 생성합니다.
- XcodeGen을 쓰지 않기로 하면: Xcode로 프로젝트를 한 번 만들고(폴더 동기화 그룹 사용) `.xcodeproj`를 커밋하는 방식으로 바꿉니다. 나머지 구조는 동일합니다.
