import CoreGraphics
import Foundation
import Testing
import MenuBarDomain
@testable import MenuBarServices

/// 가짜 메뉴바 + 구분자. 1000pt 폭 화면에 아이템을 오른쪽 정렬로 늘어놓는다.
/// 구분자를 늘이면 그 왼쪽의 아이템은 화면 밖 좌표로 읽히고(보이지 않고), 구분자 자신은 어느 목록에도 나오지 않는다 —
/// 실제 macOS 26 에서 읽히는 모습과 같다 (platform-notes 7.8).
@MainActor
final class FakeSeparatorBar: ItemDiscovering, ItemReordering, SeparatorItemControlling {
    static let screenWidth: CGFloat = 1000
    static let separatorID = "me#1"
    /// 왼쪽 → 오른쪽. 구분자("me#1")를 포함한다.
    var order: [String]
    private(set) var isExpanded = false
    var expandHistory: [Bool] = []
    var dragCount = 0
    var fullScanCount = 0
    /// 드래그해도 움직이지 않는 아이템
    var stuck: Set<String> = []
    /// 드래그하는 순간 구분자가 늘어나 있었던 횟수 (있어서는 안 된다)
    var dragsWhileExpanded = 0
    /// 다음 드래그 직전에 실행한다 (진행 도중 끼어드는 조작을 흉내 낸다)
    var beforeNextDrag: (@MainActor () -> Void)?
    /// 앞으로 이 횟수만큼의 드래그는 먹지 않는다 (가끔 한 번씩 먹지 않는 것을 흉내 낸다)
    var dragsToIgnore = 0
    /// 접근성 식별자를 가진 아이템 (제어 센터가 그리는 시스템 아이콘)
    var identifiers: [String: String] = [:]

    init(order: [String]) { self.order = order }

    private func width(_ id: String) -> CGFloat { id == Self.separatorID ? 16 : 30 }

    private func makeItem(_ id: String, x: CGFloat, width: CGFloat, screenMaxX: CGFloat) -> MenuBarItem {
        let parts = id.split(separator: "#")
        return MenuBarItem(bundleID: String(parts[0]), appName: String(parts[0]), index: Int(parts[1]) ?? 0, title: nil,
                           frame: CGRect(x: x, y: 4, width: width, height: 24), screenMaxX: screenMaxX, identifier: identifiers[id])
    }

    /// 접힌 상태의 배치 (구분자 포함)
    private func collapsedItems() -> [MenuBarItem] {
        var x = Self.screenWidth
        var result: [MenuBarItem] = []
        for id in order.reversed() {
            x -= width(id)
            result.append(makeItem(id, x: x, width: width(id), screenMaxX: Self.screenWidth))
        }
        return result.reversed()
    }

    func snapshot(fullScan: Bool) async throws -> MenuBarSnapshot {
        if fullScan { fullScanCount += 1 }
        guard isExpanded, let index = order.firstIndex(of: Self.separatorID) else {
            return MenuBarSnapshot(visible: collapsedItems())
        }
        let shown = Set(order[(index + 1)...])
        let visible = collapsedItems().filter { shown.contains($0.id) }
        var x: CGFloat = -4000
        let offscreen = order[..<index].map { id -> MenuBarItem in
            defer { x += width(id) }
            return makeItem(id, x: x, width: width(id), screenMaxX: x + width(id))
        }
        return MenuBarSnapshot(visible: visible, offscreen: offscreen)
    }

    func currentItems(fullScan: Bool) async throws -> [MenuBarItem] { try await snapshot(fullScan: fullScan).visible }
    func appsOwningItems() async throws -> Set<BundleID> { Set(order.map { String($0.split(separator: "#")[0]) }) }

