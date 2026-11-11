import CoreGraphics
import Foundation

// 구분자 확장 방식의 숨김(macOS 26 이하)에 쓰는 모델·규칙·프로토콜.
// 이 앱의 보이지 않는 상태 아이템(구분자)을 아주 길게 늘여 그 왼쪽의 아이콘을 화면 밖으로 밀어낸다.
// 숨길 앱의 아이콘은 ⌘+드래그를 대신 수행해 구분자 왼쪽으로 옮긴다.
// (docs/adr/0012-separator-visibility-macos26.md, docs/architecture/platform-notes.md 7절)

/// 숨김 백엔드의 성질. 방식에 따라 필요한 권한과 화면에 내놓을 기능이 달라진다.
public struct VisibilityTraits: Equatable, Sendable {
    /// 숨기려면 접근성 권한이 필요한가 (숨길 아이콘을 앱이 옮겨야 하는 방식)
    public var requiresAccessibility: Bool
    /// 시스템 아이콘(Wi-Fi·배터리)을 숨길 수 있는가
    public var supportsSystemItems: Bool
    /// 숨김 중에는 알림 센터가 열리지 않는가 (시계를 누를 때 숨김을 풀어 줘야 하는가)
    public var blocksNotificationCenter: Bool
    /// /Applications 밖에 있는 앱의 아이콘은 숨김 중에 표시할 수 없는가
    public var hidesAppsOutsideApplications: Bool

    public init(requiresAccessibility: Bool, supportsSystemItems: Bool, blocksNotificationCenter: Bool, hidesAppsOutsideApplications: Bool) {
        self.requiresAccessibility = requiresAccessibility
        self.supportsSystemItems = supportsSystemItems
        self.blocksNotificationCenter = blocksNotificationCenter
        self.hidesAppsOutsideApplications = hidesAppsOutsideApplications
    }

    /// 시스템 허용 목록 방식 (docs/adr/0003-visibility-mechanism.md)
    public static let allowlist = VisibilityTraits(
        requiresAccessibility: false, supportsSystemItems: true, blocksNotificationCenter: true, hidesAppsOutsideApplications: true)
    /// 구분자 확장 방식 (docs/adr/0012-separator-visibility-macos26.md)
    public static let separator = VisibilityTraits(
        requiresAccessibility: true, supportsSystemItems: false, blocksNotificationCenter: false, hidesAppsOutsideApplications: false)
}

/// 메뉴바를 한 번 읽은 결과.
public struct MenuBarSnapshot: Equatable, Sendable {
    /// 지금 화면에 표시된 아이템 (왼쪽 → 오른쪽)
    public var visible: [MenuBarItem]
    /// 크기는 있지만 어느 화면에도 걸치지 않는 아이템 — 구분자에 밀려 화면 밖에 있는 것 (검증됨, platform-notes 7.8)
    public var offscreen: [MenuBarItem]

    public init(visible: [MenuBarItem], offscreen: [MenuBarItem] = []) {
        self.visible = visible
        self.offscreen = offscreen
    }
}

/// 이 앱의 구분자 아이템. 구현은 MenuBarSystem 에 있다.
@MainActor
public protocol SeparatorItemControlling: AnyObject {
    /// 길게 늘여 놓았는가 (= 숨김 적용 중)
    var isExpanded: Bool { get }
    func setExpanded(_ expanded: Bool)
    /// 접혀 있을 때, 구분자가 놓인 모니터의 오른쪽 끝에서 구분자 왼쪽 가장자리까지의 거리.
    /// 늘여 놓았거나 아직 메뉴바에 없으면 nil.
    var trailingOffset: CGFloat? { get }
    /// 접혀 있을 때의 폭
    var collapsedWidth: CGFloat { get }
}

/// 구분자를 기준으로 어느 아이콘이 어느 쪽에 있어야 하는지, 옮기려면 어디에 놓아야 하는지 계산한다.
public enum SeparatorPlanner {
    public enum Side: Equatable, Sendable {
        /// 구분자의 왼쪽 — 구분자를 늘이면 화면 밖으로 밀려난다
        case hidden
        /// 구분자의 오른쪽 — 항상 보인다
        case shown
    }

    public struct Placement: Equatable, Sendable {
        public let item: MenuBarItem
        public let side: Side

        public init(item: MenuBarItem, side: Side) {
            self.item = item
            self.side = side
        }
    }

    public struct Relocation: Equatable, Sendable {
        public let item: MenuBarItem
        /// 옮겨 갈 쪽
        public let to: Side

        public init(item: MenuBarItem, to: Side) {
            self.item = item
            self.to = to
        }
    }

