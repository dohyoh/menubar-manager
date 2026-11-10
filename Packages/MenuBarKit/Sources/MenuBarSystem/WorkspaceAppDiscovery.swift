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
    private var observers: [NSObjectProtocol] = []
    /// 설치된 앱 목록은 디스크를 훑어야 하므로 잠깐 캐시한다.
    private var installedCache: (apps: [ManagedApp], at: Date)?
    private static let installedCacheLifetime: TimeInterval = 30

    public init(selfBundleID: BundleID) {
        self.selfBundleID = selfBundleID
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?() }
            })
        }
    }

    // 앱이 살아 있는 동안 하나만 유지되므로 관찰자를 따로 해제하지 않는다.

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
