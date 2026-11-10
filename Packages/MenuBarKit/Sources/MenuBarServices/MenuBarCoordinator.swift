import Foundation
import Observation
import MenuBarDomain

/// 앱의 상태를 혼자 소유한다. 아이콘·메뉴·설정 창은 여기서 읽고, 의도만 보낸다.
/// 상태 전이는 docs/architecture/overview.md 6절.
@MainActor
@Observable
public final class MenuBarCoordinator {
    public private(set) var state: ManagerState = .paused(.userOff)
    public private(set) var layout = Layout()
    public private(set) var options = Options()
    public private(set) var apps: [ManagedApp] = []
    /// 메뉴바 아이콘을 가진 앱. 접근성 권한이 없어 알 수 없으면 nil.
    public private(set) var menuBarApps: Set<BundleID>?

    /// 상태가 바뀔 때마다 호출된다 (메뉴바 아이콘 갱신용).
    @ObservationIgnored public var onStateChange: (@MainActor (ManagerState) -> Void)?
    /// 단축키 설정이 바뀌면 호출된다 (실제 등록은 App 이 한다).
    @ObservationIgnored public var onHotkeysChange: (@MainActor ([Int: Hotkey]) -> Void)?
    /// "새로 나타난 앱" 개수가 바뀌면 호출된다 (메뉴바 아이콘 표시용).
    @ObservationIgnored public var onPendingChange: (@MainActor (Int) -> Void)?

    @ObservationIgnored private let visibility: any VisibilityControlling
    @ObservationIgnored private let discovery: any AppDiscovering
    @ObservationIgnored private let presence: any SelfPresenceChecking
    @ObservationIgnored private let store: any StateStoring
    @ObservationIgnored private let scheduler: any RehideScheduling
    @ObservationIgnored private let activity: (any MenuBarActivityChecking)?
    @ObservationIgnored private let permission: (any PermissionChecking)?
    @ObservationIgnored private let itemDiscovery: (any ItemDiscovering)?
    @ObservationIgnored private let pause: @MainActor (Int) async -> Void
    /// 새로 실행된 앱이 메뉴바 아이콘을 만들 때까지 기다리는 시간(ms)
    public static let newAppSettleMilliseconds = 1500
    /// 메뉴바를 쓰는 중이라 자동 숨기기를 미룰 때, 다시 확인하기까지의 시간
    public static let rehideRetrySeconds = 2
    /// 비동기 적용 도중 다른 조작이 끼어들었는지 판별한다.
    @ObservationIgnored private var operationID = 0

    public init(
        visibility: any VisibilityControlling,
        discovery: any AppDiscovering,
        presence: any SelfPresenceChecking,
        store: any StateStoring,
        scheduler: any RehideScheduling,
        activity: (any MenuBarActivityChecking)? = nil,
        permission: (any PermissionChecking)? = nil,
        itemDiscovery: (any ItemDiscovering)? = nil,
        pause: @escaping @MainActor (Int) async -> Void = { try? await Task.sleep(for: .milliseconds($0)) }
    ) {
        self.visibility = visibility
        self.discovery = discovery
        self.presence = presence
        self.store = store
        self.scheduler = scheduler
        self.activity = activity
        self.permission = permission
        self.itemDiscovery = itemDiscovery
        self.pause = pause
    }

    /// 숨김을 쓸 수 있는 환경인가 (진단 표시용).
    public var isHidingSupported: Bool { visibility.isSupported }
    public var isInstalledInApplications: Bool { presence.isInstalledInApplications }
    public var isAccessibilityGranted: Bool { permission?.isAccessibilityGranted ?? false }

    // MARK: 시작·종료

    public func start() async {
        let persisted = store.load()
        layout = persisted.layout
        options = persisted.options
        discovery.onChange = { [weak self] in
            Task { await self?.appsDidChange() }
        }
        refreshApps()
        absorbNewApps()

        if let blocker = blockingReason() {
            setState(.paused(blocker))
        } else if options.hidingEnabled {
            await applyHiding()
        } else {
            setState(.paused(.userOff))
        }
    }

    /// 종료 직전에 호출한다. 숨긴 아이콘을 모두 되돌린다.
    public func shutdown() {
        operationID += 1
        scheduler.cancel()
        visibility.unrestrict()
    }

    // MARK: 사용자 의도

    /// 좌클릭: 펼치기 ↔ 숨기기.
    public func toggle() async {
        switch state {
        case .collapsed:
            expand()
        case .expanded:
            await applyHiding()
        case .paused(let reason):
            if reason.canEnable { await setHidingEnabled(true) }
        case .reordering:
            break   // 순서 작업 중에는 무시한다
        }
    }

