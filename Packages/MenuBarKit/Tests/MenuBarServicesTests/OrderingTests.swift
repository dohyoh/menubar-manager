import CoreGraphics
import Foundation
import Testing
import MenuBarDomain
@testable import MenuBarServices

/// 가짜 메뉴바: 아이템을 오른쪽 정렬로 30pt 간격으로 늘어놓는다.
/// `secondScreenItems` 에 든 아이템은 두 번째 모니터(왼쪽, x 가 음수) 기준 좌표로 보고한다 —
/// 실제 macOS 에서 모니터가 두 대일 때 벌어지는 일을 흉내 낸다.
@MainActor
final class FakeBar: ItemDiscovering, ItemReordering {
    var order: [String]                     // "번들ID#0"
    var secondScreenItems: Set<String> = []
    var readCount = 0
    var dragCount = 0
    /// true 면 드래그가 먹지 않는다 (순서가 그대로)
    var ignoresDrags = false
    var visibleDuringReads: [Bool] = []
    private let visibility: FakeVisibility

    private static let mainMaxX: CGFloat = 1728
    private static let secondMaxX: CGFloat = 0

    init(order: [String], visibility: FakeVisibility) {
        self.order = order
        self.visibility = visibility
    }

    private func items() -> [MenuBarItem] {
        order.enumerated().map { index, id in
            let bundleID = String(id.split(separator: "#")[0])
            let onSecond = secondScreenItems.contains(id)
            let maxX = onSecond ? Self.secondMaxX : Self.mainMaxX
            let offset = CGFloat((order.count - index) * 30)
            let frame = CGRect(x: maxX - offset, y: onSecond ? -319 : 4, width: 24, height: 24)
            return MenuBarItem(bundleID: bundleID, appName: bundleID, index: 0, title: nil, frame: frame, screenMaxX: maxX)
        }
    }

    var owners: Set<BundleID> = []
    func appsOwningItems() async throws -> Set<BundleID> { owners }

    func currentItems(fullScan: Bool) async throws -> [MenuBarItem] {
        readCount += 1
        visibleDuringReads.append(!visibility.isRestricted)
        return MenuBarItem.sortedLeftToRight(items())
    }

    func commandDrag(from start: CGPoint, to end: CGPoint) async throws {
        dragCount += 1
        guard !ignoresDrags else { return }
        let current = items()
        guard let dragged = current.first(where: { $0.frame.contains(start) }) else { return }
        // 놓은 지점을 "모니터 오른쪽 끝에서의 거리"로 바꿔, 그보다 오른쪽에 있는 첫 아이템 앞에 끼운다.
        let dropOffset = dragged.screenMaxX - end.x
        var ids = order.filter { $0 != dragged.id }
        if let anchor = current.first(where: { $0.id != dragged.id && $0.trailingOffset < dropOffset }), let index = ids.firstIndex(of: anchor.id) {
            ids.insert(dragged.id, at: index)
        } else {
            ids.append(dragged.id)
        }
        order = ids
    }
}

@MainActor
final class FakePermission: PermissionChecking {
    var isAccessibilityGranted = true
    var requestCount = 0
    func requestAccessibility() { requestCount += 1 }
}

@MainActor
struct OrderingRig {
    let rig: Rig
    let bar: FakeBar
    let permission = FakePermission()
    let ordering: OrderingController

    init(order: [String], hidingEnabled: Bool = true) {
        rig = Rig(hidingEnabled: hidingEnabled)
        bar = FakeBar(order: order, visibility: rig.visibility)
        ordering = OrderingController(coordinator: rig.coordinator, permission: permission, discovery: bar, reorderer: bar, pause: { _ in })
    }
}

@MainActor
@Suite("순서 조정")
struct OrderingTests {
    @Test("읽는 동안 전부 펼쳤다가, 끝나면 다시 숨긴다")
    func readExpandsThenRestores() async {
        let o = OrderingRig(order: ["a#0", "b#0", "com.apple.clock#0"])
        await o.rig.coordinator.start()
        await o.ordering.read()
        #expect(o.ordering.items.map(\.id) == ["a#0", "b#0", "com.apple.clock#0"])
        #expect(o.bar.visibleDuringReads == [true])
        #expect(o.rig.coordinator.state == .collapsed)
        #expect(o.ordering.status == .idle)
    }

