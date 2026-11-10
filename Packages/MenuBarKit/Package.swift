// swift-tools-version: 6.0
import PackageDescription

// 모듈 의존 규칙: UI → Services → Domain ← System → PrivateBridge
// Services·UI 는 System 을 import 하지 않는다. (docs/architecture/project-structure.md)
let package = Package(
    name: "MenuBarKit",
    defaultLocalization: "ko",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MenuBarDomain", targets: ["MenuBarDomain"]),
        .library(name: "MenuBarServices", targets: ["MenuBarServices"]),
        .library(name: "MenuBarSystem", targets: ["MenuBarSystem"]),
        .library(name: "MenuBarUI", targets: ["MenuBarUI"]),
    ],
    targets: [
        .target(name: "MenuBarDomain"),
        .target(name: "MenuBarServices", dependencies: ["MenuBarDomain"]),
        .target(name: "MenuBarPrivateBridge"),
        .target(name: "MenuBarSystem", dependencies: ["MenuBarDomain", "MenuBarPrivateBridge"]),
        .target(name: "MenuBarUI", dependencies: ["MenuBarDomain", "MenuBarServices"], resources: [.process("Resources")]),
        .testTarget(name: "MenuBarDomainTests", dependencies: ["MenuBarDomain"]),
        .testTarget(name: "MenuBarServicesTests", dependencies: ["MenuBarServices", "MenuBarDomain"]),
    ],
    swiftLanguageModes: [.v6]
)
