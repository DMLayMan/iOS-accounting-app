# 审查问题与关闭条件

P1 表示本项目发布前应关闭，不等同于 Apple 一定拒审；P2 表示应明确修复或接受的体验/维护风险。没有证据的推测不列成已确认缺陷。

以下为 10 月 3 日发现时的状态，最新关闭证据见[10 月 8 日修复记录](../review-fix-2026-10-08/README.md)。保留“未修复”等当日描述用于追溯。

## R01 · P1 · 同一账户的余额跨页面不一致（已复现，未修复）

- 位置：`ios-app/Yuji/Views/ManageViews.swift:26` 调用 `balance(accountID:)`；`LedgerHomeView` 通过 `overview(...through: today)` 截止当天。
- 复现：期初 ¥100，新增明天 ¥10 支出。首页余额 ¥100，账户列表 ¥90。读回/备份均合法，因此不是脏数据。精确数字见 [领域探针](verification/domain-probes.json)。
- 影响：未来记账是已有正式能力，用户正常查账会对同一余额得到两个答案。
- 关闭：统一“当前余额”截止规则；未来期初明确标注未生效。补全今日/未来收支/转账/退款/未来账户起点的页面联动断言。

## R09 · P1 · 长账户名撑宽整个记账页（原生失败断言与截图确认，未修复）

- 位置：`ios-app/Yuji/Views/EntryView.swift:78`，账户和日期均使用横向 `fixedSize`，账户名未设置可压缩宽度；账户编辑允许正常保存长名称。
- 复现：新建“家庭日常共同生活专用银行卡账户用于验证长名称显示（含家庭旅行专项储蓄与长期备用金）”，记账中选择该账户。iPhone 17 Pro / iOS 26.5 上日期右边界 490.67pt，屏幕宽 402pt；金额、分类、备注和键盘也被横向撑出屏幕。
- 证据：新增 `ReleaseReadinessUITests.testLongAccountNameKeepsEntryDateOnScreen` 失败，[原生原图](assets/long-account-overflow.png)。较短的 26 字名称在同机通过，不能用短样本替代边界测试。
- 影响：正常自定义文本破坏核心记账任务，用户无法可靠操作日期/金额/保存。
- 关闭：约束账户栏可用宽度并截断/换行，在选择器中仍可读全名；日期和金额键盘独立保留布局宽度。不通过简单禁止长名称掩盖容器溢出；回归普通/长名称、两机型及大字号，保持这条失败断言。
- 建议：`/impeccable harden`，修复后补父容器、金额与保存键均在屏幕内的断言。

## R02 · P2 · 流水筛选的文档超出界面能力（文档已纠正，UI 未增加）

- 位置：`MeAndData.swift` 的 `SearchFilterView` 仅关键词、类型、分类；`LedgerBrowsing.swift` 另有账户/金额条件。
- 影响：PRD 原称账户、金额区间也可用，开发者或验收人员会误以为功能完整。
- 已做：PRD §7 改为真实界面范围；账户/金额 UI 保留为明确待办，不把领域单元测试算成页面交付。
- 关闭：首发需要时加两个简单过滤项并显示已选条件，验证转账匹配任一账户；否则商店说明与验收范围不承诺这些入口。

## R03 · P1 · 缺失发布图标（源码、归档、模拟器均确认）

- 位置：`ios-app/Yuji/Assets.xcassets/AppIcon.appiconset/Contents.json` 唯一条目没有 filename；`project.yml` 未配置有效 AppIcon 编译名称；归档 Info.plist 无 CFBundleIcons。
- 影响：设备桌面出现透明占位，不能作为完整发布体验。
- 原图：[模拟器桌面](assets/app-icon-missing.png)。
- 关闭：补齐原创图标与编译配置，检查最终安装包和提交校验。不能把未签名 archive 成功当图标有效。

## R04 · P1 · 缺隐私政策与用户支持入口（源码确认）