    @Test("숨기기가 꺼져 있었으면 끝난 뒤에도 꺼진 채로 둔다")
    func readKeepsPausedState() async {
        let o = OrderingRig(order: ["a#0", "b#0"], hidingEnabled: false)
        await o.rig.coordinator.start()
        await o.ordering.read()
        #expect(o.rig.coordinator.state == .paused(.userOff))
        #expect(o.rig.visibility.restrictCalls.isEmpty)
    }

    @Test("목표 순서가 되도록 옮기고, 시스템 아이템은 옮기지 않는다")
    func appliesTargetOrder() async {
        let o = OrderingRig(order: ["a#0", "b#0", "com.apple.wifi#0", "c#0", "com.apple.clock#0"])
        await o.rig.coordinator.start()
        let target = ["c#0", "com.apple.wifi#0", "b#0", "a#0", "com.apple.clock#0"]
        await o.ordering.apply(target: target)
        #expect(o.bar.order == target)
        #expect(o.ordering.status == .succeeded)
        #expect(o.ordering.items.map(\.id) == target)
        #expect(o.rig.coordinator.state == .collapsed)
    }

    @Test("이미 같은 순서면 드래그하지 않는다")
    func noDragWhenAlreadyInOrder() async {
        let o = OrderingRig(order: ["a#0", "b#0"])
        await o.rig.coordinator.start()
        await o.ordering.apply(target: ["a#0", "b#0"])
        #expect(o.bar.dragCount == 0)
        #expect(o.ordering.status == .succeeded)
    }

    @Test("드래그가 먹지 않으면 두 번 시도한 뒤 실패로 끝내고, 숨김 상태는 되돌린다")
    func failsWhenStuck() async {
        let o = OrderingRig(order: ["a#0", "b#0", "c#0"])
        o.bar.ignoresDrags = true
        await o.rig.coordinator.start()
        await o.ordering.apply(target: ["c#0", "a#0", "b#0"])
        #expect(o.ordering.status == .failed(.stuck))
        #expect(o.bar.dragCount == 2)
        #expect(o.rig.coordinator.state == .collapsed)
    }

    @Test("접근성 권한이 없으면 아무것도 하지 않는다")
    func requiresPermission() async {
        let o = OrderingRig(order: ["a#0", "b#0"])
        o.permission.isAccessibilityGranted = false
        await o.rig.coordinator.start()
        await o.ordering.read()
        #expect(o.ordering.status == .failed(.accessibilityNotGranted))
        #expect(o.bar.readCount == 0)
        #expect(o.rig.coordinator.state == .collapsed)
    }

    @Test("순서 작업 중에는 좌클릭과 스위치를 무시한다")
    func ignoresToggleWhileReordering() async throws {
        let o = OrderingRig(order: ["a#0"])
        await o.rig.coordinator.start()
        try await o.rig.coordinator.withEverythingVisible {
            #expect(o.rig.coordinator.state == .reordering)
            await o.rig.coordinator.toggle()
            await o.rig.coordinator.setHidingEnabled(false)
            #expect(o.rig.coordinator.state == .reordering)
        }
        #expect(o.rig.coordinator.state == .collapsed)
    }
}

@MainActor
@Suite("모니터가 두 대일 때")
struct MultiDisplayOrderingTests {
    @Test("아이템마다 좌표의 기준 모니터가 달라도 순서를 올바르게 읽는다")
    func readsOrderAcrossDisplays() async {
        let o = OrderingRig(order: ["a#0", "b#0", "c#0", "com.apple.clock#0"])
        o.bar.secondScreenItems = ["b#0", "com.apple.clock#0"]
        await o.rig.coordinator.start()
        await o.ordering.read()
        #expect(o.ordering.items.map(\.id) == ["a#0", "b#0", "c#0", "com.apple.clock#0"])
    }

    @Test("옮길 아이템과 목적지 아이템의 기준 모니터가 달라도 올바른 자리로 옮긴다")
    func movesAcrossDisplays() async {
        let o = OrderingRig(order: ["a#0", "b#0", "com.apple.wifi#0", "c#0", "com.apple.clock#0"])
        o.bar.secondScreenItems = ["a#0", "com.apple.wifi#0"]
        await o.rig.coordinator.start()
        let target = ["c#0", "b#0", "com.apple.wifi#0", "a#0", "com.apple.clock#0"]
        await o.ordering.apply(target: target)
        #expect(o.bar.order == target)
        #expect(o.ordering.status == .succeeded)
    }
}
