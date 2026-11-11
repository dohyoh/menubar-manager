#if DEBUG
import AppKit
import MenuBarDomain
import MenuBarServices
import MenuBarUI
import MenuBarSystem

/// 자동 검증용 명령 채널 (Debug 빌드 전용).
///
/// 메뉴바 아이콘 클릭은 프로그램으로 흉내 낼 수 없어(접근성 권한 필요), 같은 코드 경로를
/// 명령 파일로 실행해 화면 캡처로 확인한다. 실행 인자 `-automationDir <폴더>` 를 줄 때만 켜진다.
/// 0.2초마다 `<폴더>/cmd` 를 읽어 실행하고 `<폴더>/app.log` 에 기록한다.
///
///   state | toggle | hide on|off | sethidden <번들ID> 0|1 | autorehide on|off | seconds <n> | policy show|hide
///   settings [order|general|diagnostics] | info | welcome | menushot | menutest | quit
///   lang system|ko|en | restart                                                             (언어 저장, 앱 다시 시작)
///   viewshot <png 경로>                                                                      (설정 창 내용을 화면 없이 그려 저장)
///   axstatus | axprompt | axlist | order read | order move <id> <id|end>                       (순서 조정, 접근성 권한 필요)
///   drag <x1> <x2> <y> | dragtune <pt> <ms> <ms> | click <x> <y>                              (저수준 입력 합성 — 사용자가 쓰는 중에는 피한다)
@MainActor
final class AutomationHook {
    private let directory: URL
    private let coordinator: MenuBarCoordinator
    private let statusItem: StatusItemController
    private weak var delegate: AppDelegate?
    private let permission: any PermissionChecking
    private let itemDiscovery: AXItemDiscovery
    private let reorderer: EventSynthesisReorderer
    private let ordering: OrderingController
    private var timer: Timer?

    static func makeIfRequested(
        coordinator: MenuBarCoordinator, statusItem: StatusItemController, delegate: AppDelegate,
        permission: any PermissionChecking, itemDiscovery: AXItemDiscovery, reorderer: EventSynthesisReorderer, ordering: OrderingController
    ) -> AutomationHook? {
        // 실행 인자로만 켠다. 저장된 기본값(defaults)으로는 켜지지 않게 해서, 한 번의 설정 변경으로 계속 열려 있지 않도록 한다.
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-automationDir"), index + 1 < arguments.count else { return nil }
        let path = arguments[index + 1]
        guard !path.isEmpty else { return nil }
        return AutomationHook(directory: URL(fileURLWithPath: path), coordinator: coordinator, statusItem: statusItem, delegate: delegate,
                              permission: permission, itemDiscovery: itemDiscovery, reorderer: reorderer, ordering: ordering)
    }

    private init(
        directory: URL, coordinator: MenuBarCoordinator, statusItem: StatusItemController, delegate: AppDelegate,
        permission: any PermissionChecking, itemDiscovery: AXItemDiscovery, reorderer: EventSynthesisReorderer, ordering: OrderingController
    ) {
        self.directory = directory
        self.coordinator = coordinator
        self.statusItem = statusItem
        self.delegate = delegate
        self.permission = permission
        self.itemDiscovery = itemDiscovery
        self.reorderer = reorderer
        self.ordering = ordering
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 상태가 바뀐 시각을 남긴다 (알림 센터를 닫은 뒤 얼마나 빨리 다시 숨기는지 잴 때 쓴다).
        let previous = coordinator.onStateChange
        coordinator.onStateChange = { [weak self] state in
            previous?(state)
            self?.log("STATE \(state)")
        }
        log("launched bundleID=\(Bundle.main.bundleIdentifier ?? "-") path=\(Bundle.main.bundlePath) pid=\(ProcessInfo.processInfo.processIdentifier)")
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "\(formatter.string(from: Date())) \(message)\n"
        let url = directory.appendingPathComponent("app.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    private func describeState() -> String {
        "state=\(coordinator.state) hidden=\(coordinator.layout.hiddenApps.sorted()) options=\(coordinator.options) apps=\(coordinator.apps.count)"
    }

    private func poll() {
        let url = directory.appendingPathComponent("cmd")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: url)
        let lines = raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // 메뉴 명령은 실제 클릭처럼 Task 밖에서 바로 실행한다.
        // Task 안에서 메뉴를 열면 메뉴가 닫힐 때까지 다른 메인 액터 작업(스위치 처리)이 밀려서 실제와 다르게 보인다.
        if let first = lines.first, lines.count == 1, first == "menushot" || first == "menutest" {
            log("CMD \(first)")
            statusItem.debugShowMenu(clickSwitch: first == "menutest")
            log(describeState())
            return
        }
        Task {
            for line in lines { await run(line) }
        }
    }

