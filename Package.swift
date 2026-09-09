// swift-tools-version:5.5
// 余记 Yuji — 个人记账
// YujiCore 是纯领域层，不依赖 SwiftUI/UIKit，可在 Linux 上用 `swift test` 全量测试。
// YujiApp 是 SwiftUI 应用层，仅能在 macOS/Xcode（iOS SDK）下构建。
import PackageDescription

let package = Package(
    name: "Yuji",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "YujiCore", targets: ["YujiCore"]),
    ],
    targets: [
        .target(
            name: "YujiCore",
            path: "Sources/YujiCore"
        ),
        .testTarget(
            name: "YujiCoreTests",
            dependencies: ["YujiCore"],
            path: "Tests/YujiCoreTests"
        ),
    ]
)
