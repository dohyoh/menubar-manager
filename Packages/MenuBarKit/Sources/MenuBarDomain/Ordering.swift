import CoreGraphics
import Foundation

// 순서 조정(M3)용 모델·규칙·프로토콜.
// 접근성 권한이 있어야 동작한다. (docs/adr/0004-reorder-mechanism.md)

/// 메뉴바에 지금 보이는 아이템 하나.
public struct MenuBarItem: Identifiable, Hashable, Sendable {
    /// "번들ID#앱 안에서의 순번"
    public let id: String
    public let bundleID: BundleID
    public let appName: String
    public let index: Int
    public let title: String?
    /// 화면 좌표 (왼쪽 위가 원점)
    public let frame: CGRect
    /// 이 아이템이 놓인 모니터의 오른쪽 끝 x 좌표.
    public let screenMaxX: CGFloat
    /// macOS 가 제공하는 아이템(시계, 제어 센터, Wi-Fi 등). 순서 조정에서 옮기지 않는다.
    public var isSystem: Bool { bundleID.hasPrefix("com.apple.") }

    /// 모니터 오른쪽 끝에서 아이템 왼쪽 가장자리까지의 거리.
    ///
    /// 모니터가 여러 대면 접근성 API 가 아이템마다 다른 모니터 기준 좌표를 돌려줄 수 있다.
    /// 메뉴바 아이템은 모니터마다 오른쪽 정렬로 같은 배치이므로, 이 거리는 어느 모니터 기준이든 같다.
    /// 순서 비교와 드래그 목적지 계산에는 x 좌표 대신 이 값을 쓴다. (docs/architecture/platform-notes.md 3.23)
    public var trailingOffset: CGFloat { screenMaxX - frame.minX }

    /// 왼쪽 → 오른쪽 순서로 정렬한다 (오른쪽 끝에서 먼 것이 왼쪽).
    public static func sortedLeftToRight(_ items: [MenuBarItem]) -> [MenuBarItem] {
        items.sorted { $0.trailingOffset > $1.trailingOffset }
    }

    /// 다른 아이템의 왼쪽 가장자리가, 이 아이템이 놓인 모니터에서는 어느 x 좌표인지.
    public func xOnMyScreen(ofLeadingEdgeOf other: MenuBarItem) -> CGFloat {
        screenMaxX - other.trailingOffset
    }

    /// 다른 아이템의 오른쪽 가장자리가, 이 아이템이 놓인 모니터에서는 어느 x 좌표인지.
    public func xOnMyScreen(ofTrailingEdgeOf other: MenuBarItem) -> CGFloat {
        screenMaxX - other.trailingOffset + other.frame.width
    }

    public init(bundleID: BundleID, appName: String, index: Int, title: String?, frame: CGRect, screenMaxX: CGFloat) {
        self.id = "\(bundleID)#\(index)"
        self.bundleID = bundleID
        self.appName = appName
        self.index = index
        self.title = title
        self.frame = frame
        self.screenMaxX = screenMaxX
    }

    // CGRect 는 Hashable 이 아니라서 직접 구현한다.
    public static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.id == rhs.id && lhs.appName == rhs.appName && lhs.title == rhs.title && lhs.frame.equalTo(rhs.frame) && lhs.screenMaxX == rhs.screenMaxX
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(frame.origin.x)
        hasher.combine(frame.origin.y)
        hasher.combine(frame.size.width)
        hasher.combine(frame.size.height)
    }
}

/// 아이템 하나를 다른 아이템 바로 앞으로 옮긴다. `before` 가 nil 이면 맨 끝으로.
public struct Move<ID: Hashable & Sendable>: Equatable, Sendable {
    public let item: ID
    public let before: ID?

    public init(item: ID, before: ID?) {
        self.item = item
        self.before = before
    }
}

/// 현재 순서를 목표 순서로 바꾸는 가장 적은 이동을 계산한다.
///
/// 이미 목표 순서대로 놓인 가장 긴 묶음(최장 증가 부분수열)은 그대로 두고 나머지만 옮긴다.
/// 드래그 합성은 느리고 눈에 보이므로 이동 횟수를 줄이는 것이 중요하다.
public enum MovePlanner {
    /// - Parameter fixed: 절대 옮기지 않을 아이템(시스템 아이템). 이들 사이의 상대 순서는
    ///   현재와 목표에서 같아야 한다. 다르면 고정 조건을 무시하고 계산한다.
    public static func plan<ID: Hashable & Sendable>(current: [ID], target: [ID], fixed: Set<ID> = []) -> [Move<ID>] {
        // 양쪽 모두에 있는 것만 다룬다.
        let currentSet = Set(current)
        let wanted = target.filter { currentSet.contains($0) }
        let rank = Dictionary(uniqueKeysWithValues: wanted.enumerated().map { ($1, $0) })
        let present = current.filter { rank[$0] != nil }
        guard present.count > 1 else { return [] }

        let ranks = present.map { rank[$0]! }
        let keptRanks = keptRanks(ranks: ranks, fixedPositions: present.indices.filter { fixed.contains(present[$0]) })
        let keep = Set(keptRanks.map { wanted[$0] })

        // 오른쪽부터 처리하면 "바로 뒤 아이템"이 항상 이미 제자리에 있다.
        var moves: [Move<ID>] = []
        for i in stride(from: wanted.count - 1, through: 0, by: -1) {
            let id = wanted[i]
            guard !keep.contains(id) else { continue }
            moves.append(Move(item: id, before: i + 1 < wanted.count ? wanted[i + 1] : nil))
        }
        return moves
    }

