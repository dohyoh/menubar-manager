# MenuBarManager 문서 지도

> macOS 상단 메뉴바에 표시할 앱을 고르고, 순서를 조정하는 메뉴바 상주 앱 (가칭 **MenuBarManager**).
> 처음 보는 사람은 [overview.html](overview.html) 하나만 열어도 전체를 파악할 수 있습니다.

## 지금 상태 (2026-11-11)

| 항목 | 상태 |
|---|---|
| 버전 | **1.0.2** — [GitHub Releases](https://github.com/dohyoh/menubar-manager/releases)에 배포 (공증 없음, [ADR-0011](adr/0011-unnotarized-release.md)) |
| 단계 | **M0~M4 기능 구현 완료** — 실제 앱(`/Applications/MenuBarManager.app`)에서 숨기기·펼치기·설정·정보·순서 조정·전역 단축키·시스템 아이콘 숨김·백업·진단이 동작. 숨김 중에도 시계를 누르면 알림 센터가 열림 |
| 코드 | 제품 코드 약 4,600줄 (테스트 148개 통과). 구조는 [project-structure.md](architecture/project-structure.md). 저장소: [dohyoh/menubar-manager](https://github.com/dohyoh/menubar-manager) |
| 미출시 변경 | **macOS 26 이하에서 숨김** (구분자 확장 방식, 시스템 아이콘 포함) — macOS 26.5.2에서 확인. 재부팅·모니터 두 대는 쓰면서 확인 ([roadmap M7](plan/roadmap.md#m7--macos-26-이하에서-숨김)) |
| 다음 할 일 | ① 직접 써 보며 확인 (단축키 기록, 설정 내보내기/가져오기, 새 앱 "묻기") ② [M4의 남은 점검](plan/roadmap.md#m4--안정화편의) ③ M5(프로필 등) |
| 확정 대기 결정 | 없음 |
| 꼭 알아야 할 제약 | 앱은 `/Applications`에서 실행해야 함 ([ADR-0010](adr/0010-install-location.md)). **숨김 방식이 두 가지** — macOS 27은 허용 목록(권한 불필요), macOS 26 이하는 구분자 확장(접근성 권한 필수, [ADR-0012](adr/0012-separator-visibility-macos26.md)). 1.0.2 릴리스에는 뒤의 것이 들어 있지 않음 |

## 무엇을 하려면 어디를 보나

| 하려는 일 | 문서 |
|---|---|
| 앱을 설치하고 쓰는 방법 (받는 사람용) | [guide/user-guide_KR.md](guide/user-guide_KR.md) · [영어](guide/user-guide.md) · [중국어](guide/user-guide_CN.md) |
| 전체를 5분 안에 파악 | [overview.html](overview.html) |
| 무엇을 만드는지, 범위/우선순위 확인 | [plan/requirements.md](plan/requirements.md) |
| 다음 작업 고르기, 완료 기준 확인 | [plan/roadmap.md](plan/roadmap.md) |
| 코드 구조·모듈 경계·데이터 흐름 확인 | [architecture/overview.md](architecture/overview.md) |
| 파일을 어디에 둘지, 빌드 방법 | [architecture/project-structure.md](architecture/project-structure.md) |
| macOS 메뉴바가 실제로 어떻게 동작하는지 (제약·조사 결과) | [architecture/platform-notes.md](architecture/platform-notes.md) |
| "왜 이렇게 했지?" | [adr/README.md](adr/README.md) |
| 기술 검증을 다시 돌리거나 이어서 하기 | [Spikes/README.md](../Spikes/README.md) |
| 무엇이 언제 바뀌었는지 | [CHANGELOG.md](CHANGELOG.md) |

## 폴더 구조

```
docs/
├── README.md              ← 이 파일 (문서 지도 + 현재 상태)
├── overview.html          ← 사람이 한 번에 읽는 단일 HTML (유일한 HTML)
├── CHANGELOG.md           ← 변경사항 (코드 + 문서)
├── guide/
│   └── user-guide*.md     ← 사용 안내서 (영어 기본, _KR 한국어, _CN 중국어)
├── images/                ← 저장소 README·안내서에 쓰는 그림
├── plan/
│   ├── requirements.md    ← 요구사항, 범위, 추천 기능
│   └── roadmap.md         ← 마일스톤, 작업 체크리스트, 리스크
├── architecture/
│   ├── overview.md        ← 구성요소, 상태 모델, 데이터 흐름
│   ├── project-structure.md ← 폴더/모듈 구조, 빌드, 컨벤션
│   └── platform-notes.md  ← macOS 27·26 메뉴바 기술 조사
└── adr/
    ├── README.md          ← ADR 목록, 템플릿, 작성 규칙
    └── NNNN-제목.md       ← 결정 1건 = 파일 1개
```

## 문서 관리 규칙

1. **Markdown이 원본, HTML은 요약본.** 내용이 바뀌면 Markdown을 먼저 고치고, 같은 작업 안에서 [overview.html](overview.html)의 해당 섹션을 맞춥니다.
2. **HTML은 `docs/overview.html` 하나만 유지합니다.** 분량이 커져 나눠야 할 때만 폴더당 1개(`plan/index.html` 등)까지 허용합니다.
3. **결정은 ADR로.** 되돌리기 어려운 선택(메커니즘, 의존성, 배포 방식)을 바꾸면 기존 ADR을 수정하지 말고 새 ADR을 추가한 뒤 이전 것을 `대체됨`으로 표시합니다.
4. **변경은 CHANGELOG에.** 사용자가 체감하는 변화와 문서 구조 변경을 기록합니다. 커밋 단위 기록은 git에 맡깁니다.
5. **"지금 상태" 표를 최신으로.** 마일스톤이 바뀔 때 이 파일 맨 위 표와 `overview.html`의 상태 배지를 함께 갱신합니다.
6. **받는 사람용 문서는 세 언어를 함께 고칩니다.** 저장소 루트의 `README.md`(영어)·`README_KR.md`·`README_CN.md`와 `guide/`의 안내서는 내용이 같아야 합니다. 화면이 바뀌면 `images/`의 그림도 다시 만듭니다.
7. **검증 여부를 구분해서 적습니다.** 플랫폼 동작은 `검증됨`(직접 확인) / `보고됨`(외부 출처) / `미확인`(가설) 중 하나로 표시합니다.
