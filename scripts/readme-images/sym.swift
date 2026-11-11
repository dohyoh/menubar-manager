import AppKit
// SF Symbol 을 검은색 틀(PNG, 투명 배경)로 그려 base64 로 내보낸다: {"이름": {"w":..,"h":..,"png":"..."}}
let names = Array(CommandLine.arguments.dropFirst())
var out: [String: [String: Any]] = [:]
for name in names {
    let config = NSImage.SymbolConfiguration(pointSize: 64, weight: .medium)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
        FileHandle.standardError.write("missing \(name)\n".data(using: .utf8)!); continue
    }
    let size = base.size
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    base.draw(in: NSRect(origin: .zero, size: size))
    NSColor.black.set()
    NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
    NSGraphicsContext.current = nil
    let png = rep.representation(using: .png, properties: [:])!
    out[name] = ["w": size.width, "h": size.height, "png": png.base64EncodedString()]
}
let data = try! JSONSerialization.data(withJSONObject: out)
FileHandle.standardOutput.write(data)
