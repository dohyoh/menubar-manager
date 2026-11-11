import AppKit
import SwiftUI
import MenuBarDomain
import MenuBarServices

public enum SettingsTab: String, CaseIterable, Sendable {
    case management
    case general
    case diagnostics

    var title: String {
        switch self {
        case .management: return L("메뉴바 관리")
        case .general: return L("일반")
        case .diagnostics: return L("진단")
        }
    }
}

/// 설정 창에서 지금 보이는 탭과 첫 실행 안내 표시 여부.
/// 창을 열 때마다 "메뉴바 관리"로 되돌릴 수 있도록 밖에서 소유한다.
@MainActor
@Observable
public final class SettingsNavigation {
    public var tab: SettingsTab = .management
    public var showsWelcome = false
    /// 메뉴바 관리에서 "순서 편집" 중인가. 편집 화면은 관리 목록과 같은 자리에 뜬다.
    public var isEditingOrder = false
    /// 등록에 실패한 단축키 (HotkeyAction 의 rawValue). 다른 앱이 이미 쓰는 조합일 때.
    public var hotkeyFailures: Set<Int> = []
    public init() {}
}

/// 설정 창. 열면 "메뉴바 관리"가 먼저 보인다. (FR-17)
public struct SettingsView: View {
    private let coordinator: MenuBarCoordinator
    private let loginItem: any LoginItemManaging
    private let ordering: OrderingController
    @Bindable private var navigation: SettingsNavigation

    public init(coordinator: MenuBarCoordinator, loginItem: any LoginItemManaging, ordering: OrderingController, navigation: SettingsNavigation) {
        self.coordinator = coordinator
        self.loginItem = loginItem
        self.ordering = ordering
        self.navigation = navigation
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 창 제목 표시줄에 가려지지 않도록 탭 전환을 내용 영역 안에 둔다.
            Picker(L("탭"), selection: $navigation.tab) {
                ForEach(SettingsTab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 14)
            .padding(.bottom, 2)

            switch navigation.tab {
            case .management:
                MenuBarManagementView(coordinator: coordinator, loginItem: loginItem, ordering: ordering, navigation: navigation)
            case .general:
                GeneralSettingsView(coordinator: coordinator, loginItem: loginItem, navigation: navigation)
            case .diagnostics:
                DiagnosticsView(coordinator: coordinator, loginItem: loginItem)
            }
        }
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity, alignment: .top)
        // 다른 탭으로 가면 순서 편집을 끝낸다 (돌아왔을 때 순서를 또 읽느라 아이콘이 펼쳐지지 않도록).
        .onChange(of: navigation.tab) { navigation.isEditingOrder = false }
    }
}

// MARK: 메뉴바 관리

struct MenuBarManagementView: View {
    let coordinator: MenuBarCoordinator
    let loginItem: any LoginItemManaging
    let ordering: OrderingController
    @Bindable var navigation: SettingsNavigation
    /// 순서를 적용하고 돌아왔을 때 잠깐 보여 줄 문구
    @State private var orderNote: String?
    @State private var query = ""
    @State private var filter: AppFilter
    /// 사용자가 필터를 직접 고른 뒤에는 자동으로 바꾸지 않는다.
    @State private var didPickFilter = false

    init(coordinator: MenuBarCoordinator, loginItem: any LoginItemManaging, ordering: OrderingController, navigation: SettingsNavigation) {
        self.coordinator = coordinator
        self.loginItem = loginItem
        self.ordering = ordering
        self.navigation = navigation
        // 메뉴바 아이콘을 가진 앱을 이미 알고 있으면 처음부터 그 필터로 연다.
        // ("실행 중"으로 열었다가 조사가 끝난 뒤 바꾸면, 다른 앱들이 잠깐 보였다 사라진다.)
        _filter = State(initialValue: coordinator.menuBarApps != nil ? .menuBar : .running)
    }

