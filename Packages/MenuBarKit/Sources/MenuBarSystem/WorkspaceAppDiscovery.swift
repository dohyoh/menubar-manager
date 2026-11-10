import AppKit
import MenuBarDomain

/// 실행 중인 앱 + /Applications 에 설치된 앱. 권한이 필요 없다.
///
/// 한계: 접근성 권한 없이는 "메뉴바 아이콘을 실제로 가진 앱"만 골라낼 수 없어,
/// 아이콘이 없는 일반 앱도 목록에 포함된다 (docs/architecture/platform-notes.md 3.11).
@MainActor
public final class WorkspaceAppDiscovery: AppDiscovering {
    public var onChange: (@MainActor () -> Void)?

    private let selfBundleID: BundleID
    private var runningObservation: NSKeyValueObservation?
    private var lastRunning: Set<BundleID> = []
    private var pendingNotify: Task<Void, Never>?
    /// 앱이 여러 개 한꺼번에 뜨고 질 때 한 번만 알리도록 잠깐 모은다.
    private static let notifyDelayMilliseconds = 300
    /// 설치된 앱 목록은 디스크를 훑어야 하므로 잠깐 캐시한다.
    private var installedCache: (apps: [ManagedApp], at: Date)?
    private static let installedCacheLifetime: TimeInterval = 30

    public init(selfBundleID: BundleID) {
        self.selfBundleID = selfBundleID
        lastRunning = Self.runningBundleIDs()
        // 앱 실행 알림(didLaunchApplicationNotification)은 Dock 에 나오지 않는 앱에는 오지 않는다 (검증됨).
        // 메뉴바 앱은 대부분 그런 앱이라, 실행 중인 앱 목록 자체를 관찰한다. (platform-notes 3.27)
        runningObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.runningApplicationsChanged() }
        }
    }

    // 앱이 살아 있는 동안 하나만 유지되므로 관찰을 따로 해제하지 않는다.

    private static func runningBundleIDs() -> Set<BundleID> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private func runningApplicationsChanged() {
        let now = Self.runningBundleIDs()
        // 같은 앱의 프로세스가 늘고 주는 것은 허용 목록과 무관하다.
        guard now != lastRunning else { return }
        lastRunning = now
        pendingNotify?.cancel()
        pendingNotify = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.notifyDelayMilliseconds))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }

    public func knownBundleIDs() -> [BundleID] {
        // 허용 목록용: 시스템 프로세스까지 전부 포함한다. 빠뜨리면 그 앱의 아이콘이 숨겨진다.
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        return running + installedApps().map(\.bundleID)
    }

    public func catalog() -> [ManagedApp] {
        var byID: [BundleID: ManagedApp] = [:]
        for app in installedApps() { byID[app.bundleID] = app }

        for running in NSWorkspace.shared.runningApplications {
            guard let id = running.bundleIdentifier, let url = running.bundleURL,
                  running.activationPolicy != .prohibited, Self.isUserFacing(bundleID: id, url: url, policy: running.activationPolicy)
            else { continue }
            if var existing = byID[id] {
                existing.isRunning = true
                byID[id] = existing
            } else {
                var app = makeApp(at: url, bundleID: id)
                app.isRunning = true
                byID[id] = app
            }
        }
        return Array(byID.values)
    }

    // MARK: 내부

    private func installedApps() -> [ManagedApp] {
        if let cache = installedCache, Date().timeIntervalSince(cache.at) < Self.installedCacheLifetime { return cache.apps }
        let fm = FileManager.default
        var urls: [URL] = []
        let root = URL(fileURLWithPath: "/Applications")
        for entry in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [] {
            if entry.pathExtension == "app" {
                urls.append(entry)
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                // 한 단계 아래 폴더까지 (예: /Applications/Utilities)
                let children = (try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                urls.append(contentsOf: children.filter { $0.pathExtension == "app" })
            }
        }
        let apps = urls.compactMap { url -> ManagedApp? in
            guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
            return makeApp(at: url, bundleID: id)
        }
        installedCache = (apps, Date())
        return apps
    }

    private func makeApp(at url: URL, bundleID: BundleID) -> ManagedApp {
        let display = FileManager.default.displayName(atPath: url.path)
        let name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        let constraint: Constraint?
        if bundleID == selfBundleID {
            constraint = .protected
        } else if !(url.path.hasPrefix("/Applications/") || url.path.hasPrefix("/System/")) {
            constraint = .outsideApplications
        } else {
            constraint = nil
        }
        return ManagedApp(bundleID: bundleID, name: name, path: url.path, isRunning: false, constraint: constraint)
    }

    /// 설정 화면에 보여 줄 만한 앱인가. 시스템 백그라운드 에이전트와 헬퍼 프로세스는 제외한다.
    private static func isUserFacing(bundleID: BundleID, url: URL, policy: NSApplication.ActivationPolicy) -> Bool {
        if bundleID.hasPrefix("com.apple.") && policy != .regular { return false }
        let lower = bundleID.lowercased()
        if url.path.contains(".app/Contents/") && (lower.contains("helper") || lower.contains("webkit")) { return false }
        return true
    }
}
