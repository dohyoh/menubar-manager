import AppKit

/// 메뉴 안에서 쓰는 스위치.
///
/// 시스템 `NSSwitch` 는 자기 창이 활성 창이 아닐 때 켜진 상태를 회색으로 그린다.
/// 메뉴바 전용 앱의 메뉴는 활성 창이 아니므로, 켜져 있어도 꺼진 것처럼 보인다.
/// 그래서 켜짐을 항상 강조색으로 그리는 스위치를 직접 그린다.
/// (docs/architecture/platform-notes.md 3.16)
@MainActor
public final class MenuSwitch: NSControl {
    public var isOn: Bool = false {
        didSet {
            guard isOn != oldValue else { return }
            needsDisplay = true
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    public override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    private static let size = NSSize(width: 34, height: 20)

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(origin: frameRect.origin, size: Self.size))
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var intrinsicContentSize: NSSize { Self.size }
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { false }
    /// 메뉴가 열려 있는 동안 첫 클릭을 바로 받는다.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: 그리기

    public override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = track.height / 2
        let alpha: CGFloat = isEnabled ? 1 : 0.4

        let trackColor: NSColor = isOn ? .controlAccentColor : .tertiaryLabelColor
        trackColor.withAlphaComponent(trackColor.alphaComponent * alpha).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let inset: CGFloat = 2
        let diameter = track.height - inset * 2
        let x = isOn ? track.maxX - inset - diameter : track.minX + inset
        let knob = NSRect(x: x, y: track.minY + inset, width: diameter, height: diameter)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25 * alpha)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.white.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: 입력

    public override func mouseDown(with event: NSEvent) {
        // 누른 채 밖으로 나가 떼면 취소되도록, 뗄 때 판단한다.
    }

    public override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        toggleFromUser()
    }

    /// 사용자가 누른 것과 같은 경로: 값을 뒤집고 action 을 보낸다.
    public func toggleFromUser() {
        guard isEnabled else { return }
        isOn.toggle()
        sendAction(action, to: target)
    }

    // MARK: 손쉬운 사용

    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    public override func accessibilitySubrole() -> NSAccessibility.Subrole? { .switch }
    public override func accessibilityValue() -> Any? { NSNumber(value: isOn) }
    public override func isAccessibilityEnabled() -> Bool { isEnabled }
    public override func accessibilityPerformPress() -> Bool {
        toggleFromUser()
        return true
    }
}

/// 글자 + 스위치 한 줄. 줄 어디를 눌러도 스위치가 바뀐다.
@MainActor
final class MenuSwitchRow: NSView {
    private let menuSwitch: MenuSwitch

    init(title: String, menuSwitch: MenuSwitch) {
        self.menuSwitch = menuSwitch
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 30))
        autoresizingMask = [.width]

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.menuFont(ofSize: 0)

        let stack = NSStackView(views: [label, NSView(), menuSwitch])
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // 글자 부분을 눌렀을 때도 이 줄이 클릭을 받는다 (mouseDown 을 받아야 mouseUp 이 온다).
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        menuSwitch.toggleFromUser()
    }
}
