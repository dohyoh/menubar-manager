import AppKit
import ApplicationServices
import MenuBarDomain

// 접근성 권한이 필요한 OS 접점: 권한 확인, 메뉴바 아이템 열거, ⌘+드래그 합성.
// 이 Mac 에서 동작을 확인했다 (docs/architecture/platform-notes.md 3.21, 3.22).

@MainActor
public final class AccessibilityPermission: PermissionChecking {
    public init() {}

    public var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    public func requestAccessibility() {
        // kAXTrustedCheckOptionPrompt 의 값. 전역 변수 참조를 피하려고 문자열로 쓴다.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

/// 각 앱의 접근성 요소 `AXExtrasMenuBar` 에서 메뉴바 아이템과 좌표를 읽는다.
///
/// 숨겨졌거나 표시되지 않는 아이템도 예전 좌표를 돌려준다. 그래서 각 아이템의 중심 좌표에
/// 실제로 그 앱의 메뉴바 아이템이 있는지 확인해, 지금 표시된 것만 남긴다 (검증됨).
/// 접근성 호출은 앱마다 응답을 기다리므로 메인 스레드 밖에서 실행한다.
@MainActor
public final class AXItemDiscovery: ItemDiscovering {
    private struct AppRef: Sendable {
        let pid: pid_t
        let bundleID: String
        let name: String
    }

    /// 지난번 전체 조회에서 메뉴바 아이템이 있던 프로세스. 빠른 조회는 이들만 본다.
    private var knownPIDs: Set<pid_t> = []

    public init() {}

    public func currentItems(fullScan: Bool) async throws -> [MenuBarItem] {
        try await snapshot(fullScan: fullScan).visible
    }

    public func snapshot(fullScan: Bool) async throws -> MenuBarSnapshot {
        guard AXIsProcessTrusted() else { throw OrderingError.accessibilityNotGranted }
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> AppRef? in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return AppRef(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? bundleID)
        }
        let scanAll = fullScan || knownPIDs.isEmpty
        let known = knownPIDs
        let candidates = scanAll ? apps : apps.filter { known.contains($0.pid) }
        // 모니터 영역을 접근성 좌표계(왼쪽 위 원점)로 바꿔 넘긴다. x 는 두 좌표계에서 같고 y 만 뒤집힌다.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        let (snapshot, owners) = await Task.detached(priority: .userInitiated) { Self.scan(candidates, screens: screens) }.value
        if scanAll { knownPIDs = owners }
        return snapshot
    }

    public func appsOwningItems() async throws -> Set<BundleID> {
        guard AXIsProcessTrusted() else { throw OrderingError.accessibilityNotGranted }
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> AppRef? in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return AppRef(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? bundleID)
        }
        let owners = await Task.detached(priority: .utility) { Self.scanOwners(apps) }.value
        knownPIDs = Set(owners.map(\.pid))
        return Set(owners.map(\.bundleID))
    }

