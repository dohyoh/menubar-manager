import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers
import MenuBarDomain
import MenuBarServices

/// 설정 > 일반: 로그인 시 실행, 자동 숨기기, 새 앱 정책, 단축키, 백업, 진단.
/// (시스템 아이콘 표시 여부는 "메뉴바 관리" 탭에 있다.)
struct GeneralSettingsView: View {
    let coordinator: MenuBarCoordinator
    let loginItem: any LoginItemManaging
    @Bindable var navigation: SettingsNavigation
    @State private var launchAtLogin = false
    @State private var loginError: String?
    @State private var backupMessage: String?
    @State private var didCopyDiagnostics = false

    var body: some View {
        Form {
            Section {
                Toggle(L("로그인 시 실행"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            try loginItem.setEnabled(newValue)
                            loginError = nil
                        } catch {
                            loginError = L("로그인 항목을 바꾸지 못했습니다: \(error.localizedDescription)")
                        }
                        launchAtLogin = loginItem.isEnabled
                    }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text(L("컴퓨터를 켜고 로그인하면 자동으로 시작합니다."))
            }

            Section {
                Toggle(L("펼친 뒤 자동으로 다시 숨기기"), isOn: Binding(
                    get: { coordinator.options.autoRehide },
                    set: { coordinator.setAutoRehide($0) }
                ))
                Picker(L("다시 숨기기까지"), selection: Binding(
                    get: { coordinator.options.autoRehideSeconds },
                    set: { coordinator.setAutoRehideSeconds($0) }
                )) {
                    ForEach(secondsChoices, id: \.self) { Text(L("\($0)초")).tag($0) }
                }
                .disabled(!coordinator.options.autoRehide)
            } footer: {
                Text(L("메뉴바 아이콘을 좌클릭해 펼친 경우에만 적용됩니다. 펼친 아이콘의 메뉴를 쓰는 동안에는 숨기지 않습니다. 우클릭 메뉴의 숨기기 스위치로 끈 경우에는 다시 켤 때까지 숨기지 않습니다."))
            }

            Section {
                Picker(L("새로 설치하거나 처음 실행한 앱"), selection: Binding(
                    get: { coordinator.layout.newAppPolicy },
                    set: { coordinator.setNewAppPolicy($0) }
                )) {
                    Text(L("표시")).tag(NewAppPolicy.show)
                    Text(L("숨김")).tag(NewAppPolicy.hide)
                    Text(L("묻기")).tag(NewAppPolicy.ask)
                }
            } footer: {
                Text(L("\"숨김\"으로 두면 앞으로 처음 나타나는 앱이 숨길 앱에 자동으로 추가됩니다. \"묻기\"는 메뉴바 아이콘을 가진 새 앱을 \"메뉴바 관리\"의 \"새로 나타난 앱\"에 올려 두고 정하게 합니다 (접근성 권한이 필요하며, 없으면 \"표시\"처럼 동작합니다). 이미 있는 앱에는 영향이 없습니다."))
            }

            Section {
                hotkeyRow(L("숨긴 앱 펼치기 / 숨기기"), action: .toggle)
                hotkeyRow(L("설정 열기"), action: .openSettings)
            } header: {
                Text(L("전역 단축키"))
            } footer: {
                Text(L("버튼을 누른 뒤 ⌘·⌃·⌥ 중 하나 이상을 포함한 키 조합을 누르세요. Esc 로 취소합니다."))
            }

            Section {
                HStack {
                    Button(L("설정 내보내기…")) { exportSettings() }
                    Button(L("설정 가져오기…")) { importSettings() }
                    Spacer()
                }
                if let backupMessage {
                    Text(backupMessage).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(L("백업"))
            } footer: {
                Text(L("숨길 앱 목록과 옵션을 파일로 저장하거나 불러옵니다."))
            }

            Section {
                ForEach(diagnostics, id: \.label) { row in
                    LabeledContent(row.label) {
                        Text(row.value).foregroundStyle(row.isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                }
                HStack {
                    Button(didCopyDiagnostics ? L("복사했습니다") : L("진단 정보 복사")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diagnostics.map { "\($0.label): \($0.value)" }.joined(separator: "\n"), forType: .string)
                        didCopyDiagnostics = true
                    }
                    Spacer()
                }
            } header: {
                Text(L("진단"))
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = loginItem.isEnabled }
    }

    // MARK: 단축키

    private func hotkeyRow(_ title: String, action: HotkeyAction) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(title) {
                HotkeyRecorder(hotkey: coordinator.options.hotkeys[action.rawValue]) { coordinator.setHotkey($0, for: action) }
            }
            if navigation.hotkeyFailures.contains(action.rawValue) {
                Text(L("이 조합은 등록하지 못했습니다. 다른 앱이 이미 쓰고 있을 수 있습니다."))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: 백업

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MenuBarManager-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(coordinator.exportState()).write(to: url, options: .atomic)
            backupMessage = L("설정을 내보냈습니다.")
        } catch {
            backupMessage = L("내보내지 못했습니다: \(error.localizedDescription)")
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let state = try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: url))
            Task {
                backupMessage = await coordinator.importState(state)
                    ? L("설정을 가져와 적용했습니다.")
                    : L("이 파일은 가져올 수 없습니다. MenuBarManager 에서 내보낸 설정 파일인지 확인해 주세요.")
            }
        } catch {
            backupMessage = L("이 파일은 가져올 수 없습니다. MenuBarManager 에서 내보낸 설정 파일인지 확인해 주세요.")
        }
    }

