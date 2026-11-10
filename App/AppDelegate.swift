import AppKit
import Carbon.HIToolbox
import SwiftUI
import MenuBarDomain
import MenuBarServices
import MenuBarSystem
import MenuBarUI

/// 조립(Composition Root)과 생명주기. 구현체를 고르는 곳은 여기뿐이다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: MenuBarCoordinator!
    private var statusItem: StatusItemController!
    private var settingsWindow: HostedWindow!
    private var infoWindow: HostedWindow!
    private let loginItem = LoginItemManager()
    private let settingsNavigation = SettingsNavigation()
    // 순서 조정(M3)용. 접근성 권한이 있어야 동작한다.
    private let permission = AccessibilityPermission()
    private let itemDiscovery = AXItemDiscovery()
    private let reorderer = EventSynthesisReorderer()
    private var ordering: OrderingController!
    private let clockMonitor = ClockClickMonitor()
    private let activityChecker = MenuBarActivityChecker()
    private let hotkeys = GlobalHotkeyCenter()
    #if DEBUG
    private var automation: AutomationHook?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let presence = SelfPresenceChecker()
        let coordinator = MenuBarCoordinator(
            visibility: AssessmentModeVisibilityController(),
            discovery: WorkspaceAppDiscovery(selfBundleID: presence.selfBundleID),
            presence: presence,
            store: JSONStateStore(),
            scheduler: TaskRehideScheduler(),
            activity: activityChecker,
            permission: permission,
            itemDiscovery: itemDiscovery
        )
        self.coordinator = coordinator

        let ordering = OrderingController(coordinator: coordinator, permission: permission, discovery: itemDiscovery, reorderer: reorderer)
        self.ordering = ordering

        let loginItem = self.loginItem
        let navigation = settingsNavigation
        settingsWindow = HostedWindow(title: L("설정"), resizable: true, minSize: NSSize(width: 480, height: 420), initialSize: NSSize(width: 580, height: 600)) {
            SettingsView(coordinator: coordinator, loginItem: loginItem, ordering: ordering, navigation: navigation)
        }
        let info = Bundle.main.infoDictionary
        let appName = info?["CFBundleDisplayName"] as? String ?? "MenuBarManager"
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        infoWindow = HostedWindow(title: L("정보"), resizable: false) {
            InfoView(appName: appName, version: version)
        }

        statusItem = StatusItemController(
            coordinator: coordinator,
            onSettings: { [weak self] in self?.showSettings() },
            onInfo: { [weak self] in self?.showInfo() },
            onQuit: { NSApp.terminate(nil) }
        )

        #if DEBUG
        automation = AutomationHook.makeIfRequested(
            coordinator: coordinator, statusItem: statusItem, delegate: self,
            permission: permission, itemDiscovery: itemDiscovery, reorderer: reorderer, ordering: ordering
        )
        let isAutomated = automation != nil
        #else
        let isAutomated = false
        #endif

        // 시계를 누르면 알림 센터가 열리도록, 누르는 순간 숨김을 잠깐 푼다.
        clockMonitor.onMouseDown = { [weak self] point in self?.clockPressed(at: point) }
        clockMonitor.start()
        updateClockZone()

        coordinator.onHotkeysChange = { [weak self] in self?.registerHotkeys($0) }
        observeSystemEvents()

        Task {
            await coordinator.start()
            self.registerHotkeys(coordinator.options.hotkeys)
            self.statusItem.refresh()
            if coordinator.state == .paused(.notInstalledInApplications) {
                self.showInstallLocationNotice()
            } else if !coordinator.options.didShowWelcome, !isAutomated {
                // 첫 실행: 설정 창을 열어 사용법과 "로그인할 때 자동으로 실행"을 안내한다. 한 번만.
                self.showWelcome()
            }
        }
    }

    /// 종료할 때 숨긴 아이콘을 모두 되돌린다. (강제 종료·크래시 때는 시스템이 되돌린다.)
    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }

    /// 탈출구: 메뉴바 아이콘이 보이지 않을 때 응용 프로그램 폴더에서 앱을 다시 열면 설정 창이 뜬다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    /// 설정 창은 항상 "메뉴바 관리"부터 보여 준다.
    func showSettings(tab: SettingsTab = .management) {
        settingsNavigation.tab = tab
        settingsWindow.show()
    }
    func showInfo() { infoWindow.show() }

    /// 숨김 중에 시계를 눌렀다: 알림 센터가 열리도록 숨김을 바로 푼다.
    ///
    /// 누름과 뗌 사이가 0.1초쯤 되면 같은 클릭으로 열리지만, 더 빠른 클릭은 숨김이 풀리기 전에 끝나 열리지 않는다 (검증됨).
    /// 그 경우 접근성 권한이 있고 시계 위치를 정확히 알 때만, 같은 자리를 한 번 더 눌러 준다.
    private func clockPressed(at point: CGPoint) {
        guard coordinator.expandForSystemUI() else { return }
        guard permission.isAccessibilityGranted, clockMonitor.isZonePrecise else { return }
        Task {
            // 사용자가 버튼을 뗄 때까지 기다린다 (길게 누르는 중에 끼어들지 않도록).
            for _ in 0..<40 where NSEvent.pressedMouseButtons != 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard coordinator.state == .expanded, !activityChecker.isNotificationCenterOpen() else { return }
            try? await reorderer.click(at: point)
        }
    }

    /// 시계의 실제 위치를 읽어 클릭 감지 영역을 맞춘다. 접근성 권한이 있을 때만 가능하고,
    /// 없으면 기본 너비를 쓴다. 숨김과 무관하게 시계는 항상 표시되므로 펼칠 필요가 없다.
    private func updateClockZone() {
        guard permission.isAccessibilityGranted else { return }
        Task {
            guard let clock = try? await itemDiscovery.currentItems(fullScan: true).last, clock.isSystem else { return }
            clockMonitor.zoneWidth = clock.trailingOffset + 4
            clockMonitor.isZonePrecise = true
        }
    }

    #if DEBUG
    /// 자동 검증용: 임시 단축키(⌃⌥⇧⌘Y)를 "설정 열기"에 걸고 그 키를 합성해 눌러, 설정 창이 뜨는지 본다.
    /// 저장된 설정은 바꾸지 않고, 끝나면 저장된 단축키로 되돌린다.
    /// (합성한 기능 키 F13~F19 는 단축키로 인식되지 않아 글자 키를 쓴다 — platform-notes 3.25)
    func debugHotkeyProbe() async -> String {
        let wasVisible = settingsWindow.isVisible
        settingsWindow.close()
        var probe = coordinator.options.hotkeys
        probe[HotkeyAction.openSettings.rawValue] = Hotkey(
            keyCode: UInt32(kVK_ANSI_Y), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey), display: "⌃⌥⇧⌘Y")
        registerHotkeys(probe)
        let registered = !settingsNavigation.hotkeyFailures.contains(HotkeyAction.openSettings.rawValue)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_Y), keyDown: isDown)
            event?.flags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            event?.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(for: .milliseconds(600))
        let opened = settingsWindow.isVisible
        if !wasVisible { settingsWindow.close() }
        registerHotkeys(coordinator.options.hotkeys)
        return "registered=\(registered) settingsOpened=\(opened) restoredFailures=\(settingsNavigation.hotkeyFailures)"
    }
    #endif

    /// 저장된 전역 단축키를 등록한다. 실패한 것(다른 앱이 이미 쓰는 조합)은 설정 화면에 표시한다.
    private func registerHotkeys(_ map: [Int: Hotkey]) {
        var failures = Set<Int>()
        for action in HotkeyAction.allCases {
            let ok = hotkeys.setHotkey(map[action.rawValue], for: action) { [weak self] in self?.perform(action) }
            if !ok { failures.insert(action.rawValue) }
        }
        settingsNavigation.hotkeyFailures = failures
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .toggle: Task { await coordinator.toggle() }
        case .openSettings: showSettings()
        }
    }

    /// 잠자기에서 깨어나면 숨김을 다시 걸고, 화면 구성이 바뀌면 시계 위치를 다시 읽는다.
    private func observeSystemEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.coordinator.reapplyIfHiding() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateClockZone() }
        }
    }

    /// 첫 실행 안내를 띄운다.
    func showWelcome() {
        settingsNavigation.showsWelcome = true
        coordinator.markWelcomeShown()
        showSettings()
    }
    func resizeSettings(to size: NSSize) { settingsWindow.resize(to: size) }
    var isSettingsVisible: Bool { settingsWindow.isVisible }
    var isInfoVisible: Bool { infoWindow.isVisible }

    /// /Applications 밖에서 실행하면 숨김을 켰을 때 이 앱의 아이콘도 사라진다. (docs/adr/0010-install-location.md)
    private func showInstallLocationNotice() {
        let alert = NSAlert()
        alert.messageText = L("응용 프로그램 폴더로 옮겨 주세요")
        alert.informativeText = L("MenuBarManager는 응용 프로그램 폴더에서 실행해야 숨김 기능을 쓸 수 있습니다. 다른 위치에서는 숨김을 켜면 이 앱의 아이콘도 함께 사라지기 때문에 숨김을 꺼 두었습니다. 응용 프로그램 폴더로 옮기면 그곳에서 다시 실행합니다.")
        alert.addButton(withTitle: L("응용 프로그램 폴더로 옮기기"))
        alert.addButton(withTitle: L("나중에"))
        alert.addButton(withTitle: L("Finder에서 보기"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: moveToApplications()
        case .alertThirdButtonReturn: NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        default: break
        }
    }

    /// 응용 프로그램 폴더로 복사한 뒤 그 사본을 실행하고 이 프로세스는 끝낸다.
    /// 같은 이름의 앱이 이미 있으면 휴지통으로 보낸다 (되돌릴 수 있게). 원래 파일은 지우지 못해도 무시한다.
    private func moveToApplications() {
        let source = Bundle.main.bundleURL
        let destination = URL(fileURLWithPath: "/Applications", isDirectory: true).appendingPathComponent(source.lastPathComponent)
        let files = FileManager.default
        do {
            if files.fileExists(atPath: destination.path) {
                try files.trashItem(at: destination, resultingItemURL: nil)
            }
            try files.copyItem(at: source, to: destination)
        } catch {
            showMoveFailure(error.localizedDescription)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            let message = error?.localizedDescription
            Task { @MainActor in
                if let message {
                    self.showMoveFailure(message)
                } else {
                    try? FileManager.default.trashItem(at: source, resultingItemURL: nil)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func showMoveFailure(_ reason: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("옮기지 못했습니다")
        alert.informativeText = L("Finder에서 앱을 응용 프로그램 폴더로 직접 끌어 옮긴 뒤 다시 실행해 주세요. (\(reason))")
        alert.addButton(withTitle: L("확인"))
        alert.runModal()
    }
}
