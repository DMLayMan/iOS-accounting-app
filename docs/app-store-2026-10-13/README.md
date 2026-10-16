> 10/15最新：构建7已实际安装并通过进入/重开。本人登录后完成两笔18/CNY的真实Sandbox交易，已验签落盘；但重新拉取仍展示USD，价格一致性未关闭，当前不可送审。见 [当前取证](../release-validation-2026-10-15/build7-iap-hang.md)。

> 最新覆盖：用户真机体验后撤回构建 9 隐藏金额方案。9 已安装并通过选择页技术检查，但不能作为送审候选；本地已恢复明确价格展示，币种问题未解决。详见[撤回与修正记录](../release-validation-2026-10-15/price-transparency.md)。以下构建 9 旧方案记录仅作历史证据。

> 10/15 最新：1.0（6）已重新打包、上传处理并进入原内部群组，手机实际安装和 App 内版本均回读为 6。A→B 备注修改、此前 B→A 新增、连接失败后的恢复、真实只读拦截和恢复编辑权限回读已通过；仍 2 笔 ¥32.34。新包真人支付取消与其余异常矩阵待关闭，商店草稿仍 4，未送审。见[最新验证](../release-validation-2026-10-15/README.md)。

# 余记 · App Store 发布准备

最新状态（2026-10-15）：1.0（9）已上传并进入原 TestFlight 内部验收组，金额确认兜底、三档 IAP 新审核图/备注、商店描述及公开隐私/支持页已保存回读。手机最后实测为 8，真实双账号昵称、改名与归属已通过；9 的实际安装与系统取消验收仍待本人更新，其他真实云异常与备案等门槛保留。**当前不可送审**，以[构建 9 当前交付](../release-validation-2026-10-15/build9-delivery.md)及[分层验证状态](../release-validation-2026-10-15/validation-status.json)为准。下列 10 月 13/14 日产物及表格为历史快照，不覆盖最新结果。

最新跟进：2026-10-15，[审核联系人与版权及新版协议](contact-update-2026-10-15.md)均已关闭。联系人和版权保存、刷新回读通过；用户在具体弹窗接受协议后，新一轮刷新核实签发日期 2026-10-14、接受日期 2026-10-15，待接受提示消失。代理未代签，电话和审核邮箱不进入公开文档。

10 月 14 日回收：见[送审前复审](../pre-submit-review-2026-10-14/README.md)。手机为 1.0 (3) Debug Development 联调包，本次未覆盖安装。新版真实 Sandbox 支付 ¥6/CNY 已核实，用户确认关闭及感谢体验正常；Development 双账号核心共享、冷/热邀请、互记和 SDK 权限/撤权已验。Release 默认云配置和隐私说明已修复，新未签名 1.0 (1) 归档通过资源门槛；此前签名与备案 IPA 未包含近期修复，不能直接发布。Production、最新正式签名、TestFlight、完整真实矩阵及后台材料仍待闭环；未提交 Apple 审核或上架。

10 月 14 日登录回读时，描述、关键词、支持 URL、版权与审核联系字段为空，正式截图 0 张、未选择构建；App 隐私问卷/URL、年龄分级和内容版权仍待完成。10 月 15 日已补齐版权和审核联系人，其余缺项未因本次保存自动完成。审核说明及手动发布已存在。旧记录中“文案已保存”是历史批次结果，不猜测字段变化原因。

正常启动自动发现了同账号 Development 验收账本（3 笔测试数据），原用户实体与选择未变。已备份、完成精确预览并获授权清理，正常重启未回流，原业务、其他云绑定和支付日志保留，见[清理回收](../icloud-delivery-2026-10-08/test-fixture-cleanup-2026-10-14.md)；备案按用户要求等待审核，本轮未回读或修改。

## 账号约束

只使用用户在当前对话中指定的 Apple 账号；不得选择其他 Apple 账号或其他账号的开发团队。用户已在本机完成登录，Xcode 中邮箱精确匹配，仅有 wang kai 团队，角色 Admin；经界面选择后从生成工程核对 Team ID 为 7S626H9YL4，并写回 canonical project.yml。账号核对记录在本地 `evidence/app-store-20261013/signing-account.json`。邮箱不作为公开客服地址，不写入版本化发布资料。

## 分阶段材料与历史产物

