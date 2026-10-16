# 隐私填写依据与最终检查

## 2026-10-15 当前候选：1.0（10）

已按构建 10 与固定 SDK `de43e661585e4e01d1aff2ae05dc3146bb32c686` 再检索实际链接的 DeveloperSupportKit、EngagementPromptKit 及宿主 Cloud/Support：没有新增开发者上传、public CloudKit 数据库或分析客户端。昵称仍由用户自己的 private/shared CloudKit 数据域保存；恢复金额展示与统计记账人筛选没有改变数据接收方。以下构建 4/9 记录是历史依据，不替代本次包核对。

实际构建 10 归档的 PrivacyPolicy.md 与 canonical 字节一致，PrivacyInfo.xcprivacy 声明不跟踪、不收集、FileTimestamp/C617.1。公开隐私/支持页匿名 GET 成功，并与 Pages 当前提交 `7c3ffd2319c0c59f9e613ec9fe7b77f989fec859` 字节一致；公开政策 16 段正文与 canonical 一致。最早 staging 文件及构建 9 的网站提交已过时，不再作为当前逐字节比较对象。

用户明确授权后，已发布构建 10 核对过的 App Privacy 答案。后台回读显示已发布，发布按钮消失，政策 URL 正确。答案为：**开发者不从 App 收集数据**；不表示数据永远不离开设备，用户主动启用的 CloudKit、StoreKit 和导出已在政策说明。此操作只发布隐私信息，没有提交 App Review，也不等于 Apple 已批准 App。

当前详情与证据边界见 [构建 10 最终云验收](../release-validation-2026-10-15/cloud-final.md)。

## 历史核对记录

2026-10-14 最新：Debug 默认关闭云适配，Release 默认开启 Production 并引用云权限文件。新未签名归档的 PrivacyPolicy.md 与更新后的 canonical 政策字节一致；此前 0.1.0 / 1.0 (1) 签名材料保留为历史，不能替代最新源码。归档包含 PrivacyInfo.xcprivacy；FileTimestamp / C617.1 对应恢复点枚举自己的创建时间。包内声明不跟踪、未声明收集数据；这不替代最终签名包的 Organizer Privacy Report 或 App Privacy 表单，也不表示 CloudKit 数据处理已完成隐私验收。

| 数据/连接 | 当前处理 | 后台填写与验证原则 |
| --- | --- | --- |
| 金额、备注、账户、预算、草稿 | 默认本地；未见开发者账本服务或分析 SDK | 不因本地处理财务信息就自动勾选开发者收集；按最终包实际是否发送、保留及可访问确认 |
| CloudKit | Release 云能力开启；逐账本选择 private/shared；账号及环境缓存隔离；主动输入受邀邮箱提交 Apple 查找与授权 | 核对 Apple CloudKit 的实际访问与开发者/伙伴可获取范围；不能把本地存储结论覆盖云选择或隐去受邀邮箱处理 |
| StoreKit | 正式客户端与 Apple 通信，交易/邀请状态本地保存；Apple 提供时保存支持金额、币种和撤销状态 | 核对上游固定 revision，无第三方交易上传/分析；真实支付卡号、密码由 Apple 处理 |
| 备份和 CSV | 用户主动选择系统分享或文件提供器 | 说明导出含账本信息和删除状态；用户自行选择接收方，不作为自动遥测上传 |
| 项目问题反馈 | 用户主动打开 GitHub 公开 issues | 页面明确不上传真实账本、备份、身份与支付信息；GitHub 的处理见其政策 |
| 下载、用量、崩溃 | 平台工具可获得的聚合与用户同意数据 | 不编写逐用户路径 SDK；数据覆盖和延迟单独注明 |

2026-10-15 完成上述边界核对后，已将「未收集数据」保存为 App Privacy 草稿，未点击发布。依据不是简单的“本地优先”：实际签名 1.0（4）使用 Apple private/shared CloudKit，开发者不通过服务器或 Console 获取用户私有账本；Apple 框架自身的处理与开发者实际收集分开。受邀邮箱提交 Apple 查找参与者，不另建开发者联系人库；支持交易仅本地保存；所用两个 SDK 产品无自动上传或分析。未来引入开发者可获取的数据、公开 CloudKit 数据库或遥测 SDK，必须重审此答案。

依赖：YujiCore 本地包；IOSBase revision aaa646c95d472243507c3c1062d6eb77f25ada74 的 DeveloperSupportKit / EngagementPromptKit。已检索实际使用的两个 target，无 UserDefaults、第三方上传或分析客户端调用；同仓 FeedbackKit 的 URLSession 不属于 App 消费的产品，不能以整仓搜索命中冒充新增网络行为。不能只审宿主而漏掉依赖，也不要根据 framework 名称猜测新增网络服务。

公开 privacy.html 从 canonical docs/privacy/PrivacyPolicy.md 转换，HTML 只进行转义与段落/标题排版，不改写政策。正式部署后匿名读取并核对段落一致。2026-10-15 已获用户明确授权，独立分支仅含 privacy.html / support.html；Pages built，两个匿名 HTTPS GET 200，与候选文件字节一致，后台 URL 已保存回读。详见[本轮发布验证](../release-validation-2026-10-15/README.md)。

官方要求：iOS 必须提供政策 URL，隐私答案涵盖宿主与所集成伙伴代码且持续准确。[Apple App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)

## 填写依据的官方边界

- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)：收集定义为开发者/伙伴可在实时请求必要时间以外访问的离端数据；仅在设备上处理不属于收集。使用 Apple 框架时声明开发者收集的数据，不负责 Apple 自身的收集；外部 Apple 支付页面且开发者无法访问的支付资料不计为开发者收集。
- [CloudKit private database](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)：用户拥有私有数据，开发者不能通过开发者门户查看。共享仅面向用户指定参与者，不是开发者开放数据库。
- 本答案范围仅为当前签名包和固定 SDK revision。它不证明真实 Production 同步成功；网络门槛另列，不隐藏云数据处理说明。

## 2026-10-15 构建 9 准备复核

本轮重新检查宿主 Cloud/Support 和当前组件消费：未发现 publicCloudDatabase、分析 SDK 或开发者数据上传；App 只链接 DeveloperSupportKit 与 EngagementPromptKit，不链接 FeedbackKit。新增昵称由账号 private 资料与已有共享参与者访问的成员记录承载，保留在本机/用户 Apple 数据域；当前声明仍以“不由开发者收集”为草稿依据。系统确认模式只改变展示，没有新增数据上报。

canonical 政策已更新昵称、支持交易字段及确认金额动线；构建 9 实际归档政策字节一致，公开两页已发布并匿名回读一致。ASC 会话已恢复，商店/IAP 说明已保存回读；App Privacy 草稿发布仍留最终人工核对，本轮已重新读取 App Privacy：政策 URL 正确，预览为“未收集数据”，仍显示“发布”按钮；本轮未点发布。不要把源代码检查写成所有隐私表单已完成或 Apple 已批准。
