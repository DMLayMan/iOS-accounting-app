// swift-tools-version:5.5
// 余记 Yuji — 个人记账
// YujiCore 是纯领域层，不依赖 SwiftUI/UIKit，可在 Linux 上用 `swift test` 全量测试。
// YujiApp 是 SwiftUI 应用层，仅能在 macOS/Xcode（iOS SDK）下构建。
import PackageDescription

var targets: [Target] = [
    .target(name: "YujiCore", path: "Sources/YujiCore"),
    .testTarget(name: "YujiCoreTests", dependencies: ["YujiCore"], path: "Tests/YujiCoreTests")
]
#if os(macOS)
// 同一 AppState 源码可在 macOS 上隔离验证持久化失败，不依赖模拟器测试宿主。
targets += [
    .target(name: "YujiAppState", dependencies: ["YujiCore"], path: "ios-app/Yuji",
            exclude: ["Assets.xcassets", "Info.plist", "Design.swift", "Views", "Components", "YujiApp.swift"],
            sources: ["AppState.swift"]),
    .testTarget(name: "YujiAppStateTests", dependencies: ["YujiAppState", "YujiCore"],
                path: "ios-app/YujiTests", exclude: ["Native"])
]
#endif

let package = Package(
    name: "Yuji",
    platforms: [
        .iOS(.v15), .macOS(.v12)
    ],
    products: [
        .library(name: "YujiCore", targets: ["YujiCore"]),
    ],
    targets: targets
)
