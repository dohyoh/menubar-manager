import Foundation

// OS 에 닿는 기능의 인터페이스. 구현은 MenuBarSystem 모듈에만 둔다.
// (docs/adr/0005-backend-abstraction-private-api.md)

/// 메뉴바 아이콘 표시 제한.
@MainActor
public protocol VisibilityControlling: AnyObject {
    /// 이 macOS 에서 숨김 기능을 쓸 수 있는가
    var isSupported: Bool { get }
    var isRestricted: Bool { get }
    /// 허용 목록에 있는 앱·시스템 아이템만 표시한다. 이미 제한 중이면 깜빡임 없이 교체한다.
    func restrict(to allowlist: Allowlist) async throws
    /// 제한 해제 — 전부 표시
    func unrestrict()
}

/// 앱 목록 수집. 권한이 필요 없다.
@MainActor
public protocol AppDiscovering: AnyObject {
    /// 설정 화면에 보여 줄 앱 (실행 중 + 설치됨, 시스템 백그라운드 프로세스 제외)
    func catalog() -> [ManagedApp]
    /// 허용 목록 계산에 쓸 모든 번들 ID (시스템 프로세스 포함)
    func knownBundleIDs() -> [BundleID]
    /// 앱이 실행·종료되면 호출된다
    var onChange: (@MainActor () -> Void)? { get set }
}

/// 이 앱 자신에 대한 정보.
@MainActor
public protocol SelfPresenceChecking: AnyObject {
    var selfBundleID: BundleID { get }
    /// /Applications 에 설치되어 있는가. 아니면 숨김을 켰을 때 자기 아이콘도 사라진다.
    var isInstalledInApplications: Bool { get }
}

@MainActor
public protocol LoginItemManaging: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// 사용자가 지금 메뉴바를 쓰고 있는가 (메뉴가 열려 있거나 포인터가 메뉴바 위에 있음).
/// 펼친 뒤 자동으로 다시 숨길 때, 쓰는 도중에 아이콘이 사라지지 않게 하려고 확인한다.
@MainActor
public protocol MenuBarActivityChecking: AnyObject {
    func isMenuBarInUse() -> Bool
}

/// 전역 단축키 등록. 권한이 필요 없다.
@MainActor
public protocol HotkeyRegistering: AnyObject {
    /// 단축키를 등록한다. hotkey 가 nil 이면 해제한다.
    /// - Returns: 등록에 성공했으면 true (다른 앱이 이미 쓰는 조합이면 실패할 수 있다)
    @discardableResult
    func setHotkey(_ hotkey: Hotkey?, for action: HotkeyAction, handler: @escaping @MainActor () -> Void) -> Bool
}

/// 저장소.
@MainActor
public protocol StateStoring: AnyObject {
    func load() -> PersistedState
    func save(_ state: PersistedState)
}

/// "펼친 뒤 자동으로 다시 숨기기"용 타이머. 테스트에서 가짜로 바꿀 수 있게 분리한다.
@MainActor
public protocol RehideScheduling: AnyObject {
    func schedule(after seconds: Int, _ action: @escaping @MainActor () -> Void)
    func cancel()
}

public enum VisibilityError: Error, Equatable, Sendable {
    case unsupported
    case activationFailed
    case timedOut
}
