import CoreGraphics
import Foundation
import MenuBarDomain

/// 구분자 확장 방식의 숨김 (macOS 26 이하). (docs/adr/0012-separator-visibility-macos26.md)
///
/// - 숨기기·펼치기는 구분자의 길이만 바꾼다. 포인터를 움직이지 않고 바로 반영된다.
/// - 숨길 앱의 아이콘이 구분자 오른쪽에 있거나 표시할 앱의 아이콘이 왼쪽에 있으면,
///   잠깐 접어 전부 보이게 한 뒤 ⌘+드래그를 대신 수행해 옮기고 다시 늘인다.
/// - 프로세스가 끝나면 구분자가 사라지므로, 어떤 경우에도 전부 표시로 돌아간다 (검증됨, platform-notes 7.4).
///
/// 어느 아이콘이 어느 앱의 것인지 알아내고 옮기는 데 접근성 권한이 필요하다.
@MainActor
public final class SeparatorVisibilityController: VisibilityControlling {
    private let separator: any SeparatorItemControlling
    private let discovery: any ItemDiscovering
    private let reorderer: any ItemReordering
    private let permission: any PermissionChecking
    private let selfBundleID: BundleID
    private let pause: @MainActor (Int) async -> Void

    /// 구분자를 접거나 아이콘을 옮긴 뒤 메뉴바가 자리 잡기를 기다리는 시간(ms)
    public static let settleMilliseconds = 600
    /// 구분자를 늘인 뒤 기다리는 시간(ms)
    public static let expandSettleMilliseconds = 300
    /// 한 아이콘을 옮겨 보는 횟수. 이만큼 해도 그대로면 그 아이콘은 포기한다.
    static let attemptsPerItem = 2
    /// 한 번 적용할 때 옮기는 횟수의 상한 (끝나지 않는 일을 막는다)
    static let maximumMoves = 40

    /// 진행 중인 적용이 뒤따른 조작(펼치기, 새 적용)에 밀려났는지 판별한다.
    private var generation = 0
    /// 진행 중인 적용. 다음 적용은 이것이 물러난 뒤에 시작한다 (드래그가 겹치지 않도록).
    private var running: Task<Void, Error>?
    /// 마지막으로 배치를 맞춘 허용 목록. 같으면 먼저 숨기고 나서 확인한다.
    private var lastArranged: Set<BundleID>?
    /// 옮겨지지 않아 포기한 아이템. 숨길 때마다 다시 시도해 메뉴바가 깜빡이지 않게 한다.
    private var unmovable: Set<MenuBarItem.ID> = []

    public init(
        separator: any SeparatorItemControlling,
        discovery: any ItemDiscovering,
        reorderer: any ItemReordering,
        permission: any PermissionChecking,
        selfBundleID: BundleID,
        pause: @escaping @MainActor (Int) async -> Void = { try? await Task.sleep(for: .milliseconds($0)) }
    ) {
        self.separator = separator
        self.discovery = discovery
        self.reorderer = reorderer
        self.permission = permission
        self.selfBundleID = selfBundleID
        self.pause = pause
    }

    public var isSupported: Bool { true }
    public var isRestricted: Bool { separator.isExpanded }
    public var traits: VisibilityTraits { .separator }

    public func isOwnSeparator(_ item: MenuBarItem) -> Bool {
        SeparatorPlanner.isSeparator(item, selfID: selfBundleID, separatorOffset: separator.trailingOffset)
    }

    public func restrict(to allowlist: Allowlist) async throws {
        guard permission.isAccessibilityGranted else { throw VisibilityError.accessibilityRequired }
        generation += 1
        let mine = generation
        let previous = running
        let task = Task { [weak self] in
            // 앞선 적용은 세대가 바뀐 것을 보고 곧 물러난다.
            _ = await previous?.result
            guard let self else { return }
            try await self.apply(Set(allowlist.bundleIDs), generation: mine)
        }
        running = task
        try await task.value
    }

    public func unrestrict() {
        generation += 1
        separator.setExpanded(false)
    }

    // MARK: 내부

    private struct Superseded: Error {}

    private func checkCurrent(_ mine: Int) throws {
        if mine != generation { throw Superseded() }
    }

