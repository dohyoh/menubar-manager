# 프로젝트 구조

- 최종 수정: 2026-11-10 (실제 생성된 구조 반영)
- 관련: [overview.md](overview.md) · [ADR-0006](../adr/0006-tech-stack-and-project-layout.md)

> 기반 구조와 숨김·설정·정보 기능까지 구현되어 있습니다. 아래 트리에서 **(예정)** 표시가 없는 것은 실제로 있는 파일입니다.

## 1. 기술 스택

| 항목 | 선택 | 비고 |
|---|---|---|
| 언어 | Swift 6 (언어 모드 6, 엄격한 동시성). Xcode 27.2 / Swift 6.4.2로 빌드 확인 | 비공개 API 브리지만 Objective-C |
| UI | SwiftUI + AppKit | 패널·설정은 SwiftUI, 상태 아이템·창·이벤트는 AppKit |
| 최소 OS | macOS 15.0 (숨김은 시스템 기능이 있는 버전에서만) | [ADR-0002](../adr/0002-target-macos-27.md) |
| 프로젝트 생성 | XcodeGen (`project.yml`) | `.xcodeproj`는 생성물, git에 넣지 않음 |
| 모듈화 | 로컬 Swift Package (`Packages/MenuBarKit`) | 앱 타깃은 얇게 |
| 테스트 | Swift Testing | `swift test`로 Xcode 없이 실행 |
| 외부 의존성 | 없음 | 전역 단축키는 Carbon 핫키를 직접 사용. 후보: Sparkle(M6) |
| 샌드박스 | 끔 | [ADR-0007](../adr/0007-distribution.md) |
| 실행 위치 | 항상 `/Applications` | [ADR-0010](../adr/0010-install-location.md) |

## 2. 폴더 구조

