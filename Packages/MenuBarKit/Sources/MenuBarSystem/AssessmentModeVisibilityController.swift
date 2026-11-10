import Foundation
import MenuBarDomain
import MenuBarPrivateBridge

/// 시스템 허용 목록 방식의 숨김. (docs/adr/0003-visibility-mechanism.md)
/// 앱이 종료·강제 종료되면 시스템이 제한을 자동으로 풀어 준다 (검증됨).
@MainActor
public final class AssessmentModeVisibilityController: VisibilityControlling {
    private let bridge = MBKVisibilityBridge()

    public init() {}

    public var isSupported: Bool { MBKVisibilityBridge.isSupported }
    public var isRestricted: Bool { bridge.isRestricted }

    public func restrict(to allowlist: Allowlist) async throws {
        guard isSupported else { throw VisibilityError.unsupported }
        let items = allowlist.systemItems.map { NSNumber(value: $0) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bridge.restrict(toBundleIdentifiers: allowlist.bundleIDs, systemItems: items) { error in
                if let error = error as NSError? {
                    continuation.resume(throwing: error.code == 3 ? VisibilityError.timedOut : VisibilityError.activationFailed)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func unrestrict() {
        bridge.unrestrict()
    }
}
