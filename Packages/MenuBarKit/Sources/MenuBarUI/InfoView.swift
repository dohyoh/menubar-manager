import SwiftUI

/// "정보" 화면의 설명 문구. 기능이 바뀌면 여기를 함께 고친다. (FR-20)
public struct InfoItem: Identifiable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public let title: String
    public let body: String
}

public enum InfoContent {
    public static var items: [InfoItem] {
        [
            InfoItem(symbol: "cursorarrow.click",
                     title: L("숨긴 앱 펼치기 / 숨기기"),
                     body: L("메뉴바의 이 앱 아이콘을 좌클릭합니다. 한 번 누르면 숨긴 앱이 모두 나타나고, 다시 누르면 숨습니다.")),
            InfoItem(symbol: "switch.2",
                     title: L("숨기기 켜고 끄기"),
                     body: L("아이콘을 우클릭한 뒤 \"숨기기\" 스위치를 사용합니다. 끄면 다시 켤 때까지 모든 아이콘을 표시합니다.")),
            InfoItem(symbol: "checklist",
                     title: L("숨길 앱 고르기"),
                     body: L("우클릭 > 설정…의 \"메뉴바 관리\"에서 앱별 스위치를 끄면 그 앱의 아이콘이 숨겨집니다. 앱이 많으면 검색과 필터로 찾습니다. 목록 아래쪽에서 Wi-Fi·배터리 같은 시스템 아이콘도 고를 수 있습니다.")),
            InfoItem(symbol: "timer",
                     title: L("자동으로 다시 숨기기"),
                     body: L("설정 > 일반에서 켜 두면, 좌클릭으로 펼친 뒤 지정한 시간이 지나면 자동으로 다시 숨깁니다. 펼친 아이콘의 메뉴를 쓰는 동안에는 숨기지 않습니다.")),
            InfoItem(symbol: "arrow.left.arrow.right",
                     title: L("메뉴바 아이콘 옮기기"),
                     body: L("설정 > 메뉴바 관리의 \"순서 편집\"에서 목록을 드래그해 바꾼 뒤 적용합니다 (접근성 권한 필요). 또는 ⌘(Command) 키를 누른 채 메뉴바의 아이콘을 직접 좌우로 드래그해도 됩니다. 숨긴 앱은 먼저 펼친 다음 옮깁니다.")),
            InfoItem(symbol: "keyboard",
                     title: L("전역 단축키"),
                     body: L("설정 > 일반에서 \"숨긴 앱 펼치기 / 숨기기\"와 \"설정 열기\"에 키 조합을 지정하면, 어느 앱을 쓰는 중이든 그 키로 실행합니다.")),
            InfoItem(symbol: "bell",
                     title: L("알림 센터"),
                     body: L("숨김 중에도 메뉴바의 시계를 누르면 알림 센터가 열립니다 (열려 있는 동안 숨긴 아이콘이 잠깐 보입니다). 트랙패드를 쓸어서 여는 경우에는 먼저 이 앱 아이콘을 좌클릭해 펼쳐 주세요.")),
            InfoItem(symbol: "exclamationmark.circle",
                     title: L("알아 둘 점"),
                     body: L("응용 프로그램 폴더 밖에 있는 앱과 제어 센터에서 꺼낸 항목(타이머 등)은 숨김 중에는 표시되지 않습니다. 이 앱을 종료하면 숨긴 아이콘은 모두 돌아옵니다. 아이콘이 보이지 않을 때는 응용 프로그램 폴더에서 이 앱을 다시 열면 설정 창이 나타납니다.")),
        ]
    }
}

public struct InfoView: View {
    private let appName: String
    private let version: String

    public init(appName: String, version: String) {
        self.appName = appName
        self.version = version
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("\(appName) 사용법")).font(.title2.bold())
                Text(L("버전 \(version)")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(InfoContent.items) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(.tint)
                        .frame(width: 28, alignment: .center)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.body.weight(.semibold))
                        Text(item.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 460, alignment: .leading)
    }
}
