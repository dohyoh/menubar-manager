import Foundation

public typealias BundleID = String

/// 메뉴바 아이템을 가질 수 있는 앱 하나. 표시/숨김의 단위.
public struct ManagedApp: Identifiable, Hashable, Sendable {
    public var id: BundleID { bundleID }
    public let bundleID: BundleID
    public var name: String
    /// 앱 번들 경로. 아이콘을 읽을 때와 설치 위치 판단에 쓴다.
    public var path: String?
    public var isRunning: Bool
    /// 표시/숨김을 사용자가 바꿀 수 없는 이유. nil 이면 자유롭게 바꿀 수 있다.
    public var constraint: Constraint?

    public init(bundleID: BundleID, name: String, path: String? = nil, isRunning: Bool = false, constraint: Constraint? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.isRunning = isRunning
        self.constraint = constraint
    }
}

public enum Constraint: String, Sendable, Codable {
    /// 이 앱 자신 — 항상 표시
    case protected
    /// /Applications 밖 — 숨김 중에는 표시할 수 없다 (docs/adr/0010-install-location.md)
    case outsideApplications
}

/// 저장되는 설정 한 벌.
///
/// 시스템 API 는 "허용 목록"을 받지만, 여기에는 "숨길 앱"을 저장한다.
/// 사용자 의도가 "이것들을 숨겨라"이고, 새 앱은 기본적으로 보여야 하기 때문이다.
public struct Layout: Codable, Equatable, Sendable {
    public var hiddenApps: Set<BundleID>
    /// 지금까지 본 앱. 여기 없는 앱이 나타나면 "새 앱"이다.
    public var knownApps: Set<BundleID>
    public var newAppPolicy: NewAppPolicy
    /// 새로 나타났고 아직 표시할지 숨길지 정하지 않은 앱 (정책이 "묻기"일 때). 정할 때까지는 표시된다.
    public var pendingApps: Set<BundleID>
    /// 숨길 시스템 아이콘 (SystemItem 의 번호)
    public var hiddenSystemItems: Set<Int>

    public init(hiddenApps: Set<BundleID> = [], knownApps: Set<BundleID> = [], newAppPolicy: NewAppPolicy = .show,
                pendingApps: Set<BundleID> = [], hiddenSystemItems: Set<Int> = []) {
        self.hiddenApps = hiddenApps
        self.knownApps = knownApps
        self.newAppPolicy = newAppPolicy
        self.pendingApps = pendingApps
        self.hiddenSystemItems = hiddenSystemItems
    }

    // 이전 버전이 저장한 파일에는 뒤에 추가된 필드가 없다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hiddenApps = try c.decodeIfPresent(Set<BundleID>.self, forKey: .hiddenApps) ?? []
        knownApps = try c.decodeIfPresent(Set<BundleID>.self, forKey: .knownApps) ?? []
        newAppPolicy = try c.decodeIfPresent(NewAppPolicy.self, forKey: .newAppPolicy) ?? .show
        pendingApps = try c.decodeIfPresent(Set<BundleID>.self, forKey: .pendingApps) ?? []
        hiddenSystemItems = try c.decodeIfPresent(Set<Int>.self, forKey: .hiddenSystemItems) ?? []
    }
}

/// 숨길 수 있는 시스템 아이콘. 번호는 이 Mac 에서 확인한 것만 있다 (docs/architecture/platform-notes.md 3.5).
/// 시계(2)와 제어 센터(8)는 숨기지 않는다 — 시계는 알림 센터의 입구이고, 제어 센터는 다른 시스템 기능의 입구다.
public enum SystemItem: Int, CaseIterable, Sendable {
    case wifi = 6
    case battery = 0
}

/// 전역 단축키로 실행할 동작.
public enum HotkeyAction: Int, CaseIterable, Sendable, Codable {
    case toggle = 1
    case openSettings = 2
}

/// 전역 단축키 하나. 키 코드와 조합 키는 Carbon 값이다.
public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    /// 화면에 보여 줄 표기 (예: "⌃⌥H")
    public var display: String

    public init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }
}

/// 단축키를 화면에 보여 줄 글자로 바꾼다.
public enum HotkeyFormatter {
    // Carbon 의 조합 키 값
    public static let command: UInt32 = 256
    public static let shift: UInt32 = 512
    public static let option: UInt32 = 2048
    public static let control: UInt32 = 4096

