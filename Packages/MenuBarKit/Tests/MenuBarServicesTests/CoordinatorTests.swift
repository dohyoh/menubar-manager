import Foundation
import Testing
import MenuBarDomain
@testable import MenuBarServices

// MARK: 가짜 백엔드

@MainActor
final class FakeVisibility: VisibilityControlling {
    var isSupported = true
    var isRestricted = false
    var shouldFail = false
    var restrictCalls: [Allowlist] = []
    var unrestrictCount = 0

    func restrict(to allowlist: Allowlist) async throws {
        restrictCalls.append(allowlist)
        if shouldFail { throw VisibilityError.activationFailed }
        isRestricted = true
    }

    func unrestrict() {
        unrestrictCount += 1
        isRestricted = false
    }
}

@MainActor
final class FakeDiscovery: AppDiscovering {
    var apps: [ManagedApp] = [
        ManagedApp(bundleID: "com.a", name: "A", isRunning: true),
        ManagedApp(bundleID: "com.b", name: "B", isRunning: true),
    ]
    var onChange: (@MainActor () -> Void)?
    func catalog() -> [ManagedApp] { apps }
    func knownBundleIDs() -> [BundleID] { apps.map(\.bundleID) }
}

@MainActor
final class FakePresence: SelfPresenceChecking {
    var selfBundleID: BundleID = "me"
    var isInstalledInApplications = true
}

@MainActor
final class FakeStore: StateStoring {
    var state = PersistedState()
    var saveCount = 0
    func load() -> PersistedState { state }
    func save(_ state: PersistedState) { self.state = state; saveCount += 1 }
}

@MainActor
final class FakeScheduler: RehideScheduling {
    var scheduledSeconds: Int?
    var action: (@MainActor () -> Void)?
    var cancelCount = 0
    func schedule(after seconds: Int, _ action: @escaping @MainActor () -> Void) {
        scheduledSeconds = seconds
        self.action = action
    }
    func cancel() { cancelCount += 1; scheduledSeconds = nil; action = nil }
    /// 타이머가 만료된 것처럼 실행한다.
    func fire() async {
        action?()
        await Task.yield()
        await Task.yield()
    }
}

@MainActor
final class FakeActivity: MenuBarActivityChecking {
    var inUse = false
    func isMenuBarInUse() -> Bool { inUse }
}

@MainActor
struct Rig {
    let visibility = FakeVisibility()
    let discovery = FakeDiscovery()
    let presence = FakePresence()
    let store = FakeStore()
    let scheduler = FakeScheduler()
    let activity = FakeActivity()
    let coordinator: MenuBarCoordinator

    init(hidingEnabled: Bool = true, hidden: Set<BundleID> = ["com.b"], autoRehide: Bool = true) {
        store.state = PersistedState(layout: Layout(hiddenApps: hidden), options: Options(hidingEnabled: hidingEnabled, autoRehide: autoRehide, autoRehideSeconds: 10))
        coordinator = MenuBarCoordinator(visibility: visibility, discovery: discovery, presence: presence, store: store, scheduler: scheduler, activity: activity)
    }
}

/// 타이머·알림 콜백이 만든 Task 가 끝날 때까지 기다린다.
@MainActor
func settle() async {
    for _ in 0..<5 { await Task.yield() }
}

// MARK: 테스트

@MainActor
@Suite("시작")
struct StartTests {
    @Test("숨기기가 켜진 채 저장되어 있으면 숨김 상태로 시작한다")
    func startsCollapsed() async {
        let rig = Rig(hidingEnabled: true)
        await rig.coordinator.start()
        #expect(rig.coordinator.state == .collapsed)
        #expect(rig.visibility.restrictCalls.last?.bundleIDs == ["com.a", "me"])
    }

    @Test("숨기기가 꺼져 있으면 전부 표시 상태로 시작한다")
    func startsPaused() async {
        let rig = Rig(hidingEnabled: false)
        await rig.coordinator.start()
        #expect(rig.coordinator.state == .paused(.userOff))
        #expect(rig.visibility.restrictCalls.isEmpty)
    }

