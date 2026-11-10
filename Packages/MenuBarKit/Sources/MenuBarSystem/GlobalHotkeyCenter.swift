import AppKit
import Carbon.HIToolbox
import MenuBarDomain

/// 전역 단축키. Carbon 의 핫키 등록을 쓴다 — 접근성·입력 모니터링 권한이 필요 없다.
@MainActor
public final class GlobalHotkeyCenter: HotkeyRegistering {
    private var references: [HotkeyAction: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    /// 이 앱의 핫키를 구분하는 서명 ("MBMK")
    private static let signature: OSType = 0x4D42_4D4B

    public init() {}

    @discardableResult
    public func setHotkey(_ hotkey: Hotkey?, for action: HotkeyAction, handler: @escaping @MainActor () -> Void) -> Bool {
        if let existing = references.removeValue(forKey: action) { UnregisterEventHotKey(existing) }
        handlers[UInt32(action.rawValue)] = nil
        guard let hotkey else { return true }

        installEventHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: UInt32(action.rawValue))
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetEventDispatcherTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        references[action] = reference
        handlers[UInt32(action.rawValue)] = handler
        return true
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let hotkeyID = id.id
            // 핫키 이벤트는 메인 스레드의 이벤트 루프에서 전달된다.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotkeyCenter>.fromOpaque(userData).takeUnretainedValue().handlers[hotkeyID]?()
            }
            return noErr
        }
        InstallEventHandler(GetEventDispatcherTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }
}