    /// 키 코드 → 자판에 적힌 이름. 입력 소스가 한글이어도 "ㅛ"가 아니라 "Y"로 보여 주려고
    /// 눌린 글자가 아닌 키 위치로 정한다 (미국식 자판 기준).
    static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    /// - Parameter fallback: 표에 없는 키일 때 쓸 글자 (그 키로 입력된 문자)
    public static func display(keyCode: UInt32, modifiers: UInt32, fallback: String = "") -> String {
        var text = ""
        if modifiers & control != 0 { text += "⌃" }
        if modifiers & option != 0 { text += "⌥" }
        if modifiers & shift != 0 { text += "⇧" }
        if modifiers & command != 0 { text += "⌘" }
        if let name = keyNames[keyCode] { return text + name }
        let key = fallback.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return text + (key.isEmpty ? "#\(keyCode)" : key)
    }
}

/// 처음 보는 앱이 나타났을 때.
public enum NewAppPolicy: String, Codable, Sendable, CaseIterable {
    /// 그대로 표시 (기본)
    case show
    /// 숨길 앱에 자동으로 추가
    case hide
    /// 표시한 채로 "새로 나타난 앱"에 올려 두고 사용자가 정하게 한다.
    /// 그 앱이 메뉴바 아이콘을 가졌는지 알아야 하므로 접근성 권한이 필요하다. 없으면 "표시"처럼 동작한다.
    case ask
}

public struct Options: Codable, Equatable, Sendable {
    /// 우클릭 메뉴의 "숨기기" 스위치. 다음 실행 때 이 상태로 시작한다.
    public var hidingEnabled: Bool
    /// 좌클릭으로 펼친 뒤 자동으로 다시 숨길지
    public var autoRehide: Bool
    public var autoRehideSeconds: Int
    /// 첫 실행 안내를 이미 보여 줬는가
    public var didShowWelcome: Bool
    /// 전역 단축키 (키: HotkeyAction 의 rawValue)
    public var hotkeys: [Int: Hotkey]

    public static let autoRehideChoices = [3, 5, 10, 15, 30, 60]

    public init(hidingEnabled: Bool = false, autoRehide: Bool = true, autoRehideSeconds: Int = 10, didShowWelcome: Bool = false, hotkeys: [Int: Hotkey] = [:]) {
        self.hidingEnabled = hidingEnabled
        self.autoRehide = autoRehide
        self.autoRehideSeconds = autoRehideSeconds
        self.didShowWelcome = didShowWelcome
        self.hotkeys = hotkeys
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Options()
        hidingEnabled = try c.decodeIfPresent(Bool.self, forKey: .hidingEnabled) ?? defaults.hidingEnabled
        autoRehide = try c.decodeIfPresent(Bool.self, forKey: .autoRehide) ?? defaults.autoRehide
        autoRehideSeconds = try c.decodeIfPresent(Int.self, forKey: .autoRehideSeconds) ?? defaults.autoRehideSeconds
        didShowWelcome = try c.decodeIfPresent(Bool.self, forKey: .didShowWelcome) ?? defaults.didShowWelcome
        hotkeys = try c.decodeIfPresent([Int: Hotkey].self, forKey: .hotkeys) ?? [:]
    }
}

/// 디스크에 저장하는 전체 상태.
public struct PersistedState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var layout: Layout
    public var options: Options

    public init(schemaVersion: Int = PersistedState.currentSchemaVersion, layout: Layout = Layout(), options: Options = Options()) {
        self.schemaVersion = schemaVersion
        self.layout = layout
        self.options = options
    }
}

/// 앱의 관리 상태. (docs/architecture/overview.md 6절)
public enum ManagerState: Equatable, Sendable {
    /// 전부 표시, 관리하지 않음
    case paused(PauseReason)
    /// 숨김 적용 중 — 평소 상태
    case collapsed
    /// 좌클릭으로 잠깐 펼친 상태
    case expanded
    /// 순서를 읽거나 바꾸는 중 — 전부 펼쳐 놓고 작업한다. 끝나면 이전 상태로 돌아간다.
    case reordering

    public var isHiding: Bool { self == .collapsed }
}

public enum PauseReason: Equatable, Sendable {
    /// 사용자가 메뉴의 숨기기 스위치를 끔
    case userOff
    /// /Applications 밖에서 실행 중 — 숨김을 켜면 자기 아이콘이 사라진다
    case notInstalledInApplications
    /// 이 macOS 에는 숨김에 필요한 시스템 기능이 없다
    case unsupported
    case error(String)

    /// 사용자가 스위치나 좌클릭으로 숨김을 켤 수 있는 상태인가
    public var canEnable: Bool { self == .userOff || isError }

    private var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

/// 시스템에 넘기는 허용 목록.
public struct Allowlist: Equatable, Sendable {
    public var bundleIDs: [BundleID]
    public var systemItems: [Int]

    public init(bundleIDs: [BundleID], systemItems: [Int]) {
        self.bundleIDs = bundleIDs
        self.systemItems = systemItems
    }
}