    /// 접근성으로 읽은 좌표와 자기 창에서 읽은 좌표의 차이를 이만큼까지 같은 것으로 본다 (실제 차이는 1~2pt).
    static let matchTolerance: CGFloat = 8
    /// 이보다 넓은 자기 아이템은 늘여 놓은 구분자다.
    static let expandedMinimumWidth: CGFloat = 500
    /// 놓을 지점: 목표 가장자리에서 이만큼 왼쪽 (platform-notes 7.9)
    public static let dropInset: CGFloat = 6

    /// 이 아이템이 구분자 자신인가. 구분자도 이 앱의 상태 아이템이라 읽은 목록에 함께 나온다.
    /// - Parameter separatorOffset: 접혀 있을 때 구분자의 `trailingOffset`. 늘여 놓았으면 nil.
    public static func isSeparator(_ item: MenuBarItem, selfID: BundleID, separatorOffset: CGFloat?) -> Bool {
        guard item.bundleID == selfID else { return false }
        if item.frame.width >= expandedMinimumWidth { return true }
        guard let separatorOffset else { return false }
        return abs(item.trailingOffset - separatorOffset) < matchTolerance
    }

    /// 구분자가 접혀 있을 때(전부 보일 때): 위치로 어느 쪽인지 정한다.
    public static func placements(collapsed items: [MenuBarItem], selfID: BundleID, separatorOffset: CGFloat) -> [Placement] {
        items.compactMap { item in
            guard !isSeparator(item, selfID: selfID, separatorOffset: separatorOffset) else { return nil }
            return Placement(item: item, side: item.trailingOffset > separatorOffset ? .hidden : .shown)
        }
    }

    /// 구분자를 늘여 놓았을 때: 보이는 것은 오른쪽, 화면 밖으로 밀려난 것은 왼쪽이다.
    public static func placements(expanded snapshot: MenuBarSnapshot, selfID: BundleID) -> [Placement] {
        let visible = snapshot.visible
            .filter { !isSeparator($0, selfID: selfID, separatorOffset: nil) }
            .map { Placement(item: $0, side: .shown) }
        let offscreen = snapshot.offscreen
            .filter { !isSeparator($0, selfID: selfID, separatorOffset: nil) }
            .map { Placement(item: $0, side: .hidden) }
        return offscreen + visible
    }

    /// 지금 있는 쪽과 있어야 할 쪽이 다른 아이템.
    ///
    /// 허용 목록에 없는 앱의 아이콘은 숨김 쪽에, 나머지는 표시 쪽에 있어야 한다. 이 앱 자신은 항상 표시 쪽이다.
    /// 시스템 아이템은 옮기지 않는다 (docs/adr/0004-reorder-mechanism.md).
    /// - Parameter skipping: 옮기기를 포기한 아이템
    public static func relocations(
        _ placements: [Placement], allowed: Set<BundleID>, selfID: BundleID, skipping: Set<MenuBarItem.ID> = []
    ) -> [Relocation] {
        placements.compactMap { placement in
            let item = placement.item
            guard !item.isSystem, !skipping.contains(item.id) else { return nil }
            let wanted: Side = item.bundleID == selfID || allowed.contains(item.bundleID) ? .shown : .hidden
            return wanted == placement.side ? nil : Relocation(item: item, to: wanted)
        }
    }

    /// 아이콘을 놓을 x 좌표 (옮길 아이템이 놓인 모니터 기준). 구분자가 접혀 있을 때의 배치로 계산한다.
    ///
    /// - 숨김 쪽으로: 구분자 왼쪽 가장자리의 바로 왼쪽
    /// - 표시 쪽으로: 구분자 바로 오른쪽 아이템의 왼쪽 가장자리의 바로 왼쪽 (그 아이템 앞에 들어간다).
    ///   그 지점은 구분자 위다. 접힌 구분자는 폭이 16pt 뿐이라, 구분자의 오른쪽 절반 안에 놓이도록 덜 들어간다.
    /// - Parameter alternate: 첫 시도가 먹지 않았을 때 쓰는 다른 지점
    public static func dropX(
        for relocation: Relocation, placements: [Placement], separatorOffset: CGFloat, separatorWidth: CGFloat, alternate: Bool = false
    ) -> CGFloat {
        let item = relocation.item
        let separatorLeading = item.screenMaxX - separatorOffset
        switch relocation.to {
        case .hidden:
            return separatorLeading - (alternate ? dropInset * 2.5 : dropInset)
        case .shown:
            // 표시 쪽에서 가장 왼쪽에 있는 아이템 (오른쪽 끝에서 가장 먼 것)
            let anchor = placements
                .filter { $0.side == .shown && $0.item.id != item.id }
                .max { $0.item.trailingOffset < $1.item.trailingOffset }?.item
            guard let anchor else { return separatorLeading + separatorWidth + dropInset }
            let anchorLeading = item.xOnMyScreen(ofLeadingEdgeOf: anchor)
            return alternate ? anchorLeading + min(dropInset, anchor.frame.width / 4) : anchorLeading - min(dropInset, separatorWidth / 4)
        }
    }
}