    /// 이동을 순서 배열에 적용한다 (검증·미리보기용).
    public static func apply<ID: Hashable & Sendable>(_ moves: [Move<ID>], to order: [ID]) -> [ID] {
        var result = order
        for move in moves {
            guard let from = result.firstIndex(of: move.item) else { continue }
            result.remove(at: from)
            if let before = move.before, let to = result.firstIndex(of: before) {
                result.insert(move.item, at: to)
            } else {
                result.append(move.item)
            }
        }
        return result
    }

    /// 제자리에 둘 아이템의 순위들. 고정 아이템은 반드시 포함하고,
    /// 고정 아이템 사이 구간마다 그 범위에 들어가는 가장 긴 증가 수열을 고른다.
    static func keptRanks(ranks: [Int], fixedPositions: [Int]) -> [Int] {
        let fixedRanks = fixedPositions.map { ranks[$0] }
        guard !fixedPositions.isEmpty, fixedRanks == fixedRanks.sorted() else {
            return longestIncreasingSubsequence(ranks)
        }
        var kept: [Int] = []
        let bounds = [-1] + fixedPositions + [ranks.count]
        for segment in 0..<(bounds.count - 1) {
            let lowerRank = segment == 0 ? Int.min : ranks[bounds[segment]]
            let upperRank = segment == bounds.count - 2 ? Int.max : ranks[bounds[segment + 1]]
            let start = bounds[segment] + 1, end = bounds[segment + 1]
            if start < end {
                kept += longestIncreasingSubsequence(ranks[start..<end].filter { $0 > lowerRank && $0 < upperRank })
            }
            if segment < bounds.count - 2 { kept.append(upperRank) }
        }
        return kept
    }

    /// 값이 증가하는 가장 긴 부분수열의 값들을 돌려준다. O(n log n)
    static func longestIncreasingSubsequence(_ values: [Int]) -> [Int] {
        guard !values.isEmpty else { return [] }
        var tails: [Int] = []                               // tails[k] = 길이 k+1 인 수열의 마지막 인덱스
        var previous = Array(repeating: -1, count: values.count)
        for (i, value) in values.enumerated() {
            var low = 0, high = tails.count
            while low < high {
                let mid = (low + high) / 2
                if values[tails[mid]] < value { low = mid + 1 } else { high = mid }
            }
            if low > 0 { previous[i] = tails[low - 1] }
            if low == tails.count { tails.append(i) } else { tails[low] = i }
        }
        var result: [Int] = []
        var cursor = tails.last ?? -1
        while cursor >= 0 {
            result.append(values[cursor])
            cursor = previous[cursor]
        }
        return result.reversed()
    }
}

// MARK: 백엔드 프로토콜

@MainActor
public protocol PermissionChecking: AnyObject {
    var isAccessibilityGranted: Bool { get }
    /// 시스템의 권한 요청 창을 띄운다. 허용 여부는 사용자가 정한다.
    func requestAccessibility()
}

/// 메뉴바에 지금 실제로 표시된 아이템과 위치. 접근성 권한이 필요하다.
///
/// 숨겨졌거나 표시되지 않는 아이템은 예전 좌표를 돌려주므로, 구현은 그 좌표에 실제로
/// 그 아이템이 있는지 확인해 걸러내야 한다. (docs/architecture/platform-notes.md 3.21)
@MainActor
public protocol ItemDiscovering: AnyObject {
    /// 왼쪽 → 오른쪽 순서.
    /// - Parameter fullScan: 실행 중인 모든 앱을 다시 훑는다(느림). false 면 지난번에 아이템이 있던 앱만 본다.
    func currentItems(fullScan: Bool) async throws -> [MenuBarItem]
    /// 메뉴바 아이콘을 가진 앱들 (지금 숨겨져 있는 것도 포함).
    func appsOwningItems() async throws -> Set<BundleID>
}

/// ⌘ 을 누른 채 드래그하는 동작을 대신 수행한다. 접근성 권한이 필요하다.
@MainActor
public protocol ItemReordering: AnyObject {
    func commandDrag(from start: CGPoint, to end: CGPoint) async throws
}

public enum OrderingError: Error, Equatable, Sendable {
    case accessibilityNotGranted
    case eventCreationFailed
    /// 드래그를 했는데도 순서가 바뀌지 않는다
    case stuck
    /// 숨김을 켤 수 없는 상태 등, 지금은 순서를 다룰 수 없다
    case unavailable
}
