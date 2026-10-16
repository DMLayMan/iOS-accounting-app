# 余记 Yuji

个人使用的原生 iPhone 记账应用。快捷录入、两级分类、可下钻统计、账本与分类预算、可恢复的本地数据。SwiftUI + UIKit，最低 iOS 17，仅 CNY，无自建服务端。

当前主界面为 **账本 / 流水 / 居中记账 / 统计 / 我的**。首次打开进入账本，正中记账为操作入口，保存或取消后回到发起页。流水和统计共用同一套时间组件与期间状态。

2026-10-16 当前：**1.0（13）正在自测与准备分发**，包含价格刷新与交易核对、完整冲突字段比较、昵称同步反馈，以及统计/记账预算布局优化。详见[本轮变更和验证](docs/release-validation-2026-10-15/build13-polish.md)。上一已安装版本为 12；备案等待，未提交 App Review。

支持开发者已接入：我的 → 顶部「好用，请开发者喝杯☕吧」，另有本机成功新建 100 笔后的一次性邀请。付款与邀请记录独立于账本，支持不解锁权益、不自动生成流水。App Store Connect 已创建三个商品草稿；2026-10-13 回读付费协议有效、两份税表使用中、银行可用。用户确认 App 免费、打赏 ¥6 / ¥18 / ¥30、首发中国大陆；商品配置与真实 Sandbox 分别验收。[发布准备](docs/app-store-2026-10-13/README.md)维护当前后台状态，原生图集、本地 StoreKit 测试批次与限制见 [支持开发者交付](docs/developer-support-2026-10-08/README.md)。

## 当前文档

| 文档 | 用途 |
| --- | --- |
| [完整 PRD](docs/PRD.md) | 当前功能、规则、用户动线、异常与验收标准 |
| [设计规范](DESIGN.md) | 配色、布局、组件状态、弹层与操作约定 |
| [页面复刻清单](docs/UI-SPEC.md) | 每页结构、共享组件、尺寸、交互与原生截图 |
| [架构与扩展指南](docs/ARCHITECTURE.md) | 状态归属、数据边界、组件复用和扩展步骤 |
| [最新送审前复审](docs/pre-submit-review-2026-10-14/README.md) | 当前问题、最新测试、产物门槛、后台字段和行动清单 |
| [10 月 8 日复审与修复](docs/review-fix-2026-10-08/README.md) | 历史原生表现、架构/性能与修复证据 |
| [支持开发者交付](docs/developer-support-2026-10-08/README.md) | 固定依赖、100 笔一次邀请、独立付款恢复、本地 StoreKit 与真实付款边界 |
| [10 月发布前审查](docs/release-audit-2026-10-03/README.md) | 历史问题、失败证据和原始页面矩阵 |
| [9 月实现回归](docs/regression-2026-09-11.md) | 历史基线，不能替代最新发布前审查 |
| [产品上下文](PRODUCT.md) | 用户已确认的产品取舍 |
| [文档索引](docs/README.md) | 当前规范与历史迭代的区别 |

## 本地开发

需要 macOS、Xcode（选择 Command Line Tools）、XcodeGen 及 Node.js（回归筛选与文档校验）。此次验证环境与结果见回归文档；最低系统声明不等于已经覆盖所有 iOS 版本。

原生工程通过私有 SSH 依赖 `DMLayMan/ios-base` 的支付修复提交 `97f38bb1b9aa31cae0f469a58a37e1641aa8870f`，需要已有仓库读取权限。消费 `DeveloperSupportKit` 的付款模型与 UI，并仅使用 `EngagementPromptKit` 的邀请 UI；纯领域和 macOS AppState 测试不依赖此远端包。

```sh
brew install xcodegen
swift test
xcodegen generate --spec ios-app/project.yml
open ios-app/Yuji.xcodeproj
xcrun simctl list devices available
```

选定模拟器 UUID 后，运行可重复的隔离回归：