    private func apply(_ allowed: Set<BundleID>, generation mine: Int) async throws {
        try checkCurrent(mine)
        // 지난번에 맞춰 둔 목록 그대로면 먼저 숨긴다 — 좌클릭으로 숨길 때 바로 반영되도록. 배치는 그 뒤에 확인한다.
        if !separator.isExpanded, allowed == lastArranged {
            separator.setExpanded(true)
            await pause(Self.expandSettleMilliseconds)
            try checkCurrent(mine)
        }

        // 새로 실행된 앱의 아이콘도 봐야 하므로 전체를 훑는다.
        var placements = try await readPlacements(fullScan: true)
        try checkCurrent(mine)
        if !SeparatorPlanner.relocations(placements, allowed: allowed, selfID: selfBundleID, skipping: unmovable).isEmpty,
           try await arrange(allowed: allowed, generation: mine) {
            // 옮긴 뒤의 실제 배치를 다시 읽는다.
            placements = try await readPlacements(fullScan: false)
            try checkCurrent(mine)
        }

        // 자기 아이콘이 숨김 쪽에 있으면(옮기지 못했으면) 숨기지 않는다 — 숨기면 이 앱을 다룰 수단이 사라진다 (fail-open).
        if placements.contains(where: { $0.item.bundleID == selfBundleID && $0.side == .hidden }) {
            separator.setExpanded(false)
            throw VisibilityError.activationFailed
        }

        if !separator.isExpanded {
            separator.setExpanded(true)
            await pause(Self.expandSettleMilliseconds)
            try checkCurrent(mine)
        }
        lastArranged = allowed
    }

    /// 지금 배치를 읽는다. 구분자를 늘여 놓았으면 "보이는가"로, 접혀 있으면 위치로 어느 쪽인지 정한다.
    private func readPlacements(fullScan: Bool) async throws -> [SeparatorPlanner.Placement] {
        let snapshot = try await discovery.snapshot(fullScan: fullScan)
        if separator.isExpanded {
            return SeparatorPlanner.placements(expanded: snapshot, selfID: selfBundleID)
        }
        guard let offset = separator.trailingOffset else { throw VisibilityError.activationFailed }
        return SeparatorPlanner.placements(collapsed: snapshot.visible, selfID: selfBundleID, separatorOffset: offset)
    }

    /// 구분자를 접어 전부 보이게 한 뒤, 잘못 놓인 아이콘을 하나씩 구분자 너머로 옮긴다.
    /// 한 번 옮길 때마다 다시 읽어 실제 결과를 확인한다.
    /// - Returns: 한 번이라도 옮겼으면 true
    private func arrange(allowed: Set<BundleID>, generation mine: Int) async throws -> Bool {
        if separator.isExpanded {
            separator.setExpanded(false)
            await pause(Self.settleMilliseconds)
            try checkCurrent(mine)
        }
        var attempts: [MenuBarItem.ID: Int] = [:]
        var moves = 0
        while moves < Self.maximumMoves {
            let snapshot = try await discovery.snapshot(fullScan: false)
            try checkCurrent(mine)
            guard !separator.isExpanded, let offset = separator.trailingOffset else { throw VisibilityError.activationFailed }
            let placements = SeparatorPlanner.placements(collapsed: snapshot.visible, selfID: selfBundleID, separatorOffset: offset)
            let pending = SeparatorPlanner.relocations(placements, allowed: allowed, selfID: selfBundleID, skipping: unmovable)
            // 옮긴 아이콘은 구분자 바로 옆에 놓인다. 여러 개를 옮겨도 서로의 순서가 유지되도록,
            // 숨길 것은 왼쪽 것부터, 표시할 것은 오른쪽 것부터 옮긴다 (목록은 왼쪽 → 오른쪽 순서다).
            guard let next = pending.first(where: { $0.to == .hidden }) ?? pending.last else { break }

            let tried = attempts[next.item.id, default: 0]
            if tried >= Self.attemptsPerItem {
                // 드래그가 먹지 않는 아이콘이다. 이것 때문에 숨김 전체를 포기하지 않고 건너뛴다.
                unmovable.insert(next.item.id)
                continue
            }
            attempts[next.item.id] = tried + 1

            let destinationX = SeparatorPlanner.dropX(
                for: next, placements: placements, separatorOffset: offset,
                separatorWidth: separator.collapsedWidth, alternate: tried > 0)
            try await reorderer.commandDrag(
                from: CGPoint(x: next.item.frame.midX, y: next.item.frame.midY),
                to: CGPoint(x: destinationX, y: next.item.frame.midY)
            )
            moves += 1
            await pause(Self.settleMilliseconds)
            try checkCurrent(mine)
        }
        return moves > 0
    }
}