    /// 놓은 지점이 어떤 아이템의 왼쪽 절반이면 그 앞에, 오른쪽 절반이면 그 뒤에 들어간다.
    func commandDrag(from start: CGPoint, to end: CGPoint) async throws {
        beforeNextDrag?()
        beforeNextDrag = nil
        dragCount += 1
        if isExpanded { dragsWhileExpanded += 1 }
        if dragsToIgnore > 0 { dragsToIgnore -= 1; return }
        let items = collapsedItems()
        guard let dragged = items.first(where: { $0.frame.minX <= start.x && start.x < $0.frame.maxX }), !stuck.contains(dragged.id) else { return }
        var ids = order.filter { $0 != dragged.id }
        let others = items.filter { $0.id != dragged.id }
        if let target = others.first(where: { $0.frame.minX <= end.x && end.x < $0.frame.maxX }), let index = ids.firstIndex(of: target.id) {
            ids.insert(dragged.id, at: end.x < target.frame.midX ? index : index + 1)
        } else if let firstRight = others.first(where: { $0.frame.minX > end.x }), let index = ids.firstIndex(of: firstRight.id) {
            ids.insert(dragged.id, at: index)
        } else {
            ids.append(dragged.id)
        }
        order = ids
    }

    func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        expandHistory.append(expanded)
    }

    var trailingOffset: CGFloat? {
        guard !isExpanded, let separator = collapsedItems().first(where: { $0.id == Self.separatorID }) else { return nil }
        return separator.trailingOffset
    }

    var collapsedWidth: CGFloat { 16 }
}

@MainActor
struct SeparatorRig {
    let bar: FakeSeparatorBar
    let permission = FakePermission()
    let controller: SeparatorVisibilityController

    init(order: [String]) {
        bar = FakeSeparatorBar(order: order)
        controller = SeparatorVisibilityController(separator: bar, discovery: bar, reorderer: bar, permission: permission, selfBundleID: "me", pause: { _ in })
    }

    /// 허용 목록: 주어진 앱 + 이 앱 자신 + 시스템 프로세스들
    func allow(_ bundleIDs: BundleID..., hidingSystem keys: Set<String> = []) -> Allowlist {
        Allowlist(bundleIDs: bundleIDs + ["me", "com.apple.clock", "com.apple.controlcenter", "com.apple.TextInputMenuAgent"],
                  systemItems: [], hiddenSystemItemKeys: keys)
    }
}

