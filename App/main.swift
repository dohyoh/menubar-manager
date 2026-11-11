import AppKit
import MenuBarServices
import MenuBarSystem

// 메뉴바 전용 앱 (Info.plist 의 LSUIElement). SwiftUI App 대신 NSApplication 을 직접 띄워
// 상태 아이콘의 좌클릭/우클릭과 창 표시를 정확히 제어한다.

// 설정에서 고른 화면 언어는 문자열을 처음 찾기 전에 지정해야 하므로 가장 먼저 한다.
let stateStore = AppDelegate.makeStateStore()
AppLanguageSupport.apply(code: stateStore.load().options.language.overrideCode)

let app = NSApplication.shared
let delegate = AppDelegate(store: stateStore)
app.delegate = delegate
app.run()