    /// 전부 펼쳐 놓고 해야 하는 작업(순서 읽기·바꾸기)을 감싼다.
    /// 숨김 중이었으면 잠시 풀고, 작업이 끝나면 이전 상태로 되돌린다.
    public func withEverythingVisible<T: Sendable>(_ work: @MainActor () async throws -> T) async throws -> T {
        let previous = state
        guard previous != .reordering else { throw OrderingError.unavailable }
        operationID += 1
        scheduler.cancel()
        if visibility.isRestricted { visibility.unrestrict() }
        setState(.reordering)

        let result: Result<T, Error>
        do { result = .success(try await work()) } catch { result = .failure(error) }

        switch previous {
        case .collapsed:
            await applyHiding()
        case .expanded:
            setState(.expanded)
            rescheduleIfExpanded()
        default:
            setState(previous)
        }
        return try result.get()
    }

    /// 시계를 눌러 알림 센터를 열려는 경우처럼, 시스템 화면을 위해 숨김을 잠깐 푼다.
    ///
    /// 숨김이 걸려 있으면 알림 센터가 열리지 않는다. 누르는 순간 풀어 주면 같은 클릭으로 열린다.
    /// 그 뒤에는 "자동으로 다시 숨기기" 설정과 무관하게, 메뉴바를 쓰지 않게 되면(알림 센터가 닫히면) 다시 숨긴다.
    /// 마우스 누름과 뗌 사이에 끝나야 하므로 기다리지 않고 바로 푼다.
    /// - Returns: 실제로 숨김을 풀었으면 true
    @discardableResult
    public func expandForSystemUI() -> Bool {
        guard state == .collapsed else { return false }
        operationID += 1
        visibility.unrestrict()
        setState(.expanded)
        scheduler.cancel()
        scheduler.schedule(after: Self.rehideRetrySeconds) { [weak self] in
            Task { await self?.rehideFired() }
        }
        return true
    }

    /// 우클릭 메뉴의 "숨기기" 스위치.
    /// 끄면 전부 표시한 채로 유지한다 — 자동으로 다시 숨기지 않는다.
    public func setHidingEnabled(_ enabled: Bool) async {
        guard state != .reordering else { return }
        if enabled {
            if let blocker = blockingReason() {
                setState(.paused(blocker))
                return
            }
            options.hidingEnabled = true
            persist()
            await applyHiding()
        } else {
            operationID += 1
            scheduler.cancel()
            visibility.unrestrict()
            options.hidingEnabled = false
            persist()
            setState(.paused(blockingReason() ?? .userOff))
        }
    }

    /// 설정 화면에서 앱의 표시 여부를 바꿈.
    public func setHidden(_ bundleID: BundleID, hidden: Bool) async {
        guard bundleID != presence.selfBundleID else { return }
        if hidden { layout.hiddenApps.insert(bundleID) } else { layout.hiddenApps.remove(bundleID) }
        persist()
        if state == .collapsed { await applyHiding() }
    }

    public func setAutoRehide(_ enabled: Bool) {
        options.autoRehide = enabled
        persist()
        rescheduleIfExpanded()
    }

    public func setAutoRehideSeconds(_ seconds: Int) {
        options.autoRehideSeconds = max(1, seconds)
        persist()
        rescheduleIfExpanded()
    }

    public func setNewAppPolicy(_ policy: NewAppPolicy) {
        layout.newAppPolicy = policy
        persist()
    }

    /// 시스템 아이콘(Wi-Fi, 배터리)의 표시 여부.
    public func setSystemItemHidden(_ item: SystemItem, hidden: Bool) async {
        if hidden { layout.hiddenSystemItems.insert(item.rawValue) } else { layout.hiddenSystemItems.remove(item.rawValue) }
        persist()
        if state == .collapsed { await applyHiding() }
    }

    /// "새로 나타난 앱"을 표시할지 숨길지 정한다.
    public func resolvePending(_ bundleID: BundleID, hide: Bool) async {
        guard layout.pendingApps.remove(bundleID) != nil else { return }
        if hide { layout.hiddenApps.insert(bundleID) }
        persist()
        onPendingChange?(layout.pendingApps.count)
        if hide, state == .collapsed { await applyHiding() }
    }

    public func setHotkey(_ hotkey: Hotkey?, for action: HotkeyAction) {
        options.hotkeys[action.rawValue] = hotkey
        persist()
        onHotkeysChange?(options.hotkeys)
    }

    /// 메뉴바 아이콘을 가진 앱을 다시 조사한다. 접근성 권한이 없으면 아무것도 하지 않는다.
    public func refreshMenuBarApps() async {
        guard let itemDiscovery, permission?.isAccessibilityGranted == true else {
            menuBarApps = nil
            return
        }
        if let found = try? await itemDiscovery.appsOwningItems() { menuBarApps = found }
    }

    /// 잠자기에서 깨어난 뒤 등, 숨김이 걸려 있어야 하는 상태면 다시 건다.
    public func reapplyIfHiding() async {
        if state == .collapsed { await applyHiding() }
    }