@MainActor
@Suite("구분자 방식의 숨김")
struct SeparatorVisibilityTests {
    @Test("숨길 앱의 아이콘을 구분자 왼쪽으로 옮긴 뒤 구분자를 늘인다")
    func hidesByMovingItemLeft() async throws {
        let rig = SeparatorRig(order: ["me#1", "me#0", "a#0", "b#0", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow("b"))
        #expect(rig.bar.order == ["a#0", "me#1", "me#0", "b#0", "com.apple.clock#0"])
        #expect(rig.bar.dragCount == 1)
        #expect(rig.bar.isExpanded)
        #expect(rig.controller.isRestricted)
        #expect(rig.bar.dragsWhileExpanded == 0)
    }

    @Test("이미 제자리에 있으면 옮기지 않고 구분자만 늘인다")
    func noDragWhenArranged() async throws {
        let rig = SeparatorRig(order: ["a#0", "me#1", "me#0", "b#0", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow("b"))
        #expect(rig.bar.dragCount == 0)
        #expect(rig.bar.expandHistory == [true])
    }

    @Test("숨김 중에 표시할 앱이 숨김 쪽에서 발견되면 잠깐 접고 옮긴 뒤 다시 늘인다")
    func showsItemFoundOnHiddenSide() async throws {
        let rig = SeparatorRig(order: ["a#0", "me#1", "me#0", "b#0", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow("b"))
        // 숨김 중에 새 앱 c 가 실행됐다. 새 아이콘은 가장 왼쪽(숨김 쪽)에 놓인다.
        rig.bar.order.insert("c#0", at: 0)
        try await rig.controller.restrict(to: rig.allow("b", "c"))
        #expect(rig.bar.order == ["a#0", "me#1", "c#0", "me#0", "b#0", "com.apple.clock#0"])
        #expect(rig.bar.expandHistory == [true, false, true])
        #expect(rig.bar.dragsWhileExpanded == 0)
        #expect(rig.bar.isExpanded)
    }

    @Test("펼쳤다가 같은 목록으로 다시 숨길 때는 먼저 늘이고 나서 확인한다")
    func hidesImmediatelyWhenListUnchanged() async throws {
        let rig = SeparatorRig(order: ["a#0", "me#1", "me#0", "b#0", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow("b"))
        rig.controller.unrestrict()
        #expect(!rig.controller.isRestricted)
        try await rig.controller.restrict(to: rig.allow("b"))
        #expect(rig.bar.expandHistory == [true, false, true])
        #expect(rig.bar.dragCount == 0)
    }

    @Test("숨길 앱을 바꾸면 숨김 중에도 새 배치로 맞춘다")
    func rearrangesWhenListChanges() async throws {
        let rig = SeparatorRig(order: ["a#0", "me#1", "me#0", "b#0", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow("b"))
        // 이번에는 a 를 표시하고 b 를 숨긴다.
        try await rig.controller.restrict(to: rig.allow("a"))
        #expect(rig.bar.order == ["b#0", "me#1", "a#0", "me#0", "com.apple.clock#0"])
        #expect(rig.bar.dragCount == 2)
        #expect(rig.bar.isExpanded)
    }

    @Test("여러 아이콘을 옮겨도 서로의 순서는 그대로다")
    func keepsRelativeOrder() async throws {
        let rig = SeparatorRig(order: ["me#1", "me#0", "a#0", "a#1", "a#2", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow())
        #expect(rig.bar.order == ["a#0", "a#1", "a#2", "me#1", "me#0", "com.apple.clock#0"])
        // 다시 표시로 바꾸면 원래 있던 자리로 돌아간다.
        try await rig.controller.restrict(to: rig.allow("a"))
        #expect(rig.bar.order == ["me#1", "me#0", "a#0", "a#1", "a#2", "com.apple.clock#0"])
        #expect(rig.bar.dragCount == 6)
    }

    @Test("여러 개를 숨겼다가 일부만 표시해도 원래 순서대로 놓인다")
    func returnsToPlaceEvenWhenNeighborIsHidden() async throws {
        let rig = SeparatorRig(order: ["me#1", "me#0", "a#0", "b#0", "c#0", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow("c"))
        #expect(rig.bar.order == ["a#0", "b#0", "me#1", "me#0", "c#0", "com.apple.clock#0"])
        // a 만 표시: 원래 오른쪽 이웃 b 는 아직 숨겨져 있으므로, 그다음 이웃 c 의 앞에 놓인다.
        try await rig.controller.restrict(to: rig.allow("a", "c"))
        #expect(rig.bar.order == ["b#0", "me#1", "me#0", "a#0", "c#0", "com.apple.clock#0"])
        // b 도 표시하면 처음 순서로 돌아온다.
        try await rig.controller.restrict(to: rig.allow("a", "b", "c"))
        #expect(rig.bar.order == ["me#1", "me#0", "a#0", "b#0", "c#0", "com.apple.clock#0"])
    }

    @Test("돌려놓는 드래그가 한 번 먹지 않으면 같은 자리로 다시 시도한다")
    func retriesReturningToOriginalPlace() async throws {
        let rig = SeparatorRig(order: ["me#1", "me#0", "x#0", "a#0", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow("x"))
        #expect(rig.bar.order == ["a#0", "me#1", "me#0", "x#0", "com.apple.clock#0"])
        rig.bar.dragsToIgnore = 1
        try await rig.controller.restrict(to: rig.allow("x", "a"))
        #expect(rig.bar.order == ["me#1", "me#0", "x#0", "a#0", "com.apple.clock#0"])
        #expect(rig.bar.dragCount == 3)   // 숨길 때 한 번, 돌려놓을 때 두 번
    }

    @Test("원래 자리로 두 번 해도 안 되면 구분자 바로 오른쪽에 놓는다")
    func fallsBackNextToSeparator() async throws {
        let rig = SeparatorRig(order: ["me#1", "me#0", "x#0", "a#0", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow("x"))
        rig.bar.dragsToIgnore = 2
        try await rig.controller.restrict(to: rig.allow("x", "a"))
        #expect(rig.bar.order == ["me#1", "a#0", "me#0", "x#0", "com.apple.clock#0"])
    }

    @Test("원래 자리를 모르는 아이콘들은 구분자 바로 오른쪽에 순서대로 놓인다")
    func keepsOrderWithoutKnownPlace() async throws {
        // 처음부터 숨김 쪽에 있던 아이콘들 (이 앱이 옮긴 적이 없다)
        let rig = SeparatorRig(order: ["a#0", "a#1", "a#2", "me#1", "me#0", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow("a"))
        #expect(rig.bar.order == ["me#1", "a#0", "a#1", "a#2", "me#0", "com.apple.clock#0"])
    }

    @Test("숨기기로 한 시스템 아이콘을 구분자 왼쪽으로 옮기고, 표시로 바꾸면 원래 자리로 돌려놓는다")
    func hidesSystemItemByKey() async throws {
        let rig = SeparatorRig(order: ["me#1", "me#0", "a#0", "com.apple.TextInputMenuAgent#0", "com.apple.controlcenter#0", "com.apple.controlcenter#1"])
        rig.bar.identifiers = ["com.apple.controlcenter#0": "com.apple.menuextra.battery", "com.apple.controlcenter#1": "com.apple.menuextra.clock"]
        try await rig.controller.restrict(to: rig.allow("a", hidingSystem: ["com.apple.menuextra.battery", "com.apple.TextInputMenuAgent"]))
        #expect(rig.bar.order == ["com.apple.TextInputMenuAgent#0", "com.apple.controlcenter#0", "me#1", "me#0", "a#0", "com.apple.controlcenter#1"])
        #expect(rig.bar.isExpanded)

        // 배터리만 다시 표시: 시계 앞(원래 자리)으로 돌아간다.
        try await rig.controller.restrict(to: rig.allow("a", hidingSystem: ["com.apple.TextInputMenuAgent"]))
        #expect(rig.bar.order == ["com.apple.TextInputMenuAgent#0", "me#1", "me#0", "a#0", "com.apple.controlcenter#0", "com.apple.controlcenter#1"])
        #expect(rig.bar.isExpanded)
    }

    @Test("시계와 제어 센터는 숨기기로 해도 옮기지 않는다")
    func neverMovesClockOrControlCenter() async throws {
        let rig = SeparatorRig(order: ["me#1", "me#0", "com.apple.controlcenter#0", "com.apple.controlcenter#1"])
        rig.bar.identifiers = ["com.apple.controlcenter#0": "com.apple.menuextra.controlcenter", "com.apple.controlcenter#1": "com.apple.menuextra.clock"]
        try await rig.controller.restrict(to: rig.allow(hidingSystem: ["com.apple.menuextra.controlcenter", "com.apple.menuextra.clock"]))
        #expect(rig.bar.dragCount == 0)
        #expect(rig.bar.isExpanded)
    }

    @Test("시스템 아이콘을 숨기기로 한 것만 바뀌어도 숨김 중에 바로 반영한다")
    func appliesSystemKeyChangeWhileHidden() async throws {
        let rig = SeparatorRig(order: ["me#1", "me#0", "com.apple.TextInputMenuAgent#0", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow())
        #expect(rig.bar.dragCount == 0)
        try await rig.controller.restrict(to: rig.allow(hidingSystem: ["com.apple.TextInputMenuAgent"]))
        #expect(rig.bar.order == ["com.apple.TextInputMenuAgent#0", "me#1", "me#0", "com.apple.clock#0"])
        #expect(rig.bar.expandHistory == [true, false, true])
    }

    @Test("이 앱의 아이콘이 숨김 쪽에 있으면 표시 쪽으로 옮긴다")
    func movesOwnIconOut() async throws {
        let rig = SeparatorRig(order: ["me#0", "me#1", "a#0", "com.apple.clock#0"])
        try await rig.controller.restrict(to: rig.allow("a"))
        #expect(rig.bar.order == ["me#1", "me#0", "a#0", "com.apple.clock#0"])
        #expect(rig.bar.isExpanded)
    }

    @Test("자기 아이콘을 표시 쪽으로 옮기지 못하면 숨기지 않는다")
    func failsOpenWhenOwnIconStaysHidden() async {
        let rig = SeparatorRig(order: ["me#0", "me#1", "a#0", "com.apple.clock#0"])
        rig.bar.stuck = ["me#0"]
        await #expect(throws: VisibilityError.activationFailed) { try await rig.controller.restrict(to: rig.allow("a")) }
        #expect(!rig.bar.isExpanded)
        // 다시 시도해도 마찬가지다 (포기한 아이템이라고 건너뛰어 숨겨 버리지 않는다).
        await #expect(throws: VisibilityError.activationFailed) { try await rig.controller.restrict(to: rig.allow("a")) }
        #expect(!rig.bar.isExpanded)
    }

    @Test("옮겨지지 않는 아이콘은 세 번 해 보고 포기하되, 나머지는 숨긴다")
    func givesUpOnStuckItem() async throws {
        let rig = SeparatorRig(order: ["me#1", "me#0", "a#0", "b#0", "com.apple.clock#0"])
        rig.bar.stuck = ["a#0"]
        try await rig.controller.restrict(to: rig.allow())
        #expect(rig.bar.order == ["b#0", "me#1", "me#0", "a#0", "com.apple.clock#0"])
        #expect(rig.bar.dragCount == 4)   // a 세 번, b 한 번
        #expect(rig.bar.isExpanded)
        // 다음에 숨길 때는 포기한 아이콘을 다시 건드리지 않는다 (메뉴바가 매번 깜빡이지 않도록).
        rig.controller.unrestrict()
        try await rig.controller.restrict(to: rig.allow())
        #expect(rig.bar.dragCount == 4)
    }

    @Test("숨기기로 하지 않은 시스템 아이콘이 숨김 쪽에 있으면 표시 쪽으로 옮긴다")
    func showsSystemItemFoundOnHiddenSide() async throws {
        let rig = SeparatorRig(order: ["com.apple.TextInputMenuAgent#0", "me#1", "me#0", "a#0"])
        try await rig.controller.restrict(to: rig.allow("a"))
        #expect(rig.bar.order == ["me#1", "com.apple.TextInputMenuAgent#0", "me#0", "a#0"])
        #expect(rig.bar.isExpanded)
    }

    @Test("접근성 권한이 없으면 숨기지 않는다")
    func requiresPermission() async {
        let rig = SeparatorRig(order: ["me#1", "me#0", "a#0"])
        rig.permission.isAccessibilityGranted = false
        await #expect(throws: VisibilityError.accessibilityRequired) { try await rig.controller.restrict(to: rig.allow()) }
        #expect(!rig.bar.isExpanded)
        #expect(rig.bar.dragCount == 0)
    }

    @Test("아이콘을 옮기는 도중에 펼치면 구분자를 다시 늘이지 않는다")
    func doesNotExpandAfterBeingCancelled() async {
        let rig = SeparatorRig(order: ["me#1", "me#0", "a#0", "b#0", "com.apple.clock#0"])
        rig.bar.beforeNextDrag = { rig.controller.unrestrict() }
        await #expect(throws: (any Error).self) { try await rig.controller.restrict(to: rig.allow()) }
        #expect(!rig.bar.isExpanded)
        #expect(rig.bar.dragCount == 1)
    }

    @Test("구분자는 순서 편집 목록에서 빼도록 알아볼 수 있다")
    func identifiesSeparator() async throws {
        let rig = SeparatorRig(order: ["a#0", "me#1", "me#0", "com.apple.clock#0"])
        let items = try await rig.bar.currentItems(fullScan: true)
        #expect(items.filter { rig.controller.isOwnSeparator($0) }.map(\.id) == ["me#1"])
    }

    @Test("이 방식은 접근성 권한이 필요하고, 시스템 아이콘은 메뉴바에서 읽은 것을 숨긴다")
    func traits() {
        let rig = SeparatorRig(order: ["me#1", "me#0"])
        #expect(rig.controller.traits == .separator)
        #expect(rig.controller.traits.requiresAccessibility)
        #expect(rig.controller.traits.supportsSystemItems)
        #expect(rig.controller.traits.discoversSystemItems)
        #expect(!VisibilityTraits.allowlist.discoversSystemItems)
        #expect(!rig.controller.traits.blocksNotificationCenter)
    }
}
