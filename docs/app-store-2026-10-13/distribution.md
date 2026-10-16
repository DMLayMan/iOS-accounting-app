# 从指定账号到可发布版本

此文件给出可执行顺序，不表示外部动作已经执行。

本轮实际进度见 [发布记录](README.md)与[分阶段验证](verification.json)。同账号 Developer 网页可通过计划资源中的 App Store Connect 团队跳转进入；单独打开 Connect 登录页曾只显示页脚，不能因此断言账户无权限。

1. Xcode Settings → Apple Accounts：登录用户指定账号，确认邮箱与当前对话相符，读取付费团队和 Team ID。在 Developer/Connect 核对会员有效、App 管理权限与协议状态；出现其他账号不继续操作，不通过旧证书推断团队。
2. 确认同团队 Explicit App ID 与唯一 Bundle ID。Apple 已拒绝旧值 com.yuji.app（不可用），用户于本轮确认替换为 com.dmlayman.yuji，云容器为 iCloud.com.dmlayman.yuji；注册、关联与新云 profile 已实际回读。`ios-app/project.yml` 为工程唯一声明，不只改生成的 xcodeproj。旧 App 不删除，新身份的数据通过应用外备份导入，不能当成原包原地升级。
3. 对共同记账启用 CloudKit：真实容器、App ID 能力、生产环境与签名 entitlements 相符。读取 provisioning 的容器值，不能只看 Info.plist。当前模板缺少/新增系统要求时，以实际 Xcode 生成与 Portal 配置核对后更新。
4. Development 建立 YujiLedger schema：name String、formatVersion Int64、payload Asset；系统 zone-wide CKShare。真实 A/B 邀请接受、互记、只读、撤权/离线与账号切换通过后，部署 schema 至 Production，再验证生产包。[详细回收表](../icloud-delivery-2026-10-08/real-cloud-acceptance.md)
5. 确认首发版本与递增 build number，冻结源码、依赖 revision 与 hash。当前已对齐为 1.0 (1)，新候选包已归档与导出；尚未上传，下一次实际上传若 build 已使用则递增。保存可恢复源快照与覆盖参数；当前大量工作树变更不能只用 HEAD 追溯。
6. 在同团队创建/读取 App Store Connect App 记录，填中文元数据；建立三个打赏商品及合同状态。地区、价格、审核联系人、版权、问卷与公开 HTTPS 政策地址必须有真实值。
7. 签名 Release archive，核对 minimumOS 17、iPhone、图标、政策、PrivacyInfo，无调试夹具/客户端。Organizer Validate App 与 Privacy Report，保存结果；未签名 archive 不能替代。
8. 经用户授权上传到指定账号 App Store Connect，等构建处理成功。TestFlight 内测安装，跑完整记录/退款/转账/预算/备份/升级保留数据、正式 IAP Sandbox 和真实云。只称完成已回收的平台步骤。
9. 将验证后的截图、App 版本和首次消耗型 IAP 加入同一 App Review 草稿，检查所有门槛，再由用户确认送审。协议接受单独交用户处理；发布准备不代表代签合同。
10. 建议选择手动发布。审批通过后按用户明确发布指令上线，在目标地区实际查找/下载，核对版本和真机数据保存。审核通过、上架可下载、长期使用反馈分别留证据。

## 恢复策略

发布前保留用户的应用外备份和可恢复源状态，禁止为了测试删除/重置个人账本。TestFlight 出错时停止对该构建继续分发，修复后提交更高 build number；App Store 出错不能假设用户可一键降级。必要时暂停新用户下载，已有设备数据仍需要兼容修复版。schema 部署与客户端兼容独立核对，不在生产云中清空数据验证。

## 发布后观察

使用 App Store Connect Sales and Trends / App Analytics 查看下载、转化和可获得的使用指标，Xcode Organizer / Connect 查看崩溃、性能与 TestFlight 反馈。用户选择分享、样本门槛和延迟会影响覆盖；没有行为 SDK 就不能得到每个用户完整路径。[既有监测方案](../analytics-plan-2026-10-08.md)

## 本次暴露的前置检查

- 在正式签名/发布前验证 Bundle ID 和商店名称可用性；它们是两套独立的占用检查。原型的通用 ID 不能直接假设可发布。
- Bundle ID 变化会成为新 App 身份；保留旧包与应用外备份，不能称作已验证原地升级。启动脚本读取构建产物的 CFBundleIdentifier，避免再写死旧 ID。
- Development profile 可能是团队 wildcard；同时核对 profile 匹配规则与二进制实际 application-identifier，不能要求 wildcard profile 字面等于具体 App ID，或只查 profile 忽略实际签名。
- App ID 能力修改会使已有相关描述文件失效。一次旧归档重导出仍复用缓存的旧 profile，不能仅以 EXPORT SUCCEEDED 推断更新成功。新的云归档导出已生成 2026-10-13T02:34:49Z profile 并检查权限；旧 IPA 仅留历史证据。
- Profile 表示允许的权限范围，实际二进制表示请求的权限。此次 profile 的 iCloud services 为通配符、环境包含 Development 与 Production；二进制实际为 CloudKit 与 Production。应验证权限被 profile 允许，而不是要求两份值完全字面相等。初始过严检查已修正，属于验证器问题，未改 App 行为。
- 后台创建草稿默认 1.0，原工程为 0.1.0；已对齐并重归档。上传前必须对齐版本、配置和证据；草稿创建成功不代表候选包已经能送审。
