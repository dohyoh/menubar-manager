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

    public func load() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL),
              var state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return PersistedState() }
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
