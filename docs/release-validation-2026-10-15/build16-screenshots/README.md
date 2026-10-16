# 构建 16 商店截图

2026-10-16，源代码 af89f013529cc87f5f12fafb3b114ec52a53e5d0，1.0（16）。五张 PNG 均为原生 Release App 运行截图，1206 × 2622，无透明通道；没有拼贴、重绘或调整页面内容。文件与原始 XCTest 附件对应关系和 SHA-256 见 [manifest.json](manifest.json)。

1. [记账](appstore16-01-entry.png)：分类、金额、备注和数字键盘。
2. [统计](appstore16-02-statistics.png)：分类饼图、排行和同页明细。
3. [预算](appstore16-03-budgets.png)：月年总额与分类规则。
4. [账本](appstore16-04-ledger.png)：累计汇总及账户。
5. [流水](appstore16-05-feed.png)：期间、收支及分行备注。

使用独立 iPhone 16 Pro / iOS 26.5 模拟器 Yuji-Store16-20261016（9CB08041-7682-4577-8A5E-B42F10C18E42），仅合成账本，没有个人数据或云绑定。AUT 是本次正常 Xcode 签名的 Release；独立 Debug XCTest runner 驱动截图。两个 AppStoreCapture 用例通过，0 失败、0 跳过，截图逐张视觉复核。

原始证据保留在私有 evidence/build16-20261016/：Capture16Final.xcresult、capture-final-summary.json、capture-attachments。最初关闭模拟器代码签名导致 CloudKit entitlement 缺失，随后手工补签也未启动；两个失败批次保留，不能算产品回归通过。正式 App Store IPA 不受这些截图工具调整影响。

后台截图更新仅移除版本中的旧图关联，旧素材仍保留在素材库。实际保存和审核草稿结果见 [构建 16 交付](../build16-delivery.md)。