    // MARK: 진단

    private struct DiagnosticRow {
        let label: String
        let value: String
        var isProblem = false
    }

    private var diagnostics: [DiagnosticRow] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        func yesNo(_ value: Bool) -> String { value ? L("예") : L("아니요") }
        return [
            DiagnosticRow(label: L("앱 버전"), value: "\(version) (\(build))"),
            DiagnosticRow(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString),
            DiagnosticRow(label: L("현재 상태"), value: StatePresentation.summary(for: coordinator.state)),
            DiagnosticRow(label: L("숨김 기능 사용 가능"), value: yesNo(coordinator.isHidingSupported), isProblem: !coordinator.isHidingSupported),
            DiagnosticRow(label: L("응용 프로그램 폴더에 설치됨"), value: yesNo(coordinator.isInstalledInApplications), isProblem: !coordinator.isInstalledInApplications),
            DiagnosticRow(label: L("접근성 권한 (순서 조정용)"), value: yesNo(coordinator.isAccessibilityGranted)),
            DiagnosticRow(label: L("로그인 시 실행"), value: yesNo(launchAtLogin)),
            DiagnosticRow(label: L("숨긴 앱"), value: L("\(coordinator.layout.hiddenApps.count)개")),
            DiagnosticRow(label: L("메뉴바 아이콘을 가진 앱"), value: coordinator.menuBarApps.map { L("\($0.count)개") } ?? L("알 수 없음 (접근성 권한 필요)")),
        ]
    }

    /// 저장된 값이 선택지에 없으면(파일을 직접 고친 경우 등) 그 값도 보여 준다.
    private var secondsChoices: [Int] {
        let current = coordinator.options.autoRehideSeconds
        return Options.autoRehideChoices.contains(current) ? Options.autoRehideChoices : (Options.autoRehideChoices + [current]).sorted()
    }
}

/// 단축키 기록 버튼. 누른 뒤 키 조합을 누르면 그 조합을 돌려준다.
private struct HotkeyRecorder: View {
    let hotkey: Hotkey?
    let onChange: @MainActor (Hotkey?) -> Void
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(isRecording ? L("키 조합을 누르세요…") : (hotkey?.display ?? L("단축키 기록"))) {
                if isRecording { stop() } else { start() }
            }
            if hotkey != nil, !isRecording {
                Button(L("지우기")) { onChange(nil) }
            }
        }
        .onDisappear { stop() }
        // 기록 중에 창을 닫거나 다른 창으로 가면 기록을 끝낸다 (키 입력을 계속 가로채지 않도록).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if isRecording { stop() }
        }
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 필요한 값만 꺼내 메인 액터로 넘긴다.
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let characters = event.charactersIgnoringModifiers ?? ""
            MainActor.assumeIsolated {
                if Int(keyCode) == kVK_Escape {
                    stop()
                } else if !flags.intersection([.command, .control, .option]).isEmpty {
                    let modifiers = Self.carbonModifiers(flags)
                    onChange(Hotkey(keyCode: UInt32(keyCode), modifiers: modifiers,
                                    display: HotkeyFormatter.display(keyCode: UInt32(keyCode), modifiers: modifiers, fallback: characters)))
                    stop()
                }
            }
            return nil   // 기록 중에는 키 입력을 다른 곳으로 보내지 않는다
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