```
1110_menubar_manager/
├── README.md                        # 저장소 소개: 설치·사용 안내 (받는 사람용, 영어)
├── README_KR.md · README_CN.md      # 같은 내용의 한국어·중국어 판
├── CLAUDE.md                        # 작업 규칙 요약 (문서 위치, 갱신 규칙)
├── project.yml                      # XcodeGen 프로젝트 정의 (.xcodeproj 는 생성물)
├── .gitignore
│
├── App/                             # 앱 타깃 — 얇게 유지
│   ├── main.swift                   # NSApplication 시작
│   ├── AppDelegate.swift            # 의존성 조립, 생명주기, 창 열기, 설치 위치 안내
│   ├── StatusItemController.swift   # 메뉴바 아이콘 — 좌클릭 토글 / 우클릭 메뉴
│   ├── Info.plist                   # LSUIElement = YES, 지원 언어(ko·en, 그 밖의 환경은 en), 아이콘
│   ├── Resources/AppIcon.icns       # 앱 아이콘 (scripts/make-icon.swift 로 생성)
│   └── Debug/AutomationHook.swift   # Debug 전용 명령 채널 (자동 검증용)
│
├── Packages/MenuBarKit/
│   ├── Package.swift                # 모듈 의존 규칙을 타깃 의존성으로 강제
│   ├── Sources/
│   │   ├── MenuBarDomain/           # 순수 모델·규칙·프로토콜 (Foundation 만)
│   │   │   ├── Models.swift         #   ManagedApp, Layout, Options, ManagerState, Allowlist
│   │   │   ├── Rules.swift          #   AllowlistBuilder, NewAppRule, AppListFilter
│   │   │   ├── Ordering.swift       #   순서 조정용: MenuBarItem, MovePlanner, 관련 프로토콜
│   │   │   └── Backends.swift       #   VisibilityControlling, AppDiscovering … (프로토콜)
│   │   ├── MenuBarServices/         # 앱 로직
│   │   │   ├── MenuBarCoordinator.swift   # 상태 머신 (유일한 상태 소유자)
│   │   │   ├── OrderingController.swift   # 순서 읽기·적용 흐름
│   │   │   └── Storage.swift              # JSONStateStore, TaskRehideScheduler
│   │   ├── MenuBarSystem/           # OS 접점 — OS 의존 코드는 여기에만
│   │   │   ├── AssessmentModeVisibilityController.swift   # 숨김 (허용 목록)
│   │   │   ├── WorkspaceAppDiscovery.swift                # 실행 중 + 설치된 앱
│   │   │   ├── SystemServices.swift                       # SelfPresenceChecker, LoginItemManager
│   │   │   ├── AccessibilityBackends.swift                # 접근성 권한, 아이템 열거, ⌘+드래그 합성, 메뉴바 사용 중·알림 센터 감지, 시계 클릭 감지
│   │   │   └── GlobalHotkeyCenter.swift                   # 전역 단축키 (Carbon 핫키)
│   │   ├── MenuBarPrivateBridge/    # Objective-C. 비공개 API 문자열은 여기에만
│   │   │   ├── include/MenuBarPrivateBridge.h
│   │   │   └── Bridge.m
│   │   └── MenuBarUI/               # 화면
│   │       ├── StatusMenuController.swift   # 우클릭 메뉴 (숨기기 스위치 · 새로 나타난 앱 · 설정… · 정보 · 종료)
│   │       ├── MenuSwitch.swift             # 메뉴용 스위치 (켜짐을 강조색으로 직접 그림)
│   │       ├── SettingsView.swift           # 설정 창 틀(탭: 메뉴바 관리 / 일반 / 진단) + 메뉴바 관리 (앱 목록, 새로 나타난 앱, 시스템 아이콘)
│   │       ├── GeneralSettingsView.swift    # 일반 탭: 로그인 시 실행, 자동 숨기기, 새 앱, 단축키, 백업
│   │       ├── DiagnosticsView.swift        # 진단 탭: 버전·상태·환경 점검 결과, 복사
│   │       ├── OrderEditor.swift            # 메뉴바 관리의 "순서 편집" 화면
│   │       ├── InfoView.swift               # 정보 화면 + 설명 문구(InfoContent)
│   │       ├── Presentation.swift           # 상태별 문구·아이콘, HostedWindow
│   │       ├── Strings.swift                # L("…") — 모든 사용자 문자열이 거치는 번역 함수
│   │       └── Resources/Localizable.xcstrings   # 한국어 원문 + 영어 번역
│   └── Tests/
│       ├── MenuBarDomainTests/      # 허용 목록, 목록 필터, 새 앱 처리, 이동 계획 (24개)
│       └── MenuBarServicesTests/    # 상태 머신·저장소·순서 조정 — 가짜 백엔드 사용 (34개)
│
├── Spikes/                          # 기술 검증용 일회성 코드 (제품에 포함 안 됨)
│   ├── README.md
│   └── MenuBarSpike/                # 숨김·좌/우클릭·설정·정보 검증용 앱
│
├── scripts/
│   ├── bootstrap.sh                 # 도구 확인 + Xcode 프로젝트 생성
│   ├── build.sh                     # 빌드. `install` / `run` 인자로 /Applications 에 설치·실행
│   ├── release.sh                   # 배포용 zip 만들기 (임시 서명, build/release/ 에 생성)
│   ├── strings.py                   # 문자열 카탈로그 동기화·번역 누락 검사
│   ├── make-icon.swift              # 앱 아이콘 생성
│   └── readme-images/               # README·안내서용 그림 생성 (make.sh → docs/images/)
│
└── docs/                            # → docs/README.md 참고
```

**아직 없는 것 (예정):** 로그(`os.Logger`), 프로필(M5), 공증·자동 업데이트(M6).

## 3. 모듈 의존 규칙

```
App ─▶ MenuBarUI ─▶ MenuBarServices ─▶ MenuBarDomain
 │                                         ▲
 └────▶ MenuBarSystem ─────────────────────┘
            └─▶ MenuBarPrivateBridge
```

- `MenuBarDomain`은 AppKit을 import하지 않습니다 (CoreGraphics 타입까지만).
- `MenuBarServices`·`MenuBarUI`는 `MenuBarSystem`을 import하지 않습니다. `Package.swift`의 타깃 의존성으로 강제합니다.
- 비공개 API 문자열(클래스명·셀렉터)은 `MenuBarPrivateBridge` 밖에 두지 않습니다.
- 새 OS 접점이 필요하면: ① Domain에 프로토콜 추가 → ② System에 구현 → ③ 테스트에 가짜 구현 → ④ App에서 주입.

## 4. 빌드·실행

