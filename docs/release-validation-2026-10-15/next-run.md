> 当前：[TestFlight 构建 15](build15-reissue.md)已在 iPhone 12 覆盖安装，设备与帮助页核对通过。升级数据保护、真实 Production 同步、统计人员筛选与同页明细通过，测试后数据除同步时间外不变。15 与 14 产品源码一致（仅构建号不同），签名、资源、Production 配置和 CI 已通过。14 下载卡住根因仍未确定；本人暂时不方便听读，真机 VoiceOver 保留待验证，本次不再请求或占用手机。[iOS 17 与无障碍验证](ios17-accessibility-2026-10-16.md)保留实际已测范围和未关闭告警。商店草稿最近核对为 13，未提交审核；Apple 反馈与备案等待。

> 已安装基线：[TestFlight 1.0（13）](build13-polish.md) 已完成本地验证、签名导出、上传及原内部组分发回读。SDK 97f38bb，产品源码 e0a6cc2，App 草稿 PR #3；已回读 CI e54e9f8（run 38850819923）的 Core 与 iOS build 通过。13 与三档 IAP 已关联同一份四项审核草稿；五张新版截图、审核说明、手动发布刷新回读一致。13 真机升级和数据保留已通过；三档刷新后仍为 USD，[真实断网昵称及恢复](build13-live.md)已通过，真实价格一致性继续核对。备案等待，不提交 App Review。

## 下一步（构建 15 已安装，2026-10-16）

