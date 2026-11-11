// 검증용 코드 (제품 코드 아님). macOS 26 에서 접근성 권한이 필요한 질문에 답한다 (ADR-0012 의 T1~T3).
//   T1 접근성으로 아이콘과 앱의 대응·위치를 읽을 수 있는가
//   T2 ⌘+드래그 합성으로 아이콘이 구분자를 넘어가는가
//   T3 화면 밖으로 밀린 아이콘의 접근성 좌표
// 자기 상태 아이템 H · S(구분자) · V 를 만들고, <폴더>/cmd 의 명령을 실행해 <폴더>/app.log 에 적는다.
// 읽기와 드래그는 제품 코드(MenuBarSystem 의 AXItemDiscovery, EventSynthesisReorderer)를 그대로 쓴다.
//
//   report | expand [길이] | collapse | newitem | axstatus | axprompt
//   axlist            제품 코드로 읽은 "지금 표시된 아이템"
//   axraw             걸러 내지 않은 원본: 앱마다 AXExtrasMenuBar 의 자식, 좌표, 그 좌표에 실제로 있는 요소
//   hit <x> <y>       그 좌표의 접근성 요소
//   drag <x1> <x2> <y> | dragtune <pt> <ms> <ms>
//   quit
import AppKit
import ApplicationServices
import MenuBarDomain
import MenuBarSystem

@MainActor
final class Spike {
    let directory: URL
    let visible: NSStatusItem
    let separator: NSStatusItem
    let hidden: NSStatusItem
    var extras: [NSStatusItem] = []
    let discovery = AXItemDiscovery()
    let reorderer = EventSynthesisReorderer()
    var timer: Timer?

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 나중에 만든 아이템이 더 왼쪽에 놓인다: H · S · V
        visible = Self.makeItem("V")
        separator = Self.makeItem("S")
        hidden = Self.makeItem("H")
        log("launched pid=\(getpid()) bundle=\(Bundle.main.bundleIdentifier ?? "-") path=\(Bundle.main.bundlePath) ax=\(AXIsProcessTrusted())")
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    static func makeItem(_ title: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = title
        return item
    }

    func log(_ message: String) {
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

    func poll() {
        let url = directory.appendingPathComponent("cmd")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: url)
        let lines = raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        Task { for line in lines { await run(line) } }
    }

    /// 자기 아이템의 창 위치. AppKit 좌표의 x 는 화면 좌표와 같다.
    func frame(_ item: NSStatusItem) -> String {
        guard let w = item.button?.window else { return "no-window" }
        return "x=\(Int(w.frame.minX)) w=\(Int(w.frame.width)) occluded=\(!w.occlusionState.contains(.visible))"
    }

    func report(_ label: String) {
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let screenWidth = Double(NSScreen.screens.first?.frame.width ?? 0)
        var on: [(Double, String)] = []
        var off: [String] = []
        for w in list where (w[kCGWindowLayer as String] as? Int) == 25 {
            let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let x = b["X"] as? Double ?? 0, width = b["Width"] as? Double ?? 0
            guard width > 0 else { continue }
            if x + width > 0 && x < screenWidth, (w[kCGWindowIsOnscreen as String] as? Bool) == true {
                on.append((x, "\(Int(x))+\(Int(width))"))
            } else {
                off.append("\(Int(x))+\(Int(width))")
            }
        }
        var text = "REPORT \(label) | H: \(frame(hidden)) | S: \(frame(separator)) len=\(separator.length) | V: \(frame(visible))"
        for (i, item) in extras.enumerated() { text += " | N\(i): \(frame(item))" }
        text += " | 화면 안 \(on.count): \(on.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: " ")) | 화면 밖 \(off.count): \(off.joined(separator: " "))"
        log(text)
    }