```bash
./scripts/bootstrap.sh
```

```bash
./scripts/build.sh install
```

```bash
swift test --package-path Packages/MenuBarKit
```

- 처음 한 번 `bootstrap.sh`, 이후에는 `build.sh install`(또는 `run`)과 `swift test`만 쓰면 됩니다. `build.sh`가 매번 프로젝트를 다시 생성하므로 파일을 추가해도 따로 할 일이 없습니다.
- 일상 개발은 `swift test`로 Domain·Services를 빠르게 검증합니다.
- **OS 연동 확인은 `/Applications`에 설치한 빌드로 합니다.** 다른 위치에서 실행하면(Xcode의 ⌘R 포함) 숨김을 켰을 때 자기 아이콘이 사라집니다 ([ADR-0010](../adr/0010-install-location.md)).
- **서명:** 접근성 권한은 코드 서명에 묶입니다. 임시(ad-hoc) 서명이면 빌드할 때마다 권한을 다시 줘야 하므로, `build.sh`는 빌드를 임시 서명으로 한 뒤 **완성된 앱을 키체인의 개발 인증서로 다시 서명**합니다 (인증서가 없으면 임시 서명 그대로). 키체인이 키 접근을 물으면 **"항상 허용"** 을 선택해야 명령줄 빌드가 멈추지 않습니다.
- Xcode가 직접 고정 인증서로 서명하게 하면 패키지의 리소스 번들에 개발 팀 설정을 요구하며 실패합니다. 그래서 빌드 후 다시 서명하는 방식을 씁니다.
- 임시 서명을 강제하려면 `CODESIGN_IDENTITY="-" ./scripts/build.sh install`.
- 고정 인증서로 서명할 때는 강화된 런타임(`--options runtime`)을 함께 켠다.
- **평소에 쓰는 앱은 Release로 설치한다** — `CONFIG=Release ./scripts/build.sh install`. Debug 빌드에는 자동 검증용 명령 채널(`App/Debug/AutomationHook.swift`)이 들어 있어, 같은 사용자의 다른 프로세스가 실행 인자를 주어 이 앱의 접근성 권한으로 입력을 합성할 수 있다.

## 5. 코드 컨벤션

| 항목 | 규칙 |
|---|---|
| 이름 | Swift API Design Guidelines. 프로토콜은 역할(`…ing`), 구현은 방식+역할(`AXItemDiscovery`) |
| 파일 | 타입 1개 = 파일 1개. 300줄을 넘으면 분리 검토 |
| 상태 | UI 상태는 `@Observable`. 전역 싱글턴 금지, 주입으로 전달 |
| 오류 | OS 접점은 `throws` + 도메인 오류 타입. `try!`·강제 언래핑 금지 (System 모듈 특히) |
| 로그 | `os.Logger`, 카테고리 = 모듈명. 개인 식별 정보는 `.private` |
| 주석 | "왜"만 적음. OS 동작에 기댄 코드는 [platform-notes.md](platform-notes.md)의 해당 절을 링크 |
| 문자열 | 사용자에게 보이는 문자열은 전부 `L("…")`로 감싼다. 추가·수정 후 `python3 scripts/strings.py sync`로 카탈로그에 넣고 영어 번역을 채운 뒤 `check` |
| 커밋 | 한 가지 변경 = 한 커밋. 문서 갱신은 같은 커밋에 포함 |

## 6. 테스트 전략

| 대상 | 방법 | 자동화 |
|---|---|---|
| 규칙 (허용 목록 계산, 이동 계획) | 단위 테스트, 표 기반 케이스 | ✅ `swift test` |
| 상태 머신 (Coordinator) | 가짜 백엔드 + 가짜 시계로 전이 검증 | ✅ `swift test` |
| 저장 (LayoutStore) | 임시 디렉터리, 스키마 마이그레이션 | ✅ `swift test` |
| OS 접점 (System) | 앱 내 자가진단 + 수동 체크리스트 | ⚠️ 수동 (권한·실제 메뉴바 필요) |
| UI | SwiftUI 미리보기 | 수동 |

OS 접점은 자동 테스트가 어렵기 때문에, **System 모듈을 얇게** 유지하고 판단 로직은 Domain·Services로 끌어올리는 것이 핵심입니다.
