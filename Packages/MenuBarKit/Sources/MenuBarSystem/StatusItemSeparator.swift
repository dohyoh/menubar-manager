import AppKit
import MenuBarDomain
import MenuBarPrivateBridge

/// 이 Mac 에서 쓸 수 있는 숨김 방식.
public enum VisibilityBackendKind: Sendable {
    /// 시스템 허용 목록 (docs/adr/0003-visibility-mechanism.md) — macOS 27 에서 확인
    case allowlist
    /// 구분자 확장 (docs/adr/0012-separator-visibility-macos26.md) — macOS 26.5.2 에서 확인
    case separator
    case unavailable

    /// 버전 번호보다 기능 유무를 먼저 본다. 허용 목록 기능이 없고, 메뉴바가 아이콘마다 창을 갖는 구조(macOS 26 이하)이면
    /// 구분자 방식을 쓴다. macOS 27 부터는 그 구조가 아니어서 구분자 방식이 통하지 않는다 (보고됨, platform-notes 4절).
    @MainActor
    public static func detect() -> VisibilityBackendKind {
        if MBKVisibilityBridge.isSupported { return .allowlist }
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 { return .separator }
        return .unavailable
    }
}

/// 구분자: 내용이 없는 이 앱의 상태 아이템. 길이를 아주 크게 주면 그 왼쪽의 아이콘이 화면 밖으로 밀려난다.
///
/// - 길이는 항상 화면 폭보다 훨씬 크게 준다. 어중간한 길이는 다른 아이콘까지 사라지게 한다 (검증됨, platform-notes 7.3).
/// - 접었을 때는 길이 0 을 줘도 16pt 의 빈칸으로 남는다 (7.6).
/// - 프로세스가 끝나면 아이템이 사라지면서 밀려났던 아이콘이 모두 돌아온다 (7.4).
@MainActor
public final class StatusItemSeparator: SeparatorItemControlling {
    public static let expandedLength: CGFloat = 10_000
    private static let autosaveName = "MenuBarManagerSeparator"

    private var item: NSStatusItem?
    public private(set) var isExpanded = false

    public init() {}

    /// 구분자를 메뉴바에 만든다. 새 상태 아이템은 가장 왼쪽에 놓이므로, 이 앱의 아이콘을 만든 **뒤에** 부른다 —
    /// 그래야 처음 실행했을 때 자기 아이콘이 구분자의 오른쪽(항상 보이는 쪽)에 있다.
    /// 그 뒤로는 시스템이 기억하는 자리에 놓인다.
    public func install() {
        guard item == nil else { return }
        let created = NSStatusBar.system.statusItem(withLength: 0)
        created.autosaveName = Self.autosaveName
        created.behavior = []
        if let button = created.button {
            button.title = ""
            button.image = nil
            button.setAccessibilityIdentifier(Self.autosaveName)
        }
        item = created
    }

    public func setExpanded(_ expanded: Bool) {
        guard let item else { return }
        item.length = expanded ? Self.expandedLength : 0
        isExpanded = expanded
    }

    public var trailingOffset: CGFloat? {
        guard !isExpanded, let window = item?.button?.window, let screen = window.screen ?? NSScreen.screens.first else { return nil }
        return screen.frame.maxX - window.frame.minX
    }

    public var collapsedWidth: CGFloat {
        guard !isExpanded, let width = item?.button?.window?.frame.width, width > 0 else { return 16 }
        return width
    }

    /// 검증용 요약.
    public var debugDescription: String {
        guard let window = item?.button?.window else { return "not installed" }
        return "expanded=\(isExpanded) x=\(Int(window.frame.minX)) w=\(Int(window.frame.width)) offset=\(trailingOffset.map { String(Int($0)) } ?? "-")"
    }
}