    @Test("응용 프로그램 폴더 밖이면 숨김을 켜지 않는다")
    func refusesOutsideApplications() async {
        let rig = Rig(hidingEnabled: true)
        rig.presence.isInstalledInApplications = false
        await rig.coordinator.start()
        #expect(rig.coordinator.state == .paused(.notInstalledInApplications))
        await rig.coordinator.toggle()
        await rig.coordinator.setHidingEnabled(true)
        #expect(rig.visibility.restrictCalls.isEmpty)
    }

    @Test("시스템 기능이 없으면 숨김을 켜지 않는다")
    func refusesWhenUnsupported() async {
        let rig = Rig(hidingEnabled: true)
        rig.visibility.isSupported = false
        await rig.coordinator.start()
        #expect(rig.coordinator.state == .paused(.unsupported))
        #expect(rig.visibility.restrictCalls.isEmpty)
    }
}

@MainActor
@Suite("좌클릭")
struct ToggleTests {
    @Test("숨김 → 펼침 → 숨김")
    func togglesBetweenStates() async {
        let rig = Rig()
        await rig.coordinator.start()
        await rig.coordinator.toggle()
        #expect(rig.coordinator.state == .expanded)
        #expect(!rig.visibility.isRestricted)
        await rig.coordinator.toggle()
        #expect(rig.coordinator.state == .collapsed)
        #expect(rig.visibility.isRestricted)
    }

    @Test("펼치면 설정한 시간으로 자동 숨기기를 예약하고, 만료되면 다시 숨긴다")
    func autoRehide() async {
        let rig = Rig()
        await rig.coordinator.start()
        await rig.coordinator.toggle()
        #expect(rig.scheduler.scheduledSeconds == 10)
        await rig.scheduler.fire()
        await settle()
        #expect(rig.coordinator.state == .collapsed)
    }

    @Test("자동 숨기기가 꺼져 있으면 예약하지 않는다")
    func noAutoRehideWhenDisabled() async {
        let rig = Rig(autoRehide: false)
        await rig.coordinator.start()
        await rig.coordinator.toggle()
        #expect(rig.coordinator.state == .expanded)
        #expect(rig.scheduler.scheduledSeconds == nil)
    }

    @Test("펼친 상태에서 시간을 바꾸면 새 시간으로 다시 예약한다")
    func changingSecondsReschedules() async {
        let rig = Rig()
        await rig.coordinator.start()
        await rig.coordinator.toggle()
        rig.coordinator.setAutoRehideSeconds(30)
        #expect(rig.scheduler.scheduledSeconds == 30)
        #expect(rig.store.state.options.autoRehideSeconds == 30)
    }

    @Test("스위치가 꺼진 상태에서 좌클릭하면 숨김을 켠다")
    func toggleFromUserOffEnables() async {
        let rig = Rig(hidingEnabled: false)
        await rig.coordinator.start()
        await rig.coordinator.toggle()
        #expect(rig.coordinator.state == .collapsed)
        #expect(rig.store.state.options.hidingEnabled)
    }
}

@MainActor
@Suite("숨기기 스위치")
struct SwitchTests {
    @Test("끄면 전부 표시하고, 자동으로 다시 숨기지 않는다")
    func switchOffStaysOff() async {
        let rig = Rig()
        await rig.coordinator.start()
        await rig.coordinator.setHidingEnabled(false)
        #expect(rig.coordinator.state == .paused(.userOff))
        #expect(!rig.visibility.isRestricted)
        #expect(rig.scheduler.scheduledSeconds == nil)
        #expect(!rig.store.state.options.hidingEnabled)
    }

    @Test("펼친 상태에서 끄면 예약된 자동 숨기기가 취소된다")
    func switchOffCancelsPendingRehide() async {
        let rig = Rig()
        await rig.coordinator.start()
        await rig.coordinator.toggle()
        await rig.coordinator.setHidingEnabled(false)
        #expect(rig.scheduler.action == nil)
        #expect(rig.coordinator.state == .paused(.userOff))
    }

    @Test("켜면 숨김을 적용하고 상태를 저장한다")
    func switchOn() async {
        let rig = Rig(hidingEnabled: false)
        await rig.coordinator.start()
        await rig.coordinator.setHidingEnabled(true)
        #expect(rig.coordinator.state == .collapsed)
        #expect(rig.store.state.options.hidingEnabled)
    }
}

