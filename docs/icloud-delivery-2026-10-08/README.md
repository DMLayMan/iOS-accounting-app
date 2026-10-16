# iCloud 同步与多人账本交付

2026-10-15 新增：[共享记账人和统一昵称](../shared-nickname-2026-10-15/README.md)。本地实现/验证与真实服务验收分开；不沿用旧财务共享结果证明昵称已在 Production 通过。

原始批次：2026-10-08。范围：CloudKit 适配、可恢复的本地同步状态、邀请/成员页面、确定性多客户端自测。该批次真实容器、签名与双账号尚未完成；下方模拟测试仍为历史证据。默认构建不实例化未配置的 CloudKit 容器，真实验收包显式启用适配器。

2026-10-13 更新：真实容器、Development / Production签名及Development三个字段已核对。新增真机A端隔离账本的真实Development上传、1234分支出同步、重启回读通过，缓存与服务器base一致；原个人账本字节未变。真实B邀请/接受、互记、撤权和Production仍待验证。见[真实服务联调](../live-services-2026-10-13/README.md)及[schema证据](../app-store-2026-10-13/cloud-schema-check.json)。下文10月8日批次仍是历史模拟验证。

2026-10-14 最新：B 的真实身份与 A 不同。Development 指定私有成员、冷/热系统链接接受、双方新增、重启、重复邀请、SDK 只读/恢复编辑/撤权及重新邀请恢复通过；两端 3 笔财务快照一致。系统权限面板逐项操作、完整真实矩阵与 Production 仍待验，见[真实双账号验收](dual-account-acceptance-2026-10-14.md)。手工支付后的正常启动发现同账号云验收账本，原用户实体未变；备份和精确预览后，已获授权清理目标 zone 和正常缓存，普通启动未回流，见[清理回收](test-fixture-cleanup-2026-10-14.md)。

## 用户动线

- 账本名称右侧云图标 → 同步与成员 → 开启同步 → 明确确认上传范围。尚未邀请别人；仅这个账本进入当前系统 iCloud 的私有数据库。同账号其他设备在打开 App/回到前台时发现账本。
- 拥有者同步完成后 → 邀请成员 → 填对方 Apple 账户邮箱、选择可编辑或只读 → 邀请并复制/分享私有链接。改权限、移除及停止共享走管理成员的系统面板。其他账本、草稿、外观偏好不上传。
- 接受邀请 → 展示账本与共享范围 → 接受 → 下载、验证成功 → 切到加入的账本。应用/场景代理处理冷启动及运行中的 CloudKit 分享回调；重复邀请以完整云地址定位现有账本。
- 共同记账先原子保存本地。新增、修改、分类、账户与预算同一同步路径；新记录保留记账成员来源。打开 App、返回前台、记账后防抖，以及前台每 30 秒尝试更新；暂停自动同步仍允许手动刷新。后台不承诺实时拉取。
- 只读成员：记账入口解释当前权限，详情修改/删除/退款及账本预算/转账禁用；底层统一写入检查也拒绝其他管理路径的业务变更。个人草稿和外观仍是本机操作。
- 冲突 → 比较本机/云端 → 保留独立未同步副本并采用云端，需确认。两个版本都保留，不静默覆盖金额。退出共享先保存本地副本，再撤销自己在共享 zone 中的访问；拥有者用系统面板管理或停止共享。
- 系统账号改变立即隐藏上个账号账本，并停止它的发送；缓存和待同步修改保留。账号重新确认后才显示对应缓存。首次启动未能确认身份时只显示本地账本，页内说明云账本等待账号确认。
- 同一设备的两个账号均参加同一本账本时，也保留各自独立的缓存与待传修改；可见数据声明所属账号，切换后不把另一账号的离线内容写进当前缓存。系统账号暂不可用时，保留已确认缓存并停止云请求，检查成功后恢复。
- 从备份恢复的本地账本再次开启同步，若云端已有相同来源 ID，先明确确认“另建副本并同步”。新副本重映射全部业务 ID，原本地数据与原共同账本都保留，不创建两个相同身份的云 zone。

## 实现与取舍

| 层 | 唯一责任 |
| --- | --- |
| YujiCore/CloudSync | 云地址、单账本快照、共同祖先合并、身份隔离、独立副本及引用映射 |
| AppState + CloudState | 原子落盘、持久化待同步内容、账号生命周期、统一权限检查、串行同步与结果应用 |
| CloudKitTransport | private/shared 数据库、独立 zone、CKAsset、条件保存、CKShare、错误映射 |
| CloudInvitations | SwiftUI 应用/场景回调、邀请确认、UICloudSharingController 生命周期 |
| CloudBook/Overview/Conflict | 共享范围、成员权限、同步状态、恢复动作，复用主题与原生列表 |

第一版使用**按账本的版本化快照提交**：一条 `YujiLedger` record 的 `payload` 是 CKAsset，记录元数据包含名称、格式版本；一个账本一个自定义 zone，可用 zone-wide CKShare 共享。CloudKit 的 change tag 条件保存是唯一的云端提交顺序，不用手机时钟排序。整账本提交让退款合计和引用完整性在每次成功版本上成立；合并在实体 ID 和字段层进行。