- 15 版本、数据保留、同步和统计复验已通过；本人暂时不方便 VoiceOver 听读，先记录为暂缓且未验证；待本人方便时再回收流水、统计筛选和记账键盘三项，不重复催问，也不能将自动检查计作真人听读通过。先读 [真实验收报告](build13-live.md) 和 [结构化状态](validation-status.json)。昵称断网保存、重启、联网、另一真实账号回读与原昵称恢复已经完成，不再重复改名。
- 价格未通过：本人确认应用「小小鼓励」US$0.99，Apple 系统确认页 ¥6，随后取消；没有新增交易。不要将系统确认报价写成已付款。不要换算、固定人民币、隐藏金额或要求重复付款。
- [Apple 脱敏反馈](apple-storekit-feedback-draft.md)已更新并获发送授权；已实际提交并回读 [FB25209457](https://feedbackassistant.apple.com/feedback/25209457)，仅文字、0 附件，等待 Apple 处理结论。不要重建重复反馈；需要补充诊断时先准备最小脱敏材料，再按敏感数据范围取得授权。
- QA 当前 8 笔、¥666.99，原昵称已经恢复；私有快照在 `evidence/ux13-20261016/phone13-after-restore` 及 `phone13-after-price-return`。不按历史 2/4/6 笔基线回滚，不清理既有数据。
- 同账号多物理设备、精确 iOS 17.0/实体最低系统、人工 VoiceOver、SDK 自身 CI 计费限制单列未验证（iOS 17.5 模拟器已补验）；不能使用不同账号 Catalyst 观察端或 App CI 替代。
- 商店候选仍为 13 与三档 IAP，截图和审核说明已关联，手动发布。备案等审核；无最终送审授权不提交 App Review。

以下保留各版本的历史交接，不能据此恢复旧候选或重跑已完成的写操作。

> 历史安装基线为 [TestFlight 1.0（12）](build12-reissue.md)：手机实际安装和帮助页已核对；两项原生测试验证同步及按记账人筛选，10 项数据保护检查通过。审核草稿已关联 12 与三档 IAP，刷新回读为四项，保留手动发布，未提交 App Review。新版付费协议有效，备案等待。

> 历史过程（已由 12 安装结果覆盖）：[共享退出修复与构建 11](cloud-resume-2026-10-16.md)。新私有邀请接受、修复后的真实成员退出、本地副本与重新加入已通过；统计人员筛选实测通过。构建 11 已加入原 TestFlight 内部组，手机升级待核对。下方构建 10 的待重邀/退出描述为历史状态，以最新报告和 validation-status.json 为准。

> 历史交接（构建 10）：手机实际版本已验证；完成真实断网新增/重启、恢复联网、同笔并发保留副本、丢回执去重、只读拦截、恢复写入、撤销后保留本地副本。A 端新邀请已准备，手机停在邀请成功页；旧邀请已被 Apple 判失效，等待本人转交新私有链接，才能继续 B 接受、退出与恢复成员。不得重复新增三笔测试数据。构建 10 和三档 IAP 已放入同一份 4 项审核草稿；隐私答案已明确授权发布，未提交 App Review。详细证据和边界见 [当前报告](cloud-final.md)、[结构化状态](validation-status.json)。

以下旧交接为历史，版本安装、材料与待办被上方当前状态覆盖。

# 下一轮继续位置

> 最新覆盖：用户真机体验后撤回构建 9 隐藏金额方案。9 已安装并通过选择页技术检查，但不能作为送审候选；本地已恢复明确价格展示，币种问题未解决。详见[撤回与修正记录](price-transparency.md)。以下构建 9 旧方案记录仅作历史证据。

## 最新：构建 9

[金额确认兜底与本轮发布记录](build9-delivery.md)：SDK de43e66，1.0（9）已上传；172 项 portable、原生 93 通过/9 专项跳过/0 失败、SDK Pro 11 与 SE 两项通过。公开两页已同步并匿名回读。手机最后确认仍是 8，不能将上传等同于安装；后续按 validation-status.json 继续。

以下为此前阶段记录；被构建 9 覆盖的版本、依赖和待办以上方链接为准。

2026-10-15 当前记录，先读本人最新回复和 [验证状态](validation-status.json)，不要把上传/处理/可用/实际安装/真人支付混为一个门槛。未获最终确认不提交App Review；备案继续等审核。

## 当前候选 1.0（8）——18:28 昵称验收完成

先读 [完整交付与真实 A/B 结果](../shared-nickname-2026-10-15/live-testflight8.md)。手机已实际安装 8，不再让本人更新 7/8、切换账号或重复支付。本轮目标闭环：同一 Production QA 上 A TestFlight 原生 UI 与 B 另一真实 Mac iCloud 的原生集成/云回读完成昵称互看、双向改名、冷启动、A 新建、B 编辑 A 及原昵称恢复。独立 runner 无 AUT 安装路径，147 文件冻结源在更新文档前全部匹配。

- QA 原两笔保留，新增 B 2222 分、A 1111 分；最终 4 笔 6567 分。A 新笔 author=A、lastEditor=B，备注带“B已核对”；两个临时昵称均恢复为空偏好。新样本暂留，尚无该批永久回收授权。
- 私有证据 `evidence/people-20261015/live-build8/`：context/manifest、原昵称备份、前后 AppSupport、每阶段 xcresult、完整源快照、上传证据、只读 `verify_final.py` / `final-verification.json`。后者全部通过：原两笔、其他环境绑定、设置和实体不变，3 条收据逐字节保留，新建计数只从 2 到 3。不要重跑 baseline、A 新增或 B 新增，更不能按旧“2 笔”覆盖当前数据。
- SDK 已授权推送 28969d194cb42584085cb97c4317b8f0dacca810，更新既有 PR #4；App 已固定到该提交。44 条 Swift 及同源码 Pro4/SE2 原生批次通过；4 项远端 CI 仍因 GitHub 计费/额度未启动，不能说绿色。未合并、未 tag。
- 8 的签名归档、资源和 Production 配置通过，Organizer 上传、ASC 处理/内部组及手机安装已验证；8 的本地 App Store IPA 导出未通过，不能引用 7 的 IPA 当作 8。
- 下一步发布门槛仍包括 TestFlight 目录 USD 与实际 CNY 的差异、公开隐私站点昵称说明、真实昵称只读/离线等额外异常、备案及最终 App Review 确认。本轮没有再次支付、改在线配置或提交审核。

以下为构建 7 及更早的历史交接，版本/依赖/待办已被上方构建 8 记录覆盖的部分以最新记录为准。

## 历史候选 1.0（7）

ASC已处理7，仅加入原「首发验收」群组（f8122c0b-5bc8-4b78-ab6c-c407840ab8f3，1位测试员），说明保存刷新回读一致，截图已向用户展示。本人、设备清单和原生帮助页均确认已安装7。独立runner13的进入/选择/关闭重开1条通过，用户接受此动线。

用户已澄清点击的是「请一杯」；认证等待取证完成。本人随后登录并确认链路正常，系统日志与App独立日志已回收两笔新coffee收据，每笔Sandbox18/CNY、有当次attempt关联；原收据保留，邀请字节相同，业务数据仅cloudLinks元数据改变。旧在途调用最终返回ExpiredLongLivedToken相关认证失败；两次新购买已完成，不再请求本人重复支付。

**当前关键问题是目录币种不一致。** 登录后新的独立真机进入/重开检查仍US$0.99/US$2.99/US$3.99，Storefront仍USA；实际新收据却CNY18。不能把Storefront和Product同为USD当作正确性的证明，不能从USD推断实际购买身份美区，不强改货币符号。详见 [当前取证](build7-iap-hang.md)。Apple论坛有相似TestFlight一手报告，DTS建议提交Feedback；只作为研判，未证明本App同根因或正式AppStore正常。[脱敏反馈草稿](apple-storekit-feedback-draft.md)已准备但未发送。

最新SDK本地修正仅为等待体验：阶段文字、自定义可读禁用态、15秒后可关闭且不自动重试提示。44条Swift、最终Release与Pro4/SE2原生专项全部通过（4个不同方法，共6次），截图浅色/大字深色/小屏复看完成，源码冻结哈希相同。首轮Pro首次本地StoreKit目录不可用的失败与诊断保留，已注册后复测原失败通过，最终新构建4/2均通过；不拼成全套9条回归。Xcode收集本批模拟器诊断久未结束，测试体结束后仅停止本批自己的simctl diagnose子进程。

新SDK工作树为本轮等待UI/测试/文档修改，未推送/升级App依赖/上传；App仍固定远端4f573f2与构建7。UI改动的原生截图在ios-base/docs/assets/support-wait，测试和manifest在.artifacts/purchase-wait-20261015。不要把该反馈修正称为Apple认证或币种根因修复。

Apple官方区分Development与TestFlight指定Sandbox账号路径；切换正常Media & Purchases可能影响既购内容，当前未获授权且未执行。本人只读询问已回复为“登录解决、整体正常、金额仍美元”，未继续索取账号/密码。

7的签名归档在私有evidence/release-20261015/release-1.0-7.xcarchive；111文件完整源码/资源/测试/验证脚本快照build7-source-complete-*已逐项哈希回读，App工作树大量既有改动保护，不能凭旧HEAD复现候选。SDK固定远端4f573f2fee49e30626ef702af0db72eb6e71ebac，Package.resolved及解析的源码与本地测试逐项相同。

实际App Store IPA位于build7-app-store-export/Yuji.ipa，4,030,676字节，严格codesign、资源、团队/Bundle/Production容器与get-task-allow=false通过。SHA256：4274f9e0f87420662bf398878bde33c980092f328e8f3880d7dff2ab36a6be82。归档签名与分发IPA的证据各自保存，不替代手机验收。

## 最新修正与测试

7移除历史购买标记对金额选择的阻断；每次重新加载Apple商品、不预选、可多次主动支持。仅当次核价/系统调用防连点，pending/unknown只内联提示，取消安静返回。收据后台验签、去重、持久化后finish；lastPresentationCompletion仅关闭当前这次支持，历史迟到确认不影响新选择。旧schema1的receipts/目录/scope保留，忽略旧unresolvedProduct，不删除收据、不自动付款。详见 [重复支持修正](repeat-support.md)。

- SDK最终43条Swift、7条原生harness、Release、消费者、relay16条、策略4条、dry-run及audit0漏洞通过。PR#4已更新并回读匹配，未合并/tag。新CI run38693970346的四项annotations仍为GitHub账号付款/额度而未启动，未改计费/跳过检查。
- 余记根swift test为113Core＋48AppState，原生专项22条（13支持UI＋6邀请＋3呈现依赖）通过、0失败/跳过；两次真实本地StoreKit支持、旧批准不关闭新页、取消与未知/待批准重开、深色/最大字号可达均验。最初脚本因generic/arm64两清单而保护退出，明确选择最终arm64后执行22条；准备失败保留。不能与旧135通过＋24专项跳过合成候选全回归。
- 原6是5仅构建号变化的重发；当前已实际7。旧5下载失败根因未确认，不再要求本人重试5。

## 手机与数据边界

上传前只读Application Support备份在build7-device-before；进入/重开后与build7-device-after-entry对照：support.json和邀请文件字节相同，所有业务实体相同，只有cloudLinks[1].lastSync/version改变。build7-entry-data-safety.json已记录。不能宣称全ledger字节相同。这些对照覆盖此前进入/重开阶段；真人登录后的新快照已确认新增两笔18/CNY验签收据、旧收据保留，邀请仍字节相同，账本仅cloudLinks变化。旧调用已返回，不再按在途挂起处理。原始备份、邀请、账号与收据不公开，不覆盖旧快照。

独立runner13已编译：.build-release-20261015-distribution-driver13/Build/Products/ReleaseAcceptance.xctestrun，无UITargetAppPath、无Yuji.app依赖，不覆盖安装调试App。方法DistributionInspectionTests/DistributionInspectionUITests/testBuild7FreshSupportEntryAndReopen只activate、检查帮助页7、打开/选择/关闭重开，不点击付款、不清journal、不改账本。已实际执行1条通过、0失败/跳过，截图已回收。

真机购买/取消由本人执行，先activate回读稳定结果与日志，之后才做冷启动；不要用launch打断购买页/回调。保持发布账号、Mac用户、iCloud及媒体购买账号；不卸载/恢复/重置数据。测试derivedData冻结，xcresult结束后顺序读取summary/附件。

## Production共享基线与余项

私有上下文在evidence/release-20261015/distribution-driver/production-peer-context.json；只使用同一精确QA账本、zone与双方身份。已完成A真实TestFlight4上传1234分→不同B接收下载→B-add一次2000分→A真实连接失败保留缓存→随后恢复2笔3234分，B独立回读一致；截图显示Wi-Fi，只证明恢复，不能称纯蜂窝成功。

6实际A修改原交易备注，ID/金额不变，revision1→2；B Production回读一致。不要重跑B-add，也不要再次修改原备注。A实际系统成员管理设B只读，B回读writable=false且修改被拦截、隔离数据编码不变；A恢复编辑，B回读writable=true。普通Mac文件指纹未变。恢复后的再次写入、双方真实离线/并发冲突、撤销重邀/退出仍未全关闭；本批QA/失败云数据未获清理授权。

Mac接收包固定.build-release-20261015-catalyst-production/.../Yuji.app，仅云QA（旧SDK），不是公开Mac产品或7支付证明。文件更新不会替换内存进程；重接邀请前安全退出并核对精确路径/启动时间晚于二进制。共享闪退已由捕获并注入同一AppState修复，真实接收通过；不再让本人反复重发同一邀请。

## 发布剩余

商店版本草稿仍4，手动发布且审核需要登录=false。隐私答案发布、首次IAP关联、7真机支付动线与真实云异常矩阵、备案结果及最终人工App Review确认仍需闭环。不得直接提交旧草稿4。仅两页隐私/支持HTTPS站点已单独授权并发布；不推送其他未提交App源码或个人证据。
