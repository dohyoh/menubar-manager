import Foundation
import ServiceManagement
import MenuBarDomain

/// 이 앱 자신의 번들 ID 와 설치 위치.
///
/// 숨김 중에 자기 아이콘이 사라졌는지는 앱이 스스로 알 수 없다 (창 상태 값이 그대로임을 확인).
/// 그래서 원인이 되는 조건 — /Applications 밖에서 실행 — 을 미리 막는다. (docs/adr/0010-install-location.md)
@MainActor
public final class SelfPresenceChecker: SelfPresenceChecking {
    public let selfBundleID: BundleID
    public let isInstalledInApplications: Bool

    public init(bundle: Bundle = .main) {
        selfBundleID = bundle.bundleIdentifier ?? ""
        isInstalledInApplications = bundle.bundlePath.hasPrefix("/Applications/")
    }
}

/// 로그인 시 실행. 시스템 설정 > 일반 > 로그인 항목에 표시된다.
@MainActor
public final class LoginItemManager: LoginItemManaging {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        }
    }
}
