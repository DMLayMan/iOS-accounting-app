> 当前打赏动线已按 2026-10-15 新要求调整，见 [重复支持修正](../release-validation-2026-10-15/repeat-support.md)。下方早期测试计数为历史批次。

# 余记 · 支持开发者交付（2026-10-08）

入口位置于 2026-10-09 已移至「我的」页顶部，见 [首屏调整](../support-entry-2026-10-09/README.md)。本记录及图集保留 10 月 8 日的付款/邀请验收和当时入口位置，不覆盖历史截图。

状态：宿主接入、本地隔离验证及最后辅助色修改的原生重跑均已完成。最新未签名 Release 构建成功；正式 App Store Connect 商品、合同及真机 Sandbox 未配置、未验证，尚未发布或真实扣款。

先看 [原生效果图集](index.html)，截图来源映射见 [captures.json](captures.json)。最终文件核对和截图复审由 [verification.json](verification.json) / [visual-review.md](visual-review.md)记录；具体测试批次见下表，不以图集或编译成功代替付款验收。

## 当前行为

手动路径：我的 → 关于 →「好用，请开发者喝杯☕吧」→ 选择档位 → 主动点击支付 → Apple 确认 → 感谢 → 继续使用。进入不预选金额，选择本身不发起付款；关闭回到原页面。支持与否不影响原有功能，不自动生成记账流水。手动入口不受邀请门槛或此前支持状态限制。

自动路径：此功能接入后的本机成功新建收入、支出、退款或转账，跨所有账本累计 100 个不同稳定 ID 后，只自动邀请一次。第 100 笔必须先完成账本落盘；保存失败、重复 ID、编辑、删除/撤销删除、导入、备份/恢复、云端拉取及历史记录库存均不增加计数。

达到门槛后先恢复/检查付款状态并取得可用商品，已支持者不自动邀请；商品暂不可用时保留资格。协调器等当前 sheet、键盘、保存、错误或云加入提示退出后呈现，不需要再创建一笔。邀请显示「已经记下 100 笔」，可点「请一杯咖啡」或「继续记账」，也可关闭；接受先 dismiss 邀请，再打开同一支持页。

`consumedAt` 在自动展示前原子保存。保留本机安装文件时，关闭、重启、升级、恢复账本、切换账本均不重复邀请；删除 App 可清除记录并重新计数。没有使用时长邀请、评分、分析 SDK、支持后端、订阅或功能权益系统。

## 依赖、外观与数据边界