    private var hidden: Set<BundleID> { coordinator.layout.hiddenApps }
    private var listed: [ManagedApp] {
        AppListFilter.apply(coordinator.apps, filter: filter, query: query, hidden: hidden, menuBarApps: coordinator.menuBarApps)
    }
    /// 목록에 보여 줄 시스템 아이콘. 검색어가 있으면 이름으로, "숨긴 앱" 필터에서는 숨긴 것만 고른다.
    private var listedSystemItems: [SystemItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return SystemItem.allCases.filter { item in
            if !q.isEmpty { return SystemItemRow.name(of: item).localizedCaseInsensitiveContains(q) }
            return filter != .hidden || coordinator.layout.hiddenSystemItems.contains(item.rawValue)
        }
    }
    /// 새로 나타났고 아직 표시할지 숨길지 정하지 않은 앱
    private var pending: [ManagedApp] {
        coordinator.apps.filter { coordinator.layout.pendingApps.contains($0.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if navigation.isEditingOrder {
                // 순서 편집: 같은 자리에서 목록이 메뉴바 순서로 바뀐다.
                OrderEditor(coordinator: coordinator, ordering: ordering) { note in
                    orderNote = note
                    navigation.isEditingOrder = false
                }
            } else {
                management
            }
        }
        .padding(16)
        .onAppear { coordinator.refreshApps() }
        .task {
            // 메뉴바 아이콘을 가진 앱을 조사해, 알 수 있으면 그 필터를 기본으로 한다.
            await coordinator.refreshMenuBarApps()
            if coordinator.menuBarApps != nil, !didPickFilter { filter = .menuBar }
            if coordinator.menuBarApps == nil, filter == .menuBar { filter = .running }
        }
    }

    @ViewBuilder
    private var management: some View {
        let listed = self.listed
        let shownApps = listed.filter { AppListFilter.isShown($0, hidden: hidden) }
        let hiddenApps = listed.filter { !AppListFilter.isShown($0, hidden: hidden) }
        let systemItems = listedSystemItems

        VStack(alignment: .leading, spacing: 12) {
            if navigation.showsWelcome {
                WelcomeBanner(loginItem: loginItem) { navigation.showsWelcome = false }
            }

            if !pending.isEmpty {
                PendingAppsBox(apps: pending) { app, hide in
                    Task { await coordinator.resolvePending(app.bundleID, hide: hide) }
                }
            }

            HStack(spacing: 10) {
                TextField(L("앱 이름 검색"), text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker(L("필터"), selection: Binding(get: { filter }, set: { filter = $0; didPickFilter = true })) {
                    // 어떤 앱이 메뉴바 아이콘을 가졌는지 알 때만(접근성 권한) 이 필터를 보여 준다.
                    if coordinator.menuBarApps != nil { Text(L("메뉴바")).tag(AppFilter.menuBar) }
                    Text(L("실행 중")).tag(AppFilter.running)
                    Text(L("숨긴 앱")).tag(AppFilter.hidden)
                    Text(L("전체")).tag(AppFilter.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            // 표시 구역과 숨김 구역으로 나눠 보여 준다.
            List {
                if !shownApps.isEmpty {
                    Section(L("표시 \(shownApps.count)개")) {
                        ForEach(shownApps) { row(for: $0) }
                    }
                }
                if !hiddenApps.isEmpty {
                    Section(L("숨김 \(hiddenApps.count)개")) {
                        ForEach(hiddenApps) { row(for: $0) }
                    }
                }
                // 시스템 아이콘(Wi-Fi, 배터리)도 같은 목록에서 고른다.
                if !systemItems.isEmpty {
                    Section {
                        ForEach(systemItems, id: \.self) { item in
                            SystemItemRow(item: item, isShown: !coordinator.layout.hiddenSystemItems.contains(item.rawValue)) { nowShown in
                                Task { await coordinator.setSystemItemHidden(item, hidden: !nowShown) }
                            }
                        }
                    } header: {
                        Text(L("시스템 아이콘"))
                    } footer: {
                        // 설명은 목록의 한 칸이 아니라 구역 아래의 글로 둔다.
                        Text(L("끄면 숨기기가 켜져 있는 동안 그 아이콘도 숨깁니다. 시계와 제어 센터는 숨기지 않습니다."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // 줄무늬 배경을 쓰면 내용이 끝난 아래쪽까지 빈 칸이 그려진다. 다른 탭처럼 내용만 보이게 한다.
            .listStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .overlay {
                if listed.isEmpty, systemItems.isEmpty {
                    Text(query.isEmpty ? L("해당하는 앱이 없습니다.") : L("\"\(query)\"에 해당하는 앱이 없습니다."))
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            HStack {
                Text(orderNote ?? StatePresentation.summary(for: coordinator.state))
                Spacer()
                Text(L("전체 \(coordinator.apps.count)개 · 숨김 \(hidden.count)개"))
                    .foregroundStyle(.secondary)
                Button(L("순서 편집")) {
                    orderNote = nil
                    navigation.isEditingOrder = true
                }
                if StatePresentation.canToggleHiding(coordinator.state) {
                    Button(coordinator.state.isHiding ? L("숨기기 끄기") : L("숨기기 켜기")) {
                        Task { await coordinator.setHidingEnabled(!coordinator.state.isHiding) }
                    }
                }
            }

            Text(coordinator.menuBarApps == nil
                 ? L("스위치를 끄면 그 앱의 아이콘이 숨겨집니다. 목록에는 메뉴바 아이콘이 없는 앱도 포함됩니다 — \"순서 편집\"에서 접근성 권한을 허용하면 메뉴바에 있는 앱만 볼 수 있습니다. 제어 센터에서 메뉴바로 꺼낸 항목(타이머 등)은 숨김 중에는 항상 숨겨집니다.")
                 : L("스위치를 끄면 그 앱의 아이콘이 숨겨집니다. 제어 센터에서 메뉴바로 꺼낸 항목(타이머 등)은 숨김 중에는 항상 숨겨집니다."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(for app: ManagedApp) -> some View {
        AppRow(app: app, isShown: AppListFilter.isShown(app, hidden: hidden)) { nowShown in
            Task { await coordinator.setHidden(app.bundleID, hidden: !nowShown) }
        }
    }
}

/// 새로 나타난 앱(정책이 "묻기"일 때). 표시할지 숨길지 정할 때까지는 표시된다.
private struct PendingAppsBox: View {
    let apps: [ManagedApp]
    let onResolve: @MainActor (ManagedApp, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("새로 나타난 앱")).font(.headline)
            ForEach(apps) { app in
                HStack(spacing: 10) {
                    Image(nsImage: AppIconCache.icon(for: app)).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
                    Text(app.name).lineLimit(1)
                    Spacer()
                    Button(L("표시")) { onResolve(app, false) }
                    Button(L("숨김")) { onResolve(app, true) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 첫 실행 안내. 한 번 닫으면 다시 나오지 않는다.
private struct WelcomeBanner: View {
    let loginItem: any LoginItemManaging
    let onClose: () -> Void
    @State private var launchAtLogin = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("시작하기")).font(.headline)
            Text(L("숨길 앱의 스위치를 끈 다음, 메뉴바의 이 앱 아이콘을 우클릭해 \"숨기기\"를 켜세요. 아이콘을 좌클릭하면 숨긴 앱이 잠깐 펼쳐집니다."))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if launchAtLogin {
                    Label(L("로그인할 때 자동으로 실행됩니다"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button(L("로그인할 때 자동으로 실행")) {
                        do {
                            try loginItem.setEnabled(true)
                            errorText = nil
                        } catch {
                            errorText = L("로그인 항목을 바꾸지 못했습니다: \(error.localizedDescription)")
                        }
                        launchAtLogin = loginItem.isEnabled
                    }
                }
                Spacer()
                Button(L("닫기"), action: onClose)
            }
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { launchAtLogin = loginItem.isEnabled }
    }
}

private struct AppRow: View {
    let app: ManagedApp
    let isShown: Bool
    let onChange: @MainActor (Bool) -> Void

    private var note: String {
        switch app.constraint {
        case .protected: return L("이 앱 — 항상 표시")
        case .outsideApplications: return L("응용 프로그램 폴더 밖 — 숨김 중에는 표시할 수 없음")
        case nil: return app.isRunning ? L("실행 중") : L("설치됨 · 실행 중 아님")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconCache.icon(for: app))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name).lineLimit(1)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(app.constraint == .outsideApplications ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle(L("\(app.name) 메뉴바에 표시"), isOn: Binding(get: { isShown }, set: { onChange($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(app.constraint != nil)
        }
        .padding(.vertical, 2)
    }
}

/// 시스템 아이콘 한 줄 (Wi-Fi, 배터리). 앱 줄과 같은 모양의 스위치를 쓴다.
private struct SystemItemRow: View {
    let item: SystemItem
    let isShown: Bool
    let onChange: @MainActor (Bool) -> Void

    static func name(of item: SystemItem) -> String {
        switch item {
        case .wifi: return L("Wi-Fi")
        case .battery: return L("배터리")
        }
    }

    private var symbolName: String {
        switch item {
        case .wifi: return "wifi"
        case .battery: return "battery.100percent"
        }
    }

    var body: some View {
        let name = Self.name(of: item)
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(name).lineLimit(1)
            Spacer(minLength: 8)
            Toggle(L("\(name) 메뉴바에 표시"), isOn: Binding(get: { isShown }, set: { onChange($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

@MainActor
enum AppIconCache {
    private static var cache: [BundleID: NSImage] = [:]

    static func icon(for app: ManagedApp) -> NSImage {
        if let cached = cache[app.bundleID] { return cached }
        let image = app.path.map { NSWorkspace.shared.icon(forFile: $0) }
            ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            ?? NSImage()
        cache[app.bundleID] = image
        return image
    }
}
