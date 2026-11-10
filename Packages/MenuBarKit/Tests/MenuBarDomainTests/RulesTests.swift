import Foundation
import Testing
@testable import MenuBarDomain

@Suite("허용 목록 계산")
struct AllowlistBuilderTests {
    @Test("숨길 앱은 빠지고 나머지는 순서대로 남는다")
    func excludesHidden() {
        let list = AllowlistBuilder.build(known: ["a", "b", "c"], hidden: ["b"], selfID: "me")
        #expect(list.bundleIDs == ["a", "c", "me"])
    }

    @Test("자기 자신은 숨길 목록에 있어도 항상 허용된다")
    func alwaysAllowsSelf() {
        let list = AllowlistBuilder.build(known: ["a", "me"], hidden: ["me", "a"], selfID: "me")
        #expect(list.bundleIDs == ["me"])
    }

    @Test("중복과 빈 문자열을 제거한다")
    func deduplicates() {
        let list = AllowlistBuilder.build(known: ["a", "", "a", "b"], hidden: [], selfID: "b")
        #expect(list.bundleIDs == ["a", "b"])
    }

    @Test("시스템 아이템은 기본으로 0...255 전체를 허용한다")
    func allowsAllSystemItemsByDefault() {
        let list = AllowlistBuilder.build(known: [], hidden: [], selfID: "me")
        #expect(list.systemItems.count == 256)
        #expect(list.systemItems.first == 0 && list.systemItems.last == 255)
    }
}

@Suite("앱 목록 필터")
struct AppListFilterTests {
    let apps = [
        ManagedApp(bundleID: "com.b", name: "Bravo", isRunning: true),
        ManagedApp(bundleID: "com.a", name: "alpha", isRunning: false),
        ManagedApp(bundleID: "com.c", name: "Charlie", isRunning: true),
    ]

    @Test("실행 중 필터는 실행 중인 앱만, 이름순으로")
    func runningFilter() {
        let out = AppListFilter.apply(apps, filter: .running, query: "", hidden: [])
        #expect(out.map(\.name) == ["Bravo", "Charlie"])
    }

    @Test("숨긴 앱 필터")
    func hiddenFilter() {
        let out = AppListFilter.apply(apps, filter: .hidden, query: "", hidden: ["com.a"])
        #expect(out.map(\.bundleID) == ["com.a"])
    }

    @Test("전체 필터는 대소문자 구분 없이 이름순")
    func allFilterSorted() {
        let out = AppListFilter.apply(apps, filter: .all, query: "", hidden: [])
        #expect(out.map(\.name) == ["alpha", "Bravo", "Charlie"])
    }

    @Test("검색어가 있으면 필터와 무관하게 전체에서 찾는다")
    func queryOverridesFilter() {
        let out = AppListFilter.apply(apps, filter: .running, query: " ALP ", hidden: [])
        #expect(out.map(\.name) == ["alpha"])
    }

    @Test("번들 ID 로도 검색된다")
    func queryMatchesBundleID() {
        let out = AppListFilter.apply(apps, filter: .all, query: "com.c", hidden: [])
        #expect(out.map(\.name) == ["Charlie"])
    }

    @Test("스위치 상태: 보호 대상은 항상 켜짐, 폴더 밖 앱은 항상 꺼짐")
    func shownState() {
        let me = ManagedApp(bundleID: "me", name: "Me", constraint: .protected)
        let outside = ManagedApp(bundleID: "out", name: "Out", constraint: .outsideApplications)
        let normal = ManagedApp(bundleID: "n", name: "N")
        #expect(AppListFilter.isShown(me, hidden: ["me"]))
        #expect(!AppListFilter.isShown(outside, hidden: []))
        #expect(AppListFilter.isShown(normal, hidden: []))
        #expect(!AppListFilter.isShown(normal, hidden: ["n"]))
    }
}

@Suite("새 앱 처리")
struct NewAppRuleTests {
    @Test("첫 실행에는 지금 있는 앱을 기록만 하고 숨기지 않는다")
    func firstRunOnlyRecords() {
        let layout = Layout(newAppPolicy: .hide)
        let out = NewAppRule.absorb(["a", "b"], into: layout, selfID: "me")
        #expect(out.hiddenApps.isEmpty)
        #expect(out.knownApps == ["a", "b"])
    }

    @Test("정책이 숨김이면 새 앱을 숨길 앱에 추가한다")
    func hidePolicyHidesNewcomers() {
        let layout = Layout(knownApps: ["a"], newAppPolicy: .hide)
        let out = NewAppRule.absorb(["a", "new", "me"], into: layout, selfID: "me")
        #expect(out.hiddenApps == ["new"])
        #expect(out.knownApps == ["a", "new", "me"])
    }

    @Test("정책이 표시이면 기록만 한다")
    func showPolicyKeepsVisible() {
        let layout = Layout(knownApps: ["a"], newAppPolicy: .show)
        let out = NewAppRule.absorb(["a", "new"], into: layout, selfID: "me")
        #expect(out.hiddenApps.isEmpty)
        #expect(out.knownApps == ["a", "new"])
    }

    @Test("새 앱이 없으면 그대로다")
    func noChangeWithoutNewcomers() {
        let layout = Layout(hiddenApps: ["a"], knownApps: ["a", "b"], newAppPolicy: .hide)
        #expect(NewAppRule.absorb(["a", "b"], into: layout, selfID: "me") == layout)
    }

