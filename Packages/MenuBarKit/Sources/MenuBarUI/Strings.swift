import Foundation

/// 사용자에게 보이는 문자열은 모두 이 함수를 거친다.
/// 원문은 한국어이고, 번역은 `Resources/Localizable.xcstrings` 에 있다.
/// 문자열을 추가·수정하면 `scripts/strings.py check` 로 번역 누락을 확인한다.
public func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
