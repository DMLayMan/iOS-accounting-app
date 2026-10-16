> 构建 10 已进入内部 TestFlight，恢复明确价格并增加按记账人筛选；下方 App Store 文案仍为本地草稿，未据此同步后台。后台旧构建 9 的隐藏金额说明和审核图需随最终候选更新，禁止直接送审。

# App Store 中文资料草案

2026-10-15 跟进：审核联系人已按用户提供信息填写并保存，版权 `2026 wang kai` 已刷新回读；新版开发者协议由本人接受，官网接受日期已更新至 10 月 15 日，见[后台更新记录](contact-update-2026-10-15.md)。下方 10 月 14 日快照中的其他缺项保持原验证边界。

当前状态（2026-10-15）：1.0（10）已上传并加入原 TestFlight 内部群组，说明与群组刷新回读完成；手机最后确认是 9，10 待本人更新。真实 Production 双账号昵称、改名和记账人归属的证据属于构建 8，本次没有重跑真实云服务。未提交审核。后台 App Store 版本草稿上次回读仍为构建 4，最终候选通过后需要更新；本次仅核对 TestFlight，不把此前商品、网址和审核字段视为本轮再验。完整状态见[构建 10 交付](../release-validation-2026-10-15/build10-delivery.md)。

## 可复制字段

商店名称：余记账本（用户确认且后台已创建；「余记」已被占用）。2026-10-13 用户确认桌面名称也统一为余记账本，应用内品牌仍为余记；新签名导出包的显示名已回读，详见[名称核对](display-name-check.json)。

副标题：随手记账，清晰预算与收支

关键词：记账,账本,预算,收支,流水,分类,账单,本地,个人财务

推广文本：记下每一笔，理清每一月。快速录入、分类预算和可下钻的收支统计，帮你看清钱花在哪里。

### 描述

余记是一款简洁的个人记账工具。打开即可记账，默认保存在本机，无需注册余记账号。

• 快速记一笔：输入金额，选择分类，保存。一级分类组织、二级分类归属，常用分类触手可及。
• 多个账本：分别管理日常、旅行或其他用途，查看累计收支与账户余额。
• 清晰流水：按月、年或日期范围查账，结合账户、金额和分类筛选，保留查找上下文。
• 收支统计：按时间和记账人筛选，分类饼图、排序与明细同页联动，了解支出结构，查看同比和环比。
• 账本与分类预算：设置月、年预算，以及一个或多个分类规则；超预算仍可记录。
• 完整记账：支持收入、支出、退款和账户转账，退款与原支出关联，转账不混入收支。
• 备份与恢复：主动导出备份或 CSV，在换机、整理数据前保留独立副本。
• 可选 iCloud：按账本开启同步，通过私有邀请与受信任成员共同记账；可设置只读或编辑权限，修改自己的昵称，查看每笔账的创建人。
• 你的外观：选择主题颜色、自定义颜色，以及跟随系统、浅色或深色模式。

核心记账功能不因是否支持开发者而受到限制。App 内提供一次性自愿支持，无自动续费、无功能解锁；价格以 Apple 购买页面为准。

本地账本请定期备份。删除 App 前请将备份保存到应用外，避免丢失未同步数据。

### 云能力补充（本地文案已就绪，待后台保存回读）

可逐账本开启 iCloud；同账号设备同步，也可通过系统私有邀请与受信任成员共同记账，设置只读或编辑权限。未开启同步的账本、个人草稿与外观不共享。同步不替代独立备份。

## 后台字段