- [商店文案与字段草案](metadata.zh-Hans.md)：可复制文案及明确未确定的商店字段。
- [打赏商品配置与验收步骤](iap.md)：三个精确商品 ID、类型、文案与真实 Sandbox 门槛。
- [隐私表单依据](privacy-review.md)：逐数据流区分本地处理、Apple 通信和开发者收集，最终包再核对。
- [签名、云与分发操作表](distribution.md)：账号核对、Bundle ID、容器、签名、TestFlight、送审和发布的顺序及边界。
- [公开网页源文件](public/privacy.html)：10 月 15 日已获授权仅发布两页 GitHub Pages；见上方最新验证。原候选记录保留。
- [初始 Release 归档检查](artifact-check.json)：0.1.0 未签名历史归档，最低 iOS 17、iPhone 竖屏、图标/离线政策/隐私清单已入包，测试夹具与模拟实现未入包。
- [历史 App Store 签名产物](distribution-check.json)：0.1.0 本地包；容器绑定前的导出记录，仅保留历史证据。
- [1.0 生产环境签名候选包](production-candidate-check.json)：新 profile、指定团队/Bundle ID/容器、Production 实际 entitlements、get-task-allow=false、严格签名与资源检查均通过。尚未安装或上传，生产云服务验收未完成。
- [统一安装名称检查](display-name-check.json)：用户已确认桌面与商店同为「余记账本」，应用内保留「余记」；新候选包已重归档、导出并严格验签，155 项 portable 测试重跑通过，手机旧包未覆盖。
- [真机记录](device-check.json)：iPhone 12 / iOS 26.6.1 已安装与启动；独立测试账本验收后恢复普通 Release 包。
- [CloudKit 签名核对](cloud-signing-check.json)：新容器已登记并关联 App ID，Development 签名/描述文件与实际 entitlements 对齐；尚未上传账本或验证共享。
- [Development schema 回读](cloud-schema-check.json)与[官方导出文本](cloudkit-development.ckdb)：YujiLedger 的 name / formatVersion / payload 已保存并刷新回读；未部署 Production 或写入账本。
- [大陆 App 备案材料与路径及低价比较](china-filing.md)：北京个人主体；名称和候选包技术材料已核对。用户已付款并本人提交备案，实际订单处于阿里云初审，尚无备案号；网页未部署。
- [备案提交后的发布顺序](after-submission.md)、[审核状态回读](filing-review-check.json)：当前初审、后续短信核验和管局审核，以及等待期间的支付、云共享、网页和商店验收。
- [真实 Sandbox 与双账号 iCloud 联调](../live-services-2026-10-13/README.md)：保留首轮历史与最新跟进；[新版支付](../support-payment-2026-10-14/README.md)及[双账号验收](../icloud-delivery-2026-10-08/dual-account-acceptance-2026-10-14.md)为最新证据，不以 Development 替代生产回归。
- [ECS 配置与静态网页部署草案](hosting/README.md)、[配置回读](ecs-hosting-check.json)：北京 2核2GB/40GB/3Mbps/Ubuntu 24.04/1年，付款成功、运行与备案资源资格已回读；¥99 为购买报价，实际付款金额未独立回读。仅网页80/443入站，无自动续费；云助手只读检查 ExitCode=0。DNS、网站备案范围、HTTPS和端内真实访问待完成。
- [商店价格与供应回读](store-distribution-check.json)：App 免费、只选中国大陆、Mac/Vision Pro 未供应，副标题及财务类别已保存；不代表通过备案或已发布。
- [初始源码指纹](source-fingerprints.json)、[0.1.0 签名配置指纹](signing-source-fingerprints.json)、[原 1.0 候选包指纹](production-source-fingerprints.json)与[当前同名候选包指纹](named-production-source-fingerprints.json)：125 个输入文件，本次显示名只改 Info.plist/project.yml；归档不能仅用 HEAD 代表。公开 Repo 当前分支未查到 PR 或 CI 记录。

## 10 月 14 日发布阻塞快照（当前状态见上方链接）

