# 余记上线后的数据与诊断方案

核查日期：2026-10-08。用户目标仍是独立可用、本地优先、低维护。本文件是方案研究；当前 App 没有接入第三方分析/崩溃 SDK，也未增加遥测上传、创建统计账号或报表任务。

研判：首版优先使用 **App Store Connect Analytics + Analytics Reports API + Xcode Organizer**。下载、活跃、使用时长与崩溃都有 Apple 的现成数据渠道，无须让余记额外上传账本或搭建业务服务端。自定义漏斗有明确问题需要回答时再引入 SDK。

## 看什么、从哪里看

| 关注点 | 现成入口 | 接入与口径 |
| --- | --- | --- |
| 下载、新增来源与商店转化 | App Store Connect → Apps → 余记 → Analytics，获客与指标；也可下载报表 | 区分首次下载、重复下载、总下载；总下载不是独立使用人数。无需分析 SDK。见 [获客说明](https://developer.apple.com/help/app-store-connect-analytics/acquisition/acquisition/) |
| 小规模首下载核对 | App Store Connect → Trends / Sales and Trends → App Units | 免费或付费 App 均可看；App Units 是首次 Get/Buy，更新、同账号其他设备下载与重复下载不计新单位，数据通常次日提供。不能混同 Analytics 安装数。见 [报表工具](https://developer.apple.com/help/app-store-connect/measure-app-performance/overview-of-reporting-tools/)与 [Units 定义](https://developer.apple.com/help/app-store-connect/measure-app-performance/view-units-proceeds-sales-and-pre-orders/) |
| 活跃、会话、留存、删除与崩溃次数 | App Store Connect Analytics → Metrics / Engagement | 使用数据基于同意共享诊断/使用信息的设备；活跃设备不等于真实人数，Sessions 为至少使用两秒的会话。见 [App usage](https://developer.apple.com/help/app-store-connect-analytics/engagement/app-usage/) |
| 使用时长 | Analytics Reports API → App Sessions report | 有 Sessions、Total Session Duration（秒）、Unique Devices。某聚合范围的平均时长 = 总时长 / 总会话；分母为零不计算，也不能把各行平均值直接再平均。见 [App Sessions](https://developer.apple.com/documentation/analytics-reports/app-sessions) |
| 崩溃定位 | Xcode → Window → Organizer → Crashes，登录有权限的发布团队 | Apple 分发的 App Store / TestFlight 报告用于定位具体栈；保留每个发布构建的 archive 和匹配 dSYM。见 [诊断报告](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)与 [构建调试信息](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information) |
| 启动、卡顿、内存、CPU 等更深诊断 | Xcode 的性能工具；可选接入 MetricKit | MetricKit 是设备端诊断框架，不自动提供跨用户运营后台。自行接收的报告需要本地导出或另有聚合接收方案。iOS 27 新 API 不能直接用于最低 iOS 16 路径。见 [WWDC26 MetricKit](https://developer.apple.com/videos/play/wwdc2026/222/) |
| 单次保存失败、备份失败、云同步错误 | 当前仅 App 的错误状态、自测日志与用户反馈；Apple 崩溃统计不覆盖所有业务失败 | 如需线上汇总，应额外设计最小事件或诊断导出；不是配置 App Store Connect 就自动具备 |

## 可用性限制必须保留

App Store Connect 的 Analytics 下载指标有至少五次首次下载的展示门槛；Usage 指标要求所选范围至少五个活跃设备。报表亦有最低样本、聚合和隐私处理，低量级可能没有行。个人一两台设备自用时，**没有数据显示不等于没有使用或没有崩溃**。[Apple 指标定义](https://developer.apple.com/help/app-store-connect-analytics/reference/metrics-definitions)、[Reports API](https://developer.apple.com/help/app-store-connect-analytics/overview/analytics-reports-api/)

App Sessions report 仅含授权样本，并要求至少五个用户产生事件；按日数据可能在五天内补全，周/月报默认完整。它不是实时逐用户时间线。平均时长用于版本/时期趋势，不能宣传为全部用户精确平均。[App Sessions](https://developer.apple.com/documentation/analytics-reports/app-sessions)

使用/崩溃指标缺失记为“不可用”，不是 0；隐私处理后的 Unique Devices 不跨日直接求和当去重人数。下载与使用的覆盖群体不同，不能把授权样本留存或崩溃率偷偷换成全部下载用户口径。Apple 的 App Store In-App Events 是商店活动，不是余记内部按钮事件。

## 第三方现成方案

| 方案 | 能解决的问题 | 代价与余记适用判断 |
| --- | --- | --- |
| Firebase Crashlytics | 崩溃、非致命错误、issue 聚合及诊断上下文，Firebase Console 看报告 | 接 SDK、配置项目、上传匹配 dSYM、核对实际发送的数据；无须自建接收服务器，但仍使用 Google 的服务。需要详细线上错误回收时再考虑。[Apple 平台接入](https://firebase.google.com/docs/crashlytics/ios/get-started)、[可选上报控制](https://firebase.google.com/docs/crashlytics/ios/customize-crash-reports) |
| Google Analytics for Firebase | 自动使用事件、自定义事件、功能使用与漏斗分析 | 能回答“打开录入后是否保存”等问题；不会替代 Apple 商店下载口径。SDK 会发送使用数据，需要明确数据范围与用户选择。[官方报表说明](https://firebase.google.com/docs/analytics/reports) |

核查时官方价格页将 Analytics 与 Crashlytics 标为 No-cost；不能据此推断 BigQuery、托管或其他 Google Cloud 服务全部免费。[Firebase Pricing](https://firebase.google.com/pricing)

研判：上述托管方案减少自建服务端维护，但增加网络依赖、SDK 升级和数据管理成本。首版先用 Apple 官方数据更贴合余记的产品约束。第三方在目标地区的真实网络可靠性没有实测，不先承诺能稳定上报。

## 余记应追求的产品指标

记账工具应减少用户完成记录的时间；“使用越久越好”不能作为成功目标。商店与 Apple 会话数据用于观察获客、留存、版本稳定性；如将来做最小事件，优先回答：

1. 打开记账后到成功保存的中位数 / P90，排除退后台与恢复草稿，避免把离开后时间也算进操作耗时。
2. 本地保存失败、恢复失败、云同步失败率，分别定义尝试与结果；本地保存成功与云端已同步不能混成一个成功事件。
3. 分类选择与新增的完成率、统计下钻使用率、备份成功保存到外部位置的确认，不把打开系统分享面板当备份完成。

这是待实现方案。允许的最小字段应限于 App 版本、系统版本、动作类型、错误类型、耗时桶等；账本名、金额、账户名、分类名、备注、分享对象、Apple 身份和备份内容不进入分析事件。默认不开会话录屏或把财务页面当错误附件。实际字段与隐私说明必须随最终实现一起核对。

## 发布后的回收方式

- 每个发行构建保存版本/构建号、源码指纹、归档和匹配 dSYM；对应商店构建核对后，再比较同版本下载、授权样本会话及崩溃。
- 初期直接在 Apple 控制台查看，配合用户可复现步骤与系统诊断；数据不存在时明确显示“样本不足/待数据补全”。
- 需要持续汇总时，可由 Mac/CI 的脚本使用 App Store Connect API 拉取官方聚合报表，产生本地 CSV/图表；API 密钥放系统凭据或 CI secret，不打包进 App、不写仓库。此任务尚未建立，也未授权自动通知或第三方共享密钥。
- 只在官方数据无法回答具体产品问题时评估最小 SDK 接入；云账本与产品遥测保持独立，不把 CloudKit 私有账本拿来当运营数据仓库。

本次没有实际发布团队的后台访问记录，没有下载/时长/崩溃的真实运营值。以上为当日官方渠道核查和实现建议，不能当作余记后台已经接通。