    @Test("이전 버전이 저장한 파일도 읽는다")
    func decodesOldFormat() throws {
        let json = #"{"schemaVersion":1,"layout":{"hiddenApps":["x"]},"options":{"autoRehide":true,"autoRehideSeconds":10,"hidingEnabled":false}}"#
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        #expect(state.layout.hiddenApps == ["x"])
        #expect(state.layout.newAppPolicy == .show)
        #expect(state.options.didShowWelcome == false)
    }
}

@Suite("이동 계획")
struct MovePlannerTests {
    @Test("이미 같은 순서면 이동이 없다")
    func noMovesWhenEqual() {
        #expect(MovePlanner.plan(current: ["a", "b", "c"], target: ["a", "b", "c"]).isEmpty)
    }

    @Test("하나만 옮기면 되는 경우 이동은 한 번이다")
    func singleMove() {
        let moves = MovePlanner.plan(current: ["a", "b", "c", "d"], target: ["b", "c", "d", "a"])
        #expect(moves == [Move(item: "a", before: nil)])
    }

    @Test("맨 뒤 아이템을 맨 앞으로")
    func moveLastToFront() {
        let moves = MovePlanner.plan(current: ["a", "b", "c"], target: ["c", "a", "b"])
        #expect(moves == [Move(item: "c", before: "a")])
    }

    @Test("이동을 적용하면 목표 순서가 되고, 횟수는 최소다", arguments: [
        (["a", "b", "c", "d", "e"], ["e", "d", "c", "b", "a"], 4),
        (["a", "b", "c", "d", "e"], ["b", "a", "d", "c", "e"], 2),
        (["a", "b", "c", "d", "e", "f"], ["a", "c", "e", "b", "d", "f"], 2),
        (["x"], ["x"], 0),
    ])
    func reachesTargetWithMinimalMoves(current: [String], target: [String], expectedCount: Int) {
        let moves = MovePlanner.plan(current: current, target: target)
        #expect(MovePlanner.apply(moves, to: current) == target)
        #expect(moves.count == expectedCount)
    }

    @Test("한쪽에만 있는 아이템은 무시한다")
    func ignoresUnknownItems() {
        let moves = MovePlanner.plan(current: ["a", "b", "c"], target: ["c", "zzz", "a", "b"])
        #expect(MovePlanner.apply(moves, to: ["a", "b", "c"]) == ["c", "a", "b"])
    }

    @Test("무작위 순서 200개에서도 목표에 도달한다")
    func randomizedOrders() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let count = Int.random(in: 2...12, using: &generator)
            let current = (0..<count).map { "i\($0)" }
            let target = current.shuffled(using: &generator)
            let moves = MovePlanner.plan(current: current, target: target)
            #expect(MovePlanner.apply(moves, to: current) == target)
            #expect(moves.count < count)
        }
    }
}

@Suite("이동 계획 — 고정 아이템")
struct MovePlannerFixedTests {
    @Test("고정 아이템은 옮기지 않고, 그 대신 다른 아이템을 옮긴다")
    func neverMovesFixedItems() {
        // sys 를 왼쪽으로 옮기는 편이 한 번으로 끝나지만, 고정이므로 a 와 b 를 옮겨야 한다.
        let current = ["a", "b", "sys", "c"]
        let target = ["sys", "a", "b", "c"]
        let moves = MovePlanner.plan(current: current, target: target, fixed: ["sys"])
        #expect(!moves.contains { $0.item == "sys" })
        #expect(MovePlanner.apply(moves, to: current) == target)
    }

    @Test("고정 아이템 사이로 옮기기")
    func movesBetweenFixedItems() {
        let current = ["app", "s1", "s2", "s3"]
        let target = ["s1", "app", "s2", "s3"]
        let moves = MovePlanner.plan(current: current, target: target, fixed: ["s1", "s2", "s3"])
        #expect(moves == [Move(item: "app", before: "s2")])
    }

    @Test("무작위 순서에서도 고정 아이템은 그대로 두고 목표에 도달한다")
    func randomizedWithFixed() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let apps = (0..<Int.random(in: 1...7, using: &generator)).map { "app\($0)" }
            let system = (0..<Int.random(in: 1...5, using: &generator)).map { "sys\($0)" }
            // 시스템 아이템의 상대 순서는 유지하고 앱만 사이사이에 끼운다.
            func interleave() -> [String] {
                var result = system
                for app in apps.shuffled(using: &generator) { result.insert(app, at: Int.random(in: 0...result.count, using: &generator)) }
                return result
            }
            let current = interleave(), target = interleave()
            let moves = MovePlanner.plan(current: current, target: target, fixed: Set(system))
            #expect(!moves.contains { system.contains($0.item) })
            #expect(MovePlanner.apply(moves, to: current) == target)
        }
    }
}

@Suite("메뉴바 앱 필터")
struct MenuBarFilterTests {
    let apps = [
        ManagedApp(bundleID: "com.a", name: "A", isRunning: true),
        ManagedApp(bundleID: "com.b", name: "B", isRunning: true),
        ManagedApp(bundleID: "com.c", name: "C", isRunning: false),
    ]

    @Test("메뉴바 아이콘을 가진 앱만 남긴다 (실행 중이 아니어도)")
    func keepsOnlyMenuBarApps() {
        let out = AppListFilter.apply(apps, filter: .menuBar, query: "", hidden: [], menuBarApps: ["com.b", "com.c"])
        #expect(out.map(\.bundleID) == ["com.b", "com.c"])
    }

    @Test("어떤 앱이 아이콘을 가졌는지 모르면 실행 중인 앱으로 대신한다")
    func fallsBackToRunning() {
        let out = AppListFilter.apply(apps, filter: .menuBar, query: "", hidden: [], menuBarApps: nil)
        #expect(out.map(\.bundleID) == ["com.a", "com.b"])
    }
}
