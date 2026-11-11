import AppKit
import SwiftUI
import MenuBarDomain

/// 상태를 사용자에게 보여 주는 문구·아이콘. 한곳에 모아 메뉴·설정 창·아이콘이 같은 말을 쓰게 한다.
public enum StatePresentation {
    /// 메뉴바 아이콘 (SF Symbol 이름)
    ///  - 숨김 적용 중: 닫힌 커튼
    ///  - 전부 표시 (잠깐 펼침, 또는 숨기기를 끔): 열린 커튼
    ///  - 숨김을 켤 수 없는 상태: 느낌표 네모
    ///
    /// 펼치면 숨긴 앱이 이 아이콘의 양옆에 나타나므로, 한쪽을 가리키는 화살표 대신
    /// 가운데에서 양쪽으로 열리는 모양을 쓴다.
    public static func symbolName(for state: ManagerState) -> String {
        switch state {
        case .collapsed:
            return "curtains.closed"
        case .expanded, .reordering, .paused(.userOff), .paused(.error):
            return "curtains.open"
        case .paused(.notInstalledInApplications), .paused(.unsupported):
            return "exclamationmark.square"
        }
    }

    public static func accessibilityLabel(for state: ManagerState) -> String {
        switch state {
        case .collapsed: return L("MenuBarManager — 숨김 적용 중")
        case .expanded: return L("MenuBarManager — 펼침")
        case .reordering: return L("MenuBarManager — 순서 작업 중")
        case .paused(.notInstalledInApplications), .paused(.unsupported): return L("MenuBarManager — 숨김을 켤 수 없음")
        case .paused: return L("MenuBarManager — 숨기기 꺼짐 (전부 표시)")
        }
    }

    /// 설정 창 상태 줄
    public static func summary(for state: ManagerState) -> String {
        switch state {
        case .collapsed: return L("숨김 적용 중")
        case .expanded: return L("잠깐 펼친 상태")
        case .reordering: return L("순서를 읽거나 바꾸는 중입니다")
        case .paused(.userOff): return L("숨기기가 꺼져 있습니다 (전부 표시)")
        case .paused(.notInstalledInApplications): return L("응용 프로그램 폴더에서 실행해야 숨김을 켤 수 있습니다")
        case .paused(.unsupported): return L("이 macOS 버전에서는 숨김 기능을 쓸 수 없습니다")
        case .paused(.error): return L("숨김 적용에 실패했습니다 (전부 표시)")
        }
    }

    /// 숨김을 켤 수 없을 때 메뉴에 보여 줄 이유. 켤 수 있으면 nil.
    public static func blockerNote(for state: ManagerState) -> String? {
        switch state {
        case .paused(.notInstalledInApplications): return L("응용 프로그램 폴더로 옮긴 뒤 다시 실행해 주세요")
        case .paused(.unsupported): return L("이 macOS 버전에서는 숨김을 쓸 수 없습니다")
        default: return nil
        }
    }

    /// 사용자가 숨김을 켜고 끌 수 있는 상태인가
    public static func canToggleHiding(_ state: ManagerState) -> Bool {
        state != .reordering && blockerNote(for: state) == nil
    }
}

/// SwiftUI 화면을 일반 창으로 띄운다.
/// 메뉴바 전용(LSUIElement) 앱은 창을 열 때 앱을 직접 활성화해야 창이 앞에 보인다.
@MainActor
public final class HostedWindow {
    private var window: NSWindow?
    private let title: String
    private let resizable: Bool
    private let minSize: NSSize?
    private let initialSize: NSSize?
    private let makeContent: () -> AnyView

    public init<Content: View>(title: String, resizable: Bool, minSize: NSSize? = nil, initialSize: NSSize? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.resizable = resizable
        self.minSize = minSize
        self.initialSize = initialSize
        self.makeContent = { AnyView(content()) }
    }

    public var isVisible: Bool { window?.isVisible ?? false }

    public func close() { window?.orderOut(nil) }

    /// 창 크기를 바꾼다 (자동 검증에서 긴 화면을 한 번에 캡처할 때 쓴다).
    public func resize(to size: NSSize) {
        window?.setContentSize(size)
        window?.center()
    }

    /// 창의 내용을 화면을 거치지 않고 그려 PNG 로 저장한다 (자동 검증용).
    /// 화면이 잠겨 있어 캡처할 수 없을 때도 된다. 제목 막대는 들어가지 않는다.
    @discardableResult
    public func renderContent(to url: URL) -> Bool {
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    public func show() {
        if window == nil {
            let host = NSHostingController(rootView: makeContent())
            let created = NSWindow(contentViewController: host)
            created.title = title
            created.styleMask = resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable]
            created.isReleasedWhenClosed = false
            if let minSize { created.contentMinSize = minSize }
            if let initialSize { created.setContentSize(initialSize) }
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