| 项目 | 当前状态 | 下一步与关闭依据 |
| --- | --- | --- |
| 账号、团队与签名 | 已核对；设备登记、开发签名和分发 IPA 导出均通过 | 最终功能配置重归档后再跑 Apple 平台校验 |
| App 记录与唯一标识 | 余记账本 / Apple ID 6822126066 / SKU yuji-ios，状态准备提交；审核说明及手动发布存在，描述/关键词/支持 URL 本次为空 | 补齐最新实际字段、截图与构建，不能沿用旧保存结论 |
| iCloud | 容器和 Development schema 已登记；不同身份的核心邀请/互记/权限验收通过；现 Debug 默认 NO，Release 默认 YES/Production，新未签名归档已核对 | 回收剩余真实矩阵与系统成员管理 UI；授权部署 Production 后再验正式包，先处理开发缓存备份与恢复 |
| 打赏 | 真机真实目录 ¥6/¥18/¥30；新版 Sandbox ¥6/CNY 新收据已核实，用户确认价格与完成反馈正常；原自动观察超时保留 | 真实取消/pending/撤销未全部回收；最终包审核截图与 TestFlight；首次三个商品随App版本送审 |
| 公开政策和支持页 | Repo 可公开访问，GitHub Pages API 返回 404；未有可用政策网页 | 候选网页审核后部署到 HTTPS 地址，无需业务后端；匿名访问并核对与包内政策一致 |
| 真机与最低系统 | iPhone12/iOS26.6.1 当前1.0(3)Debug；最新真实共享及支付见独立记录，原用户实体未变；iOS17未运行 | 最低系统、完整恢复/升级、最终发布包仍需验；不能把换BundleID当原地升级 |
| 商店字段与截图 | 10 月 15 日版权/联系人已保存回读；正式截图、隐私与年龄分级、三档 IAP 等缺项仍未关闭 | 最新包生成合成数据正式截图及 IAP 审核图，填写并回读；补齐可访问政策与支持 URL |
| 协议与地区资格 | 新版开发者协议已由本人接受并回读 10 月 15 日记录；中国大陆 ICP 字段上次仍空，用户此前已提交备案，本轮未查询阿里云进度 | 协议门槛已关闭；等待备案结果，取得号码并核对名称后填 ASC/端内，不将历史“初审”当今天状态 |

不为绕过真实云验收擅自删去用户已要求的共同记账能力。若考虑缩小首发范围，需要用户明确决定，并同步帮助、商店文案和构建配置。

## 2026-10-13 历史签名与回归批次

Release archive 成功；Portable 155/155（113 Core＋42 AppState）通过。归档资源核对通过；编译保留了 17 条非致命警告，主要是 iOS 17 onChange 旧重载的弃用提示，详见 [原始警告](compiler-warnings.json)，没有据此改动本轮已冻结产品源。

原生定向发布回归 55/55（43 unit＋12 UI）通过，无失败、跳过或运行时警告；范围为全部当前 YujiTests、9 个 ReleaseReadiness 路径与 3 个支持入口/一次邀请路径。采用新隔离会话，保护个人账本。完整细项见 [分阶段验证状态](verification.json)。此前 10 月 8/9 日图集仅作设计参考，不冒充本轮正式签名包截图。

账号登录后变更团队与用户确认的新 Bundle ID/容器，启动脚本改为读取构建包的真实 Bundle ID；首发版本对齐为 1.0。记账业务代码没有变化。原始未签名归档与测试指纹保留，不覆盖成后续签名配置。无设备、签名模式冲突和旧标识占用的失败日志均保留，不能当成当前构建结果。

1.0 (1) Production 云签名候选包归档/导出与严格签名检查通过，生成容器绑定后的新 profile；该 Production IPA 尚未安装，schema及共享仍待验。手机此前为0.1.0本地Release，当前已备份并在保留个人账本的前提下升级到1.0(2)Debug开发云联调包，真实服务使用UUID隔离文件。两项初步通过不证明正式Production可用。

本次统一桌面名后，新的 `cloud-production-named-export/Yuji.ipa` 已验签回读「余记账本」，应用内仍为「余记」。155 项 portable 测试已重跑；上文 55 项模拟器原生和 2 项真机测试是改名之前的结果，未重复运行。编译原生代码段比对一致，完整二进制及 IPA 因重新签名重新计算摘要。旧源码快照与旧包保留为历史证据。

真机 UI 定向回归 2/2 通过：收支/退款/转账/重启余额守恒；备份/CSV 系统分享和导入取消。使用 Debug 隔离测试环境，不冒充正式 IAP/云或完整系统恢复验收。结束后重新安装并启动普通 Release 包，未卸载或清空应用数据。原始 xcresult 在 evidence/app-store-20261013/device-ui/。

[真机重启后的账本截图](assets/physical-balanced-relaunch.png)来自独立验收数据：收入 120、支出 30、退款 10、转账 25；净支出 20、结余/余额 100，现金 75、银行卡 25。此图为验收证据，非最终商店截图。

本地日志/归档：`evidence/app-store-20261013/`（不提交数 GB 归档、签名资料、设备标识或真实账本）。协议、付款和备案提交由用户本人完成；代理未代签，未公开部署、推送或提交 App Review。

## 官方依据

已于本轮读取 [SDK 与最低系统要求](https://developer.apple.com/news/upcoming-requirements/)、[截图规范](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)、[隐私信息](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)、[首次 IAP 提交](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/)、[App 信息与大陆备案字段](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)。最终以登录后实际账号表单和处理结果为准。
