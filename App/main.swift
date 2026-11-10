import AppKit

// 메뉴바 전용 앱 (Info.plist 의 LSUIElement). SwiftUI App 대신 NSApplication 을 직접 띄워
// 상태 아이콘의 좌클릭/우클릭과 창 표시를 정확히 제어한다.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
