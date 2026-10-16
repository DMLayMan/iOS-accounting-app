# App Store 发布门槛

核查：2026-10-03。此清单记录当前差距，不代表已创建商店记录、已上传或承诺审核通过。

历史门槛快照：图标、语言、离线政策/帮助与开发占位已在[10 月 8 日复审](../review-fix-2026-10-08/README.md)处理；真实公开政策 URL、发布资料、签名和设备/分发验证仍需完成。下表保留当日证据。

| 门槛 | 当前证据 | 关闭条件 |
|---|---|---|
| 首发功能范围 | 本地版完整功能已存在；iCloud/共享只有方案 | 明确首发本地、同账号云同步或共享。需要云能力时另开实现与双真机验收，不能把未实现能力写进描述 |
| SDK / 最低系统 | 本机 Xcode 27.0 (27A266a)，归档 iPhoneOS27.0；MinimumOSVersion 16.0 | 满足当前 SDK 要求；iOS 16 实机/runtime 回归尚缺，或者另行决定提高最低系统 |
| Release 产物 | `xcodebuild archive` 通过，0.1.0 (1)，com.yuji.app，iPhone 竖屏 | 最终签名归档、Validate App、上传处理均成功；不能直接上传当前未签名包 |
| 开发者资格/团队 | 已有 Apple Development 证书；project 的 DEVELOPMENT_TEAM 为空 | 选定发布团队，验证 Developer Program、App Store Connect 权限、协议与分发签名；开发证书不证明这些已具备 |
| App 图标 | AppIcon 只有无 filename 的 1024 条目，产物无 CFBundleIcons | 完整原创图标、asset catalog 编译设置、桌面/设置/商店展示核验。当前桌面为透明占位 |
| 隐私政策与用户支持 | App 内没有对应入口/有效 URL/支持方式 | 本地政策说明+可访问政策 URL、Support URL 与真实联系方式；离线也能读到数据保存/删除/备份说明 |
| 隐私声明 | source 未发现网络/分析/广告 SDK；只引用本地包和 Apple 框架 | 以最终二进制审计填写 App Privacy，不因“记账涉及财务数据”就误选开发者收集。检查手动分享/文件提供器及系统备份措辞 |
| Privacy manifest | 源码与归档未有 PrivacyInfo.xcprivacy；常见 required-reason API 文本/符号抽查无命中 | 对最终依赖和 API 清单逐项核对并生成隐私报告；有适用 API 则添加实际理由。不能仅凭无 manifest 判违法，也不能用一次 rg 承诺不需要 |
| 商店资料 | 当前仓库没有最终商店资产包 | 名称可用性、主语言、类别、介绍、关键词、真实截图、版权、年龄分级、审核联系/说明和发布方式 |
| 语言配置 | 原生界面强制 zh_CN，产物 developmentRegion 为 en，未声明中文本地化 | 明确首发语言，在工程资源/商店主语言上保持一致，英文系统下实测系统控件语言与字号 |
| 价格与地区 | 尚未确认 | 由用户确定定价、上架地区；收费协议/税务按实际商业模式办理，不默认加入订阅或后台 |
| 中国大陆可用性 | 尚未读取该 App 的商店地区资格状态 | 若选择大陆，根据 App Store Connect 的适用条件核对备案和资料；不假设离线 App 自动豁免，也不笼统断言所有 App 必须同样备案 |
| 功能完整性 | “iCloud 同步：未开放”仍出现在我的 | 首发本地版时清楚表达本地存储/备份，移除开发占位；商店不宣传不存在功能 |
| 真机稳定性 | 本轮设备发现没有可连接的物理 iPhone | 最终 Release/TestFlight 包完成离线、重启、后台、跨日、锁屏文件、文件分享恢复、触觉/VoiceOver |
| 数据升级 | 核心结构兼容有单元测试，尚无旧安装版覆盖安装记录 | 保留旧版真实格式的脱敏夹具，签名升级安装后逐项对账，导出→恢复不漏草稿/回收站/预算/归档 |
| 测试分发 | 本轮未上传 TestFlight | 至少一次真实安装与完整记账周期验收，确认版本号/构建号/commit/hash 相同 |
| 发布决定 | 存在已确认产品问题与未完成门槛 | 关闭 P1，补齐下方“用户输入”，提交审核后再区分审核通过与正式发布 |

## 已准备、仍需用户确定的发布输入

首发是否依赖 iCloud、开发者团队、真实支持联系方式、商店地区与定价。政策文案/图标/截图/介绍可以先本地准备；不需要自建业务后端。公共政策/支持网页可以是静态网站，但托管地址及公开发布仍需确定。不要从电脑上的开发证书或工作邮箱自动推断对外客服身份。

## 官方依据（本轮重新读取）

- [当前提交要求](https://developer.apple.com/news/upcoming-requirements/)：2026-04-28 起 Xcode 26+ / iOS26 SDK；2026-09-09 起 iOS app target 至少 iOS13。本机工具链满足工具要求，不代表所有兼容系统已验证。
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)：1.5 支持联系方式、2.1 完整可用且经过设备测试、2.3 准确元数据、5.1.1 应用内与商店隐私政策入口。
- [管理 App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)：政策 URL 与实际数据处理声明。
- [添加图标](https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon/)：在 Xcode 工程配置并随构建上传。
- [Required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)：按实际 API 使用声明；页面正文受 JS 渲染限制，本轮未把文本抽查当作 Organizer 隐私报告。
- [创建 App 记录](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)：上传前需可用的 App Store Connect 记录与有效协议。
- [中国大陆合规资料](https://developer.apple.com/help/app-store-connect/manage-compliance-information/view-china-mainland-compliance-information)：地区和 App 类型相关，最终以适用资格与商店校验为准。
