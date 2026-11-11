import AppKit
import SwiftUI
import MenuBarDomain
import MenuBarServices

/// 설정 > 진단: 앱이 지금 어떤 상태인지, 숨김을 쓸 수 있는 환경인지 보여 준다. (FR-8)
/// 문제가 생겼을 때 그대로 복사해 전달할 수 있다.
struct DiagnosticsView: View {
    let coordinator: MenuBarCoordinator
    let loginItem: any LoginItemManaging
    let navigation: SettingsNavigation
    @State private var launchAtLogin = false
    @State private var didCopy = false

    var body: some View {
        Form {
            Section {
                ForEach(rows, id: \.label) { row in
                    LabeledContent(row.label) {
                        Text(row.value).foregroundStyle(row.isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                }
            } footer: {
                HStack {
                    Button(didCopy ? L("복사했습니다") : L("진단 정보 복사")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n"), forType: .string)
                        didCopy = true
                    }
                    Spacer()
                }
                .padding(.top, 6)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = loginItem.isEnabled }
        // 이 탭으로 올 때마다 새로 읽는다 (탭을 바꿔도 이 화면은 그대로 남아 있다).
        .onChange(of: navigation.tab) {
            guard navigation.tab == .diagnostics else { return }
            didCopy = false
            // 새로 읽는 일은 화면이 먼저 바뀐 뒤에 한다.
            Task {
                launchAtLogin = loginItem.isEnabled
                await coordinator.refreshMenuBarApps()
            }
        }
    }

    private struct Row {
        let label: String
        let value: String
        var isProblem = false
    }

    private var rows: [Row] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        func yesNo(_ value: Bool) -> String { value ? L("예") : L("아니요") }
        let traits = coordinator.visibilityTraits
        // 구분자 방식에서는 접근성 권한이 없으면 숨김 자체를 쓸 수 없다.
        let needsAccessibility = traits.requiresAccessibility
        return [
            Row(label: L("앱 버전"), value: "\(version) (\(build))"),
            Row(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString),
            Row(label: L("현재 상태"), value: StatePresentation.summary(for: coordinator.state)),
            Row(label: L("숨김 기능 사용 가능"), value: yesNo(coordinator.isHidingSupported), isProblem: !coordinator.isHidingSupported),
            Row(label: L("숨김 방식"), value: !coordinator.isHidingSupported ? L("없음") : needsAccessibility ? L("구분자 (macOS 26 이하)") : L("시스템 허용 목록")),
            Row(label: L("응용 프로그램 폴더에 설치됨"), value: yesNo(coordinator.isInstalledInApplications), isProblem: !coordinator.isInstalledInApplications),
            Row(label: needsAccessibility ? L("접근성 권한 (숨김·순서 조정용)") : L("접근성 권한 (순서 조정용)"), value: yesNo(coordinator.isAccessibilityGranted),
                isProblem: needsAccessibility && !coordinator.isAccessibilityGranted),
            Row(label: L("로그인 시 실행"), value: yesNo(launchAtLogin)),
            Row(label: L("숨긴 앱"), value: L("\(coordinator.layout.hiddenApps.count)개")),
            Row(label: L("메뉴바 아이콘을 가진 앱"), value: coordinator.menuBarApps.map { L("\($0.count)개") } ?? L("알 수 없음 (접근성 권한 필요)")),
        ]
    }
}
