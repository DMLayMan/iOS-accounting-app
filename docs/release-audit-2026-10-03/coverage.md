# 全功能与页面回收矩阵

审查日期：2026-10-03。实现基线 `58aed2d`，应用代码与已合并 PR #1 相同。以下是**可观察的用户能力**，不把领域方法当作已经开放的功能。最终批次结果见 [审查报告](README.md)。本轮使用模拟器；真机、最低 iOS 16、VoiceOver 听读及 App Store Connect 校验不在通过范围。

本表为历史基线；账户/金额筛选、后台检查点、离线政策/帮助和恢复点管理已在[10 月 8 日](../review-fix-2026-10-08/README.md)继续实现与回归，不以本表的旧待办覆盖最新规范。

## 功能核对

| 用户任务 | 实现与数据边界 | 本轮证据入口 | 回收结论/需补充 |
|---|---|---|---|
| 首次使用、正常重启 | 默认个人账本、现金/银行卡、两级分类；正式入口账本 | LifecycleUITests、AppStateTests | 已有原生断言；DEBUG 直达统计不能当首次使用 |
| 文件损坏、首次写入失败 | 恢复页阻断写入；重试不覆盖坏文件 | AppStateRecoveryTests、LifecycleUITests | 领域与文件负向测试；真实锁屏/磁盘满仍需真机 |
| 新建收入/支出 | 十进制算式→整数分；一个二级分类 | CalculatorTests、MoneyEditingTests、ReleaseReadinessUITests | 补充从空账本录入、退款、转账、重启对账 |
| 编辑与取消 | 稳定交易 ID；修改退出页内确认 | StatsStressUITests、ThemeUITests | 保留独立新建草稿；输入不因保存失败丢失 |
| 草稿 | 新建关闭才写草稿，不入统计 | AppStateTests、StatsStressUITests | 没有输入过程中/退后台自动保存；不能承诺强杀前未关闭输入可恢复 |
| 金额与文字键盘 | 备注聚焦隐藏金额键盘；完成再恢复 | TimeNavigationUITests、InlineCategoryUITests | 正常/小屏/大字号路径；长账户名增加独立探针 |
| 账户与日期选择 | 可用账户；日期默认今天；起点约束 | DesignQualityUITests、DomainAcceptanceTests | 归档/无可用账户须确认易理解的纠错路径 |
| 分类一级/二级 CRUD | 同层重名校验、换组、图标、归档/恢复、引用保护 | CategoryExperienceTests、DesignQualityUITests | 新增/改名/图标有原生测试；部分归档/换组/引用保护主要由领域证据支持 |
| 分类展示与顺序 | 一级一行、二级行优先两行、长按分页拖动 | InlineCategoryUITests | 保留用户确认方案；手动顺序不被推荐随意改写 |
| 多账本创建/切换/管理 | 一次提交默认目录、预算和切换；最后可用账本保护 | LedgerFeedUITests、LifecycleUITests | 删除空账本有确认；账本排序没有界面入口 |
| 账本汇总 | 累计收支与含期初账户余额分离，截至今天 | LedgerBrowsingTests、LedgerFeedUITests | 数值有合成数据断言；账户列表截止口径存在 R01 |
| 账户管理 | 新增、改名、期初/起点、归档/恢复 | DesignQualityUITests、DataIntegrityTests | 物理删除只有领域能力；当前 UI 以归档停用 |
| 转账 | 同账本不同账户，一条记录、两端余额、收支/预算不变 | DomainAcceptanceTests、ReleaseReadinessUITests | 新补保存正向路径，原测试主要查看空表单 |
| 退款 | 关联原支出、日期/额度约束、可退到其他账户 | DomainAcceptanceTests、StatsStressTests、ReleaseReadinessUITests | 新补实际保存与重启；原 UI 测试部分只打开预填页 |
| 删除、撤销、回收站 | 有退款支出保护，恢复再次校验，永久删检查引用 | StatsStressUITests、DomainAcceptanceTests、DataIntegrityTests | 3.5 秒撤销窗口；永久删除原生点按/听读尚需补充 |
| 流水检索 | 共用时间栏；类型/分类/分类关键词；备注不检索 | LedgerFeedUITests、StatsStressUITests | 账户/金额区间筛选目前只在领域层，R02 |
| 月/年/全部/自定 | 两页同一期间；取消不提交、跨年、空月、未来 | ICostTimeUITests、TimeNavigationUITests、BrowsingPeriodTests | 流水含未来，统计截至今天，口径在页内说明 |
| 统计基础金额 | E/R/N/I/S；期初/转账/草稿/回收站排除 | StatsStressTests、DomainAcceptanceTests | 500 条、2022–2026；有独立预期值，不是仅看不崩溃 |
| 构成、排名与下钻 | 毛额做占比；退款单列；同页筛选、同页明细 | StatsStressUITests、StatsStressTests | 前四排行可展开、明细每次增加 20 条；返回保留条件 |
| 同比/环比 | 净支出、同进度、零/负/未覆盖基期、闰日 YTD | StatsStressTests、DomainAcceptanceTests、StatsStressUITests | 不把减少支出评价为“好”；无适用窗口不输出增长率 |
| 月/年账本预算 | 留空/零区分、有效期历史、超额可保存 | BudgetTests、BudgetEntryUITests | 两周期独立，不自动乘 12、不结转 |
| 分类预算 | 一级/二级，0 到多条规则，父子独立，前两条超额 | CategoryBudgetTests、CategoryBudgetUITests | 编辑草稿统一提交；统计与录入各有展示 |
| 全量备份与恢复 | 结构/引用/金额清单验证、替换前恢复点 | DiskPersistenceTests、AppStateRecoveryTests、DesignQualityUITests | 原 UI 恢复预览通过 DEBUG 入口；不能替代系统文件选择后全链路 |
| 文件分享与导入入口 | 分享 JSON/CSV，系统文件选择 | ReleaseReadinessUITests | 本轮新增入口/取消验证；“已生成”不等于已保存至用户外部位置 |
| CSV | 当前账本含已删状态、关系 ID、公式/引号/换行转义 | DomainAcceptanceTests、ReleaseReadinessUITests | 核对用，不能导入还原 |
| 主题与偏好 | 六色+自定义、系统/浅/深、语义色、触觉/减弱动态 | ThemeTests、ThemeRenderingTests、ThemeUITests | 对比度为选定 token 的验证，非所有系统材质全面保证 |
| iCloud/共享 | 仅方案，无同步仓储、账号/队伍/冲突实现 | 当前 source/project 检查 | 未实现；是否首发必需待用户确认 |
| 商店交付 | Release 归档、图标、签名、政策/支持/商店信息 | [发布门槛](app-store-checklist.md) | 本地构建不等于 TestFlight/App Review 通过 |

