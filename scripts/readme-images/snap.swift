import AppKit
import WebKit
// 로컬 HTML 을 그려 PNG 로 저장한다 (배경 투명, 높이는 내용에 맞춤).
//   snap <html> <png> <너비 pt>
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let width = CGFloat(Double(args[3]) ?? 1200)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
final class Loader: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().height)") { value, _ in
            let height = CGFloat((value as? NSNumber)?.doubleValue ?? 2000)
            webView.frame = NSRect(x: 0, y: 0, width: webView.frame.width, height: height)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let config = WKSnapshotConfiguration()
                config.rect = NSRect(x: 0, y: 0, width: webView.frame.width, height: height)
                webView.takeSnapshot(with: config) { image, _ in
                    if let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: out); print("saved", Int(webView.frame.width), Int(height))
                    } else { print("snapshot failed") }
                    exit(0)
                }
            }
        }
    }
}
let loader = Loader()
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 1000))
web.navigationDelegate = loader
web.setValue(false, forKey: "drawsBackground")
web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
DispatchQueue.main.asyncAfter(deadline: .now() + 15) { print("timeout"); exit(1) }
app.run()