@MainActor
@Suite("앱 표시 여부 변경")
struct HiddenAppsTests {
    @Test("숨김 중에 바꾸면 즉시 허용 목록을 다시 적용한다")
    func reappliesWhenCollapsed() async {
        let rig = Rig(hidden: [])
        await rig.coordinator.start()
        let before = rig.visibility.restrictCalls.count
        await rig.coordinator.setHidden("com.a", hidden: true)
        #expect(rig.visibility.restrictCalls.count == before + 1)
        #expect(rig.visibility.restrictCalls.last?.bundleIDs == ["com.b", "me"])
        #expect(rig.store.state.layout.hiddenApps == ["com.a"])
    }

    @Test("숨김이 꺼져 있으면 저장만 한다")
    func onlySavesWhenPaused() async {
        let rig = Rig(hidingEnabled: false, hidden: [])
        await rig.coordinator.start()
        await rig.coordinator.setHidden("com.a", hidden: true)
        #expect(rig.visibility.restrictCalls.isEmpty)
        #expect(rig.store.state.layout.hiddenApps == ["com.a"])
    }

    @Test("자기 자신은 숨길 수 없다")
    func cannotHideSelf() async {
        let rig = Rig(hidden: [])
        await rig.coordinator.start()
        await rig.coordinator.setHidden("me", hidden: true)
        #expect(rig.store.state.layout.hiddenApps.isEmpty)
    }

    @Test("새 앱이 실행되면 숨김 중일 때 허용 목록을 갱신한다")
    func reappliesOnAppLaunch() async {
        let rig = Rig()
        await rig.coordinator.start()
        rig.discovery.apps.append(ManagedApp(bundleID: "com.new", name: "New", isRunning: true))
        rig.discovery.onChange?()
        await settle()
        #expect(rig.visibility.restrictCalls.last?.bundleIDs.contains("com.new") == true)
        #expect(rig.coordinator.apps.count == 3)
    }
}

@MainActor
@Suite("실패와 종료")
struct FailureTests {
    @Test("숨김 적용이 실패하면 전부 표시로 돌아간다")
    func failsOpen() async {
        let rig = Rig()
        rig.visibility.shouldFail = true
        await rig.coordinator.start()
        #expect(rig.coordinator.state == .paused(.error("activationFailed")))
        #expect(!rig.visibility.isRestricted)
        #expect(rig.visibility.unrestrictCount >= 1)
    }

    @Test("오류 뒤에는 좌클릭으로 다시 시도할 수 있다")
    func canRetryAfterError() async {
        let rig = Rig()
        rig.visibility.shouldFail = true
        await rig.coordinator.start()
        rig.visibility.shouldFail = false
        await rig.coordinator.toggle()
        #expect(rig.coordinator.state == .collapsed)
    }

    @Test("종료할 때 숨김을 해제한다")
    func shutdownUnrestricts() async {
        let rig = Rig()
        await rig.coordinator.start()
        rig.coordinator.shutdown()
        #expect(!rig.visibility.isRestricted)
    }

    @Test("상태가 바뀔 때마다 알린다")
    func notifiesStateChanges() async {
        let rig = Rig()
        var seen: [ManagerState] = []
        rig.coordinator.onStateChange = { seen.append($0) }
        await rig.coordinator.start()
        await rig.coordinator.toggle()
        await rig.coordinator.setHidingEnabled(false)
        #expect(seen == [.collapsed, .expanded, .paused(.userOff)])
    }
}

