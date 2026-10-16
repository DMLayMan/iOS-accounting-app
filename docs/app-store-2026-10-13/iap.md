> 2026-10-15 构建7最新：本人登录后支付恢复，新增两笔18/CNY/Sandbox验签收据；目录和Storefront仍返回USD/USA，重新拉取无效。不能解释为美区实际计价或强改货币符号，价格一致性仍待关闭。见 [故障及回收](../release-validation-2026-10-15/build7-iap-hang.md)。

> 2026-10-15 最新要求：取消历史状态阻断，每次打开直接选择最新金额，支持主动多次打赏；后续构建验证见 [重复支持修正](../release-validation-2026-10-15/repeat-support.md)。旧手动核对并解锁方案已被替代，勿再请求用户执行。

# 自愿支持 · 正式商品与验收

Apple 消耗型商品，不是订阅或功能解锁；商品 ID 与 `DeveloperSupportCoordinator.tiers` 精确一致。用户确认 App 免费、三档打赏 ¥6 / ¥18 / ¥30、首发中国大陆。三个商品草稿的简体中文名称、描述、审核备注、价格和销售地区均已保存并刷新回读，未提交审核。2026-10-14 新版真实 Sandbox ¥6/CNY 收据已核实，用户确认完成体验正常；最新证据与剩余场景见[支付复审](../support-payment-2026-10-14/README.md)，不代表 TestFlight 或审核通过。

应用 Bundle ID 于本轮调整为 com.dmlayman.yuji。上述商品 ID 是独立的稳定标识，本轮不随应用标识改名；正式后台创建时必须使用表内完整值。支持收据和一次邀请的本地 scope 同样保留，不能用整仓文本替换破坏已有契约。

| Product ID | 类型 | 中文显示名 | 描述 | 已保存 CNY 价格 |
| --- | --- | --- | --- | ---: |
| com.yuji.app.support.encourage | Consumable | 小小鼓励 | 自愿支持余记开发，所有记账功能仍可使用。 | 6 |
| com.yuji.app.support.coffee | Consumable | 一杯咖啡 | 请开发者喝杯咖啡，不解锁功能、不自动续费。 | 18 |
| com.yuji.app.support.generous | Consumable | 加倍支持 | 一次性支持后续开发，记账功能不受影响。 | 30 |

## 后台准备

先核对指定账号的付费 App 协议、税务、收款及角色。协议与真实金融/税务信息由用户确认和填写。每个商品建立准确 ID、类型、价格计划、销售地区、中文本地化和审核截图/说明，记录后台商品状态。购买界面读取 Apple displayPrice；不把测试配置价格当商品已上线的证明。

