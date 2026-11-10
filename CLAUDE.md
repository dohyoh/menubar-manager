# MenuBarManager (가칭)

macOS 메뉴바에 표시할 앱을 고르고 순서를 조정하는 메뉴바 상주 앱. macOS 15부터 실행되고, 숨김 기능은 필요한 시스템 기능이 있는 버전(macOS 27에서 확인)에서만 동작한다.

## 빌드·테스트

- `./scripts/build.sh install` — 빌드 후 `/Applications/MenuBarManager.app`에 설치 (`run`이면 실행까지)
- `CONFIG=Release ./scripts/build.sh install` — 평소에 쓰는 앱은 이렇게 설치한다. Debug 빌드에는 아래의 명령 채널이 들어 있어, 검증이 끝나면 Release로 다시 설치해 둔다.
- `./scripts/release.sh` — 배포용 zip 생성 (`build/release/`). 버전은 `project.yml`의 `MARKETING_VERSION` (docs/adr/0011-unnotarized-release.md)
- `swift test --package-path Packages/MenuBarKit` — 단위 테스트
- `python3 scripts/strings.py check` — 문자열 번역 누락 검사 (문자열을 추가·수정했으면 `sync` 후 영어 번역을 채운다)
- Debug 빌드를 `open -n /Applications/MenuBarManager.app --args -automationDir <폴더>`로 실행하면 `<폴더>/cmd`에 명령을 써서 조작하고 `<폴더>/app.log`로 결과를 볼 수 있다 (`App/Debug/AutomationHook.swift`). 메뉴바 아이콘은 프로그램으로 클릭할 수 없으므로 이 방법과 화면 캡처로 확인한다.

## 문서

- 시작점: [docs/README.md](docs/README.md) — 현재 상태와 문서 지도
- 다음 작업: [docs/plan/roadmap.md](docs/plan/roadmap.md)
- 구조: [docs/architecture/overview.md](docs/architecture/overview.md), [docs/architecture/project-structure.md](docs/architecture/project-structure.md)
- macOS 메뉴바 동작·제약: [docs/architecture/platform-notes.md](docs/architecture/platform-notes.md)
- 결정 이유: [docs/adr/README.md](docs/adr/README.md)

## 작업 규칙

- 문서 원본은 Markdown. 내용을 바꾸면 같은 작업 안에서 `docs/overview.html`의 해당 섹션도 맞춘다. HTML은 `docs/overview.html` 하나만 유지한다 (필요 시 폴더당 1개까지).
- 되돌리기 어려운 결정은 `docs/adr/`에 새 ADR로 남긴다. 채택된 ADR은 고치지 않고 새 ADR로 대체한다.
- 사용자가 체감하는 변경과 문서 구조 변경은 `docs/CHANGELOG.md`에 적는다.
- 마일스톤이 바뀌면 `docs/README.md`의 "지금 상태" 표와 `overview.html`의 상태 표시를 갱신한다.
- OS 동작에 대한 사실은 `platform-notes.md`에 검증됨 / 보고됨 / 미확인을 구분해 적는다.

## 코드 규칙 (요약)

- OS에 닿는 코드는 `MenuBarSystem` 모듈에만 둔다. 비공개 API 문자열은 `MenuBarPrivateBridge` 밖에 두지 않는다.
- 어떤 오류에서도 메뉴바는 "전부 표시" 상태로 돌아가야 한다 (fail-open).
- 숨김 동작은 반드시 `/Applications`에 설치한 빌드로 확인한다. 다른 위치에서 실행하면 자기 아이콘이 숨겨진다 (docs/adr/0010-install-location.md).
- 기술 검증 코드는 `Spikes/`에 두고 제품 코드와 섞지 않는다.
- 판단 로직은 `MenuBarDomain`·`MenuBarServices`에 두고 `swift test`로 검증한다.
- 사용자에게 보이는 문자열은 `L("…")`로 감싼다 (원문 한국어, 번역은 `Localizable.xcstrings`).
- 입력 합성(드래그·클릭) 검증은 사용자의 포인터를 움직이고 실제 메뉴바 순서를 바꾼다. 사용자가 쓰는 중에는 꼭 필요한 만큼만 하고, 바꾼 순서는 원래대로 되돌린다.
- 자동 검증을 할 때 사용자가 저장해 둔 설정(`~/Library/Application Support/MenuBarManager/state.json`의 숨길 앱 목록 등)을 바꾸지 않는다.