@MainActor
@Suite("저장소")
struct StoreTests {
    @Test("저장한 값을 그대로 다시 읽는다")
    func roundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mbm-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONStateStore(directory: dir)
        #expect(store.load() == PersistedState())
        let state = PersistedState(layout: Layout(hiddenApps: ["x", "y"]), options: Options(hidingEnabled: true, autoRehide: false, autoRehideSeconds: 30))
        store.save(state)
        #expect(JSONStateStore(directory: dir).load() == state)
    }

    @Test("깨진 파일은 기본값으로 덮어쓰기 전에 사본으로 남긴다")
    func corruptFileIsPreserved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mbm-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: dir.appendingPathComponent("state.json"))
        let store = JSONStateStore(directory: dir)
        #expect(store.load() == PersistedState())
        store.save(PersistedState())   // 기본값으로 덮어써도
        #expect(try String(contentsOf: store.unreadableCopyURL, encoding: .utf8) == "{ broken")   // 원래 내용은 남아 있다
    }

    @Test("더 새로운 버전이 쓴 파일은 읽지 않고 사본으로 남긴다")
    func newerSchemaIsPreserved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mbm-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONStateStore(directory: dir)
        store.save(PersistedState(schemaVersion: PersistedState.currentSchemaVersion + 1, layout: Layout(hiddenApps: ["x"])))
        #expect(store.load() == PersistedState())
        #expect(FileManager.default.fileExists(atPath: store.unreadableCopyURL.path))
    }

    @Test("파일이 없으면(첫 실행) 사본을 만들지 않는다")
    func firstRunMakesNoCopy() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mbm-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONStateStore(directory: dir)
        #expect(store.load() == PersistedState())
        #expect(!FileManager.default.fileExists(atPath: store.unreadableCopyURL.path))
    }

    @Test("깨진 파일이면 기본값으로 시작한다")
    func corruptFileFallsBack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mbm-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("state.json"))
        #expect(JSONStateStore(directory: dir).load() == PersistedState())
    }
}

@MainActor
@Suite("사용 중에는 자동 숨기기를 미룬다")
struct DeferRehideTests {
    @Test("메뉴바를 쓰는 중이면 숨기지 않고 다시 예약한다")
    func defersWhileInUse() async {
        let rig = Rig()
        await rig.coordinator.start()
        await rig.coordinator.toggle()
        rig.activity.inUse = true
        await rig.scheduler.fire()
        await settle()
        #expect(rig.coordinator.state == .expanded)
        #expect(rig.scheduler.scheduledSeconds == MenuBarCoordinator.rehideRetrySeconds)

        rig.activity.inUse = false
        await rig.scheduler.fire()
        await settle()
        #expect(rig.coordinator.state == .collapsed)
    }
}

@MainActor
@Suite("새 앱 정책")
struct NewAppPolicyTests {
    @Test("정책이 숨김이면 실행 중 새로 나타난 앱이 숨겨진다")
    func hidesNewAppWhenPolicyIsHide() async {
        let rig = Rig(hidden: [])
        await rig.coordinator.start()
        rig.coordinator.setNewAppPolicy(.hide)
        rig.discovery.apps.append(ManagedApp(bundleID: "com.new", name: "New", isRunning: true))
        rig.discovery.onChange?()
        await settle()
        #expect(rig.coordinator.layout.hiddenApps == ["com.new"])
        #expect(rig.visibility.restrictCalls.last?.bundleIDs.contains("com.new") == false)
        #expect(rig.store.state.layout.newAppPolicy == .hide)
    }

    @Test("시작할 때 있던 앱은 정책과 무관하게 숨기지 않는다")
    func existingAppsStayVisibleOnFirstRun() async {
        let rig = Rig(hidden: [])
        rig.store.state.layout.newAppPolicy = .hide
        await rig.coordinator.start()
        #expect(rig.coordinator.layout.hiddenApps.isEmpty)
        #expect(rig.coordinator.layout.knownApps == ["com.a", "com.b"])
    }
}

@MainActor
@Suite("알림 센터를 위해 잠깐 풀기")
struct SystemUITests {
    @Test("숨김을 바로 풀고, 자동 숨기기 설정이 꺼져 있어도 다시 숨기기를 예약한다")
    func expandsImmediatelyAndAlwaysSchedulesRehide() async {
        let rig = Rig(autoRehide: false)
        await rig.coordinator.start()
        rig.coordinator.expandForSystemUI()
        #expect(rig.coordinator.state == .expanded)
        #expect(!rig.visibility.isRestricted)
        #expect(rig.scheduler.scheduledSeconds == MenuBarCoordinator.rehideRetrySeconds)
    }

    @Test("알림 센터가 열려 있는 동안에는 숨기지 않고, 닫히면 다시 숨긴다")
    func waitsUntilNotInUse() async {
        let rig = Rig(autoRehide: false)
        await rig.coordinator.start()
        rig.coordinator.expandForSystemUI()
        rig.activity.inUse = true
        await rig.scheduler.fire()
        await settle()
        #expect(rig.coordinator.state == .expanded)
        rig.activity.inUse = false
        await rig.scheduler.fire()
        await settle()
        #expect(rig.coordinator.state == .collapsed)
    }