    private func run(_ line: String) async {
        let parts = line.split(separator: " ").map(String.init)
        guard let command = parts.first else { return }
        log("CMD \(line)")
        switch command {
        case "state":
            break
        case "toggle":
            await coordinator.toggle()
        case "hide":
            await coordinator.setHidingEnabled(parts.dropFirst().first == "on")
        case "sethidden":
            guard parts.count >= 3 else { return log("usage: sethidden <bundleID> 0|1") }
            await coordinator.setHidden(parts[1], hidden: parts[2] == "1")
        case "autorehide":
            coordinator.setAutoRehide(parts.dropFirst().first == "on")
        case "seconds":
            if let seconds = parts.dropFirst().first.flatMap(Int.init) { coordinator.setAutoRehideSeconds(seconds) }
        case "settings":
            // settings order 는 메뉴바 관리의 "순서 편집" 화면을 연다.
            if parts.dropFirst().first == "order" {
                delegate?.showOrderEditor()
            } else {
                delegate?.showSettings(tab: SettingsTab(rawValue: parts.dropFirst().first ?? "") ?? .management)
            }
            log("settings visible=\(delegate?.isSettingsVisible ?? false)")
        case "info":
            delegate?.showInfo()
            log("info visible=\(delegate?.isInfoVisible ?? false)")
        case "welcome":
            delegate?.showWelcome()
        case "lang":
            // lang system|ko|en — 저장만 한다. 화면은 `restart` 로 다시 시작해야 바뀐다.
            coordinator.setLanguage(AppLanguage(rawValue: parts.dropFirst().first ?? "") ?? .system)
            log("LANG saved=\(coordinator.options.language.rawValue) current=\(AppLanguageSupport.currentCode) system=\(AppLanguageSupport.systemPreferredLanguages) sample=\(L("설정 열기"))")
        case "viewshot":
            // viewshot <png 경로> — 설정 창의 내용을 화면을 거치지 않고 그려 저장한다 (화면이 잠겨 있어도 된다)
            guard parts.count >= 2 else { return log("usage: viewshot <path>") }
            log("VIEWSHOT \(delegate?.debugRenderSettings(to: parts[1]) == true ? "saved" : "failed") \(parts[1])")
        case "restart":
            delegate?.restart()
        case "policy":
            coordinator.setNewAppPolicy(NewAppPolicy(rawValue: parts.dropFirst().first ?? "") ?? .show)
        case "sysitem":
            // sysitem wifi|battery 0|1   (1 = 숨김)
            guard parts.count >= 3, let item: SystemItem = parts[1] == "wifi" ? .wifi : parts[1] == "battery" ? .battery : nil else { return log("usage: sysitem wifi|battery 0|1") }
            await coordinator.setSystemItemHidden(item, hidden: parts[2] == "1")
            log("SYSITEM hidden=\(coordinator.layout.hiddenSystemItems.sorted())")
        case "mbapps":
            await coordinator.refreshMenuBarApps()
            log("MBAPPS \(coordinator.menuBarApps.map { "count=\($0.count) \($0.sorted().joined(separator: " "))" } ?? "unknown") pending=\(coordinator.layout.pendingApps.sorted())")
        case "winsize":
            guard parts.count >= 3, let w = Double(parts[1]), let h = Double(parts[2]) else { return log("usage: winsize <w> <h>") }
            delegate?.resizeSettings(to: NSSize(width: w, height: h))
        case "hit":
            // hit <x> <y>: 그 지점이 메뉴바로 판정되는지 (시계 클릭 감지 검증용)
            guard parts.count >= 3, let x = Double(parts[1]), let y = Double(parts[2]) else { return log("usage: hit <x> <y>") }
            log("HIT (\(Int(x)),\(Int(y))) isMenuBar=\(delegate?.debugIsMenuBar(at: CGPoint(x: x, y: y)) ?? false)")
        case "key":
            // key <keycode>: ⌃⌥⇧⌘ + 그 키를 합성해 누른다 (다른 프로세스의 단축키 실험용)
            guard let code = parts.dropFirst().first.flatMap({ UInt16($0) }) else { return log("usage: key <keycode>") }
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: isDown)
                event?.flags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
                event?.post(tap: .cghidEventTap)
            }
            log("KEY posted \(code)")
        case "hotkeytest":
            // 저장된 설정은 건드리지 않고, 임시 단축키(⌃⌥⇧⌘F19)를 등록해 눌러 본 뒤 원래대로 되돌린다.
            let result = await delegate?.debugHotkeyProbe() ?? "no delegate"
            log("HOTKEYTEST \(result)")
        case "axstatus":
            log("accessibility granted=\(permission.isAccessibilityGranted)")
        case "axprompt":
            permission.requestAccessibility()
            log("accessibility prompt requested, granted=\(permission.isAccessibilityGranted)")
        case "axlist":
            do {
                let items = try await itemDiscovery.currentItems(fullScan: true)
                for item in items {
                    log("AXITEM id=\(item.id) app=\(item.appName) x=\(Int(item.frame.minX)) y=\(Int(item.frame.minY)) w=\(Int(item.frame.width)) title=\(item.title ?? "-")")
                }
                log("AXLIST total=\(items.count)")
            } catch {
                log("AXLIST failed: \(error)")
            }
        case "order":
            // order read            순서 읽기 (설정 > 순서의 "메뉴바에서 순서 읽기"와 같은 경로)
            // order move <id> <id|end>   <id> 를 두 번째 아이템 바로 앞(또는 맨 끝)으로 옮긴 순서를 적용
            if parts.dropFirst().first == "read" {
                await ordering.read()
            } else if parts.count >= 4, parts[1] == "move" {
                var ids = ordering.items.map(\.id)
                guard let from = ids.firstIndex(of: parts[2]) else { return log("order: unknown item \(parts[2])") }
                ids.remove(at: from)
                if parts[3] == "end" { ids.append(parts[2]) } else if let to = ids.firstIndex(of: parts[3]) { ids.insert(parts[2], at: to) } else { return log("order: unknown anchor \(parts[3])") }
                await ordering.apply(target: ids)
            }
            log("ORDER status=\(ordering.status) items=\(ordering.items.map { "\($0.id)@x\(Int($0.frame.minX))/off\(Int($0.trailingOffset))" }.joined(separator: " "))")
        case "ncwin":
            let windows = MenuBarActivityChecker().notificationCenterWindows()
            log("NCWIN count=\(windows.count) panelOpen=\(MenuBarActivityChecker().isNotificationCenterOpen()) \(windows.joined(separator: " | "))")
        case "ncax":
            let lines = MenuBarActivityChecker().notificationCenterAccessibilityDump()
            log("NCAX onscreenWindows=\(MenuBarActivityChecker().notificationCenterWindows().count)\n    " + lines.joined(separator: "\n    "))
        case "ncprobe":
            // 알림 센터 실험. 시계(가장 오른쪽 아이템)를 대상으로 한다.
            //   ncprobe click       그냥 한 번 클릭
            //   ncprobe downup      누름 → (숨김 중이면) 숨김 해제 → 120ms 뒤 뗌   ← 사용자의 한 번 클릭 안에서 풀어 주는 경우를 흉내
            //   ncprobe thenclick   (숨김 중이면) 숨김 해제 → 300ms 뒤 한 번 클릭
            do {
                guard let clock = try await itemDiscovery.currentItems(fullScan: true).last else { return log("ncprobe: no items") }
                let point = CGPoint(x: clock.frame.midX, y: clock.frame.midY)
                let mode = parts.dropFirst().first ?? "click"
                let checker = MenuBarActivityChecker()
                log("NCPROBE \(mode) at \(Int(point.x)),\(Int(point.y)) state=\(coordinator.state) before=\(checker.notificationCenterWindows().count)")
                switch mode {
                case "downup":
                    try await reorderer.press(at: point)
                    if coordinator.state == .collapsed { await coordinator.toggle() }
                    try? await Task.sleep(for: .milliseconds(120))
                    try reorderer.release(at: point)
                case "hold":
                    // ncprobe hold <ms>: 누른 채 <ms> 만큼 있다가 뗀다. 숨김 해제는 앱의 시계 클릭 감지에 맡긴다.
                    let original = CGEvent(source: nil)?.location
                    try await reorderer.press(at: point)
                    try? await Task.sleep(for: .milliseconds(Int(parts.dropFirst(2).first ?? "") ?? 100))
                    try reorderer.release(at: point)
                    // 사용자의 포인터를 시계 위에 남겨 두지 않는다.
                    try? await Task.sleep(for: .milliseconds(80))
                    if let original { CGWarpMouseCursorPosition(original) }
                case "thenclick":
                    if coordinator.state == .collapsed { await coordinator.toggle() }
                    try? await Task.sleep(for: .milliseconds(300))
                    try await reorderer.click(at: point)
                default:
                    try await reorderer.click(at: point)
                }
                try? await Task.sleep(for: .milliseconds(900))
                let after = checker.notificationCenterWindows()
                log("NCPROBE after count=\(after.count) state=\(coordinator.state) \(after.joined(separator: " | "))")
            } catch {
                log("ncprobe failed: \(error)")
            }
        case "click":
            guard parts.count >= 3, let x = Double(parts[1]), let y = Double(parts[2]) else { return log("usage: click <x> <y>") }
            do { try await reorderer.click(at: CGPoint(x: x, y: y)); log("click done") } catch { log("click failed: \(error)") }
        case "dragtune":
            // dragtune <한 걸음 거리 pt> <걸음 간격 ms> <놓기 전 멈춤 ms>
            guard parts.count >= 4, let d = Double(parts[1]), let i = Int(parts[2]), let h = Int(parts[3]) else { return log("usage: dragtune <stepPt> <stepMs> <holdMs>") }
            reorderer.stepDistance = d; reorderer.stepInterval = i; reorderer.holdBeforeRelease = h
        case "drag":
            guard parts.count >= 4, let x1 = Double(parts[1]), let x2 = Double(parts[2]), let y = Double(parts[3]) else { return log("usage: drag <x1> <x2> <y>") }
            do {
                try await reorderer.commandDrag(from: CGPoint(x: x1, y: y), to: CGPoint(x: x2, y: y))
                log("drag done \(x1) -> \(x2)")
            } catch {
                log("drag failed: \(error)")
            }
        case "menushot":
            statusItem.debugShowMenu(clickSwitch: false)
        case "menutest":
            statusItem.debugShowMenu(clickSwitch: true)
        case "quit":
            NSApp.terminate(nil)
        default:
            log("unknown command")
        }
        log(describeState())
    }
}
#endif