## 页面清单与最短动线

“页面”包括独立任务 sheet 和系统面板；同页统计筛选等写为状态，避免把组件数当页面数。自动化覆盖的深浅色/字号场景按测试名字与截图区分，未跑所有页面×全部主题的笛卡尔积。

| ID | 页面/状态 | 进入 → 完成/退出 | 原生检查入口 |
|---|---|---|---|
| U01 | 首次/空账本首页 | 启动 → 账本 → 中央记账 | LifecycleUITests |
| U02 | 累计账本页 | 账本 → 查看累计、余额、概况 | LedgerFeedUITests |
| U03 | 切换账本 | 账本切换 → 选账本 → 原页 | LedgerFeedUITests |
| U04 | 新建账本 | 新建 → 名称/可选预算 → 创建并使用 | LedgerFeedUITests、BudgetEntryUITests |
| U05 | 账本管理/改名/删除确认 | 我的 → 我的账本 → 行菜单 | LifecycleUITests、DesignQualityUITests |
| U06 | 账户列表 | 我的/账本管理 → 账户 | DesignQualityUITests；R01 |
| U07 | 新增/编辑账户 | 账户 → 表单 → 保存/取消/归档 | DesignQualityUITests、ReleaseReadinessUITests |
| U08 | 新建记账 | 中央动作 → 金额+二级 → 保存 | InlineCategoryUITests、ReleaseReadinessUITests |
| U09 | 记账编辑/放弃/草稿恢复 | 单笔编辑或中央动作 → 原上下文 | StatsStressUITests、ThemeUITests |
| U10 | 备注键盘 | 记账备注 → 系统输入 → 完成 | TimeNavigationUITests |
| U11 | 记账账户选择 | 账户 → 选可用项 → 记账 | DesignQualityUITests、ReleaseReadinessUITests |
| U12 | 记账日期选择 | 日期 → 调整 → 确定/取消 | DesignQualityUITests |
| U13 | 全部分类/搜索/空搜索 | 全部分类 → 搜索 → 选二级 | InlineCategoryUITests、DesignQualityUITests |
| U14 | 分类管理/归档显示 | 我的分类管理或入口编辑 → 管理 | DesignQualityUITests |
| U15 | 新增/编辑分类及一级分组 | 新增 → 图标/名称/归属 → 保存 | DesignQualityUITests |
| U16 | 分类拖动/分页/撤销 | 长按 → 移位 → 放下/撤销 | InlineCategoryUITests |
| U17 | 流水及空状态 | 流水 → 时间 → 日期分组 → 单笔 | LedgerFeedUITests、StatsStressUITests |
| U18 | 流水搜索筛选 | 放大镜 → 类型/分类/关键词 → 应用/取消 | StatsStressUITests；R02 |
| U19 | 共用月/年选择 | 年月 → 年份/月格 → 应用 | ICostTimeUITests、TimeNavigationUITests |
| U20 | 自定义期间 | 范围 → 起止日期 → 应用/取消 | ICostTimeUITests、TimeNavigationUITests |
| U21 | 月统计/纯未来/空月 | 统计 → 月 → 金额、预算、比较 | StatsStressUITests、TimeNavigationUITests |
| U22 | 年统计/月份趋势 | 年 → 月份柱图或月按钮 → 月 | StatsStressUITests |
| U23 | 饼图/排行/分类明细 | 点类别 → 同页二级/明细 → 单笔 | StatsStressUITests |
| U24 | 比较本期/基期 | 同/环比 → 展开 → 切时期 → 同页分析 | StatsStressUITests |
| U25 | 收入/支出/退款/转账详情 | 流水或统计 → 单笔 → 返回/编辑/删除 | StatsStressUITests、ReleaseReadinessUITests |
| U26 | 新建退款 | 支出详情 → 退款 → 额度/账户/日期 → 保存 | StatsStressUITests、ReleaseReadinessUITests |
| U27 | 新建转账 | 账本 → 转账 → 两账户/金额 → 保存 | DesignQualityUITests、ReleaseReadinessUITests |
| U28 | 账本预算表单 | 账本/统计 → 预算管理 → 保存 | BudgetEntryUITests |
| U29 | 分类预算编辑 | 预算表单 → 添加/编辑规则 → 完成 → 统一保存 | CategoryBudgetUITests |
| U30 | 预算分类选择 | 规则 → 分类 → 选一级或二级 | CategoryBudgetUITests |
| U31 | 我的 | Tab 我的 → 管理/数据/偏好 | DesignQualityUITests |
| U32 | 最近删除/恢复/永久删确认 | 我的 → 最近删除 → 恢复/永久删 | DesignQualityUITests；关系保护由领域测试补充 |
| U33 | 数据管理/恢复预览/恢复点 | 我的 → 数据 → 预览 → 替换 | DesignQualityUITests、DiskPersistenceTests |
| U34 | 系统分享/文件选择 | 数据 → 生成文件/选择备份 → 系统面板 | ReleaseReadinessUITests |
| U35 | 外观/自定义颜色/反馈 | 我的 → 外观与反馈 → 选择主题/开关 | ThemeUITests、DesignQualityUITests |
| U36 | 数据不可读恢复页 | 启动失败 → 重读/备份恢复 | LifecycleUITests、AppStateRecoveryTests |

## 仍须真实设备回收的状态

- 签名安装、离线启动、退后台/强杀、重启、跨日、锁屏再解锁；已保存流水与关闭生成的草稿分别验收。
- 文件 App 真实保存备份→用户选回同文件→恢复→金额/引用一致；提供器权限拒绝、损坏文件、大文件与取消。
- VoiceOver 从首页独立完成新建、查账、退款、恢复；别只检查 `accessibilityLabel` 存在。
- 小屏、大字号、深色已有模拟器场景；触觉、滑动手感、掉帧和功耗需真机。
- 已装旧版覆盖安装新版本后数据保留；iOS 16 为声明最低版本，当前只有 26.5/27 runtime 可用。
