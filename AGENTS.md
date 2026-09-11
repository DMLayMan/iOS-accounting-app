# 余记协作约定

先读 PRODUCT.md、DESIGN.md 和最近相关 docs 验收记录。用户明确要求主动把关所有页面的美感与操作动线。

新能力设计、跨应用复用或完整交付方法参考 [独立 iOS 开发沉淀](docs/indie-ios/README.md)；可按需使用仓库 `skills/indie-ios-product/SKILL.md`。它提供任务、状态和验收方法，不覆盖本项目已确认的分类、时间栏或导航设计；小改动不需要加载整套方法。

- 改 UI 前说明用户要完成的任务和最少步骤，避免见到问题就加 sheet。统计筛选必须同页联动；只有单笔详情进入层级页面。
- 默认应用已安装的 `impeccable` 原生 iOS 审查/打磨原则；产品方案不清晰时使用 `opportunity-solution-tree` 比较解决方式。技能路径不可用时重新发现；不要因此停下已获授权的低风险修复。
- 用户既有审美和明确动线高于通用技能模板。输出克制的原生工具界面。
- 页面改动先查代码与当前截图，再做最多两轮集中视觉检查；明确的功能错误继续修复。新加控件要检查深色、大字号、小屏、键盘、错误和退出状态。
- 技术校验：`swift test`；原生工程 `xcodegen generate --spec ios-app/project.yml`；按改动运行 XCUITest。确认测试使用新的 YUJI_STRESS_SESSION / YUJI_UI_TEST_SESSION 隔离文件，保护个人 ledger.json 和用户已有体验 session。
- 交付在 docs 留设计决策、问题关闭情况、实际测试与剩余限制，在 evidence 留日志与原生截图；先给用户可直接看效果的入口。
- 无请求不提交、推送或发布；当前真机签名未配置时按用户已选模拟器路径完成。
