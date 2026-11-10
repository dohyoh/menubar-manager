import Foundation
import MenuBarDomain

/// 설정을 JSON 파일 하나로 저장한다.
/// 기본 위치: ~/Library/Application Support/MenuBarManager/state.json
@MainActor
public final class JSONStateStore: StateStoring {
    public let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("state.json")
    }

    public convenience init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.init(directory: base.appendingPathComponent("MenuBarManager"))
    }

    /// 읽지 못한 설정 파일을 옮겨 두는 곳. 기본값으로 덮어쓰기 전에 사본을 남긴다.
    public var unreadableCopyURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("state.unreadable.json") }

    public func load() -> PersistedState {
        // 파일이 없으면 첫 실행이다.
        guard let data = try? Data(contentsOf: fileURL) else { return PersistedState() }
        // 깨졌거나 더 새로운 버전이 쓴 파일이면, 기본값으로 시작하되 원래 파일은 사본으로 남긴다.
        // (그러지 않으면 다음 저장 때 숨길 앱 목록이 조용히 사라진다.)
        guard var state = try? JSONDecoder().decode(PersistedState.self, from: data),
              state.schemaVersion <= PersistedState.currentSchemaVersion
        else {
            try? FileManager.default.removeItem(at: unreadableCopyURL)
            try? FileManager.default.copyItem(at: fileURL, to: unreadableCopyURL)
            return PersistedState()
        }
        // 손으로 고친 파일 등 비정상 값 방어
        if state.options.autoRehideSeconds < 1 { state.options.autoRehideSeconds = Options().autoRehideSeconds }
        return state
    }

    public func save(_ state: PersistedState) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            // 저장 실패는 동작을 막지 않는다. 다음 저장 때 다시 시도된다.
        }
    }
}

/// 실제 시간으로 동작하는 자동 숨기기 타이머.
@MainActor
public final class TaskRehideScheduler: RehideScheduling {
    private var task: Task<Void, Never>?

    public init() {}

    public func schedule(after seconds: Int, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}
