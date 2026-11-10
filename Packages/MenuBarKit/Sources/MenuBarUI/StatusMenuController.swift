import AppKit
import MenuBarDomain

/// 메뉴바 아이콘 우클릭 메뉴: 숨기기(스위치) · (새로 나타난 앱 N개…) · 설정… · 정보 · 종료
/// (docs/adr/0009-interaction-model.md)
@MainActor
public final class StatusMenuController: NSObject, NSMenuDelegate {
    public let menu = NSMenu()

    /// 메뉴가 열릴 때 현재 상태를 읽어 온다.
    public var stateProvider: () -> ManagerState = { .paused(.userOff) }
    /// 표시할지 숨길지 아직 정하지 않은 새 앱의 수. 0 이면 항목을 보이지 않는다.
    public var pendingCountProvider: () -> Int = { 0 }
    public var onHidingChanged: (Bool) -> Void = { _ in }
    public var onSettings: () -> Void = {}
    public var onInfo: () -> Void = {}
    public var onQuit: () -> Void = {}
    /// 자동 검증용: 메뉴가 열리고 닫힐 때
    public var onOpenChange: (Bool) -> Void = { _ in }

    public let hideSwitch = MenuSwitch()
    private let noteItem = NSMenuItem()
    private lazy var pendingItem = makeItem("", action: #selector(settingsClicked), key: "")

    public override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(makeSwitchItem())
        noteItem.isEnabled = false
        noteItem.isHidden = true
        menu.addItem(noteItem)
        menu.addItem(.separator())
        pendingItem.isHidden = true
        menu.addItem(pendingItem)
        menu.addItem(makeItem(L("설정…"), action: #selector(settingsClicked), key: ","))
        menu.addItem(makeItem(L("정보"), action: #selector(infoClicked), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem(L("종료"), action: #selector(quitClicked), key: "q"))
    }

    /// "숨기기" 글자 + 스위치. 켜면 숨김 적용, 끄면 전부 표시를 유지한다.
    private func makeSwitchItem() -> NSMenuItem {
        hideSwitch.target = self
        hideSwitch.action = #selector(switchChanged)
        hideSwitch.setAccessibilityLabel(L("숨기기"))

        let item = NSMenuItem()
        item.view = MenuSwitchRow(title: L("숨기기"), menuSwitch: hideSwitch)
        return item
    }

    private func makeItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        let state = stateProvider()
        hideSwitch.isOn = state.isHiding
        hideSwitch.isEnabled = StatePresentation.canToggleHiding(state)
        if let note = StatePresentation.blockerNote(for: state) {
            noteItem.title = note
            noteItem.isHidden = false
        } else {
            noteItem.isHidden = true
        }
        let pending = pendingCountProvider()
        pendingItem.isHidden = pending == 0
        if pending > 0 { pendingItem.title = L("새로 나타난 앱 \(String(pending))개…") }
        onOpenChange(true)
    }

    public func menuDidClose(_ menu: NSMenu) {
        onOpenChange(false)
    }

    // MARK: 동작

    @objc private func switchChanged() { onHidingChanged(hideSwitch.isOn) }
    @objc private func settingsClicked() { onSettings() }
    @objc private func infoClicked() { onInfo() }
    @objc private func quitClicked() { onQuit() }
}
