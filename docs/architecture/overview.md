# 아키텍처 개요

- 최종 수정: 2026-11-10 (순서 조정 구현 반영)
- 관련: [project-structure.md](project-structure.md) · [platform-notes.md](platform-notes.md) · [adr/](../adr/README.md)

> 숨김·펼치기·설정·정보·순서 조정이 구현되어 동작합니다. 아래 코드 조각은 설계 설명용이며, 실제 선언은 `Packages/MenuBarKit/Sources/MenuBarDomain`에 있습니다.

## 1. 설계 원칙

1. **Fail-open.** 무엇이 잘못되든 메뉴바는 "전부 표시" 상태로 돌아간다. 이 앱의 아이콘은 항상 보인다.
2. **OS 의존 코드는 한 곳에.** 비공개 API·접근성·이벤트 합성은 `MenuBarSystem` 모듈 안에만 있고, 나머지는 프로토콜만 본다. ([ADR-0005](../adr/0005-backend-abstraction-private-api.md))
3. **상태의 주인은 하나.** `MenuBarCoordinator`가 유일한 상태 소유자. 아이콘·메뉴·설정 창은 읽고 의도(intent)만 보낸다.
4. **미리 막는다.** 자기 아이콘이 숨겨졌는지는 앱이 알 수 없으므로([platform-notes 3.13](platform-notes.md#313-자기-아이콘이-숨겨졌는지는-알-수-없다)), 그 원인(응용 프로그램 폴더 밖 실행, 시스템 기능 없음)을 숨김을 켜기 전에 확인한다.
5. **이벤트 기반.** 주기적 폴링 대신 앱 실행/종료, 디스플레이 변경 알림에 반응한다.
6. **권한은 필요한 기능에만.** 숨김·펼치기는 권한 없이 동작한다. 접근성 권한은 순서 변경에서만 요구한다.

## 2. 사용자 접점

| 접점 | 역할 | 구현 위치 |
|---|---|---|
| 메뉴바 아이콘 좌클릭 | 펼치기 ↔ 숨기기 | `App/StatusItemController` → `Coordinator.toggle()` |
| 메뉴바 아이콘 우클릭 | 메뉴: 숨기기 스위치 · (새로 나타난 앱 N개…) · 설정… · 정보 · 종료 | `MenuBarUI/StatusMenuController` |
| 설정 창 > 메뉴바 관리 | 앱별 표시 여부, 검색·필터(메뉴바 / 실행 중 / 숨긴 앱 / 전체), 새로 나타난 앱, 시스템 아이콘(Wi-Fi·배터리) 표시 여부 | `MenuBarUI/SettingsView` |
| 설정 창 > 메뉴바 관리 > 순서 편집 | 관리 목록과 같은 자리에서 메뉴바 순서 읽기, 목록 드래그, 적용 (접근성 권한 필요). 적용·취소하면 관리 목록으로 복귀 | `MenuBarUI/OrderEditor` + `MenuBarServices/OrderingController` |
| 설정 창 > 일반 | 로그인 시 실행, 펼친 뒤 자동으로 다시 숨기기, 새 앱 정책, 전역 단축키, 백업 | `MenuBarUI/GeneralSettingsView` |
| 설정 창 > 진단 | 앱·macOS 버전, 상태, 숨김 기능·설치 위치·접근성 권한 등 표시와 복사 | `MenuBarUI/DiagnosticsView` |
| 전역 단축키 | 펼치기 ↔ 숨기기, 설정 열기 (사용자가 지정) | `MenuBarSystem/GlobalHotkeyCenter` → `AppDelegate` |
| 시계 누름 (숨김 중) | 알림 센터가 열리도록 숨김을 잠깐 풂 | `MenuBarSystem/ClockClickMonitor` → `Coordinator.expandForSystemUI()` |
| 정보 화면 | 주요 기능의 간략한 설명 (메뉴바 아이콘 옮기기 포함), 버전 | `MenuBarUI/Info` |

패널(팝오버)은 없습니다 ([ADR-0009](../adr/0009-interaction-model.md)).

## 3. 계층

```
┌──────────────────────────────────────────────────────────────┐
│ App (실행 파일)                                               │
│   @main, AppDelegate, 의존성 조립                              │
│   StatusItemController (좌/우클릭), 설정 창 열기               │
└───────────────┬──────────────────────────────────────────────┘
                │
┌───────────────▼───────────┐
│ MenuBarUI (SwiftUI)       │  우클릭 메뉴, 설정 창(메뉴바 관리·일반), 온보딩
└───────────────┬───────────┘
                │ 의도(intent) ↓   상태(state) ↑
┌───────────────▼───────────┐
│ MenuBarServices           │  MenuBarCoordinator(상태 머신),
│                           │  LayoutStore, RehideTimer, AppCatalog, HotkeyCenter
└───────┬───────────────────┘
        │ 프로토콜로만 의존
┌───────▼───────────┐      ┌──────────────────────────────────┐
│ MenuBarDomain     │◀─────│ MenuBarSystem (OS 접점)           │
│ 모델·규칙·프로토콜 │ 구현  │  허용 목록 제어, 앱/아이템 열거,   │
│ (Foundation만)    │      │  이벤트 합성, 권한, 로그인 항목,   │
└───────────────────┘      │  설치 위치 확인                   │
                           │   └─ MenuBarPrivateBridge (ObjC)  │
                           └──────────────────────────────────┘
```

**의존 방향:** `UI → Services → Domain ← System`. `Services`와 `UI`는 `System`을 직접 import하지 않습니다. `App`만 구현체를 골라 주입합니다.

## 4. 모듈 책임

| 모듈 | 책임 | 의존 | 테스트 |
|---|---|---|---|
| `MenuBarDomain` | 모델(`ManagedApp`, `Layout` …), 순수 규칙(허용 목록 계산, 이동 계획, 목록 검색·필터), 백엔드 프로토콜 정의 | Foundation | 단위 테스트 (핵심) |
| `MenuBarServices` | `MenuBarCoordinator` 상태 머신, 저장, 타이머, 앱 카탈로그, 단축키, 프로필 | Domain | 가짜 백엔드로 단위 테스트 |
| `MenuBarSystem` | 프로토콜의 실제 구현. OS API 호출 전부 | Domain, AppKit, ApplicationServices, ServiceManagement | 수동 검증 + 자가진단 |
| `MenuBarPrivateBridge` | 비공개 클래스 런타임 조회·호출 (Objective-C) | Foundation | 존재 여부 검사 |
| `MenuBarUI` | SwiftUI 화면, 우클릭 메뉴 구성 | Domain, Services | 미리보기 |
| `App` | 조립, 생명주기, 상태 아이콘 입력 처리, 창 관리 | 전부 | 수동 |

## 5. 도메인 모델

```swift
/// 메뉴바 아이템을 가질 수 있는 앱 하나. 표시/숨김의 단위.
struct ManagedApp: Identifiable, Hashable, Codable {
    let id: BundleID              // "com.example.app"
    var name: String
    var location: URL?            // 설치 경로
    var presence: Presence        // .inMenuBar | .running | .installedOnly
    var kind: Kind                // .thirdParty | .system(number) | .selfApp
    var constraint: Constraint?   // 표시/숨김을 제어할 수 없는 이유
    var items: [MenuBarItem]      // 접근성 권한이 있을 때만 채워짐
}

enum Constraint: Codable {
    case protected                // 자기 자신, 시계, 제어 센터 — 숨길 수 없음
    case outsideApplications      // /Applications 밖 — 숨김 중 표시할 수 없음
    case controlCenterModule      // 타이머 등 — 숨김 중 항상 숨겨짐
}

/// 아이템 하나. 순서 조정의 단위.
struct MenuBarItem: Identifiable, Hashable, Codable {
    let id: ItemID                // bundleID + 앱 내 식별자
    var title: String?
    var frame: CGRect?            // 현재 화면 좌표 (보일 때만)
    var isMovable: Bool
}

/// 저장되는 설정 한 벌.
struct Layout: Codable, Equatable {
    var hiddenApps: Set<BundleID>         // 숨길 앱. 나머지는 표시
    var hiddenSystemItems: Set<Int>       // 숨길 시스템 아이템 번호 (Wi-Fi 6, 배터리 0 만 허용)
    var knownApps: Set<BundleID>          // 한 번이라도 본 앱 — "처음 보는 앱" 판별용
    var pendingApps: Set<BundleID>        // 정책이 "묻기"일 때, 아직 정하지 않은 새 앱
    var newAppPolicy: NewAppPolicy        // .show | .hide | .ask
}                                         // 순서는 저장하지 않는다 (시스템이 기억)

struct Options: Codable {
    var hidingEnabled: Bool = false       // 메뉴의 숨기기 스위치. 다음 실행 때 이 상태로 시작
    var autoRehide: Bool = true           // 펼친 뒤 자동으로 다시 숨기기
    var autoRehideSeconds: Int = 10       // 설정 > 일반에서 3·5·10·15·30·60초 중 선택
    var hotkeys: [Int: Hotkey] = [:]      // 전역 단축키 (HotkeyAction → 키 코드·조합 키·표시 문자열)
}
```

**숨길 앱을 저장합니다 (표시할 앱이 아니라).** 시스템 API는 "허용 목록"을 받지만, 사용자 의도는 "이것들을 숨겨라"이고 새 앱은 기본적으로 보여야 하기 때문입니다. 허용 목록은 적용 시점에 계산합니다:

```
허용 목록 = (실행 중인 앱 ∪ 설치된 앱) − hiddenApps ∪ {자기 자신}
시스템 아이템 = (0...255) − hiddenSystemItems ∪ {보호 대상 번호}
```

### 백엔드 프로토콜 (Domain에 정의, System이 구현)

```swift
protocol VisibilityControlling: Sendable {
    /// 허용 목록에 있는 앱·시스템 아이템만 표시. 이미 제한 중이면 깜빡임 없이 교체.
    func restrict(to allowed: Allowlist) async throws
    /// 제한 해제 — 전부 표시
    func unrestrict() async
    var isRestricted: Bool { get async }
}

protocol AppDiscovering: Sendable {
    /// 실행 중인 앱 + 설치된 앱. 권한 불필요.
    func catalog() async -> [ManagedApp]
    /// 앱 실행/종료/설치 변화
    var changes: AsyncStream<Void> { get }
}

protocol ItemDiscovering: Sendable {
    /// 현재 메뉴바의 아이템과 좌표 (왼쪽 → 오른쪽). 접근성 권한 필요.
    func currentItems() async throws -> [MenuBarItem]
}

protocol ItemReordering: Sendable {
    func move(_ item: ItemID, to destination: MoveDestination) async throws
}

protocol SelfPresenceChecking {
    var selfBundleID: BundleID { get }
    /// 이 앱이 /Applications 에 설치되어 있는가. 아니면 숨김을 켜지 않는다.
    var isInstalledInApplications: Bool { get }
}

protocol PermissionChecking: Sendable {
    func status(of permission: Permission) -> PermissionStatus
    func request(_ permission: Permission)
}

protocol CompatibilityChecking: Sendable {
    func capabilities() -> Capabilities
}
```

`VisibilityControlling`의 구현 규칙(검증됨, [platform-notes 3.8](platform-notes.md#38-허용-목록-교체)): 교체할 때는 새 assertion을 켠 뒤 완료 핸들러에서 이전 것을 해제하고, 동시에 1개만 유지합니다.

## 6. 상태 머신

```
                    ┌──────────────┐
        시작 ──────▶│   paused     │◀──────────────────────┐
                    │ (전부 표시)   │                        │
                    └──────┬───────┘                        │
       자가진단 통과 +       │                               │ 오류 · 비호환 · 자기 아이콘 사라짐
       /Applications 설치   ▼                               │ 메뉴에서 숨기기 스위치 끔 
                    ┌──────────────┐    좌클릭      ┌────────┴─────┐
                    │  collapsed   │──────────────▶│   expanded   │
                    │ (숨김 적용)   │◀──────────────│  (전부 표시)  │
                    └──────┬───────┘  좌클릭 /      └──────────────┘
                           │          자동 타이머
                 순서 변경  ▼
                    ┌──────────────┐
                    │  reordering  │  (필요 시 잠시 펼침 → 이동 → 다시 숨김)
                    └──────────────┘
```

| 상태 | 메뉴바 | 아이콘 | 진입 |
|---|---|---|---|
| `paused` | 전부 표시 (관리 안 함) | 펼침과 같은 모양 (숨김을 켤 수 없는 상태면 느낌표 네모) | 시작 직후, 오류, 비호환, 메뉴의 숨기기 스위치 끔, 종료 직전 |
| `collapsed` | 레이아웃대로 숨김 적용 | 닫힌 커튼 | 평소 상태 |
| `expanded(until:)` | 전부 표시 | 열린 커튼 | 좌클릭 |
| `reordering` | 순서를 읽거나 바꾸는 중 — 전부 펼쳐 둠. 좌클릭·스위치는 무시 | 펼침과 같은 모양 | 순서 편집의 읽기·적용. 끝나면 이전 상태로 복귀 |

`paused`와 `expanded`는 메뉴바 모습이 같지만 뜻이 다릅니다. `expanded`는 좌클릭으로 잠깐 펼친 상태라 타이머로 `collapsed`에 돌아가고, `paused`는 사용자가 다시 켤 때까지(스위치 켬 또는 좌클릭) 유지됩니다.

우클릭 메뉴의 스위치는 `collapsed`일 때만 켜진 것으로 보입니다.

**불변 조건**
- `collapsed`에서도 허용 목록에는 항상 이 앱 자신과 보호 대상이 들어 있다.
- 응용 프로그램 폴더 밖이거나 시스템 기능이 없으면 `collapsed`로 가지 않는다 (`paused`에 이유와 함께 머문다).
- 응용 프로그램 폴더에서 앱을 다시 열면 설정 창이 뜬다 (아이콘이 안 보일 때의 탈출구).
- 어떤 상태에서든 예외가 나면 `unrestrict()` 후 `paused`.
- 앱 종료 시 `unrestrict()`를 호출한다. 크래시·강제 종료 시에는 시스템이 해제한다 (검증됨).

## 7. 주요 흐름

### 7.1 좌클릭 — 펼치기/숨기기 (FR-2)

```
좌클릭 → Coordinator.toggle()
  ├─ collapsed → unrestrict() → expanded(until: autoRehide ? now + N초 : nil)
  ├─ expanded  → restrict(to: allowlist) → collapsed
  └─ paused    → (설치 위치·호환성 확인 후) restrict → collapsed

자동 숨기기 타이머 만료 (expanded 일 때)
  ├─ 어떤 메뉴든 열려 있음 / 포인터가 메뉴바 위 (MenuBarActivityChecking): 2초 뒤 다시 확인
  └─ 그 외: restrict → collapsed
```

### 7.2 우클릭 — 메뉴 (FR-16)

```
우클릭 / Control+클릭
  → StatusMenu 구성 (현재 상태 반영)
      숨기기 [스위치] · (프로필) · 설정… · 정보 · 종료
  → 스위치 켬: (설치 위치·시스템 기능 확인) → restrict → collapsed
  → 스위치 끔: unrestrict, 타이머 취소 → paused   (자동으로 다시 숨기지 않음)
  → 설정…: 설정 창 열기
  → 정보: 정보 화면 열기 (설명 문구는 한곳에서 관리해 기능 변경 시 함께 수정)
```

### 7.3 설정에서 표시/숨김 변경 (FR-1, FR-17)

```
메뉴바 관리에서 토글
  → Coordinator.setHidden(app, true/false)
  → Layout.hiddenApps 갱신 → 저장
  → 상태가 collapsed 면: 허용 목록 다시 계산 → restrict(to:) (깜빡임 없이 교체)
  → 상태가 expanded/paused 면: 저장만 (다음에 숨길 때 적용)
```

메뉴바 관리 화면의 목록은 `AppCatalog`가 만듭니다: `AppDiscovering.catalog()` 결과에 레이아웃과 제약(`Constraint`)을 합치고, 검색·필터는 Domain의 순수 함수로 처리합니다.

### 7.4 새 앱 실행 (FR-6)

```
실행 중인 앱 목록이 바뀜 (AppDiscovering.onChange — Dock 에 나오지 않는 앱도 잡으려고 목록 자체를 관찰)
  → 정책이 .ask 면 1.5초 기다린 뒤 메뉴바 아이콘을 가진 앱을 조사 (접근성 권한 필요)
  → 처음 보는 앱이면 newAppPolicy 적용   // NewAppRule
       .show: 그대로 / .hide: hiddenApps 에 추가
       .ask : 메뉴바 아이콘을 가진 새 앱만 pendingApps 에 추가 (권한이 없으면 .show 처럼)
     첫 실행에는 지금 있는 앱을 "아는 앱"으로 기록만 한다 (전부 숨겨지지 않도록)
  → pendingApps 가 있으면 메뉴바 아이콘 옆에 점, 우클릭 메뉴에 "새로 나타난 앱 N개…"
     설정 > 메뉴바 관리의 "새로 나타난 앱"에서 [표시]/[숨김]을 고르면 목록에서 빠진다
  → 상태가 collapsed 면 허용 목록 다시 계산 → restrict(to:)
```

허용 목록은 기본이 "차단"이므로, 이 흐름이 없으면 나중에 실행된 앱의 아이콘이 보이지 않습니다.

### 7.5 순서 변경 (FR-3, M3)

```
설정 > 메뉴바 관리 > "순서 편집" (열 때 순서를 한 번 읽음) → 목록을 끌어 바꾼 뒤 "적용"
  → OrderingController.apply(target)
  → Coordinator.withEverythingVisible { … }      // state = reordering, 숨김을 잠시 풂
      → 잠깐 기다린 뒤 ItemDiscovering.currentItems(fullScan: true)   // 표시된 아이템만, 왼쪽 → 오른쪽
      → 반복: MovePlanner.plan(current, target, fixed: 시스템 아이템) 의 첫 이동을 실행
              ItemReordering.commandDrag(아이템 중심 → 목표 아이템 왼쪽 6pt)
              다시 읽어 확인. 두 번 연속 변화가 없으면 중단
  → 이전 상태로 복귀 (숨김 중이었으면 다시 restrict)
  → 목록을 실제 순서로 갱신. 순서는 저장하지 않는다 (시스템이 기억)
```

### 7.6 시작 (FR-4, FR-8, FR-18)

```
로그인 → 앱 실행 (paused)
  → isInstalledInApplications ?
      └─ 아니오: paused(.notInstalledInApplications) + 안내 창
                 [응용 프로그램 폴더로 옮기기] → 복사 → 그 사본 실행 → 이 프로세스 종료
  → VisibilityControlling.isSupported ?      // 필요한 시스템 기능이 있는가 (자가진단)
      └─ 아니오: paused(.unsupported) + 안내. 나머지 화면은 그대로 동작
  → 저장된 설정 읽기 → 숨기기 스위치가 켜져 있었으면: 허용 목록 계산 → restrict → collapsed
                      → 꺼져 있었으면: paused (전부 표시)
  → 저장된 전역 단축키 등록 (실패한 조합은 설정 > 일반에 표시)
```

진단 결과(앱·macOS 버전, 상태, 숨김 기능·설치 위치·접근성 권한 등)는 설정 > 진단에서 보고 복사할 수 있습니다.

### 7.7 숨김 중에 시계를 누름 — 알림 센터

```
시계 영역에서 마우스 누름 (ClockClickMonitor)
  → Coordinator.expandForSystemUI()      // collapsed 일 때만: 숨김 해제 → expanded
  → (접근성 권한이 있고 시계 위치를 알 때) 버튼을 뗀 뒤 0.3초 후에도 알림 센터가 안 열렸으면 같은 자리를 한 번 더 누름
  → 0.15초마다 알림 센터가 열려 있는지 확인 (MenuBarActivityChecking.isSystemPanelOpen)
       ├─ 열린 것을 본 뒤 닫힘: 곧바로 숨김 ("자동으로 다시 숨기기" 설정, 포인터 위치와 무관)
       ├─ 약 2.5초 동안 한 번도 열리지 않음: 숨김
       ├─ 닫히는 순간 어떤 메뉴가 열려 있음: 그 메뉴를 다 쓴 뒤 숨김 (7.1의 다시 확인으로 넘김)
       └─ 그 사이 사용자가 좌클릭·스위치로 직접 조작: 그 조작을 따르고 확인을 그만둠
```

숨김 중에는 시스템이 알림 센터를 열지 않고, 숨김을 유지한 채 열 방법도 없기 때문입니다. 알림 센터가 열려 있는 동안에는 숨긴 아이콘이 함께 보입니다 ([platform-notes.md 3.24](platform-notes.md)).

### 7.8 그 밖의 반응

| 일어난 일 | 반응 |
|---|---|
| 잠자기에서 깨어남 | 숨김 중이면 허용 목록을 다시 적용 |
| 화면 구성 변경 | 시계 위치를 다시 읽음 |
| 설정 가져오기 | 숨길 앱·옵션을 바꾸고, 파일의 숨기기 켜짐/꺼짐대로 적용. 단축키 다시 등록 |

## 8. 권한

| 권한 | 필요한 기능 | 없을 때 |
|---|---|---|
| (없음) | 숨김, 펼치기, 설정, 로그인 시 실행, 전역 단축키, 시스템 아이콘 숨김, 백업 | — |
| 접근성 | 순서 편집 (읽기·적용), 메뉴바 관리의 "메뉴바" 필터, 새 앱 정책 "묻기", 빠르게 누른 시계 클릭 보완 | 순서 편집 화면에 권한 안내 표시. 필터는 "실행 중"부터, "묻기"는 "표시"처럼 동작. 나머지 기능은 그대로 |
| 화면 기록 (선택) | 아이템의 실제 아이콘 이미지 | 앱 아이콘으로 대체 — 기능 제한 없음 |

## 9. 저장

| 데이터 | 위치 | 형식 |
|---|---|---|
| 숨길 앱 목록 + 옵션 | `~/Library/Application Support/MenuBarManager/state.json` | JSON, 스키마 버전 필드 포함 |
| 내보낸 설정 | 사용자가 고른 위치 (설정 > 일반 > 백업) | 위와 같은 JSON |
| 로그 | 미구현 (진단 정보는 설정 > 진단에서 복사) | |

## 10. 동시성

- `MenuBarCoordinator`는 `@MainActor @Observable`. UI와 같은 액터에서 상태를 읽고 씁니다.
- 백엔드 호출은 `async`. 허용 목록 교체와 이벤트 합성은 직렬 실행(한 번에 하나)합니다.
- Swift 6 언어 모드, 엄격한 동시성 검사를 켭니다.

## 11. 오류 처리 요약

| 상황 | 동작 |
|---|---|
| 비공개 클래스·메서드가 없음 (OS 변경) | 자가진단에서 감지 → `paused` + 안내. 크래시 금지 |
| 숨김 적용 실패 | `paused` + 오류 표시 |
| 자기 아이콘이 안 보임 (앱은 감지 불가) | 응용 프로그램 폴더에서 앱을 다시 열면 설정 창이 뜸 → 숨기기를 끌 수 있음 |
| `/Applications` 밖에서 실행 | 숨김을 켜지 않음. 옮기기 안내 |
| 순서 이동 실패 | 재시도 1회 → 실패 시 실제 순서로 동기화, 수동 ⌘+드래그 안내 |
| 접근성 권한 철회 | 순서 변경 비활성화. 숨김·펼치기는 계속 동작 |
| 앱 크래시·강제 종료 | 시스템이 제한을 자동 해제 (검증됨) → 전부 표시 |
