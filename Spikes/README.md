# Spikes — 기술 검증용 코드

제품 코드가 아닙니다. "이게 이 Mac에서 실제로 되는가"에 답하기 위한 일회성 코드입니다.

> 2026-11-10: 여기서 검증한 숨김·좌/우클릭·설정·정보는 제품 코드(`App/`, `Packages/MenuBarKit`)로 옮겨졌습니다. 이 검증용 앱은 **접근성 권한이 필요한 남은 검증(`axlist`, `drag`)** 에만 쓰면 됩니다. 제품 앱과 동시에 실행하지 마세요 — 둘 다 숨김을 걸면 결과가 섞입니다.
결과는 [docs/architecture/platform-notes.md](../docs/architecture/platform-notes.md)에, 질문 목록은 [docs/plan/roadmap.md](../docs/plan/roadmap.md#m0--기술-검증--기반-구축)에 있습니다.

## MenuBarSpike

메뉴바 아이콘 하나를 가진 검증용 앱입니다.

| 조작 | 동작 |
|---|---|
| 아이콘 **좌클릭** | 숨김 적용 ↔ 해제 (기본 숨김 대상: Magnet) |
| 아이콘 **우클릭** / Control+클릭 | 메뉴: 숨기기(스위치) · 설정… · 정보 · 종료. 스위치로 끄면 자동으로 다시 숨기지 않음 |
| 메뉴 > **설정…** | "메뉴바 관리" 창 — 앱 검색, 필터(실행 중 / 숨긴 앱 / 전체), 앱별 표시 스위치, "펼친 뒤 자동으로 다시 숨기기". 스위치를 바꾸면 숨김 중일 때 즉시 반영 |
| 메뉴 > **정보** | 주요 기능 설명 창 (좌클릭·우클릭·설정·자동 숨기기·메뉴바 아이콘 옮기기·알아 둘 점) |
| 명령 파일 | 아래 "명령으로 조작" 참고 |

- 숨길 앱 목록과 "자동으로 다시 숨기기"는 저장되어 다음 실행에도 유지됩니다.
- "펼친 뒤 자동으로 다시 숨기기"가 켜져 있으면(기본, 설정 창에서 변경) 좌클릭으로 펼친 뒤 10초 후 다시 숨깁니다.
- 소스: `SpikeApp.m`(아이콘·숨김·명령), `SettingsWindow.m`(설정 창), `InfoWindow.m`(정보 창).

### 빌드·설치·실행

```bash
./Spikes/MenuBarSpike/build.sh install
```

```bash
open -n /Applications/MenuBarSpike.app
```

- **반드시 `/Applications`에 설치해서 실행합니다.** 다른 위치에서 실행하면 숨김을 켰을 때 이 앱의 아이콘도 사라집니다 ([ADR-0010](../docs/adr/0010-install-location.md)).
- 서명: `CODESIGN_IDENTITY` 환경 변수로 인증서를 지정합니다. 없으면 첫 번째 유효한 인증서를 씁니다. 키체인 확인 창이 뜨면 "항상 허용"을 선택하세요. 임시 서명으로 빌드하려면:

```bash
CODESIGN_IDENTITY="-" ./Spikes/MenuBarSpike/build.sh install
```

- 임시 서명은 숨김·클릭 검증에는 충분합니다. 다만 접근성 권한은 빌드마다 다시 허용해야 합니다.

### 종료·삭제

우클릭 메뉴 > 종료. 종료하면 숨겼던 아이콘은 모두 돌아옵니다 (강제 종료해도 시스템이 복구).

```bash
rm -rf /Applications/MenuBarSpike.app
```

### 명령으로 조작 (자동 검증용)

앱은 0.2초마다 `<dir>/cmd` 파일을 읽어 실행하고 `<dir>/app.log`에 결과를 남깁니다. `<dir>` 기본값은 `~/Library/Logs/MenuBarSpike`, 실행 시 `--args -dir <경로>`로 바꿀 수 있습니다.

| 명령 | 동작 |
|---|---|
| `restrict <번들ID,번들ID…>` | 지정한 앱을 숨김 (생략하면 직전 목록) |
| `unrestrict` | 해제 |
| `toggle` | 좌클릭과 같음 |
| `settings` | 설정 창 열기 |
| `menutest` | 우클릭 메뉴를 열고 2초 뒤 숨기기 스위치를 누른 다음 닫음 (화면 캡처 확인용) |
| `menushot` | 우클릭 메뉴를 2.5초간 열었다 닫음 (화면 캡처 확인용) |
| `info` | 정보 창 열기 |
| `switch <번들ID>` | 설정 창 목록에서 해당 앱의 스위치를 누름 (창이 열려 있고 목록에 보일 때) |
| `self 0` / `self 1` | 허용 목록에서 자기 자신 제외/포함 |
| `selfinfo` | 자기 아이콘의 창 위치 기록 |
| `axprompt` | 접근성 권한 요청 창 띄우기 |
| `axlist` | 접근성 API로 모든 메뉴바 아이템과 좌표 기록 (S5) |
| `click <x> <y> left\|right` | 해당 좌표 클릭 합성 |
| `drag <x1> <x2> <y>` | ⌘+드래그 합성 (S6) |
| `quit` | 종료 |

```bash
echo "restrict com.crowdcafe.windowmagnet" > ~/Library/Logs/MenuBarSpike/cmd
```

## 검증 현황 (2026-11-10)

| 질문 | 결과 |
|---|---|
| S1 허용 목록으로 숨김 | ✅ |
| S2 해제·강제 종료 시 복구 | ✅ |
| S4 시스템 아이템 번호 | ✅ 배터리 0, 시계 2, Wi-Fi 6, 제어 센터 8 |
| 자기 아이콘 유지 | ✅ `/Applications` 설치 시 |
| 깜빡임 없는 목록 교체 | ✅ |
| 좌클릭/우클릭 실제 전달 | ✅ 직접 클릭으로 확인 |
| 설정 창에서 스위치 → 메뉴바 즉시 반영 | ✅ |
| 우클릭 메뉴의 숨기기 스위치 | ✅ 표시·동작 확인 |
| 우클릭 메뉴의 정보 → 설명 창 | ✅ 표시 확인 |
| 수동 ⌘+드래그로 아이콘 옮기기 | ✅ 사용자가 직접 확인 (정보 창이 안내하는 방법) |
| S5 접근성으로 아이템 열거 | ⏳ 접근성 권한 허용 후 `axlist` |
| S6·S7 순서 변경 | ⏳ 접근성 권한 허용 후 `drag` |
| S3 숨김 중 알림 센터 등 | ⏳ 숨김 상태에서 직접 눌러 확인 |

## 다음에 이어서 할 때

1. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 **MenuBarSpike**를 허용합니다.
2. `axlist` → 로그에 `AXITEM` 줄이 나오는지 확인 (S5).
3. 두 아이템의 x좌표로 `drag` → 화면 캡처로 순서가 바뀌었는지 확인 (S6).
4. 결과를 platform-notes에 `검증됨`으로 옮기고 ADR-0004를 확정합니다.

## SeparatorSpike (macOS 26)

macOS 26 이하의 "구분자 확장" 숨김이 되는지 확인하는 명령줄 프로그램입니다 ([ADR-0012](../docs/adr/0012-separator-visibility-macos26.md), [platform-notes 7절](../docs/architecture/platform-notes.md#7-macos-26에서-확인한-것-)). 권한이 필요 없고, 자기 상태 아이템(H · S · V, 나중에 N)만 만들었다가 끝나면 스스로 종료합니다. 다른 앱의 아이콘 순서는 건드리지 않습니다.

```bash
swiftc -O Spikes/SeparatorSpike/main.swift -o build/sepspike
```

```bash
build/sepspike --lengths 10000,2056,500
```

| 인자 | 동작 |
|---|---|
| `--lengths a,b,…` | 구분자 S의 길이를 차례로 바꿔 가며 H(왼쪽)·V(오른쪽)와 다른 아이콘 창의 위치를 출력 (기본 10000) |
| `--hold <초>` | 마지막에 구분자를 펼친 채 기다림. 그동안 `kill -9 <pid>`로 강제 종료해 복구를 확인 |

검증 현황 (2026-11-11, macOS 26.5.2): 숨김 ✅ · 복구 ✅ · 강제 종료 후 복구 ✅ · 새 아이콘은 숨김 쪽에 놓임 ✅.

### AXApp — 접근성 권한이 필요한 검증

`Spikes/SeparatorSpike/AXApp`은 같은 아이콘 세 개(H · S · V)를 가진 앱으로, 제품의 접근성 코드(`MenuBarSystem`의 `AXItemDiscovery`, `EventSynthesisReorderer`)를 그대로 가져다 씁니다. `xcodegen` 없이 `swift build`만으로 만들어지고, 설치하지 않고 빌드 폴더에서 실행합니다.

```bash
./Spikes/SeparatorSpike/AXApp/build.sh run
```

- 처음 실행하면 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 **SeparatorSpike**를 허용합니다. 임시 서명이라 다시 빌드하면 다시 허용해야 합니다.
- 0.2초마다 `<폴더>/cmd`를 읽어 실행하고 `<폴더>/app.log`에 적습니다. `<폴더>` 기본값은 `~/Library/Logs/SeparatorSpike`, 실행 시 `--args -dir <경로>`로 바꿀 수 있습니다.
- 드래그 검증은 자기 아이콘(H · S · V)끼리 하면 다른 앱의 순서를 건드리지 않습니다. 다른 앱의 아이콘을 옮겼으면 원래 자리로 되돌립니다.

| 명령 | 동작 |
|---|---|
| `report` | 자기 아이콘의 위치와 화면 안·밖의 아이콘 창 목록 |
| `expand [길이]` / `collapse` | 구분자 S를 늘임(기본 10000) / 되돌림 |
| `newitem` | 아이콘을 하나 더 만듦 |
| `axstatus` / `axprompt` | 접근성 권한 확인 / 요청 창 띄우기 |
| `axlist` | 제품 코드로 읽은 "지금 표시된 아이템" (T1) |
| `axraw` | 걸러 내지 않은 원본: 앱마다 `AXExtrasMenuBar`의 자식, 좌표, 그 좌표에 실제로 있는 요소 (T1·T3) |
| `hit <x> <y>` | 그 좌표의 접근성 요소 |
| `drag <x1> <x2> <y>` / `dragtune <pt> <ms> <ms>` | ⌘+드래그 합성 (T2) / 속도 조정 |
| `quit` | 종료 |

검증 현황 (2026-11-11): T1 아이콘과 앱의 대응 읽기 ✅ · T2 구분자 너머로 옮기기 ✅ (양방향, 다른 프로세스의 아이콘 포함) · T3 화면 밖 아이콘의 좌표 ✅.

