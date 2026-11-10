import Foundation

/// 숨길 앱 목록에서 시스템에 넘길 허용 목록을 만든다.
public enum AllowlistBuilder {
    /// 시스템 아이템 번호. 0...255 전체 허용이 안전하다 (docs/architecture/platform-notes.md 3.5).
    public static let allSystemItems = Array(0...255)

    /// - Parameters:
    ///   - known: 알고 있는 모든 앱(실행 중 + 설치됨)의 번들 ID. 허용 목록은 기본이 "차단"이라
    ///            여기 없는 앱은 숨겨진다.
    ///   - hidden: 숨길 앱
    ///   - selfID: 이 앱 자신. 숨길 목록에 있어도 항상 허용한다.
    public static func build(known: [BundleID], hidden: Set<BundleID>, selfID: BundleID, hiddenSystemItems: Set<Int> = []) -> Allowlist {
        // 숨길 수 있다고 확인된 시스템 아이콘만 뺀다. 그 밖의 번호(시계, 제어 센터 등)는 항상 허용한다.
        let hideable = Set(SystemItem.allCases.map(\.rawValue))
        let systemItems = allSystemItems.filter { !(hiddenSystemItems.contains($0) && hideable.contains($0)) }
        var seen = Set<BundleID>()
        var allowed: [BundleID] = []
        for id in known + [selfID] where !id.isEmpty {
            guard id == selfID || !hidden.contains(id) else { continue }
            if seen.insert(id).inserted { allowed.append(id) }
        }
        return Allowlist(bundleIDs: allowed, systemItems: systemItems)
    }
}

/// 처음 보는 앱의 처리.
public enum NewAppRule {
    /// 목록에 새로 나타난 앱을 정책에 따라 반영한 레이아웃을 돌려준다.
    /// 아직 아무 앱도 본 적이 없으면(첫 실행) 지금 있는 앱을 모두 "아는 앱"으로만 기록한다 —
    /// 그러지 않으면 정책이 "숨김"일 때 기존 앱이 전부 숨겨진다.
    /// - Parameter menuBarApps: 메뉴바 아이콘을 가진 것으로 확인된 앱. 모르면 nil.
    ///   정책이 "묻기"일 때 이 안에 있는 새 앱만 "새로 나타난 앱"에 올린다. nil 이면 "표시"처럼 동작한다.
    public static func absorb(_ present: [BundleID], into layout: Layout, selfID: BundleID, menuBarApps: Set<BundleID>? = nil) -> Layout {
        var result = layout
        let newcomers = Set(present).subtracting(layout.knownApps)
        guard !newcomers.isEmpty else { return result }
        if !layout.knownApps.isEmpty {
            let others = newcomers.subtracting([selfID])
            switch layout.newAppPolicy {
            case .show:
                break
            case .hide:
                result.hiddenApps.formUnion(others)
            case .ask:
                if let menuBarApps { result.pendingApps.formUnion(others.intersection(menuBarApps)) }
            }
        }
        result.knownApps.formUnion(newcomers)
        return result
    }
}

/// 설정 화면의 앱 목록 필터.
public enum AppFilter: String, CaseIterable, Sendable {
    /// 메뉴바 아이콘을 가진 앱 (접근성 권한이 있을 때만 알 수 있다)
    case menuBar
    case running
    case hidden
    case all
}

public enum AppListFilter {
    /// 검색어가 있으면 필터와 무관하게 전체에서 찾는다. 결과는 이름순.
    public static func apply(_ apps: [ManagedApp], filter: AppFilter, query: String, hidden: Set<BundleID>, menuBarApps: Set<BundleID>? = nil) -> [ManagedApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let picked: [ManagedApp]
        if !q.isEmpty {
            picked = apps.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.bundleID.localizedCaseInsensitiveContains(q) }
        } else {
            switch filter {
            case .menuBar: picked = apps.filter { menuBarApps?.contains($0.bundleID) ?? $0.isRunning }
            case .running: picked = apps.filter(\.isRunning)
            case .hidden: picked = apps.filter { hidden.contains($0.bundleID) }
            case .all: picked = apps
            }
        }
        return picked.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 이 앱이 지금 메뉴바에 표시되도록 설정되어 있는가 (스위치의 켜짐 상태).
    public static func isShown(_ app: ManagedApp, hidden: Set<BundleID>) -> Bool {
        switch app.constraint {
        case .protected: return true
        case .outsideApplications: return false
        case nil: return !hidden.contains(app.bundleID)
        }
    }
}
