# 余记 Yuji · 个人记账 App

少一点干扰，多一点顺手。本地优先的个人记账应用：快捷录入、可解释的统计、可恢复的数据。

依据飞书 PRD v1、UI v2 与架构文档（2026-09-09）实现。本仓库是**原生 iOS（SwiftUI）实现**，不是浏览器原型。

## 仓库结构

```
Package.swift                 Swift Package 声明（YujiCore 可跨平台 `swift test`）
Sources/YujiCore/             纯领域层（不依赖 SwiftUI/UIKit，可在 Linux/macOS 编译测试）
  Money.swift                 整数「分」金额、CNY 格式化
  Calculator.swift            十进制算式计算器（PRD §8）
  Models.swift                账本/账户/分类/标签/交易/草稿、Day/MonthKey
  LedgerData.swift            全量数据快照、设置、领域错误
  LedgerStore.swift           领域服务：全部业务不变量、CRUD、退款、批量、回收站
  Stats.swift                 月/年统计、同比环比、分类/标签分析（PRD §7）
  Persistence.swift           JSON 原子落盘、完整备份/恢复校验
  CSVExporter.swift           CSV 导出（RFC4180 + 公式注入防护）
Tests/YujiCoreTests/          单元测试（38 个，覆盖 PRD §12 全部独立验收样本）
ios-app/                      SwiftUI 应用（在 Mac/Xcode 构建）
  project.yml                 XcodeGen 工程声明
  Yuji/                       App 入口、设计系统、全部页面
```

## 已实现范围（P0 个人版）

- **多账本/账户**：创建/改名/归档/空账本删除、切换隔离；账户期初、记账起点、归档、余额公式。
- **交易 CRUD**：支出/收入/转账/退款；稳定 ID、修订号、幂等 operationID（防重复保存）。
- **两级分类（单选叶子）+ 两级标签（多选、跨组）**；改名/归档/删除规则。
- **金额计算器**：+−×÷、括号、优先级、一元负号、十进制求值（不用 Double）、舍入确认、除零/越界拦截。
- **退款**：关联原支出、累计不超额、日期不早于原支出、原支出受保护、跨月退款按发生期冲减。
- **转账**：同账本两账户整体提交，不进收支/预算统计。
- **统计**：月/年五项口径、环比/同比（当前月同进度、月份不足/基期≤0 不给误导百分比）、YTD 与闰年处理、分类守恒、标签去重与父级并集。
- **回收站**：逻辑删除、短时撤销、恢复重校验、永久删除。
- **批量操作**：整批成功或整批不变，阻塞项可见。
- **草稿**：取消保留、首页/＋恢复，不进统计。
- **备份/恢复**：完整备份含校验清单，隔离校验后切换，失败原库不动；CSV 导出。
- **UI v2**：白色画布、炭黑金额、鼠尾草绿；底部中央＋；7 常用分类；录入数字区固定底端；深色/浅色、等宽金额。

## 在 Linux 上自测领域逻辑（已在本环境执行）

```bash
swift test        # 38 个测试，0 失败
```

领域层不依赖 iOS SDK，所有金额、退款、转账、统计口径、隔离、备份恢复、批量、幂等等规则在此全量验证。

## 在 Mac 上构建 iOS App

```bash
brew install xcodegen
cd ios-app
xcodegen generate          # 生成 Yuji.xcodeproj（本地引用 ../ 的 YujiCore 包）
open Yuji.xcodeproj
# 选择 iOS 16+ 模拟器或真机运行
```

> 最低系统：iOS 16（使用 NavigationStack 等 iOS16 API）。

## 测试与验收对应

`Tests/YujiCoreTests/DomainAcceptanceTests.swift` 逐条对应 PRD §12 的 18 个独立验收样本：
基础余额、编辑与退款上限、转账删除恢复、跨月退款、分类守恒、标签重叠去重、部分月比较、
基期零/负、月份不足、YTD 同比、日期归属、多账本隔离、批量原子、回收站并发额度、
完整备份恢复、保存中断幂等，外加计算器 §8 全部用例。

## 未包含 / 后续阶段

- **个人 iCloud 同步（P1）**、**家庭共享（P2）**：架构与边界已在架构文档设计，本版入口标注「未开放」，不提供假流程。
- 预算、快捷模板、重复计划、CSV 导入（P1）：领域预留，未在本轮 UI 展开。
- 真机验收（VoiceOver、动态字号、触觉、系统键盘、签名安装、App Store 发布）需在目标 iPhone 上进行；
  本仓库的 SwiftUI 层未在本机（Linux）编译，构建以 Mac/Xcode 为准。

## 数据与隐私

仅 CNY；无业务登录、无自建服务器、无广告与第三方分析 SDK。数据保存在本机 Application Support，
可随时导出完整备份或 CSV。
