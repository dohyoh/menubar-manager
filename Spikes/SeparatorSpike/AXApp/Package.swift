// swift-tools-version: 6.0
import PackageDescription

// 검증용 (제품 코드 아님). 제품의 접근성 코드(MenuBarSystem)를 그대로 가져다 쓴다.
let package = Package(
    name: "SeparatorSpikeApp",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../../Packages/MenuBarKit")],
    targets: [
        .executableTarget(
            name: "SeparatorSpikeApp",
            dependencies: [
                .product(name: "MenuBarDomain", package: "MenuBarKit"),
                .product(name: "MenuBarSystem", package: "MenuBarKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
