# ADR-0007: 배포 — 샌드박스 없이 직접 배포

- 상태: ✅ 채택
- 날짜: 2026-11-10
- 관련: [ADR-0003](0003-visibility-mechanism.md) · [ADR-0004](0004-reorder-mechanism.md) · [ADR-0010](0010-install-location.md) · [roadmap.md M6](../plan/roadmap.md#m6--배포-배포하기로-결정한-경우)

## 맥락

이 앱은 다른 앱의 메뉴바 아이템을 다루기 위해 접근성 API, 입력 이벤트 합성, 비공개 프레임워크를 사용합니다. App Sandbox 안에서는 이들이 동작하지 않고, 비공개 API 사용은 Mac App Store 심사 기준에 맞지 않습니다.

## 결정

- **App Sandbox를 끕니다.** Hardened Runtime은 켭니다.
- **Mac App Store에 올리지 않습니다.**
- 단계별 서명:
  - 개발: 고정된 "Apple Development" 인증서 (접근성 권한이 재빌드마다 초기화되지 않도록)
  - 개인 사용: 같은 인증서로 Release 빌드 후 `/Applications`에 설치
  - 외부 배포(M6, 결정 시): Developer ID 서명 + 공증 + DMG, Sparkle 자동 업데이트

## 검토한 대안

| 대안 | 판단 |
|---|---|
| Mac App Store | 샌드박스·심사 기준상 불가 |
| 임시(ad-hoc) 서명으로 개발 | 빌드마다 접근성 권한 재승인 필요 → 개발 속도 저하, 기각 |
| Homebrew Cask | 외부 배포 시 Developer ID 빌드에 얹는 부가 채널 — M6에서 검토 |

## 결과

- 사용자는 접근성 권한을 직접 허용해야 합니다 → 온보딩 화면이 필수 (M1).
- 외부 배포 시 Apple Developer Program 가입이 필요합니다.
- 자동 업데이트를 넣으면 "네트워크 통신 없음"(NFR-5)에 예외가 생깁니다 → 그때 ADR로 기록합니다.
