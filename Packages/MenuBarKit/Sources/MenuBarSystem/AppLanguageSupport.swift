import Foundation
import MenuBarDomain

/// 화면 언어를 설정에서 고른 값으로 바꾸는 OS 접점. (docs/architecture/platform-notes.md 3.30)
///
/// macOS 는 프로세스가 문자열을 처음 찾을 때 `AppleLanguages` 기본값으로 화면 언어를 정하고, 그 뒤로는 바꾸지 않는다.
/// 그래서 고른 언어는 앱을 시작하는 맨 처음에 한 번 지정하고, 바꾸려면 앱을 다시 시작한다.
@MainActor
public enum AppLanguageSupport {
    /// 설정을 적용하기 전, macOS 가 이 앱에 주려던 선호 언어 목록. `apply` 가 부를 때 채운다.
    public private(set) static var systemPreferredLanguages: [String] = readPreferredLanguages()

    /// 화면 언어를 설정에서 고른 값으로 정한다.
    /// **프로세스가 문자열을 처음 찾기 전에** 불러야 한다 (main.swift 의 맨 앞).
    ///
    /// 실행 인자 `-AppleLanguages` 가 들어가는 자리(argument domain)에 값을 넣는다.
    /// 이 자리는 프로세스가 끝나면 사라지므로 디스크에 아무것도 남기지 않는다.
    /// "시스템 언어 따르기"일 때도 넣는다 — 어떤 언어가 될지를 이 앱의 판단(`AppLanguage`)과 항상 같게 하려는 것이다.
    public static func apply(_ language: AppLanguage) {
        systemPreferredLanguages = readPreferredLanguages()
        let languages = language.launchLanguages(preferredLanguages: systemPreferredLanguages)
        let defaults = UserDefaults.standard
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        domain["AppleLanguages"] = languages
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    private static func readPreferredLanguages() -> [String] {
        UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
    }

    /// 지금 화면에 쓰이고 있는 언어.
    public static var current: AppLanguage {
        Bundle.main.preferredLocalizations.lazy.compactMap { AppLanguage.supported(for: $0) }.first ?? AppLanguage.fallback
    }
}

/// 앱을 끝낸 뒤 같은 위치에서 다시 실행한다.
@MainActor
public enum AppRelauncher {
    /// 이 프로세스가 끝나기를 기다렸다가 앱을 다시 여는 도우미를 띄운다. 부른 쪽은 곧바로 앱을 종료해야 한다.
    ///
    /// 새 프로세스를 먼저 띄우고 끝내면 두 프로세스가 잠깐 함께 돌아, 숨김 제한과 전역 단축키 등록이 겹친다.
    /// 그래서 끝난 것을 확인한 뒤에 연다.
    /// - Parameter arguments: 새 프로세스에 넘길 실행 인자
    /// - Returns: 도우미를 띄웠으면 true
    @discardableResult
    public static func relaunchAfterExit(arguments: [String] = []) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 값은 모두 위치 인자로 넘긴다 (스크립트 문자열에 끼워 넣지 않는다).
        let script = #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.1; done; shift; exec /usr/bin/open "$@""#
        var parameters = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        if !arguments.isEmpty { parameters += ["--args"] + arguments }
        process.arguments = parameters
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
