import CoreGraphics
import Foundation
import Testing
@testable import MenuBarDomain

/// 1000pt 폭 화면에 놓인 아이템 하나. `offset` 은 화면 오른쪽 끝에서 왼쪽 가장자리까지의 거리.
private func item(_ bundleID: String, offset: CGFloat, width: CGFloat = 30, index: Int = 0) -> MenuBarItem {
    MenuBarItem(bundleID: bundleID, appName: bundleID, index: index, title: nil,
                frame: CGRect(x: 1000 - offset, y: 4, width: width, height: 24), screenMaxX: 1000)
}

@Suite("구분자 방식의 배치 계산")
struct SeparatorPlannerTests {
    // 왼쪽 → 오른쪽: a · [구분자 offset 200] · 나 · b · 시계
    private let a = item("com.a", offset: 230)
    private let separator = item("me", offset: 201, width: 18, index: 1)   // 접근성 좌표는 창 좌표와 1~2pt 다르다
    private let me = item("me", offset: 184)
    private let b = item("com.b", offset: 154)
    private let clock = item("com.apple.controlcenter", offset: 124, width: 120)

    @Test("자기 아이템 중 구분자와 같은 자리에 있는 것이 구분자다")
    func recognizesSeparator() {
        #expect(SeparatorPlanner.isSeparator(separator, selfID: "me", separatorOffset: 200))
        #expect(!SeparatorPlanner.isSeparator(me, selfID: "me", separatorOffset: 200))
        #expect(!SeparatorPlanner.isSeparator(a, selfID: "me", separatorOffset: 230))
    }

    @Test("아주 넓은 자기 아이템은 늘여 놓은 구분자다")
    func recognizesExpandedSeparator() {
        let wide = MenuBarItem(bundleID: "me", appName: "me", index: 1, title: nil, frame: CGRect(x: -3654, y: 4, width: 5002, height: 24), screenMaxX: 1348)
        #expect(SeparatorPlanner.isSeparator(wide, selfID: "me", separatorOffset: nil))
        #expect(!SeparatorPlanner.isSeparator(me, selfID: "me", separatorOffset: nil))
    }

    @Test("접혀 있을 때는 구분자보다 왼쪽이 숨김 쪽이고, 구분자 자신은 뺀다")
    func placesByPosition() {
        let placed = SeparatorPlanner.placements(collapsed: [a, separator, me, b, clock], selfID: "me", separatorOffset: 200)
        #expect(placed.map(\.item.id) == ["com.a#0", "me#0", "com.b#0", "com.apple.controlcenter#0"])
        #expect(placed.map(\.side) == [.hidden, .shown, .shown, .shown])
    }

    @Test("늘여 놓았을 때는 보이는 것이 표시 쪽, 화면 밖으로 밀린 것이 숨김 쪽이다")
    func placesByVisibility() {
        let pushed = MenuBarItem(bundleID: "com.a", appName: "a", index: 0, title: nil, frame: CGRect(x: -3691, y: 4, width: 30, height: 24), screenMaxX: -3661)
        let snapshot = MenuBarSnapshot(visible: [me, b, clock], offscreen: [pushed])
        let placed = SeparatorPlanner.placements(expanded: snapshot, selfID: "me")
        #expect(placed.map(\.side) == [.hidden, .shown, .shown, .shown])
    }

    @Test("숨길 앱이 표시 쪽에 있거나 표시할 앱이 숨김 쪽에 있으면 옮긴다")
    func findsMisplacedItems() {
        let placed = SeparatorPlanner.placements(collapsed: [a, separator, me, b, clock], selfID: "me", separatorOffset: 200)
        // a 는 표시해야 하는데 숨김 쪽에, b 는 숨겨야 하는데 표시 쪽에 있다.
        let moves = SeparatorPlanner.relocations(placed, allowed: ["com.a", "com.apple.controlcenter"], selfID: "me")
        #expect(moves == [.init(item: a, to: .shown), .init(item: b, to: .hidden)])
    }

    @Test("제자리에 있으면 옮길 것이 없다")
    func nothingToMoveWhenArranged() {
        let placed = SeparatorPlanner.placements(collapsed: [a, separator, me, b, clock], selfID: "me", separatorOffset: 200)
        #expect(SeparatorPlanner.relocations(placed, allowed: ["com.b", "com.apple.controlcenter"], selfID: "me").isEmpty)
    }

    @Test("이 앱 자신은 허용 목록에 없어도 표시 쪽으로 옮긴다")
    func ownIconAlwaysShown() {
        let hiddenSelf = item("me", offset: 260)
        let placed = SeparatorPlanner.placements(collapsed: [hiddenSelf, a, separator, b], selfID: "me", separatorOffset: 200)
        let moves = SeparatorPlanner.relocations(placed, allowed: ["com.a", "com.b"], selfID: "me")
        #expect(moves.contains(.init(item: hiddenSelf, to: .shown)))
    }

    @Test("시스템 아이템과 포기한 아이템은 옮기지 않는다")
    func skipsSystemAndUnmovable() {
        let hiddenSystem = item("com.apple.systemuiserver", offset: 260)
        let placed = SeparatorPlanner.placements(collapsed: [hiddenSystem, a, separator, b], selfID: "me", separatorOffset: 200)
        let moves = SeparatorPlanner.relocations(placed, allowed: ["com.apple.systemuiserver", "com.a"], selfID: "me", skipping: ["com.b#0"])
        #expect(moves == [.init(item: a, to: .shown)])
    }

    @Test("숨길 때는 구분자 왼쪽 가장자리의 바로 왼쪽에 놓는다")
    func dropPointForHiding() {
        let placed = SeparatorPlanner.placements(collapsed: [a, separator, me, b, clock], selfID: "me", separatorOffset: 200)
        let x = SeparatorPlanner.dropX(for: .init(item: b, to: .hidden), placements: placed, separatorOffset: 200, separatorWidth: 16)
        #expect(x == CGFloat(794))
        // 첫 시도가 먹지 않았으면 조금 더 왼쪽에 놓는다.
        let retry = SeparatorPlanner.dropX(for: .init(item: b, to: .hidden), placements: placed, separatorOffset: 200, separatorWidth: 16, alternate: true)
        #expect(retry < x)
    }

    @Test("표시할 때는 구분자 바로 오른쪽 아이템의 앞에 놓는다")
    func dropPointForShowing() {
        let placed = SeparatorPlanner.placements(collapsed: [a, separator, me, b, clock], selfID: "me", separatorOffset: 200)
        // 표시 쪽에서 가장 왼쪽은 `me` (왼쪽 가장자리 x = 816)
        let x = SeparatorPlanner.dropX(for: .init(item: a, to: .shown), placements: placed, separatorOffset: 200, separatorWidth: 16)
        #expect(x == CGFloat(812))   // 구분자(폭 16)의 오른쪽 절반 안
    }

    @Test("표시 쪽에 아무것도 없으면 구분자 오른쪽 가장자리의 바로 오른쪽에 놓는다")
    func dropPointWithoutAnchor() {
        let placed = SeparatorPlanner.placements(collapsed: [a, separator], selfID: "me", separatorOffset: 200)
        let x = SeparatorPlanner.dropX(for: .init(item: a, to: .shown), placements: placed, separatorOffset: 200, separatorWidth: 16)
        #expect(x == CGFloat(822))
    }
}
