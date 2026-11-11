// 검증용 코드 (제품 코드 아님). macOS 26 이하의 "구분자 확장" 숨김이 이 Mac 에서 되는지 확인한다.
// 자기 상태 아이템 3개(H, S, V)만 만들고 다른 앱의 아이콘 순서는 건드리지 않는다. 끝나면 스스로 종료한다.
// 결과: docs/architecture/platform-notes.md 7절
//
//   swiftc -O main.swift -o <출력 경로> && <출력 경로> [--lengths 10000,5000,...] [--hold 초]
//
// 배치(왼쪽→오른쪽): H · S(구분자) · V · [원래 있던 아이콘들]
// S 의 길이를 크게 늘리면 S 왼쪽의 H 가 화면 밖으로 밀려나는지, V 와 원래 아이콘은 그대로인지 본다.
import AppKit

setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let lengths = (value("--lengths") ?? "10000").split(separator: ",").compactMap { Double($0) }
let hold = Double(value("--hold") ?? "0") ?? 0

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func makeItem(_ title: String) -> NSStatusItem {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = title
    return item
}
// 나중에 만든 아이템이 더 왼쪽에 놓인다.
let visible = makeItem("V")
let separator = makeItem("S")
let hidden = makeItem("H")

func frame(_ item: NSStatusItem) -> String {
    guard let w = item.button?.window else { return "no-window" }
    return "x=\(Int(w.frame.minX)) w=\(Int(w.frame.width)) visible=\(w.isVisible) onScreen=\(w.screen != nil) occluded=\(!w.occlusionState.contains(.visible))"
}

/// 화면의 메뉴바 아이템 창(레이어 25)들. 권한 없이 위치만 읽는다.
func itemWindows() -> (onScreen: [String], offScreen: Int) {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    let screenWidth = Double(NSScreen.screens.first?.frame.width ?? 0)
    var on: [(Double, String)] = []
    var off = 0
    for w in list where (w[kCGWindowLayer as String] as? Int) == 25 {
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let x = b["X"] as? Double ?? 0, width = b["Width"] as? Double ?? 0
        guard width > 0 else { continue }
        if x + width > 0 && x < screenWidth, (w[kCGWindowIsOnscreen as String] as? Bool) == true {
            on.append((x, "\(Int(x))+\(Int(width))"))
        } else {
            off += 1
        }
    }
    return (on.sorted { $0.0 < $1.0 }.map(\.1), off)
}

func report(_ label: String) {
    let windows = itemWindows()
    print("== \(label)")
    print("   H: \(frame(hidden))")
    print("   S: \(frame(separator)) length=\(separator.length)")
    print("   V: \(frame(visible))")
    print("   창 \(windows.onScreen.count)개 화면 안, \(windows.offScreen)개 화면 밖: \(windows.onScreen.joined(separator: " "))")
}

var steps: [(Double, () -> Void)] = []
steps.append((1.0, { report("처음 (구분자 접힘)") }))
for length in lengths {
    steps.append((0.2, { separator.length = CGFloat(length) }))
    steps.append((1.0, { report("구분자 길이 \(Int(length))") }))
    steps.append((0.2, { separator.length = NSStatusItem.variableLength }))
    steps.append((1.0, { report("다시 접음") }))
}
// 접었을 때 길이 0 으로 두면 구분자가 보이지 않으면서 자리는 유지되는가
steps.append((0.2, { separator.length = 0 }))
steps.append((1.0, { report("구분자 길이 0") }))
steps.append((0.2, { separator.length = 10000 }))
steps.append((1.0, { report("길이 0 에서 바로 10000") }))
// 구분자를 펼친 동안 새로 생긴 아이템은 어디에 놓이는가 (새 앱이 실행된 경우)
var late: NSStatusItem?
steps.append((0.2, { late = makeItem("N") }))
steps.append((1.0, {
    report("펼친 동안 새 아이템 N 생성")
    print("   N: \(late.map(frame) ?? "-")")
}))
steps.append((0.2, { separator.length = NSStatusItem.variableLength }))
steps.append((1.0, {
    report("다시 접음")
    print("   N: \(late.map(frame) ?? "-")")
}))
if hold > 0 {
    steps.append((0.2, { separator.length = CGFloat(lengths.first ?? 10000) }))
    steps.append((1.0, { report("펼친 채로 \(Int(hold))초 대기 (강제 종료 시험용) pid=\(getpid())") }))
    steps.append((hold, {}))
}
steps.append((0.2, { print("끝"); exit(0) }))

func run(_ index: Int) {
    guard index < steps.count else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + steps[index].0) {
        steps[index].1()
        run(index + 1)
    }
}
run(0)
app.run()