    /// 메뉴바 아이템을 하나라도 가진 앱들. 숨겨져 있어도 접근성 요소는 남아 있으므로 포함된다.
    nonisolated private static func scanOwners(_ apps: [AppRef]) -> [AppRef] {
        apps.filter { app in
            let element = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(element, 0.4)
            guard let bar = attribute(element, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return false }
            // swiftlint:disable:next force_cast
            return !((attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]) ?? []).isEmpty
        }
    }

    /// (지금 표시된 아이템과 화면 밖으로 밀려난 아이템, 아이템을 가진 프로세스들)
    nonisolated private static func scan(_ apps: [AppRef], screens: [CGRect]) -> (MenuBarSnapshot, Set<pid_t>) {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.5)
        var items: [MenuBarItem] = []
        var offscreen: [MenuBarItem] = []
        var owners = Set<pid_t>()
        for app in apps {
            let element = AXUIElementCreateApplication(app.pid)
            // 응답 없는 앱 때문에 멈추지 않도록 대기 시간을 짧게 둔다.
            AXUIElementSetMessagingTimeout(element, 0.4)
            guard let bar = attribute(element, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            // swiftlint:disable:next force_cast
            let children = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
            if !children.isEmpty { owners.insert(app.pid) }
            for (index, child) in children.enumerated() {
                guard let frame = frame(of: child), frame.width > 0 else { continue }
                // 이름으로 쓸 만한 값을 차례로 찾는다. 시스템 아이템은 제목이 비어 있고 식별자만 있는 경우가 많다.
                func title() -> String? {
                    [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXHelpAttribute]
                        .lazy.compactMap { attribute(child, $0) as? String }.first { !$0.isEmpty }
                }
                let identifier = attribute(child, kAXIdentifierAttribute) as? String
                // 어느 화면에도 걸치지 않으면 구분자에 밀려 화면 밖에 있는 것이다 (macOS 26 이하, platform-notes 7.8).
                // macOS 27 은 숨겨진 아이템에 화면 안의 예전 좌표를 돌려주므로 여기에 해당하지 않는다.
                if !screens.contains(where: { $0.intersects(frame) }) {
                    offscreen.append(MenuBarItem(bundleID: app.bundleID, appName: app.name, index: index, title: title(), frame: frame, screenMaxX: frame.maxX, identifier: identifier))
                    continue
                }
                // 그 좌표에 실제로 이 앱의 메뉴바 아이템이 있을 때만 "표시됨"으로 본다.
                guard let hit = owner(at: CGPoint(x: frame.midX, y: frame.midY), systemWide: systemWide),
                      hit.pid == app.pid, hit.role == "AXMenuBarItem" else { continue }
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let screenMaxX = (screens.first { $0.contains(center) } ?? screens.first { center.x >= $0.minX && center.x <= $0.maxX })?.maxX ?? frame.maxX
                items.append(MenuBarItem(bundleID: app.bundleID, appName: app.name, index: index, title: title(), frame: frame, screenMaxX: screenMaxX, identifier: identifier))
            }
        }
        return (MenuBarSnapshot(visible: MenuBarItem.sortedLeftToRight(items), offscreen: offscreen), owners)
    }

    nonisolated private static func owner(at point: CGPoint, systemWide: AXUIElement) -> (pid: pid_t, role: String)? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success, let element else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return (pid, attribute(element, kAXRoleAttribute) as? String ?? "-")
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    nonisolated private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute), let sizeValue = attribute(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin), AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        // swiftlint:enable force_cast
        return CGRect(origin: origin, size: size)
    }
}

/// 사용자가 ⌘ 을 누른 채 아이콘을 끄는 동작을 입력 이벤트로 재현한다.
/// 끝나면 포인터를 원래 자리로 돌려놓는다.
@MainActor
public final class EventSynthesisReorderer: ItemReordering {
    /// 드래그 한 걸음의 거리(pt)와 걸음 사이 간격(ms), 놓기 전 멈춤(ms).
    /// 너무 빠르면 시스템이 중간 아이템을 건너뛰지 못해 덜 이동한다.
    public var stepDistance: CGFloat = 6
    public var stepInterval = 12
    public var holdBeforeRelease = 250

    public init() {}

    public func commandDrag(from start: CGPoint, to end: CGPoint) async throws {
        guard AXIsProcessTrusted() else { throw OrderingError.accessibilityNotGranted }
        let original = CGEvent(source: nil)?.location

        try post(.mouseMoved, at: start)
        try await pause(80)
        try post(.leftMouseDown, at: start)
        try await pause(120)
        let distance = hypot(end.x - start.x, end.y - start.y)
        let steps = max(4, Int((distance / max(1, stepDistance)).rounded(.up)))
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            try post(.leftMouseDragged, at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            try await pause(stepInterval)
        }
        try await pause(holdBeforeRelease)
        try post(.leftMouseUp, at: end)
        try await pause(80)

        if let original { CGWarpMouseCursorPosition(original) }
    }

    /// 한 번 클릭 (검증용). ⌘ 없이 누른다.
    public func click(at point: CGPoint) async throws {
        guard AXIsProcessTrusted() else { throw OrderingError.accessibilityNotGranted }
        let original = CGEvent(source: nil)?.location
        try post(.mouseMoved, at: point, flags: [])
        try await pause(80)
        try post(.leftMouseDown, at: point, flags: [])
        try await pause(60)
        try post(.leftMouseUp, at: point, flags: [])
        try await pause(80)
        if let original { CGWarpMouseCursorPosition(original) }
    }