```sh
scripts/regress.sh build SIMULATOR_UUID
scripts/regress.sh test SIMULATOR_UUID
scripts/regress.sh release
```

测试为每次运行生成新的隔离文件，业务日期固定为 2026-09-10；不会卸载应用或清空个人账本。`YUJI_REGRESSION_BUILD` 和 `YUJI_REGRESSION_OUTPUT` 可分别指定构建目录、结果目录。先 build 再 test；不要在同一构建目录测试进行中重建。`release` 生成未签名设备构建后运行 `scripts/verify-release-app.mjs`，核对真实包的云配置、资源及测试隔离；不证明签名、服务可用或发布。

`swift test` 在 macOS 运行领域与 AppState 测试；在 Linux 只运行纯领域测试。原生颜色和 XCUITest 通过 Xcode 运行。

## 代码结构

```text
Sources/YujiCore/             领域模型、分类/预算、统计、完整性校验、备份/CSV
Tests/YujiCoreTests/          金额、边界、500 条数据及领域回归
Fixtures/stats-500.json       2022–2026 年的确定性合成数据
scripts/generate-stats-fixture.mjs  夹具生成器
scripts/regress.sh           隔离测试与构建入口
ios-app/project.yml          工程声明，XcodeGen 生成工程
ios-app/Yuji/AppState.swift   统一写入、回滚、恢复及当前浏览期间
ios-app/Yuji/Support/        支持协调器、组件主题接线与独立付款生命周期
ios-app/Yuji/RecordSupportInvitation.swift  成功新建 100 笔的一次性本地邀请记录
ios-app/StoreKit/YujiSupport.storekit  消耗型商品的本地测试配置
ios-app/Yuji/Components/     流水行、分类图标、金额/日期格式等共享展示
ios-app/Yuji/Views/          各业务页及共用日期、预算、分类表单
ios-app/YujiTests/           状态/磁盘回归、原生颜色测试
ios-app/YujiUITests/         模拟器完整交互路径
docs/                       当前规范、审查记录与可移植截图
evidence/                   本机原始 xcresult、日志及旧图集（不提交 Git）
```

## 实现边界

- 本地 JSON 原子替换；保存失败回滚，损坏文件暂停写入并提供恢复入口。
- 新建关闭/后台留草稿检查点，撤回为空值清理旧点；收入/支出一笔一个二级分类；旧标签仅为历史兼容。
- 退款关联原支出，按退款日抵扣原分类；转账影响账户余额，不计收支或预算。
- 整账本及分类月/年预算独立，保留历史生效规则；超额提示不阻止保存。
- 六种主题及自定义颜色；支出暖橙、收入青绿、退款蓝色，语义不随主题改变。
- 完整备份带结构与数量/金额校验；恢复前保留旧数据；CSV 导出可供核对，不能用于完整恢复。
- **Production 不同账号基本共享、昵称同步与记录归属已有真实验证，完整异常矩阵仍待验**：单账本可选同步，跨账号私有邀请及只读/共同记账权限。Debug 默认关闭云配置，Release 默认开启并引用 Production 权限文件；各构建范围见[发布验证](docs/release-validation-2026-10-15/README.md)。纯本地功能无需账号。
- 自愿支持开发者使用 Apple 消耗型购买与 `displayPrice`；每次打开是新的支持选择，历史未决日志不要求用户处理后才能再次支持，交易验签和去重记录独立保留。邀请从功能接入后的本机成功新建事件计数，跨账本、稳定 ID 去重，展示前先消费；邀请文件损坏或写失败暂停自动邀请，不回滚账本。记录保存在稳定的 Application Support/YujiDeveloperSupport 目录，账本恢复不会重置，删除 App 可重置。
- 最新 TestFlight 上传/群组已验证，安装与体验单独验收。iOS 17 实际运行、VoiceOver 听读、真实触觉、功耗、最终审核仍待完成。没有广告、余记自建账号或第三方分析 SDK。