    func run(_ line: String) async {
        let parts = line.split(separator: " ").map(String.init)
        guard let command = parts.first else { return }
        log("CMD \(line)")
        switch command {
        case "report":
            report("now")
        case "expand":
            separator.length = CGFloat(Double(parts.dropFirst().first ?? "") ?? 10000)
            try? await Task.sleep(for: .milliseconds(800))
            report("expanded")
        case "collapse":
            separator.length = NSStatusItem.variableLength
            try? await Task.sleep(for: .milliseconds(800))
            report("collapsed")
        case "newitem":
            extras.append(Self.makeItem("N\(extras.count)"))
            try? await Task.sleep(for: .milliseconds(800))
            report("newitem")
        case "axstatus":
            log("AX granted=\(AXIsProcessTrusted())")
        case "axprompt":
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            log("AX prompt requested, granted=\(AXIsProcessTrusted())")
        case "axlist":
            do {
                let started = Date()
                let items = try await discovery.currentItems(fullScan: true)
                for item in items {
                    log("AXITEM id=\(item.id) app=\(item.appName) x=\(Int(item.frame.minX)) y=\(Int(item.frame.minY)) w=\(Int(item.frame.width)) off=\(Int(item.trailingOffset)) title=\(item.title ?? "-")")
                }
                log("AXLIST total=\(items.count) seconds=\(String(format: "%.2f", Date().timeIntervalSince(started)))")
            } catch {
                log("AXLIST failed: \(error)")
            }
        case "axraw":
            let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String)? in
                (app.processIdentifier, app.bundleIdentifier ?? "(no bundle id) \(app.localizedName ?? "?")")
            }
            let lines = await Task.detached { Self.rawScan(apps) }.value
            for line in lines { log(line) }
            log("AXRAW lines=\(lines.count)")
        case "hit":
            guard parts.count >= 3, let x = Double(parts[1]), let y = Double(parts[2]) else { return log("usage: hit <x> <y>") }
            log("HIT (\(Int(x)),\(Int(y))) \(Self.describeHit(CGPoint(x: x, y: y)))")
        case "dragtune":
            guard parts.count >= 4, let d = Double(parts[1]), let i = Int(parts[2]), let h = Int(parts[3]) else { return log("usage: dragtune <stepPt> <stepMs> <holdMs>") }
            reorderer.stepDistance = d; reorderer.stepInterval = i; reorderer.holdBeforeRelease = h
        case "drag":
            guard parts.count >= 4, let x1 = Double(parts[1]), let x2 = Double(parts[2]), let y = Double(parts[3]) else { return log("usage: drag <x1> <x2> <y>") }
            do {
                try await reorderer.commandDrag(from: CGPoint(x: x1, y: y), to: CGPoint(x: x2, y: y))
                try? await Task.sleep(for: .milliseconds(600))
                report("after drag \(Int(x1))->\(Int(x2))")
            } catch {
                log("drag failed: \(error)")
            }
        case "quit":
            log("quit")
            NSApp.terminate(nil)
        default:
            log("unknown command")
        }
    }

    // MARK: 걸러 내지 않은 접근성 조회

    nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    nonisolated static func describeHit(_ point: CGPoint) -> String {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.5)
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard error == .success, let element else { return "none(err=\(error.rawValue))" }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let role = attribute(element, kAXRoleAttribute) as? String ?? "-"
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?"
        return "pid=\(pid) bundle=\(bundle) role=\(role)"
    }

    nonisolated static func rawScan(_ apps: [(pid_t, String)]) -> [String] {
        var lines: [String] = []
        for (pid, bundle) in apps {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.4)
            guard let bar = attribute(element, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            let children = attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
            let barFrame = frame(of: bar as! AXUIElement).map { "x=\(Int($0.minX)) w=\(Int($0.width))" } ?? "-"
            lines.append("AXRAW app=\(bundle) pid=\(pid) extrasBar(\(barFrame)) children=\(children.count)")
            for (index, child) in children.enumerated() {
                let role = attribute(child, kAXRoleAttribute) as? String ?? "-"
                let subrole = attribute(child, kAXSubroleAttribute) as? String ?? "-"
                let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute].map { attribute(child, $0) as? String ?? "" }
                guard let f = frame(of: child) else { lines.append("AXRAW   #\(index) \(role) no-frame"); continue }
                let hit = describeHit(CGPoint(x: f.midX, y: f.midY))
                lines.append("AXRAW   #\(index) \(role)/\(subrole) x=\(Int(f.minX)) y=\(Int(f.minY)) w=\(Int(f.width)) h=\(Int(f.height)) title=\(names[0]) desc=\(names[1]) id=\(names[2]) | hit: \(hit)")
            }
        }
        return lines
    }
}

let arguments = CommandLine.arguments
var directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SeparatorSpike")
if let index = arguments.firstIndex(of: "-dir"), index + 1 < arguments.count {
    directory = URL(fileURLWithPath: arguments[index + 1])
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// 최상위 코드는 메인 스레드에서 실행된다.
let spike = MainActor.assumeIsolated { Spike(directory: directory) }
app.run()