这与原 9 月方案中的“逐实体网络记录”有所不同：当前避免多记录事务/协调器的首版复杂度，代价是变更后传输整个账本资产。未变化时只取记录头并复用已下载版本，不反复下载全量资产。限制 40 MB 的单账本资产并明确失败保留本地。长历史的网络流量、内存和真机序列化耗时仍需量测；后续可替换传输实现为分块/实体提交，保留当前领域合并和落盘契约。

本机 schema 升到 4，可读取 1–3 的旧文件。缓存、共同祖先、版本标识、权限、冲突副本、本机草稿和可见云数据所属账号与业务数据在同一 JSON 文件中原子保存。后续请求失败、应用重启或丢失云端确认都不会消失待发送内容。账号隔离以容器、环境、系统用户记录身份和 zone 地址为准；同一账本 ID 可以存在于不同账号缓存，只对当前可见账号执行捕获/变更校验，不按昵称或账本名称匹配。

备份只导出当前可见的业务账本，去掉云绑定和其他账号缓存；恢复为本地数据，不自动恢复共享或上传覆盖云端。旧账号的原子文件缓存仍留在应用沙盒，重新登录该账号后恢复。读取云资产先检查大小、版本、引用和退款额度。无安全合并结果时保留两边，不发布非法合并状态。云权限由 Apple 校验，成员修改不能绕过本机统一写入边界；财务约束仍须所有客户端遵守，客户端只读界面不代替云端授权。

2026-10-14 送审复审：canonical 工程现为 Debug 默认 NO、Release 默认 YES/Production，并接入实际 `.app` 资源门槛。最新未签名归档通过；尚不证明生产 schema、实际分发签名或共享可用。Development 缓存与 Production 身份分开，覆盖安装前先备份并验证恢复路径。见[最新送审前复审](../pre-submit-review-2026-10-14/README.md)。

## 10 月 8 日历史自测证据

本地领域、应用状态和原生 UI 测试在 `evidence/icloud-20261008/`。所有测试使用新的 UUID 隔离文件和确定性业务日期，不读写个人 `ledger.json`。模拟云端只在 Debug 且有效测试 UUID 存在时可构造，界面明确标为自测，不发送任何 CloudKit 请求。

**以下仅为 10 月 8 日批次，当时邀请未完成真实端到端验收。** `CloudSharingUITests` 模拟模式禁用“邀请与管理成员”；模拟通过不能证明真实邀请。10 月 14 日已完成的真实路径与未验部分见上方双账号记录，不以此历史表格作为当前状态。

| 邀请步骤 | 当前代码 | 验证状态 |
| --- | --- | --- |
| A 将一本账本上传到自己的 iCloud | CloudState.enableCloud → CloudKitTransport.save | 模拟状态/持久化通过；真实上传未验证 |
| A 点击同步与成员 → 邀请与管理成员 | CloudBookView.prepareShare → zone-wide CKShare → CloudSharingView | 已编译；模拟模式禁用入口，未实际走系统面板 |
| 系统面板选择受邀人、编辑权限并发送链接 | UICloudSharingController，限定 private / readOnly / readWrite | 真实发送及收件人身份匹配未验证 |
| B 已安装云构建，登录自己的 iCloud，打开链接 | 应用/场景代理接收 CKShare.Metadata → CloudInvitationView | 冷启动、运行中实际链接路由未验证 |
| B 接受并进入共享账本 | container.accept → shared 数据库发现/下载/验证 → switchLedger | 本地共享发现模型通过；真实接受/首次下载未验证 |
| B 记账，A 打开 App 或手动刷新后看到同一条记录 | 共同祖先合并、条件提交与本地原子保存 | 双客户端模拟通过；真实双方核对未验证 |

该历史批次的闭环判据：A 发出私有邀请，B 从链接进入并接受，双方核对同一账本及权限，B 新增一笔后 A 能看到且金额正确，再验证只读、撤权、重复邀请、冷/热启动。当时默认云配置关闭；最新 Release 配置和真实 Development 结果以上方记录为准。

最终结果：**149 项 portable 测试通过；大小屏分别覆盖 103 个最新原生用例结果（66 UI + 37 hosted 单元），无缺项和残留失败。** hosted 与 portable 的应用状态测试有重叠，不相加成独立业务场景。原始失败、针对性修复和重新验证保留在同一证据目录，不用总运行次数代替覆盖场景数量。