    /// 누르기만 / 떼기만 (검증용 — 누른 채 다른 동작을 끼워 넣을 때)
    public func press(at point: CGPoint) async throws {
        guard AXIsProcessTrusted() else { throw OrderingError.accessibilityNotGranted }
        try post(.mouseMoved, at: point, flags: [])
        try await pause(60)
        try post(.leftMouseDown, at: point, flags: [])
    }

    public func release(at point: CGPoint) throws {
        try post(.leftMouseUp, at: point, flags: [])
    }

    private func post(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags = .maskCommand) throws {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            throw OrderingError.eventCreationFailed
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func pause(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

/// 사용자가 지금 메뉴바를 쓰고 있는가. 권한이 필요 없다.
@MainActor
public final class MenuBarActivityChecker: MenuBarActivityChecking {
    private static let notificationCenterBundleID = "com.apple.notificationcenterui"

    public init() {}

    public func isMenuBarInUse() -> Bool {
        isPointerInMenuBar() || isAnyMenuOpen() || isNotificationCenterOpen()
    }

    public func isSystemPanelOpen() -> Bool { isNotificationCenterOpen() }
    public func isMenuOpen() -> Bool { isAnyMenuOpen() }

    /// 알림 센터가 열려 있는가. 숨김을 다시 걸면 알림 센터가 닫히므로, 열려 있는 동안에는 숨기지 않는다.
    ///
    /// 접근성 권한이 있으면 정확히 판단한다: 알림 센터 패널이 열려 있을 때만 그 안에
    /// "위젯 편집" 버튼(식별자 `widget-editor-button`)이 있다 (검증됨).
    /// 권한이 없으면 "알림 센터 프로세스의 창이 화면에 있는가"로 대신한다 — 알림 배너가 떠 있을 때도
    /// 참이 되지만, 그 경우는 다시 숨기기가 몇 초 늦어질 뿐이다.
    public func isNotificationCenterOpen() -> Bool {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.notificationCenterBundleID).first?.processIdentifier else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        // 데스크탑에 놓인 위젯도 이 프로세스의 창이다. 일반 창보다 위에 뜬 창(패널·배너)만 본다.
        guard windows.contains(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && (($0[kCGWindowLayer as String] as? Int) ?? 0) > 0 }) else { return false }
        guard AXIsProcessTrusted() else { return true }
        return Self.containsElement(withIdentifier: "widget-editor-button", inApplication: pid)
    }

    /// 앱의 창들에서 해당 식별자를 가진 요소를 찾는다 (얕게만 본다).
    private static func containsElement(withIdentifier identifier: String, inApplication pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var out: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &out) == .success ? out : nil
        }
        func search(_ element: AXUIElement, depth: Int) -> Bool {
            if value(element, kAXIdentifierAttribute) as? String == identifier { return true }
            guard depth < 6 else { return false }
            let children = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            return children.contains { search($0, depth: depth + 1) }
        }
        let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.contains { search($0, depth: 0) }
    }

    private func isPointerInMenuBar() -> Bool {
        let pointer = NSEvent.mouseLocation
        for screen in NSScreen.screens where pointer.x >= screen.frame.minX && pointer.x <= screen.frame.maxX {
            let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            if pointer.y <= screen.frame.maxY && pointer.y >= screen.frame.maxY - barHeight { return true }
        }
        return false
    }

    /// 알림 센터 프로세스의 접근성 구조 요약 (검증용). 접근성 권한 필요.
    public func notificationCenterAccessibilityDump() -> [String] {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.notificationCenterBundleID).first?.processIdentifier else { return ["no process"] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var out: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &out) == .success ? out : nil
        }
        func describe(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
            let role = value(element, kAXRoleAttribute) as? String ?? "-"
            let subrole = value(element, kAXSubroleAttribute) as? String ?? "-"
            let identifier = value(element, kAXIdentifierAttribute) as? String ?? "-"
            let children = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            lines.append(String(repeating: "  ", count: depth) + "\(role)/\(subrole) id=\(identifier) children=\(children.count)")
            guard depth < 5 else { return }
            for child in children.prefix(5) { describe(child, depth: depth + 1, into: &lines) }
        }
        var lines: [String] = []
        let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let running = NSRunningApplication(processIdentifier: pid)
        lines.append("windows=\(windows.count) appActive=\(running?.isActive ?? false) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-") focusedWindow=\(value(app, kAXFocusedWindowAttribute) != nil) mainWindow=\(value(app, kAXMainWindowAttribute) != nil) focusedElement=\(value(app, kAXFocusedUIElementAttribute) != nil)")
        for window in windows {
            let flags = [kAXMainAttribute, kAXFocusedAttribute, kAXModalAttribute].map { "\($0)=\((value(window, $0) as? Bool).map(String.init) ?? "-")" }.joined(separator: " ")
            lines.append("window flags: \(flags)")
            describe(window, depth: 0, into: &lines)
        }
        return lines
    }

    /// 알림 센터 프로세스의 화면에 있는 창들 (검증용 요약).
    public func notificationCenterWindows() -> [String] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.notificationcenterui" else { return nil }
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let alpha = window[kCGWindowAlpha as String] as? Double ?? -1
            return "layer=\(window[kCGWindowLayer as String] ?? "-") x=\(bounds["X"] ?? "-") y=\(bounds["Y"] ?? "-") w=\(bounds["Width"] ?? "-") h=\(bounds["Height"] ?? "-") alpha=\(alpha)"
        }
    }

    /// 어떤 앱이든 메뉴가 열려 있으면 팝업 메뉴 레벨의 창이 화면에 있다.
    private func isAnyMenuOpen() -> Bool {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowLayer as String] as? Int) == menuLevel }
    }
}