    @Test("숨김 중이 아닐 때는 아무것도 하지 않는다")
    func ignoredWhenNotCollapsed() async {
        let rig = Rig(hidingEnabled: false)
        await rig.coordinator.start()
        rig.coordinator.expandForSystemUI()
        #expect(rig.coordinator.state == .paused(.userOff))
        #expect(rig.scheduler.scheduledSeconds == nil)
    }
}

@MainActor
@Suite("M4: 시스템 아이콘·백업·새 앱 묻기·단축키")
struct M4Tests {
    @Test("시스템 아이콘을 숨기면 그 번호가 허용 목록에서 빠진다")
    func hidesSystemItem() async {
        let rig = Rig()
        await rig.coordinator.start()
        await rig.coordinator.setSystemItemHidden(.wifi, hidden: true)
        let items = rig.visibility.restrictCalls.last?.systemItems ?? []
        #expect(!items.contains(SystemItem.wifi.rawValue))
        #expect(items.contains(2) && items.contains(8))      // 시계와 제어 센터는 항상 허용
        #expect(rig.store.state.layout.hiddenSystemItems == [SystemItem.wifi.rawValue])
    }

    @Test("숨길 수 없는 시스템 번호는 저장되어 있어도 허용 목록에 남는다")
    func neverHidesProtectedSystemItems() {
        let list = AllowlistBuilder.build(known: [], hidden: [], selfID: "me", hiddenSystemItems: [2, 8, 6])
        #expect(list.systemItems.contains(2) && list.systemItems.contains(8))
        #expect(!list.systemItems.contains(6))
    }

    @Test("내보낸 설정을 가져오면 그대로 적용된다")
    func importAppliesState() async {
        let source = Rig(hidden: ["com.a"])
        await source.coordinator.start()
        source.coordinator.setAutoRehideSeconds(30)
        let exported = source.coordinator.exportState()

        let target = Rig(hidingEnabled: false, hidden: [])
        await target.coordinator.start()
        await target.coordinator.importState(exported)
        #expect(target.coordinator.layout.hiddenApps == ["com.a"])
        #expect(target.coordinator.options.autoRehideSeconds == 30)
        #expect(target.coordinator.state == .collapsed)
        #expect(target.visibility.restrictCalls.last?.bundleIDs == ["com.b", "me"])
    }

    @Test("더 새로운 형식의 설정 파일은 가져오지 않는다")
    func importRejectsNewerSchema() async {
        let rig = Rig(hidden: ["com.a"])
        await rig.coordinator.start()
        let newer = PersistedState(schemaVersion: PersistedState.currentSchemaVersion + 1, layout: Layout(hiddenApps: ["com.b"]))
        #expect(await rig.coordinator.importState(newer) == false)
        #expect(rig.coordinator.layout.hiddenApps == ["com.a"])
    }

    @Test("가져온 설정의 잘못된 시간 값은 기본값으로 바꾼다")
    func importSanitizesSeconds() async {
        let rig = Rig(hidden: [])
        await rig.coordinator.start()
        #expect(await rig.coordinator.importState(PersistedState(options: Options(hidingEnabled: false, autoRehideSeconds: 0))))
        #expect(rig.coordinator.options.autoRehideSeconds == Options().autoRehideSeconds)
    }

    @Test("단축키를 바꾸면 저장하고 알린다")
    func hotkeyChangeNotifies() async {
        let rig = Rig()
        await rig.coordinator.start()
        var notified: [Int: Hotkey]?
        rig.coordinator.onHotkeysChange = { notified = $0 }
        let hotkey = Hotkey(keyCode: 4, modifiers: 4096 | 2048, display: "⌃⌥H")
        rig.coordinator.setHotkey(hotkey, for: .toggle)
        #expect(notified?[HotkeyAction.toggle.rawValue] == hotkey)
        #expect(rig.store.state.options.hotkeys[HotkeyAction.toggle.rawValue] == hotkey)
        rig.coordinator.setHotkey(nil, for: .toggle)
        #expect(rig.store.state.options.hotkeys.isEmpty)
    }

    @Test("깨어난 뒤 숨김 상태면 다시 건다")
    func reappliesAfterWake() async {
        let rig = Rig()
        await rig.coordinator.start()
        let before = rig.visibility.restrictCalls.count
        await rig.coordinator.reapplyIfHiding()
        #expect(rig.visibility.restrictCalls.count == before + 1)
    }
}