- 位置：`MeAndData.swift` 的 `MeView`、`DataManagementView`；目前没有政策页面、可访问政策 URL、公开支持方式。
- 影响：用户不知道完整的数据保存、删除、外部分享和求助规则；不满足发布资料与应用内入口要求。
- 关闭：准备明确本地存储、手动备份/分享、系统备份可能性、删除/卸载边界的政策；加入应用入口与实际支持联系方式，并完成线上 URL 读回。公开身份和联系方式由用户确定。
- 依据：[Apple 审核指南 1.5 / 5.1.1](https://developer.apple.com/app-store/review/guidelines/)。

## R05 · P2 · 多个弹层的主题色传递不完整（原生截图确认）

- 位置：`DetailAndRefund.swift`、`LedgerCreateView.swift`、`CategoryLibraryView.swift`、`PeriodPicker.swift`、`MeAndData.swift` 的弹层；根主题在 `AppAccentModifier`，自定义实心按钮另外消费 `yujiAccent`。
- 复现：默认青竹主题，新建退款、账本、分类、预算、时间和流水筛选表单的系统按钮显示蓝色，而 Tab 和大部分主按钮是青竹。编辑记账退出确认中的“继续编辑”也变蓝。截图 `release-01-refund-save`、`23-edit-cancel-inline`、`02-month-picker`、`02-rule-management`。
- 影响：颜色系统没有覆盖系统导航按钮和多层呈现；前轮验证自定义主按钮通过不能证明整页一致。
- 原图：[退款](assets/refund-theme.png)、[编辑退出](assets/edit-theme.png)。
- 关闭：让每个呈现根显式消费同一个已解析主题，覆盖系统 tint、SwiftUI 前景和 UIKit；退款仍使用退款语义蓝，操作按钮用主题色。至少预设/自定义×浅/深检查退款、转账、类别及日期表单。

## R06 · P2 · 普通文字的字号适配不完整（源码确认）

- 位置：`EntryView.swift` 的账户日期/类型/编辑等固定 11–14pt 文案；`YujiApp.swift` 的 toast 固定 14pt；退款/转账金额输入固定 22pt。
- 影响：即使大字号下控件可点，部分说明与文字仍不会随阅读偏好放大，不能声称全面支持 Larger Text。
- 关闭：普通文案改为语义字体或 ScaledMetric；保留小屏可滚动/换行和金额有限缩放；大字号要检查“读得清”而非只有“点得到”。图标固定字号不在该问题内。

## R07 · P2 · 发布态仍含开发占位与语言配置不一致（源码/归档确认）

- 位置：我的“iCloud 同步：未开放”；Release 包包含 `stats-500.json`；Info.plist developmentRegion 为 en，应用层强制 zh_CN。
- 影响：前者让用户感到未完成；合成夹具是多余发布资源；语言声明与实际产品不一致，系统文件选择器不一定跟随应用内容语言。
- 关闭：首发范围确认后收敛存储文案；测试夹具只进测试构建；明确简体中文本地化资源与商店主语言。分别在中文、英文系统验收系统面板。

## R08 · P2 · 长期使用与中断的验收仍薄弱（明确边界）

- 全量 JSON 读写与统计查询在 MainActor；500 条通过不证明数万条流畅。用户自定义“0 到多条”预算会增加重复扫描。
- 新建录入只在关闭时保存草稿，没有输入中/退后台检查点。未关闭输入强杀会丢失，与已保存记录不丢失是两种承诺。
- 恢复点每次创建后没有保留数量策略；分享临时文件交由系统临时目录管理，没有应用级清理策略。
- 关闭：先明确草稿承诺并补中断测试；测真实设备 5k/50k 保存、筛选、内存与启动；按数据需求确定恢复点保留与清理，不能未经验证把 JSON 换成复杂数据库或简单放入 iCloud Drive。

## 发布门槛（不冒充产品代码缺陷）

没有可连接物理 iPhone；Developer Program/发布团队/商店权限尚未核实；最低 iOS 16 未实测；系统文件选择后完整恢复、VoiceOver/触觉/锁屏/真机性能、签名升级安装仍缺证据；App Store Connect 资料与上传校验尚未完成。详见 [发布门槛](app-store-checklist.md)。

## W01 · 待定位 · SwiftUI 布局运行警告

两个完整基线 xcresult 各记录 11 条 `Invalid frame dimension (negative or non-finite).`，涉及预算、分类预算、账户表单、新建/删除账本等测试。原生断言在这些路径通过；警告没有源码位置，不能仅凭警告断定可见界面损坏或归因给系统。下一批用该场景的 SwiftUI 运行时断点定位调用栈，确认是应用尺寸约束还是系统问题，保留处理结果。部分截图落在 sheet 动画中间帧，也不能当最终布局问题；视觉记录另有说明。

## 架构审查结论

继续使用现有分层，不需要为这次上架重写：纯领域 `YujiCore` → `AppState` 一处提交与回滚 → `LedgerRepository` → 原子 JSON；同一 `LedgerValidation` 守住本地读/写/备份恢复。`PeriodNavigation`、`TransactionRow`、分类编辑、预算与主题组件已复用。

应收口的契约：所有余额查询显式携带 as-of；主题穿过所有 sheet 根；PRD 区分 API 能力与实际 UI；备份系统入口完成真实闭环。后续跨进程/云同步必须另立实体冲突、账号隔离、删除传播和退款额度策略，不能沿用单文件写入假设。