/// 메뉴바의 시계를 누르는 순간을 알려 준다.
///
/// 숨김이 걸려 있으면 알림 센터가 열리지 않는다 (알림 센터가 메뉴바 표시 제한을 감시한다).
/// 시계를 누르는 순간 숨김을 풀면 같은 클릭으로 알림 센터가 열린다 (검증됨).
/// 그래서 시계 영역의 마우스 누름을 감지해 알려 준다. 마우스 이벤트 감시는 접근성 권한이 필요 없다.
/// (docs/architecture/platform-notes.md 3.24)
@MainActor
public final class ClockClickMonitor {
    /// 모니터 오른쪽 끝에서 시계 왼쪽 가장자리까지의 거리. 접근성 권한이 있으면 실제 값으로 바꾼다.
    public var zoneWidth: CGFloat = 170
    /// zoneWidth 가 실제 시계 위치에서 온 값인가 (접근성으로 읽음). 기본값이면 시계 옆 아이콘까지 포함될 수 있다.
    public var isZonePrecise = false
    /// 누른 지점을 화면 좌표(왼쪽 위 원점)로 넘긴다.
    public var onMouseDown: (@MainActor (CGPoint) -> Void)?
    private var monitor: Any?

    public init() {}

    public func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseDown() }
        }
    }

    public func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handleMouseDown() {
        let pointer = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            let inBar = pointer.y <= screen.frame.maxY && pointer.y >= screen.frame.maxY - barHeight
            let inZone = pointer.x <= screen.frame.maxX && pointer.x >= screen.frame.maxX - zoneWidth
            if inBar && inZone {
                // AppKit 좌표(왼쪽 아래 원점)를 이벤트·접근성 좌표(왼쪽 위 원점)로 바꾼다.
                let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
                let point = CGPoint(x: pointer.x, y: primaryHeight - pointer.y)
                // 전체 화면처럼 메뉴바가 가려져 있으면 그 자리는 다른 앱의 화면이다.
                guard isMenuBar(at: point) else { return }
                onMouseDown?(point)
                return
            }
        }
    }

    private static let menuBarBundleID = "com.apple.MenuBarAgent"

    /// 그 지점(왼쪽 위 원점 좌표)에 지금 메뉴바가 그려져 있는가.
    ///
    /// 접근성 권한이 있으면 그 자리의 요소가 메뉴바 프로세스의 것인지 본다 (정확).
    /// 없으면 메뉴바 프로세스의 창이 그 지점을 덮고 있는지로 대신한다.
    public func isMenuBar(at point: CGPoint) -> Bool {
        guard let menuBarPID = NSRunningApplication.runningApplications(withBundleIdentifier: Self.menuBarBundleID).first?.processIdentifier else {
            return true   // 메뉴바 프로세스를 찾지 못하는 macOS 에서는 판단하지 않는다
        }
        if AXIsProcessTrusted() {
            let systemWide = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(systemWide, 0.2)
            var element: AXUIElement?
            guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success, let element else { return false }
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            return pid == menuBarPID
        }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == menuBarPID,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return rect.contains(point)
        }
    }
}