    // MARK: 백업·복원

    public func exportState() -> PersistedState {
        PersistedState(layout: layout, options: options)
    }

    /// 내보낸 설정을 불러와 적용한다. 숨기기 켜짐/꺼짐도 파일의 값을 따른다.
    /// - Returns: 적용했으면 true. 이 버전이 모르는 더 새로운 형식이면 아무것도 바꾸지 않고 false.
    @discardableResult
    public func importState(_ imported: PersistedState) async -> Bool {
        guard imported.schemaVersion <= PersistedState.currentSchemaVersion else { return false }
        layout = imported.layout
        var newOptions = imported.options
        newOptions.didShowWelcome = true
        if newOptions.autoRehideSeconds < 1 { newOptions.autoRehideSeconds = Options().autoRehideSeconds }
        options = newOptions
        persist()
        onHotkeysChange?(options.hotkeys)
        onPendingChange?(layout.pendingApps.count)
        refreshApps()
        guard state != .reordering else { return true }
        await setHidingEnabled(options.hidingEnabled)
        return true
    }

    public func markWelcomeShown() {
        guard !options.didShowWelcome else { return }
        options.didShowWelcome = true
        persist()
    }

    public func refreshApps() {
        apps = discovery.catalog()
    }

    // MARK: 내부

    /// 숨김을 켤 수 없는 이유. 없으면 nil.
    private func blockingReason() -> PauseReason? {
        if !presence.isInstalledInApplications { return .notInstalledInApplications }
        if !visibility.isSupported { return .unsupported }
        return nil
    }

    private func expand() {
        operationID += 1
        visibility.unrestrict()
        setState(.expanded)
        rescheduleIfExpanded()
    }

    private func rescheduleIfExpanded() {
        scheduler.cancel()
        guard state == .expanded, options.autoRehide else { return }
        scheduler.schedule(after: options.autoRehideSeconds) { [weak self] in
            Task { await self?.rehideFired() }
        }
    }

    private func rehideFired() async {
        guard state == .expanded else { return }
        // 펼친 아이콘의 메뉴를 쓰는 중이면 숨기지 않고 잠시 뒤 다시 확인한다.
        if activity?.isMenuBarInUse() == true {
            scheduler.schedule(after: Self.rehideRetrySeconds) { [weak self] in
                Task { await self?.rehideFired() }
            }
            return
        }
        await applyHiding()
    }

    /// 처음 보는 앱을 정책에 따라 반영한다.
    private func absorbNewApps() {
        let updated = NewAppRule.absorb(apps.map(\.bundleID), into: layout, selfID: presence.selfBundleID, menuBarApps: menuBarApps)
        guard updated != layout else { return }
        let pendingChanged = updated.pendingApps != layout.pendingApps
        layout = updated
        persist()
        if pendingChanged { onPendingChange?(layout.pendingApps.count) }
    }

    private func applyHiding() async {
        operationID += 1
        let myOperation = operationID
        scheduler.cancel()
        let allowlist = AllowlistBuilder.build(
            known: discovery.knownBundleIDs(),
            hidden: layout.hiddenApps,
            selfID: presence.selfBundleID,
            hiddenSystemItems: layout.hiddenSystemItems
        )
        do {
            try await visibility.restrict(to: allowlist)
            // 기다리는 사이 사용자가 펼치거나 껐다면 그 결과를 덮어쓰지 않는다.
            guard myOperation == operationID else { return }
            setState(.collapsed)
        } catch {
            guard myOperation == operationID else { return }
            // fail-open: 실패하면 전부 표시로 돌아간다.
            visibility.unrestrict()
            setState(.paused(.error(String(describing: error))))
        }
    }

    private func appsDidChange() async {
        refreshApps()
        // "묻기" 정책은 새 앱이 메뉴바 아이콘을 가졌는지 알아야 한다. 아이콘이 만들어질 시간을 준 뒤 조사한다.
        if layout.newAppPolicy == .ask, itemDiscovery != nil, permission?.isAccessibilityGranted == true,
           !Set(apps.map(\.bundleID)).subtracting(layout.knownApps).isEmpty {
            // 조사에 몇 초 걸린다. 그동안 새 앱의 아이콘이 가려져 있지 않도록 허용 목록부터 갱신한다.
            if state == .collapsed { await applyHiding() }
            await pause(Self.newAppSettleMilliseconds)
            await refreshMenuBarApps()
            refreshApps()
        }
        absorbNewApps()
        // 허용 목록은 기본이 "차단"이다. 새로 실행된 앱이 보이려면 목록을 다시 적용해야 한다.
        if state == .collapsed { await applyHiding() }
    }

    private func setState(_ new: ManagerState) {
        guard state != new else { return }
        state = new
        onStateChange?(new)
    }

    private func persist() {
        store.save(PersistedState(layout: layout, options: options))
    }
}