- 私有仓库 [DMLayMan/ios-base](https://github.com/DMLayMan/ios-base)，经已有授权的 SSH 读取；固定 v0.1.0 提交 `c7d4524ff0ae4233618f59d266c5aea790794d1f`。`project.yml` 与生成的 Package.resolved 已核对相同 revision。
- 消费 `DeveloperSupportKit` 的付款模型与 UI；`EngagementPromptKit` 仅使用 `EngagementPromptView` / `PromptSkin`，不使用 `EngagementStore` 的时间门槛。用户已确认最低 iOS 17；App 与测试目标同步声明 17。
- 单个 App 生命周期协调器持有单个 `SupportModel` 并协调呈现。`SupportModel` 负责监听/恢复购买、收据去重及先持久化再 finish，`StoreKitSupportClient` 负责 SDK 购买和 Apple 验签。每次打开重新选择金额，pending/unknown 不跨次锁住入口；不自动重付，用户可主动再支持。历史确认静默补录，不关闭新面板，不要求用户管理购买历史。
- 正式稳定目录为 `Application Support/YujiDeveloperSupport/`：`support.json` scope `com.yuji.app/developer-support`；`record-invitation.json` scope `com.yuji.app/record-support-invitation`。后者保存 schema 1、前 100 个不同 ID 和 `consumedAt`；目录/scope 不带应用版本，不进入账本备份或云同步。
- 邀请坏文件/写失败保留原字节并停止自动邀请，不回滚已保存账单；付款坏文件不被覆盖为未付款。账本与邀请日志不是跨文件事务，账本落盘后、邀请落盘前进程退出可能少计一笔，不影响账务数据。
- 支持页 70% 高度可滚动，常规字号成功感谢高 280pt；邀请按内容高度并允许 large。当前主题由宿主传入；实心操作浅色白字、深色黑字；辅助文字和邀请右上关闭使用 `Color.primary.opacity(0.7)`，支持页导航栏「关闭」跟随 `appearance.accent` 的主题色。保留现有原生设计体系，详见 [UI 规格](../UI-SPEC.md#9-支持开发者与一次性邀请)。

DEBUG 测试必须有合法 `YUJI_STRESS_SESSION` / `YUJI_UI_TEST_SESSION` UUID，使用独立临时支持目录；真实本地 SDK 模式才接 `StoreKitSupportClient`，普通回归使用注入客户端。没有访问个人 ledger 文件或真实付款账户。

## 商品声明与本地测试

| 声明商品 ID | 文案 | 本地 StoreKit 测试金额 |
| --- | --- | ---: |
| com.yuji.app.support.encourage | 小小鼓励 | CNY 6 |
| com.yuji.app.support.coffee | 一杯咖啡 | CNY 18 |
| com.yuji.app.support.generous | 加倍支持 | CNY 30 |

配置在 [YujiSupport.storekit](../../ios-app/StoreKit/YujiSupport.storekit)，三个商品均为 Consumable。以上金额仅供测试，不代表真实商品已注册或定价；正式 UI 使用 Apple 返回的 `displayPrice`，不硬编码价格。该配置仅打包进 UI 测试目标，不进入 Release App。

本地实际 StoreKit SDK 已覆盖验证成功、选择不购买、成功后的重启不重播感谢、Ask-to-Buy 等待后审批更新，以及已支持时抑制自动邀请。取消、未决/未知冷重启、防重复付款另由注入客户端和上游 SupportModel 测试覆盖，不声称真实 Sandbox 已通过。

自动化的 `SKTestSession.disableDialogs = true`，因此上述 SDK 测试没有验证 Apple 系统付款确认弹窗、Face ID/密码确认或真实账号支付。它验证了本地 StoreKit 交易及宿主处理链路，没有真实扣款。

Xcode 27 本地 StoreKit 的未审批冷重启曾返回 verified unfinished 收据；最终实际 SDK 用例改为先审批再冷重启。此模拟器行为不构成真实待审批购买的冷重启验收。没有真实扣款。

## 已完成批次与最新重跑

下表保留最后辅助色修改之前的完整功能批次，并单独列出修改后完成的 Pro 11 项、SE 9 项 UI 重跑。测试按用例身份计数，颜色重跑复用既有用例，不相加为新增覆盖。当前 13 张原生截图均映射到完成的颜色重跑批次。

| 验证 | 实际完成结果 | 证据 |
| --- | --- | --- |
| Portable | 155/155（领域 113 + AppState 42） | [core.log](../../evidence/developer-support-20261008/core.log) |
| 固定依赖 SupportTests | 5/5 | [upstream-support-tests.log](../../evidence/developer-support-20261008/upstream-support-tests.log) |
| Pro / iOS 27 模拟器 | 56/56（宿主 43 + 支持 UI 11 + 既有 UI 2），0 失败/跳过/运行时警告 | [pro-final/summary.json](../../evidence/developer-support-20261008/pro-final/summary.json)、完整 pro-final/results.xcresult |
| SE 第三代 / iOS 26.5 模拟器 | 17/17（邀请 gate 6 + 支持 UI 9 + 既有 UI 2），0 失败/跳过/运行时警告 | [se-accepted/summary.json](../../evidence/developer-support-20261008/se-accepted/summary.json)、完整 se-accepted/results.xcresult |
| 最新辅助色 UI 重跑 | Pro 11/11，SE 9/9；两批均 0 失败/跳过/运行时警告 | [pro-contrast/summary.json](../../evidence/developer-support-20261008/pro-contrast/summary.json)、[se-contrast/summary.json](../../evidence/developer-support-20261008/se-contrast/summary.json) |
| 最新未签名 Release | BUILD SUCCEEDED；Info.plist `MinimumOSVersion=17.0`、Mach-O `minos=17.0`；政策/隐私声明存在；没有 stats-500 或 .storekit | [release-contrast.log](../../evidence/developer-support-20261008/release-contrast.log) |

门槛测试覆盖 99→100、ID 去重、一次消费与重启、坏文件/foreign scope 保全、消费失败和邀请写失败不回滚账单。宿主 UI 覆盖手动入口、100 笔表单退出后邀请、接受/关闭/重启、已支持抑制、商品不可用、未知/未决、不重复付款，以及深色主题、SE、小屏最大字号操作可达。

早期失败批次保留，不能作为最终通过证据：XcodeGen 资源最初未正确入包，已改用 `sources` 的 `buildPhase: resources`；AX 父标识遮蔽文字的检查已改用可见标签；SE 滚动手势误命中固定金额键盘，已用真实可滚动区限定。部分失败批次的 sysdiagnostics 停滞，不纳入通过统计；本表接受完成的 pro-final / se-accepted 功能结果包和 pro-contrast / se-contrast 颜色重跑结果包。

## 仍待验证或配置

- 真实 iOS 17 runtime/设备：本机安装的运行时仅 26.5 / 27；最低版本声明与构建检查不等于真实运行验证。
- 真机签名、VoiceOver 听读、真实触觉与长期操作体验。
- App Store Connect 三个正式消耗型商品的注册、销售区域/定价，合同、税务、收款配置。
- 真机 Sandbox 的取消、等待审批、断网/进程退出恢复、收据与退款/撤销路径；TestFlight 及 App Review。

本次没有提交、推送或发布。当前验收只证明上述源代码、本地模型、模拟器和未签名 Release 范围。