| 字段 | 建议或当前值 | 状态 |
| --- | --- | --- |
| 主语言 | 简体中文 | 与包内 zh-Hans 对齐 |
| 类别 | 财务，次类别空 | 已保存并刷新回读 |
| 最低系统/设备 | iOS 17 / iPhone | 当前包声明值；真实 iOS 17 运行待验 |
| 首发版本 | TestFlight 1.0（10）已分发；手机最后确认仍为 9 | 恢复明确价格展示并新增按人筛选；真实币种、最终审核图和材料尚未闭环，不直接送审 |
| SKU | yuji-ios | 后台已创建 |
| Bundle ID | com.dmlayman.yuji | 旧值被 Apple 拒绝；新值用户确认、Portal 登记及签名 profile 已回读 |
| 价格 | App 免费；打赏 ¥6 / ¥18 / ¥30 | 用户确认；后台 CNY 当前价格已保存回读 |
| 国家/地区 | 仅中国大陆 | 已保存，状态「App 发布时供应」；不等于已发布或备案已通过 |
| Privacy Policy URL | https://dmlayman.github.io/iOS-accounting-app/privacy.html | 已保存回读；匿名 GET 200、与批准源码字节一致；问卷草稿已保存，未点发布 |
| Support URL | https://dmlayman.github.io/iOS-accounting-app/support.html | 已保存并刷新回读，匿名 GET 200；App 内帮助仍为项目 issues |
| Copyright | 2026 wang kai | 10 月 15 日按用户提供姓名保存并刷新回读 |
| 审核联系方式 | 用户本轮明确提供的姓名、邮箱、电话 | 10 月 15 日保存及刷新核对；具体电话/邮箱不进公开文档，不自动改公共客服信息 |
| 发布方式 | 审核通过后手动发布 | 保存并刷新回读确认 |
| 年龄分级/内容版权 | 无广告、无赌博、无公共内容/聊天、无医疗诊断或保健建议 | 问卷保存回读 4+；不面向儿童类别。私有共同记账不提供公开内容分发，医疗仅为费用分类 |
| 可访问性标签 | 只选择完成对应人工标准验证的项目 | 截图和自动化不替代 VoiceOver 人工验收 |

历史保存已关闭 Apple 芯片 Mac 和 Vision Pro 供应，首发仅 iPhone。用户已购买 ECS 并本人提交北京个人 App 备案；本次按要求等待审核，未查询或改动阿里云。ASC 的 ICP 字段仍空；仅隐私/支持两页已获授权发布至临时 GitHub Pages。见[备案准备](china-filing.md)及[提交后顺序](after-submission.md)。商店、桌面和拟备案名已统一为“余记账本”，不代表备案通过。

## 截图拍摄单

顺序：快速记账 → 统计联动明细 → 预算 → 账本汇总 → 流水查找。最多五张主图，先展示核心任务。只用合成账本、无个人账户信息，正文金额可读，无测试状态或调试提示；不画出包内没有的功能。

本轮读取的 Apple 规范要求 iPhone Dynamic Island 中等显示尺寸至少一张；Pro 原生 1206×2622 或 1179×2556 为规范列出的竖屏尺寸，无 alpha。当前仅 iPhone，不为未支持的 iPad 承诺界面。最终以后台接受结果验证。原生截图与最终签名候选包版本、构建号、源指纹一起记录，不能从旧图集凑数。

## 审核说明草稿

App opens into the Ledger tab. The central Record tab opens transaction entry. Local bookkeeping requires no account. Transfers are excluded from income and expense statistics; refunds link to the original expense. Backup/export is initiated by the user through the system share sheet.

Voluntary support is available as the first row in the Me tab, titled “好用，请开发者喝杯☕吧”. Three consumable In-App Purchases offer voluntary support only. They do not unlock any feature, grant currency, or renew automatically. A one-time optional invitation may appear after 100 newly saved local records; dismissing it never restricts bookkeeping.

iCloud is optional. From a ledger, open “同步与成员” to enable syncing. The owner can invite a specific Apple account privately and grant read-only or editing access. The invited participant needs their own iCloud account; no Yuji account or developer-provided login is required. “我的 → 我的昵称” changes the display name without changing historical record authors. Drafts and appearance preferences are not shared. Local bookkeeping works without iCloud.

The app displays the localized price supplied by StoreKit before the user selects a support option. The explicit purchase button opens Apple’s native confirmation inside the app; no amount is converted or hard-coded. A successful verified tip dismisses the support sheet and shows thanks; cancellation returns to the chooser. Each support action is voluntary and may be repeated.

The review contact is provided in App Store Connect. No passwords, two-factor codes, or private invitation links belong in this document.
