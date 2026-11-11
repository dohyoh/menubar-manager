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

/// 화면 언어 설정. 저장 값은 rawValue.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    /// macOS 의 언어를 따른다 (기본값). 지원하지 않는 언어이면 영어.
    /// 설정 화면에는 따로 나오지 않고, 시스템 언어에 해당하는 항목에 "(시스템)"이 붙는다.
    case system
    case korean = "ko"
    case english = "en"
    case chineseSimplified = "zh-Hans"

    /// 설정 화면에서 고를 수 있는 언어 (나오는 순서대로)
    public static let selectable: [AppLanguage] = [.korean, .english, .chineseSimplified]
    /// macOS 의 언어를 지원하지 않을 때 쓰는 언어
    public static let fallback: AppLanguage = .english

    /// 그 언어의 말로 적은 이름. 화면 언어와 무관하게 이대로 보여 준다.
    public var nativeName: String {
        switch self {
        case .system: return ""
        case .korean: return "한국어"
        case .english: return "English"
        case .chineseSimplified: return "简体中文"
        }
    }

    /// "ko-KR", "en_US", "zh-Hans-CN" 같은 식별자가 가리키는, 이 앱이 지원하는 언어. 없으면 nil.
    /// 중국어는 간체만 지원한다 — 번체(zh-Hant, 대만·홍콩·마카오)는 지원하지 않는 언어로 본다.
    public static func supported(for identifier: String) -> AppLanguage? {
        let parts = identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        switch parts.first {
        case "ko": return .korean
        case "en": return .english
        case "zh":
            let rest = parts.dropFirst()
            if rest.contains("hans") { return .chineseSimplified }
            if rest.contains("hant") || rest.contains(where: { ["tw", "hk", "mo"].contains($0) }) { return nil }
            return .chineseSimplified
        default: return nil
        }
    }

    /// macOS 의 선호 언어 중 이 앱이 지원하는 첫 언어. 하나도 없으면 nil.
    /// - Parameter preferredLanguages: 선호 언어 목록 (예: ["ko-KR", "en-US"]). 앞에 있을수록 우선.
    public static func systemLanguage(preferredLanguages: [String]) -> AppLanguage? {
        preferredLanguages.lazy.compactMap { supported(for: $0) }.first
    }

    /// 이 설정으로 실제 화면에 쓰이는 언어 (`system` 을 실제 언어로 푼 것).
    public func resolved(preferredLanguages: [String]) -> AppLanguage {
        guard self == .system else { return self }
        return AppLanguage.systemLanguage(preferredLanguages: preferredLanguages) ?? AppLanguage.fallback
    }

    /// 앱을 시작할 때 화면 언어로 지정할 값 (`AppleLanguages`).
    /// 시스템 언어를 따를 때는 원래 식별자(예: "en-GB")를 앞에 두어 지역별 표기를 살린다.
    public func launchLanguages(preferredLanguages: [String]) -> [String] {
        let language = resolved(preferredLanguages: preferredLanguages)
        if self == .system, let identifier = preferredLanguages.first(where: { AppLanguage.supported(for: $0) == language }),
           identifier != language.rawValue {
            return [identifier, language.rawValue]
        }
        return [language.rawValue]
    }

    /// 설정 화면에서 고른 언어를 저장할 값으로 바꾼다.
    /// 시스템 언어(지원하지 않으면 영어)와 같은 항목을 고르면 `system` — 나중에 macOS 의 언어가 바뀌면 따라간다.
    public static func stored(forPicked picked: AppLanguage, preferredLanguages: [String]) -> AppLanguage {
        let system = systemLanguage(preferredLanguages: preferredLanguages) ?? fallback
        return picked == system ? .system : picked
    }
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
    /// 화면 언어. 바꾼 값은 앱을 다시 시작할 때 적용된다.
    public var language: AppLanguage

    public static let autoRehideChoices = [3, 5, 10, 15, 30, 60]

    public init(hidingEnabled: Bool = false, autoRehide: Bool = true, autoRehideSeconds: Int = 5, didShowWelcome: Bool = false, hotkeys: [Int: Hotkey] = [:],
                language: AppLanguage = .system) {
        self.hidingEnabled = hidingEnabled
        self.autoRehide = autoRehide
        self.autoRehideSeconds = autoRehideSeconds
        self.didShowWelcome = didShowWelcome
        self.hotkeys = hotkeys
        self.language = language
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Options()
        hidingEnabled = try c.decodeIfPresent(Bool.self, forKey: .hidingEnabled) ?? defaults.hidingEnabled
        autoRehide = try c.decodeIfPresent(Bool.self, forKey: .autoRehide) ?? defaults.autoRehide
        autoRehideSeconds = try c.decodeIfPresent(Int.self, forKey: .autoRehideSeconds) ?? defaults.autoRehideSeconds
        didShowWelcome = try c.decodeIfPresent(Bool.self, forKey: .didShowWelcome) ?? defaults.didShowWelcome
        hotkeys = try c.decodeIfPresent([Int: Hotkey].self, forKey: .hotkeys) ?? [:]
        // 모르는 값(더 새로운 버전이 쓴 언어 등)이면 시스템 언어를 따른다.
        language = (try? c.decode(AppLanguage.self, forKey: .language)) ?? .system
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
    /// 이 macOS 에서는 숨길 아이콘을 앱이 옮겨야 해서 접근성 권한이 필요한데, 아직 없다
    /// (docs/adr/0012-separator-visibility-macos26.md)
    case accessibilityRequired
    case error(String)

    /// 사용자가 스위치나 좌클릭으로 숨김을 켤 수 있는 상태인가.
    /// 접근성 권한이 없을 때도 켜기를 받아 준다 — 그 순간 권한을 요청하고, 그사이 허용했으면 바로 켠다.
    public var canEnable: Bool { self == .userOff || self == .accessibilityRequired || isError }

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
