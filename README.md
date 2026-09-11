# 余记 Yuji

个人使用的原生 iPhone 记账应用。快捷录入、两级分类、可下钻统计、账本与分类预算、可恢复的本地数据。SwiftUI + UIKit，最低 iOS 16，仅 CNY，无自建服务端。

当前主界面为 **账本 / 流水 / 居中记账 / 统计 / 我的**。首次打开进入账本，正中记账为操作入口，保存或取消后回到发起页。流水和统计共用同一套时间组件与期间状态。

## 当前文档

| 文档 | 用途 |
| --- | --- |
| [完整 PRD](docs/PRD.md) | 当前功能、规则、用户动线、异常与验收标准 |
| [设计规范](DESIGN.md) | 配色、布局、组件状态、弹层与操作约定 |
| [页面复刻清单](docs/UI-SPEC.md) | 每页结构、共享组件、尺寸、交互与原生截图 |
| [架构与扩展指南](docs/ARCHITECTURE.md) | 状态归属、数据边界、组件复用和扩展步骤 |
| [本轮回归与审查](docs/regression-2026-09-11.md) | 已修问题、实际验证、未覆盖边界 |
| [产品上下文](PRODUCT.md) | 用户已确认的产品取舍 |
| [文档索引](docs/README.md) | 当前规范与历史迭代的区别 |

## 本地开发

需要 macOS、Xcode（选择 Command Line Tools）及 XcodeGen。此次验证环境与结果见回归文档；最低系统声明不等于已经覆盖所有 iOS 版本。

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

测试为每次运行生成新的隔离文件，业务日期固定为 2026-09-10；不会卸载应用或清空个人账本。`YUJI_REGRESSION_BUILD` 和 `YUJI_REGRESSION_OUTPUT` 可分别指定构建目录、结果目录。先 build 再 test；不要在同一构建目录测试进行中重建。`release` 只生成未签名的设备构建，不代表安装或发布。

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
ios-app/Yuji/Components/     流水行、分类图标、金额/日期格式等共享展示
ios-app/Yuji/Views/          各业务页及共用日期、预算、分类表单
ios-app/YujiTests/           状态/磁盘回归、原生颜色测试
ios-app/YujiUITests/         模拟器完整交互路径
docs/                       当前规范、审查记录与可移植截图
evidence/                   本机原始 xcresult、日志及旧图集（不提交 Git）
```

## 实现边界

- 本地 JSON 原子替换；保存失败回滚，损坏文件暂停写入并提供恢复入口。
- 新建关闭留草稿；收入/支出一笔一个二级分类；旧标签仅为历史兼容。
- 退款关联原支出，按退款日抵扣原分类；转账影响账户余额，不计收支或预算。
- 整账本及分类月/年预算独立，保留历史生效规则；超额提示不阻止保存。
- 六种主题及自定义颜色；支出暖橙、收入青绿、退款蓝色，语义不随主题改变。
- 完整备份带结构与数量/金额校验；恢复前保留旧数据；CSV 导出可供核对，不能用于完整恢复。
- **iCloud 尚未实现**，入口始终显示未开放。[同账号与跨账号共享方案](docs/icloud-sharing-plan-2026-09-10.md)为后续设计。
- 真机签名、VoiceOver 听读、真实触觉、功耗、App Store 上传与审核尚未完成。没有广告、登录或第三方分析 SDK。
