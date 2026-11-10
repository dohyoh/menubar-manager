// 앱 아이콘을 그려 App/Resources/AppIcon.icns 로 저장한다.
//   swift scripts/make-icon.swift
// 모양: 메뉴바 아이콘과 같은 "오른쪽 절반이 채워진 네모" (숨김 적용 중 상태).
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("MenuBarManager-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)

    // 바탕: macOS 아이콘 비율의 둥근 사각형 (캔버스의 약 80%)
    let plate = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.62, blue: 0.58, alpha: 1),
               ending: NSColor(calibratedRed: 0.09, green: 0.36, blue: 0.36, alpha: 1))!.draw(in: platePath, angle: -90)

    // 기호: 흰 테두리 네모 + 오른쪽 절반 채움
    let glyph = NSRect(x: s * 0.30, y: s * 0.30, width: s * 0.40, height: s * 0.40)
    let radius = s * 0.07
    let outline = NSBezierPath(roundedRect: glyph, xRadius: radius, yRadius: radius)
    NSColor.white.setStroke()
    outline.lineWidth = s * 0.045
    outline.stroke()
    NSGraphicsContext.saveGraphicsState()
    outline.addClip()
    NSColor.white.setFill()
    NSRect(x: glyph.midX, y: glyph.minY, width: glyph.width / 2, height: glyph.height).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try draw(pixels: points * scale).write(to: iconset.appendingPathComponent(name))
}

let output = root.appendingPathComponent("App/Resources/AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(process.terminationStatus == 0 ? "wrote \(output.path)" : "iconutil failed")