2026-10-13 最新实际回读：免费与付费 App 协议均「有效」，银行状态「可用」，U.S. Certificate of Foreign Status of Beneficial Owner 与 U.S. Form W-8BEN 均「使用中」、提交日期为 2026-10-13。协议、税务和银行资料由用户本人处理；Repo 只保留状态，不保存私人证件、税号或银行标识。入口：[App Store Connect → 商务](https://appstoreconnect.apple.com/business)。此前「新」→「等待用户信息」为过程状态，不再作为当前阻塞。

同日已创建的商品记录：

| 参考名称 | Apple ID | Product ID | 后台状态 |
| --- | --- | --- | --- |
| 小小鼓励 | 6822127270 | com.yuji.app.support.encourage | 准备提交，草稿 |
| 一杯咖啡 | 6822128113 | com.yuji.app.support.coffee | 准备提交，草稿 |
| 加倍支持 | 6822128461 | com.yuji.app.support.generous | 准备提交，草稿 |

中文名称、描述与上表对应，价格基准地区为中国大陆，销售范围仅中国大陆，未勾选自动供应未来新地区。[审核备注](iap-review-notes.txt)在三个页面刷新后与本地文本一致。后台价格矩阵自动生成 175 个地区的换算价格，与仅选择一个销售地区是两套配置，不能按价格矩阵行数推断开放全球。后台「准备提交」不代表已审核上线；正式商品加载与 Sandbox 购买已有独立证据，最终审核截图和首次随 App 送审仍需完成。后台状态快照见 [商品草稿回读](iap-draft-check.json)。

审核截图从正式配置后的支持页面拍摄。路径：我的 → 首屏「好用，请开发者喝杯☕吧」→ 选择金额 → 主动购买。所有商品可选但没有默认扣款。支持邀请在本机成功新建 100 条不同记录后安全退出录入再展示，仅一次；人工入口持续可用。

Apple 当前说明：首个消耗型 IAP 必须与新 App 版本同一提交。准备阶段不点击 Submit for Review；商品与 App 版本加入同一草稿后核对，再执行最终送审。[官方提交流程](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/)

## 真机 Sandbox / TestFlight 回收

| 场景 | 成功依据 |
| --- | --- |
| 三个商品加载 | 正式 ID 与 Apple 返回价格一致，非 IsolatedSupportClient 或 .storekit 文件 |
| 系统确认与取消 | 用户看到真实系统 Sandbox/TestFlight 购买界面；取消没有成功感谢或记账限制 |
| 成功与重启 | Transaction verification 为 verified；本地持久化后 finish；重启不重复感谢/扣款 |
| 离线和未知结果 | 清晰错误，输入和账本不受影响，未确认期间阻止重复购买 |
| 待审批与恢复 | 支持可验证场景下 waiting → updates → completed；未能触发则标未验证 |
| 退款/撤销 | 对实际可提供的 Sandbox 场景核对；不可提供时保留未验证项，不以注入测试替代 |
| 独立数据 | 付款不生成账单；账本恢复/共享不带交易和邀请日志 |

不要为真实验证在生产商店执行实际扣款。Sandbox 身份与开发者发布身份用途不同；若需要专门测试身份，由用户明确提供/创建，不能使用其他现有开发者账号代替指定发布账号。

测试员已由本人创建，后台列表实际显示1个中国大陆账户；密码未保存。此前1.0(2)Debug登录前显示美区价格；1.0(3)已核对真实人民币目录，用户本人完成 Sandbox 操作，新已核实收据为小小鼓励 ¥6/CNY，自动关闭和感谢由用户确认。真实取消、pending 与撤销等未全部回收。沙盒身份与发布账号、第二真实 iCloud 身份分别处理，无需退出日常 iCloud。最新状态见[真实服务联调](../live-services-2026-10-13/README.md)。[Apple沙盒账号规范](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/create-a-sandbox-apple-account/)

已有本地 SDK 自动化设置 disableDialogs=true，未验证系统付款确认/Face ID/密码。原始证据见 [10 月 8 日接入](../developer-support-2026-10-08/README.md)。

Apple 说明后台元数据修改可能最多一小时才出现在 Sandbox；有指定发布身份并不表示已有 Sandbox 身份。开发签名 App 可在没有上传 App 二进制的情况下测试，付款前必须看见 `[Environment: Sandbox]`；未看见时停止测试，不把实际商店扣款当验收。[官方 Sandbox 测试说明](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)


## 2026-10-15 发布材料与 TestFlight 回读

三档商品的审核截图已上传并保存刷新回读，备注明确自愿单次支持、无功能解锁、无自动扣款，以及“我的”首屏入口；仍为准备提交，未送审。截图采用 10/14 真实 iPhone CNY 目录图，三档均可见，对应旧 SDK 的真实界面；5 的新增修复不改变商品展示，但旧图不能冒充新包 TestFlight CNY 验收。

实际安装 TestFlight 1.0（4）后，小小鼓励返回 US$0.99；用户核对 Apple 系统页同为 US$0.99，并取消。本次 App/系统价格一致，人民币 TestFlight 尚未通过，具体 Storefront 待核实，不通过设备语言推测地区、不硬编码金额。依据 [Apple Sandbox 测试说明](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)，TestFlight 使用 Sandbox；不为改币种擅自退出日常“媒体与购买项目”。

取消后原支持 receipts 不变，但出现 unresolvedProduct，重启提示结果待确认，不能写成取消流程通过。SDK 已修复明确取消的 Swift/NSError 桥接及旧 SKError 路径，unknown/network 仍保留保护；新提交 5a15573 的 35 条单测、6 条原生 harness 与余记 21 条专项均通过。1.0（5）已上传并进入内部群组，待安装和真人取消回读；旧 journal 不自动清空，不能把没有新增收据当成没有待处理购买的证明。详见 [当日验证](../release-validation-2026-10-15/README.md)。