| 批次 | 设备/代码 | 结果与范围 |
| --- | --- | --- |
| core-verified | 当前源码 / macOS | YujiCore 113 + 应用状态/落盘 36，全通过；包括跨五年 500 笔独立金额核对、两个离线客户端、幂等重试、并发退款、账号切换、磁盘失败 |
| full-pro-final | iPhone 18 Pro / iOS 27 / v8 | 100 通过；旧构建有一条 SwiftUI 更新警告，后续针对性关闭 |
| full-se-final | iPhone SE 3 / iOS 26.5 / v8 | 99 通过、草稿恢复 1 失败，保留原始结果；后续补强中间状态断言并复测 |
| cloud-pro-verified | iPhone 18 Pro / iOS 27 / 最终 v14 | 全部 37 hosted 单元 + 8 cloud UI + 草稿恢复，共 46 通过；运行时 warning 为空 |
| cloud-se-verified | iPhone SE 3 / iOS 26.5 / 最终 v14 | 同样 46 通过；运行时 warning 为空 |
| 两个 Release archive | 最终代码，纯本地 NO / 云配置 YES，均 Production | 均归档成功；无模拟云类、测试环境标记和 500 笔夹具，离线隐私文档与源码一致；未签名，不证明实际云访问 |

覆盖汇总以广泛回归为基线，最后修复对全部 hosted 单元、共享 UI 和失败的草稿路径重跑；**不是同一最新二进制再次跑完所有 UI**。各用例来源和最后结果见 [逐设备覆盖](verification/native-coverage.json)，源码校验见 [指纹](verification/source-fingerprints.json)。此范围避免把旧截图/旧警告伪装成最终代码全量重新执行。

已保存 [26 张原生截图画廊](gallery/index.html) 及 [原图来源/校验](gallery/manifest.json)。最终集中视觉检查核对小屏默认态、冲突两版金额、深色最大字号与新副本切换：原生分组层级、主题、取消/返回与滚动保持一致；最大字号采用自然换行并可滚到成员动作，未缩小字号掩盖边界。真实系统共享面板、VoiceOver 听读和触觉仍未在已签名真机验证。

重新核对产物：在仓库根目录运行 `node docs/icloud-delivery-2026-10-08/verify-release.mjs`、`node docs/icloud-delivery-2026-10-08/verify.mjs`。本地原始日志位于 evidence；持久文档保留逐用例覆盖、截图 hash、源码指纹和归档资源结果。

### 发现与修复

| 问题 | 修复与防回归 |
| --- | --- |
| 同一设备的 A/B 都参加同一本账本，切账号可能把可见数据捕获进另一个账号缓存 | 明确持久化可见云数据所属账号；仅对它捕获与检查变更；同账本双账号离线差异的红测先失败再通过 |
| 恢复来的本地备份保留旧业务 ID，直接开云可能另建同身份 zone | 先检查云账本来源，取消不写；确认后重映射副本全部引用，保留原本地及原云端 |
| 开启独立副本后，页面仍显示原账本，看起来确认弹窗没有响应 | 检查隔离文件发现副本已成功保存；真正原因是刷新安装时临时移除当前账本，触发默认切账本。替换数据保留当前选择；领域、状态与原生 UI 三层验证 |
| SwiftUI Tab/alert binding 同步发布应用状态时产生运行时警告 | 在主 actor 的下一任务发布提示/关闭状态；受影响原生用例重新检查 warning，而非仅看测试是否通过 |
| 小屏草稿回前台后连续删位用例未区分点击和恢复结果 | 增加前台控件就绪、每次删位及重启后断言；三个设备复测均通过，没有修改产品恢复逻辑，也未弱化最终空草稿断言。原始一次性失败的准确触发仍未完全定位，保留证据继续观察 |

复现文件如 `active-book-red.log`、`account-same-book-red.log` 与原始 native result bundle 只属于隔离测试。最终覆盖表以设备和测试身份取最后一次结果；状态测试在 portable/hosted 两种环境重复执行时不算两个独立业务场景。

## 真实 iCloud 验收前置

1. 在 Xcode 登录付费开发团队，为应用确定可注册的 Bundle ID，并在开发者后台启用 CloudKit，创建关联容器。
2. 使用 [配置说明](configuration.md) 生成签名开发包；不要将本地示例容器当成已经注册的线上容器。
3. 同账号两设备验证新增/编辑/离线/重启/重试；不同账号两设备验证邀请、可编辑/只读、权限变化、撤权、退出和停止共享。
4. 执行 [真实多账号验收表](real-cloud-acceptance.md)，保留设备、账号代号、容器环境、构建号、记录版本与金额核对结果。
5. App Store/TestFlight 前部署 CloudKit schema 到 Production，核对签名 entitlement、生产容器、共享链接、隐私声明和真实下载后协作；开发环境通过不等于生产环境可用。

来源：[Apple 共享示例](https://github.com/apple/sample-cloudkit-sharing)、[CloudKit 共享](https://developer.apple.com/documentation/cloudkit/sharing-cloudkit-data-with-other-icloud-users)、[SwiftUI 接受邀请](https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app)、[条件保存](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/ifserverrecordunchanged)、[zone-wide share](https://developer.apple.com/documentation/cloudkit/ckshare/init(recordzoneid:))。官方文档及本机 iOS 27 SDK API 已核对；云端结果待实测。
