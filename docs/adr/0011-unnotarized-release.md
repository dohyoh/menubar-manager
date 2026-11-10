# ADR-0011: 1.0.0 배포 — 공증 없이 임시 서명한 압축 파일을 GitHub Releases에 올린다

- 상태: ✅ 채택
- 날짜: 2026-11-10
- 관련: [ADR-0007](0007-distribution.md) (외부 배포는 Developer ID 서명 + 공증으로 하기로 했던 부분을 보완) · [ADR-0010](0010-install-location.md) · [roadmap.md M6](../plan/roadmap.md#m6--배포-배포하기로-결정한-경우)

## 맥락

1.0.0을 공개 저장소의 릴리스로 배포하기로 했습니다. [ADR-0007](0007-distribution.md)은 외부 배포를 "Developer ID 서명 + 공증 + DMG"로 정했지만, 지금은 Apple Developer Program에 가입되어 있지 않아 Developer ID 인증서가 없습니다. 키체인에 있는 것은 개발용(Apple Development) 인증서 하나입니다.

- 공증은 Developer ID 인증서 없이는 할 수 없습니다.
- 개발용 인증서로 서명하면 배포 파일에 개발자 이름이 들어가고, 다른 Mac에서는 어차피 Gatekeeper를 통과하지 못합니다.

## 결정

**임시(ad-hoc) 서명 + 강화된 런타임으로 만든 Release 빌드를 zip으로 묶어 GitHub Releases에 올립니다.** 공증은 하지 않습니다.

- 만드는 방법: `./scripts/release.sh` → `build/release/MenuBarManager-<버전>.zip`
- 범용 바이너리(arm64 + x86_64), 자동 검증용 명령 채널 없음(Release), 확장 속성 없음.
- 받는 사람은 처음 실행할 때 Gatekeeper 경고를 직접 풀어야 합니다. 방법은 저장소의 `README.md`에 적습니다.
- 개인 사용(이 Mac)은 이전처럼 고정 인증서로 서명한 Release 빌드를 씁니다 — 접근성 권한이 재빌드 후에도 유지되어야 하기 때문입니다.

## 검토한 대안

| 대안 | 장점 | 단점 | 판단 |
|---|---|---|---|
| Developer ID 서명 + 공증 ([ADR-0007](0007-distribution.md)의 원래 방식) | 경고 없이 열림, 업데이트해도 접근성 권한 유지 | Apple Developer Program 가입 필요 (유료) | 가입하면 이 방식으로 바꿈 |
| 개발용 인증서로 서명해 배포 | 추가 작업 없음 | 배포 파일에 개발자 이름 노출, Gatekeeper는 그대로 막음 | 기각 |
| 소스만 공개하고 각자 빌드 | 서명 문제 없음 | Xcode·XcodeGen이 있어야 해서 쓰기 어려움 | 압축 파일과 함께 제공 (README에 빌드 방법) |
| DMG | 응용 프로그램 폴더로 끌어 놓기 쉬움 | 공증 없이는 같은 경고. 앱에 "응용 프로그램 폴더로 옮기기" 버튼이 있음 | 지금은 zip으로 충분 |

## 결과

- 누구나 내려받아 쓸 수 있지만, **처음 실행할 때 경고를 푸는 단계가 필요합니다.** 내려받은 파일로 이 과정을 직접 확인하지는 못했습니다 (이 Mac에서 만든 파일은 격리 표시가 붙지 않음).
- 임시 서명은 빌드마다 서명 값이 달라집니다. **새 버전으로 바꾸면 접근성 권한을 다시 허용해야 합니다** ([platform-notes.md 3.20](../architecture/platform-notes.md)).
- 자동 업데이트(Sparkle)는 넣지 않습니다. 새 버전은 릴리스 페이지에서 직접 받습니다.
- Developer ID를 갖추면 새 ADR로 이 결정을 대체합니다.
