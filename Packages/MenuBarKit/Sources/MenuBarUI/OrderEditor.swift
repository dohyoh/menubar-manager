import SwiftUI
import MenuBarDomain
import MenuBarServices

/// 메뉴바 관리의 "순서 편집" 화면. 메뉴바의 현재 순서를 읽어 목록으로 보여 주고,
/// 드래그해 바꾼 순서를 메뉴바에 적용한다. (FR-3)
///
/// 관리 목록과 같은 자리에 뜬다. 열 때 한 번 순서를 읽고(숨긴 아이콘이 잠깐 나타난다),
/// 적용하거나 취소하면 관리 목록으로 돌아간다.
struct OrderEditor: View {
    let coordinator: MenuBarCoordinator
    let ordering: OrderingController
    /// 편집을 끝낸다. 순서를 적용했으면 관리 화면에 보여 줄 알림 문구를 넘긴다.
    let onFinish: @MainActor (String?) -> Void
    /// 사용자가 목록에서 바꾸고 있는 순서. "적용"을 누르기 전까지 메뉴바는 그대로다.
    @State private var draft: [MenuBarItem] = []

    private var isChanged: Bool { draft.map(\.id) != ordering.items.map(\.id) }

    /// 시스템 항목은 이름을 알 수 없어서(접근성 정보에 제목이 없음) 왼쪽부터 번호를 붙여 구분한다.
    private var systemOrdinals: [MenuBarItem.ID: Int] {
        var result: [MenuBarItem.ID: Int] = [:]
        for (index, item) in draft.filter(\.isSystem).enumerated() { result[item.id] = index + 1 }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if ordering.isAccessibilityGranted {
                content
            } else {
                permissionBox
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button(L("취소")) { onFinish(nil) }
                }
            }
        }
        .task {
            ordering.refreshPermission()
            if ordering.isAccessibilityGranted { await reload() }
        }
    }

    /// 메뉴바의 현재 순서를 읽어 목록을 채운다.
    private func reload() async {
        await ordering.read()
        draft = ordering.items
    }

    @ViewBuilder
    private var content: some View {
        HStack {
            Text(L("목록을 드래그해 순서를 바꾼 뒤 \"적용\"을 누르세요. 위가 메뉴바의 왼쪽입니다."))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L("메뉴바에서 순서 읽기")) { Task { await reload() } }
                .disabled(ordering.isBusy)
        }
        .padding(10)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

        List {
            ForEach(draft) { item in
                OrderRow(item: item, app: coordinator.apps.first { $0.bundleID == item.bundleID },
                         isHidden: coordinator.layout.hiddenApps.contains(item.bundleID),
                         systemOrdinal: systemOrdinals[item.id])
                    .moveDisabled(item.isSystem || ordering.isBusy)
            }
            .onMove { from, to in draft.move(fromOffsets: from, toOffset: to) }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .overlay {
            if draft.isEmpty, !ordering.isBusy {
                Text(L("\"메뉴바에서 순서 읽기\"를 눌러 현재 순서를 가져오세요."))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

        HStack {
            if ordering.isBusy { ProgressView().controlSize(.small) }
            Text(statusText)
            Spacer()
            Button(L("취소")) { onFinish(nil) }
                .disabled(ordering.isBusy)
            Button(L("적용")) {
                Task {
                    await ordering.apply(target: draft.map(\.id))
                    draft = ordering.items   // 실패했더라도 실제 순서에 맞춘다
                    // 다 옮겼으면 관리 목록으로 돌아간다. 실패했으면 남아서 결과를 보여 준다.
                    if ordering.status == .succeeded { onFinish(L("순서를 적용했습니다.")) }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isChanged || ordering.isBusy)
        }

        Text(L("읽거나 적용하는 동안 숨긴 아이콘이 잠깐 나타나고, 적용 중에는 포인터가 잠깐 움직입니다. 시스템 항목(시계, 제어 센터 등)은 옮길 수 없지만 그 사이로 다른 아이콘을 옮길 수는 있습니다. 메뉴바에서 ⌘을 누른 채 직접 끌어도 됩니다."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var permissionBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("순서를 바꾸려면 접근성 권한이 필요합니다")).font(.headline)
            Text(coordinator.visibilityTraits.requiresAccessibility
                 ? L("이 앱이 ⌘을 누른 채 아이콘을 끄는 동작을 대신 수행하기 때문입니다. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 MenuBarManager를 켜 주세요.")
                 : L("이 앱이 ⌘을 누른 채 아이콘을 끄는 동작을 대신 수행하기 때문입니다. 숨기기와 펼치기에는 이 권한이 필요하지 않습니다. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 MenuBarManager를 켜 주세요."))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("접근성 권한 요청")) { ordering.requestPermission() }
                Button(L("다시 확인")) {
                    ordering.refreshPermission()
                    if ordering.isAccessibilityGranted { Task { await reload() } }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        switch ordering.status {
        case .idle:
            if draft.isEmpty { return "" }
            return isChanged ? L("바꾼 순서는 아직 적용되지 않았습니다.") : L("메뉴바의 현재 순서입니다.")
        case .reading:
            return L("메뉴바에서 순서를 읽는 중…")
        case .applying(let done, let total):
            return L("아이콘을 옮기는 중… \(String(done))/\(String(total))")
        case .succeeded:
            return isChanged ? L("바꾼 순서는 아직 적용되지 않았습니다.") : L("순서를 적용했습니다.")
        case .failed(.stuck):
            return L("일부 아이콘을 옮기지 못했습니다. 목록을 실제 순서로 맞췄습니다.")
        case .failed(.accessibilityNotGranted):
            return L("접근성 권한이 필요합니다.")
        case .failed:
            return L("순서를 바꾸지 못했습니다.")
        }
    }
}

private struct OrderRow: View {
    let item: MenuBarItem
    let app: ManagedApp?
    let isHidden: Bool
    let systemOrdinal: Int?

    private var name: String {
        guard item.isSystem else { return item.appName }
        return systemOrdinal.map { L("시스템 항목 \(String($0))") } ?? L("시스템 항목")
    }

    private var detail: String? {
        if item.isSystem { return item.title.map(Self.readable) ?? L("시계·제어 센터·Wi-Fi 등 — 옮길 수 없음") }
        // 이 앱 자신의 제목은 현재 상태 문구라서 보여 주지 않는다.
        if app?.constraint == .protected { return nil }
        if let title = item.title, title != item.appName { return title }
        return nil
    }

    /// "com.apple.menuextra.clock" 같은 식별자는 마지막 부분만 보여 준다.
    private static func readable(_ title: String) -> String {
        guard title.hasPrefix("com.apple."), let last = title.split(separator: ".").last else { return title }
        return String(last)
    }

    var body: some View {
        HStack(spacing: 10) {
            // 끌 수 있는 줄에는 손잡이를 보여 준다. 시스템 항목은 자리를 비워 줄을 맞춘다.
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .opacity(item.isSystem ? 0 : 1)
                .accessibilityHidden(true)
            Group {
                if let app, !item.isSystem {
                    Image(nsImage: AppIconCache.icon(for: app)).resizable()
                } else {
                    Image(systemName: item.isSystem ? "lock" : "app").foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(name).lineLimit(1).foregroundStyle(item.isSystem ? .secondary : .primary)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isHidden { tag(L("숨김")) }
            if item.isSystem { tag(L("고정")) }
        }
        .padding(.vertical, 2)
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}
