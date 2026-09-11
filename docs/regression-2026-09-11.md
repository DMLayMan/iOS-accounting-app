# 全量回归与架构审查 · 2026-09-11

本轮覆盖累计尚未提交的原生功能，目标是形成可以继续扩展、按文档复刻的基线。不是 App Store 发布或 iCloud 上线结论。原始日志与 xcresult 留在本机 `evidence/full-regression-2026-09-11/`；可移植原生截图与测试清单随 Git 提交。

## 1. 审查发现与处理

| 级别 | 发现 | 处理与证据 |
| --- | --- | --- |
| P1 | 启动读失败自动忽略隔离错误并开放空库，后续写入可能覆盖原文件 | 保持原路径，storageFailure 阻断写入/导出；重试/恢复入口；AppStateRecoveryTests 原字节和失败保护断言 |
| P1 | 本地读与备份恢复校验不同，重复 ID/跨账本引用/非法日期/回收站校验缺失可进入状态 | LedgerValidation 一处维护，全库读/写/恢复共用；8 个 DataIntegrityTests 覆盖合法历史和非法组合 |
| P1 | 重复交易 ID、期初边界、编辑回收站、删除最后可用账本、草稿账户引用等生命周期约束不完整 | 领域入口补齐，AppState 最终完整性校验兜底并回滚；共享校验防止组合操作留下断链 |
| P1 | 退款详情不能删除错误退款；永久删除原支出可能留下退款孤儿 | 退款可删除/撤销；永久删除只允许回收站且无退款/草稿引用；详情永久删除加确认 |
| P1 | 转账会清除与其无关的记账草稿 | 移除清草稿操作；状态+磁盘测试确认草稿保留 |
| P1 | 删除空账本未说明连带删除草稿与目录 | 新增明确确认，隐藏最后可用账本的删除入口；取消不变更 |
| P2 | 新增 UIKit 单元测试被 macOS Swift Package 收入，swift test 无法编译 | 用 Native 子目录隔离 portable 与 native 测试；原生颜色测试留在 iOS target |
| P2 | 测试固定交易日期，却按实际当天初始化账户/表单，隔天出现失败 | 注入业务日；默认账户起点、录入/退款/转账使用同一个 today；测试 UUID + 固定日，正式环境保留跨日刷新 |
| P2 | 原生表单主按钮在 sheet 内回落系统蓝色 | AppAccentModifier 显式传递已解析主题色给 SolidActionStyle；新增 sheet 退出场景检查 |
| P2 | 跨页基础组件定义在某个业务页面内，修改时容易漏用 | 抽取 TransactionRow、CategorySymbol、LedgerFormatting；删除无调用旧标签 UI/分类 Chip/随机 tint |
| P2 | 分类拖动的刷新计时器持有 Coordinator，只在手势结束或 deinit 清理 | UIViewRepresentable 销毁时显式取消并停用 display link，防止中断拖动残留；复测原生排序路径 |
| P2 | LedgerStore 集中多种目录与规则命令，收支聚合有重复 | 按分类与预算拆扩展；Stats summary 复用 TransactionTotals；AppState Store/账本发布镜像限制外部赋值 |
| P2 | iCloud 旧设置字段可能让界面显示“已开启”，实际未连通 | 设置页始终显示未开放，保留旧字段兼容，不制造假同步状态 |
| P1 | 显式传入非法测试 session 会回退个人仓储 | 测试参数先校验，无效拒绝启动；回归脚本及每个测试均生成新 UUID |
| P2 | 旧 UI 测试还找“记一笔”“回到今天”，忽略键盘和固定时间栏遮挡，拖拽断言过度约束落点 | 按当前用户路径修复测试，统一可滚动区域计算；保留数据结果、取消、排序撤销与持久化断言 |
| P2 | README 仍是四 Tab/悬浮记账，历史方案与最新规范混合 | 重写 PRD/README/UI 清单/架构，历史文档标记，最新原生图集可随仓库分发 |

## 2. 验证记录

最终结果由 [机器清单](verification.json)、[Pro 逐项结果](verification/pro-cases.json)、[SE 逐项结果](verification/se-cases.json) 和下表维护。逐项结果按时间顺序合并，后续复测覆盖同名场景的早期失败；不把多个批次当作一次运行。

