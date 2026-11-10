import AppKit
import MenuBarDomain
import MenuBarServices
import MenuBarUI

/// 메뉴바의 이 앱 아이콘.
///  - 좌클릭: 숨긴 앱 펼치기 ↔ 숨기기
///  - 우클릭 (또는 Control+클릭): 메뉴 — 숨기기 스위치 · 설정… · 정보 · 종료
///  - 표시할지 정하지 않은 새 앱이 있으면 아이콘 옆에 점을 찍는다.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menuController = StatusMenuController()
    private let coordinator: MenuBarCoordinator

    init(coordinator: MenuBarCoordinator, onSettings: @escaping () -> Void, onInfo: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.coordinator = coordinator
        super.init()

        item.autosaveName = "MenuBarManagerMain"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        menuController.stateProvider = { [weak coordinator] in coordinator?.state ?? .paused(.userOff) }
        menuController.pendingCountProvider = { [weak coordinator] in coordinator?.layout.pendingApps.count ?? 0 }
        menuController.onHidingChanged = { [weak coordinator] enabled in
            Task { await coordinator?.setHidingEnabled(enabled) }
        }
        menuController.onSettings = onSettings
        menuController.onInfo = onInfo
        menuController.onQuit = onQuit

        coordinator.onStateChange = { [weak self] state in self?.update(for: state) }
        coordinator.onPendingChange = { [weak self] _ in self?.refresh() }
        update(for: coordinator.state)
    }

    /// 저장된 설정을 읽은 뒤 등, 상태 밖의 값(새로 나타난 앱 수)이 바뀌었을 때 아이콘을 다시 그린다.
    func refresh() { update(for: coordinator.state) }

    private func update(for state: ManagerState) {
        guard let button = item.button else { return }
        let pending = coordinator.layout.pendingApps.count
        var label = StatePresentation.accessibilityLabel(for: state)
        if pending > 0 { label += " — " + L("새로 나타난 앱 \(String(pending))개…") }
        button.image = NSImage(systemSymbolName: StatePresentation.symbolName(for: state), accessibilityDescription: label)
        button.title = pending > 0 ? "•" : ""
        button.imagePosition = pending > 0 ? .imageLeading : .imageOnly
        button.toolTip = label
        // 메뉴가 열려 있는 동안 상태가 바뀌면 스위치도 맞춘다.
        menuController.hideSwitch.isOn = state.isHiding
    }

    @objc private func clicked() {
        guard let event = NSApp.currentEvent else { return }
        let isRightClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isRightClick {
            showMenu()
        } else {
            Task { await coordinator.toggle() }
        }
    }

    /// 좌클릭을 직접 처리하기 위해 메뉴를 평소에는 붙여 두지 않고, 우클릭 때만 잠깐 붙여 띄운다.
    private func showMenu() {
        item.menu = menuController.menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    #if DEBUG
    /// 자동 검증용: 메뉴를 열고, (clickSwitch 면 잠시 뒤 스위치를 누르고) 닫는다.
    /// 메뉴가 열려 있는 동안에도 돌도록 common mode 타이머를 쓴다.
    func debugShowMenu(clickSwitch: Bool) {
        let menuController = self.menuController
        if clickSwitch {
            let click = Timer(timeInterval: 2.0, repeats: false) { _ in
                MainActor.assumeIsolated { menuController.hideSwitch.toggleFromUser() }
            }
            RunLoop.current.add(click, forMode: .common)
        }
        let close = Timer(timeInterval: clickSwitch ? 4.5 : 2.5, repeats: false) { _ in
            MainActor.assumeIsolated { menuController.menu.cancelTracking() }
        }
        RunLoop.current.add(close, forMode: .common)
        showMenu()
    }
    #endif
}
