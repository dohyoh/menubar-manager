import CoreGraphics
import Foundation
import Observation
import MenuBarDomain

/// 순서 조정(M3): 메뉴바 순서를 읽고, 목표 순서가 되도록 아이콘을 옮긴다.
///
/// 옮기는 방법은 사용자가 ⌘ 을 누른 채 아이콘을 끄는 동작을 대신 수행하는 것이다
/// (docs/adr/0004-reorder-mechanism.md). 한 번 옮길 때마다 다시 읽어 실제 결과를 확인한다.
@MainActor
@Observable
public final class OrderingController {
    public enum Status: Equatable, Sendable {
        case idle
        case reading
        case applying(done: Int, total: Int)
        case succeeded
        case failed(Failure)
    }

    public enum Failure: Equatable, Sendable {
        case accessibilityNotGranted
        /// 드래그해도 순서가 바뀌지 않았다
        case stuck
        case unavailable
        case other(String)
    }

    /// 마지막으로 읽은 순서 (왼쪽 → 오른쪽)
    public private(set) var items: [MenuBarItem] = []
    public private(set) var status: Status = .idle
    public private(set) var isAccessibilityGranted = false

    @ObservationIgnored private let coordinator: MenuBarCoordinator
    @ObservationIgnored private let permission: any PermissionChecking
    @ObservationIgnored private let discovery: any ItemDiscovering
    @ObservationIgnored private let reorderer: any ItemReordering
    @ObservationIgnored private let pause: @MainActor (Int) async -> Void

    /// 숨김을 풀거나 아이콘을 옮긴 뒤 메뉴바가 자리 잡기를 기다리는 시간(ms)
    public static let settleMilliseconds = 600
    /// 놓을 지점: 목표 아이템 왼쪽 가장자리에서 이만큼 왼쪽
    static let dropInset: CGFloat = 6

    public var isBusy: Bool {
        switch status {
        case .reading, .applying: return true
        default: return false
        }
    }

    public init(
        coordinator: MenuBarCoordinator,
        permission: any PermissionChecking,
        discovery: any ItemDiscovering,
        reorderer: any ItemReordering,
        pause: @escaping @MainActor (Int) async -> Void = { try? await Task.sleep(for: .milliseconds($0)) }
    ) {
        self.coordinator = coordinator
        self.permission = permission
        self.discovery = discovery
        self.reorderer = reorderer
        self.pause = pause
        self.isAccessibilityGranted = permission.isAccessibilityGranted
    }

    public func refreshPermission() {
        isAccessibilityGranted = permission.isAccessibilityGranted
    }

    public func requestPermission() {
        permission.requestAccessibility()
        refreshPermission()
    }

    /// 메뉴바의 현재 순서를 읽는다. 숨김 중이면 잠깐 전부 펼쳤다가 되돌린다.
    public func read() async {
        guard !isBusy else { return }
        refreshPermission()
        guard isAccessibilityGranted else { status = .failed(.accessibilityNotGranted); return }
        status = .reading
        do {
            items = try await coordinator.withEverythingVisible {
                await self.pause(Self.settleMilliseconds)
                return try await self.readItems(fullScan: true)
            }
            status = .idle
        } catch {
            status = .failed(Self.failure(from: error))
        }
    }

    /// 목표 순서(아이템 ID, 왼쪽 → 오른쪽)가 되도록 아이콘을 옮긴다.
    public func apply(target: [MenuBarItem.ID]) async {
        guard !isBusy else { return }
        refreshPermission()
        guard isAccessibilityGranted else { status = .failed(.accessibilityNotGranted); return }
        status = .applying(done: 0, total: 0)
        do {
            items = try await coordinator.withEverythingVisible {
                try await self.performMoves(target: target)
            }
            status = .succeeded
        } catch {
            status = .failed(Self.failure(from: error))
        }
    }

    private func performMoves(target: [MenuBarItem.ID]) async throws -> [MenuBarItem] {
        await pause(Self.settleMilliseconds)
        var current = try await readItems(fullScan: true)
        let fixed = Set(current.filter(\.isSystem).map(\.id))
        let total = MovePlanner.plan(current: current.map(\.id), target: target, fixed: fixed).count
        var done = 0
        var stuckCount = 0
        status = .applying(done: 0, total: total)

        // 한 번에 하나씩 옮기고, 매번 다시 읽어 남은 이동을 새로 계산한다.
        while true {
            let order = current.map(\.id)
            guard let move = MovePlanner.plan(current: order, target: target, fixed: fixed).first else { break }
            guard let item = current.first(where: { $0.id == move.item }) else { throw OrderingError.stuck }

            // 목적지는 옮길 아이템이 놓인 모니터 기준으로 계산한다 (아이템마다 좌표의 기준 모니터가 다를 수 있다).
            let destinationX: CGFloat
            if let before = move.before, let anchor = current.first(where: { $0.id == before }) {
                destinationX = item.xOnMyScreen(ofLeadingEdgeOf: anchor) - Self.dropInset
            } else if let last = current.last {
                destinationX = item.xOnMyScreen(ofTrailingEdgeOf: last) + Self.dropInset
            } else {
                throw OrderingError.stuck
            }

            try await reorderer.commandDrag(
                from: CGPoint(x: item.frame.midX, y: item.frame.midY),
                to: CGPoint(x: destinationX, y: item.frame.midY)
            )
            await pause(Self.settleMilliseconds)
            current = try await readItems(fullScan: false)
            items = current

            if current.map(\.id) == order {
                // 드래그가 먹지 않았다. 한 번은 다시 시도하고, 또 그대로면 포기한다.
                stuckCount += 1
                if stuckCount >= 2 { throw OrderingError.stuck }
            } else {
                stuckCount = 0
                done += 1
                status = .applying(done: min(done, total), total: total)
            }
        }
        return current
    }

    /// 메뉴바의 아이템을 읽는다. 숨김에 쓰는 이 앱의 구분자는 사용자가 다룰 아이콘이 아니므로 뺀다.
    private func readItems(fullScan: Bool) async throws -> [MenuBarItem] {
        try await discovery.currentItems(fullScan: fullScan).filter { !coordinator.isSeparatorItem($0) }
    }

    private static func failure(from error: Error) -> Failure {
        switch error as? OrderingError {
        case .accessibilityNotGranted: return .accessibilityNotGranted
        case .stuck: return .stuck
        case .unavailable: return .unavailable
        default: return .other(String(describing: error))
        }
    }
}