| 检查 | 结果 |
| --- | --- |
| macOS 领域 + 状态/真实文件测试 | 116 项通过；core-final.log |
| 原生 Debug / 测试目标构建 | 通过；包含恢复入口和最新测试 |
| Release 设备构建（未签名） | 通过；未做安装/上传 |
| iPhone 17 Pro 全量 UI / native unit | 49/49 个 UI 场景、18/18 个原生单元通过；全量 65/65 + 补充 31/31 + 最终 1/1，重复项不重复计数 |
| iPhone SE 3 全量及受影响路径复测 | 49/49 个 UI 场景、18/18 个原生单元通过；初轮 58/64、修复后 46/47、最终补充 23/23 |
| 图集/文档链接/源码扫描 | 92 张原始模拟器截图；8 份当前文档、图集引用和 SHA-256 自动核验；另做两轮原生视觉复核 |
| 非法隔离参数负向启动 | 明确拒绝启动；未创建个人仓储；使用新 UUID 恢复独立预览 |
| 远端 GitHub CI | [运行 34558035244](https://github.com/DMLayMan/iOS-accounting-app/actions/runs/34558035244) 通过；Linux 领域测试、macOS 状态测试与原生构建，代码提交 ff4b9c4 |

首轮 Pro：15 项原生单元通过，44 项 UI 中 9 项失败。原因是转账空表单日期差异，以及已过时的入口/键盘/拖拽/固定时间栏定位逻辑；保留首轮 xcresult 作为修复前证据。后续批次及最终修改的针对性复测见机器清单，不将不同二进制批次混写成一次运行。

SE 初轮 6 项失败分别落在预算深色表单、账本新建键盘提交、旧录入按钮/回到今天入口及固定时间栏的滚动定位。修复后只剩最大字号测试的滑动起点仍落入固定栏，统一使用实际内容区域后最后 23 项全部通过。

Pro 全量批次原生结果为 65/65 通过，但收尾 shell 返回错误：运行中的脚本被改写，产生解析错误。保留原始 xcresult 与日志；固定脚本后检查 `zsh -n`，补充批次和最终验收的驱动退出码均为 0。后续不得修改正在执行的脚本或重建正在测试的产物。

最终 Debug 构建用于最后两台设备补充验收。它与已通过 Release 构建的业务代码一致，差异仅为测试滚动辅助方法和源码空行。源码和二进制哈希均列在机器清单，测试原始产物不随仓库公开。

CI 首次成功运行提示 checkout 的 Node 20 运行时弃用。后续配置固定到 [checkout v7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1) 的提交 SHA，并关闭凭证持久化；最后提交的运行状态以 [PR Checks](https://github.com/DMLayMan/iOS-accounting-app/pull/1/checks) 为准，前述运行链接明确对应实现提交。

## 3. 场景覆盖矩阵

| 用户场景 | 数据与异常断言 | 原生路径 |
| --- | --- | --- |
| 首次进入/空账本 | 首次落盘失败阻断；损坏原文件不改名覆盖 | LifecycleUITests |
| 新建、编辑、取消、草稿、重启 | 原操作 ID 稳定；失败回滚；编辑不占用新建草稿 | StatsStressUITests、TimeNavigationUITests |
| 金额/算式/备注键盘 | 十进制与舍入、金额范围；备注不参与检索 | CalculatorTests、MoneyEditingTests、InlineCategoryUITests |
| 分类增改、图标、查找、排序 | 引用保护；同层重名；完整同级置换；历史不变 | CategoryExperienceTests、InlineCategoryUITests、DesignQualityUITests |
| 账本累计、账户、切换/新增 | 期初/转账与收支分离；同账本边界；当前账本重启 | LedgerBrowsingTests、LedgerFeedUITests、LifecycleUITests |
| 流水时间/条件/空状态 | 月、年、全部、范围；未来记录；分类/账户/金额组合 | LedgerFeedUITests、ICostTimeUITests、TimeNavigationUITests |
| 统计下钻、排行、环形图 | 一级/叶子守恒，退款归属，分母保持，同页明细一致 | StatsStressTests、StatsStressUITests |
| 同环比/闰年/YTD | 基期零/负/未覆盖，共同天数，闰日，历史整期 | DomainAcceptanceTests、StatsStressTests、StatsStressUITests |
| 账本/分类月年预算 | 历史生效点，清空/零，父子独立，编辑排除原金额 | BudgetTests、CategoryBudgetTests、BudgetEntryUITests、CategoryBudgetUITests |
| 退款、转账、删除/恢复 | 额度、日期、归档、回收站与原支出链；撤销 | DomainAcceptanceTests、DataIntegrityTests、StatsStressUITests |
| 备份/CSV/损坏/磁盘失败 | 重复/越界/跨账本/非法日期、恢复点写失败、原字节留存、CSV 转义 | AppStateTests、DiskPersistenceTests、AppStateRecoveryTests、DesignQualityUITests |
| 主题/自定义/深色/大字号 | 语义色对比，设置持久化与失败回滚，长文本触达 | ThemeTests、ThemeRenderingTests、ThemeUITests、DesignQualityUITests |

500 条合成数据跨 2022–2026 年，包含 470 条有效记录、收入/支出/退款/转账、空月、负净支出、归档和回收站；不是随机生成后仅检查页面没崩溃。代表断言：累计净支出 ¥263,163.82；累计收入 ¥754,276.21；累计结余 ¥491,112.39；含期初余额 ¥496,212.39。2026-08 净支出 ¥7,574.66、15 条流水；2026-09-10 截止净支出 ¥501.05。每项均由领域与对应原生页面检查。

## 4. 已知边界与后续工作

- 本轮只在可用的 iOS 26.5 模拟器做自动化。最低 iOS 16 是工程声明；不能据此声称所有 16～26 系统版本已实测。
- 真机签名仍未配置；真实触觉、VoiceOver 听读、锁屏文件保护、后台功耗、断电恢复和 App Store 发布不在本轮通过结论内。
- 本地 500 条数据和重复查询通过不代表 50,000 条或多进程并发可用。仓储仍为 MainActor 全量 JSON，增长后先测实际保存延迟和内存。
- iCloud 与多人共享尚未实现。远端合并、冲突、账号切换、撤权和离线退款额度必须按后续方案另行开发验收。
- 备份结构与清单校验不提供密码学来源认证；外部分享文件是否存储由用户控制。
- CSV 可核对但不能完整恢复；批量修改与账户物理删除有领域能力，当前 UI 未开放全部入口，不冒充已有界面功能。

## 5. 重现

```sh
scripts/regress.sh core
scripts/regress.sh build SIMULATOR_UUID
scripts/regress.sh test SIMULATOR_UUID
scripts/regress.sh release
```

使用独立构建目录可以保留已测试二进制；禁止一边测试同目录一边重新构建。最终 `.xcresult`、日志路径、文件哈希和图集来源见验证清单。个人 ledger.json 和用户原体验 session 不作为测试夹具。