@MainActor
@Suite("새 앱 묻기")
struct AskPolicyTests {
    @MainActor
    struct AskRig {
        let rig = Rig(hidden: [])
        let bar: FakeBar
        let permission = FakePermission()
        let coordinator: MenuBarCoordinator
        init() {
            bar = FakeBar(order: [], visibility: rig.visibility)
            coordinator = MenuBarCoordinator(visibility: rig.visibility, discovery: rig.discovery, presence: rig.presence, store: rig.store,
                                             scheduler: rig.scheduler, activity: rig.activity, permission: permission, itemDiscovery: bar, pause: { _ in })
        }
    }

    @Test("메뉴바 아이콘을 가진 새 앱만 '새로 나타난 앱'에 올린다")
    func onlyAppsWithMenuBarItemsBecomePending() async {
        let a = AskRig()
        await a.coordinator.start()
        a.coordinator.setNewAppPolicy(.ask)
        a.bar.owners = ["com.withicon"]
        a.rig.discovery.apps.append(ManagedApp(bundleID: "com.withicon", name: "With", isRunning: true))
        a.rig.discovery.apps.append(ManagedApp(bundleID: "com.noicon", name: "No", isRunning: true))
        var pendingCount = -1
        a.coordinator.onPendingChange = { pendingCount = $0 }
        a.rig.discovery.onChange?()
        await settle()
        #expect(a.coordinator.layout.pendingApps == ["com.withicon"])
        #expect(a.coordinator.layout.hiddenApps.isEmpty)          // 정하기 전에는 표시
        #expect(pendingCount == 1)
        #expect(a.coordinator.menuBarApps == ["com.withicon"])
    }

    @Test("아이콘을 조사하기 전에 허용 목록부터 갱신해 새 앱이 바로 보이게 한다")
    func reappliesBeforeInvestigating() async {
        let rig = Rig(hidden: [])
        let bar = FakeBar(order: [], visibility: rig.visibility)
        var restrictCallsAtPause = -1
        let coordinator = MenuBarCoordinator(visibility: rig.visibility, discovery: rig.discovery, presence: rig.presence, store: rig.store,
                                             scheduler: rig.scheduler, activity: rig.activity, permission: FakePermission(), itemDiscovery: bar,
                                             pause: { _ in restrictCallsAtPause = rig.visibility.restrictCalls.count })
        await coordinator.start()
        let before = rig.visibility.restrictCalls.count
        coordinator.setNewAppPolicy(.ask)
        rig.discovery.apps.append(ManagedApp(bundleID: "com.new", name: "New", isRunning: true))
        rig.discovery.onChange?()
        await settle()
        #expect(restrictCallsAtPause == before + 1)
        #expect(rig.visibility.restrictCalls[before].bundleIDs.contains("com.new"))
    }

    @Test("숨김으로 정하면 숨길 앱에 들어가고 목록에서 빠진다")
    func resolvingHides() async {
        let a = AskRig()
        await a.coordinator.start()
        a.coordinator.setNewAppPolicy(.ask)
        a.bar.owners = ["com.withicon"]
        a.rig.discovery.apps.append(ManagedApp(bundleID: "com.withicon", name: "With", isRunning: true))
        a.rig.discovery.onChange?()
        await settle()
        await a.coordinator.resolvePending("com.withicon", hide: true)
        #expect(a.coordinator.layout.pendingApps.isEmpty)
        #expect(a.coordinator.layout.hiddenApps == ["com.withicon"])
        #expect(a.rig.visibility.restrictCalls.last?.bundleIDs.contains("com.withicon") == false)
    }

    @Test("접근성 권한이 없으면 '표시'처럼 동작한다")
    func withoutPermissionBehavesLikeShow() async {
        let a = AskRig()
        a.permission.isAccessibilityGranted = false
        await a.coordinator.start()
        a.coordinator.setNewAppPolicy(.ask)
        a.rig.discovery.apps.append(ManagedApp(bundleID: "com.new", name: "New", isRunning: true))
        a.rig.discovery.onChange?()
        await settle()
        #expect(a.coordinator.layout.pendingApps.isEmpty)
        #expect(a.coordinator.layout.hiddenApps.isEmpty)
        #expect(a.coordinator.menuBarApps == nil)
    }
}
