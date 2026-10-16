# 真实 Sandbox 与双账号 iCloud 联调

日期：2026-10-13，北京时间。当前手机为 1.0 (2) Debug 开发签名包，真实 CloudKit Development 已启用；1.0 (1) App Store 签名候选包仍作为备案材料来源，尚未上传。此次联调不部署 Production schema、不提交 Apple 审核或公开网页。

当前 2026-10-14 结果见 [支付复审](../support-payment-2026-10-14/README.md) 与 [双账号验收](../icloud-delivery-2026-10-08/dual-account-acceptance-2026-10-14.md)。以下首轮表格是 10 月 13 日历史批次，不代表最新门槛。

## 已完成与未完成

| 项目 | 实际证据 | 状态 |
| --- | --- | --- |
| 真实 A 端私有云 | iPhone 12 / iOS 26.6.1；新隔离账本上传，新增支出 1234 分，重新同步并重启；本地 cached 与云端 base 一致，具有服务器版本，无冲突 | 通过；不等于双设备或双账号共享 |
| 真实商品加载 | StoreKitSupportClient 返回三个正式商品，未使用 SKTestSession、.storekit 配置或模拟客户端 | 通过 |
| 沙盒测试身份 | 指定发布团队的后台测试账户列表显示一个中国大陆账户；邮箱仅保留在本地和用户操作说明 | 已创建；设备登录另验 |
| 设备地区与价格 | 登录沙盒前，真实商品显示 US$0.99 / US$2.99 / US$3.99 | 仅美区显示已回读；中国大陆沙盒登录后仍需核对 ¥6 / ¥18 / ¥30 |
| 系统 Sandbox 取消 | 人工系统登录、识别 Sandbox 标识并取消，然后回收 UI 与购买日志 | 待本人操作 |
| 真实交易 | 人工确认 Sandbox 购买；回读 verified 交易的环境、产品、持久化、重启及不生成流水 | 待验证 |
| 双账号共享 | B 需要独立的真实 iCloud 身份；私有邀请、接受、互记、只读/可编辑、撤权、离线补同步、重复邀请 | 待第二端与邀请授权；不能用 Sandbox 账户作为 iCloud 身份 |
| Production / TestFlight | 审阅并部署生产 schema、生产签名包和发布渠道回归 | 尚未执行 |

最新机器可读结果见 [verification.json](verification.json)。两项初步真机用例通过，仅对应上传/重启和商品加载；没有把两项通过扩展为付款、分享或发布通过。

## 数据保护与执行方式

- 在安装前读出正常 `ledger.json` 并冻结本地备份；探针结束后逐字节相同。原始账本、账号、设备、云 zone 和证书信息只留在 Git 忽略的 `evidence/live-services-20261013/`。
- 真实联调使用新的 UUID、`YUJI_STRESS_SESSION` 与 `YUJI_TEST_STORE_MODE=empty`，保存在独立临时文件；支持日志使用同一个 UUID 对应的独立目录。
- `YUJI_TEST_SUPPORT_MODE=storekit` 选择真实 StoreKit 客户端；**不设置** `YUJI_TEST_CLOUD_MODE`，由签名配置选择真实 CloudKit。普通 UI 回归仍用模拟云或本地 StoreKit，不自动连接真实服务。
- 手工验收继续使用当前带隔离环境启动的进程；若强退后从桌面重新启动，环境变量不保证保留。需要冷启动时由验收工具传入同一UUID，不以普通桌面启动代替隔离恢复验证。
- 真机用例在 [LiveServiceAcceptanceUITests.swift](../../ios-app/YujiUITests/LiveServiceAcceptanceUITests.swift)。仅在 runner 同时提供显式 `YUJI_LIVE_SERVICE_ACCEPTANCE=1` 和有效 `YUJI_LIVE_SESSION` 时执行，普通回归跳过；先通过现有测试名校验器，再运行精确的用例。
- 编译已安装的 Debug 包不影响旧分发 IPA 的证书、公钥和指纹；这轮配置变更完成后，正式首发包需要重新冻结输入、归档和校验。

## 复现命令的关键配置

`xcodebuild` 使用指定团队 `7S626H9YL4`、当前 Bundle ID、Debug、构建号覆盖为 2，云开关 YES、环境 Development，以及 `YUJI_CLOUD_ENTITLEMENTS=Yuji/Cloud/Yuji.entitlements`。自定义变量仅由 App 的 `CODE_SIGN_ENTITLEMENTS` 引用；单元测试和 UI runner 不应继承 CloudKit 权限。实际 App 签名包含指定容器和 Development，runner 只有自己的测试标识、团队与调试权限；默认工程仍是 cloud NO 和空 entitlements。

生成 `build-for-testing` 后，在同一个 Products 目录复制 xctestrun，设置 runner 的两个 opt-in 变量，再 `test-without-building`，避免改变 `__TESTROOT__` 或重建进行中的结果包。测试完成后顺序读取 xcresult summary、导出附件；新的验收批次使用新结果目录。

## 本轮暴露并关闭的准备问题

1. 全局传 `CODE_SIGN_ENTITLEMENTS` 会把 App 云权限施加到测试 target，造成描述文件错误。已在 canonical project.yml 增加 App 专用的 `YUJI_CLOUD_ENTITLEMENTS` 引用；测试构建及实际 runner 签名已核对。
2. `YUJI_UI_TEST_SESSION` 会自动弹出录入页，遮挡账本和我的入口。首轮两个探针失败，原始录像、UI 树和结果保留；改用不会自动弹层的空 stress 隔离模式后，两项同名探针通过。没有通过坐标绕过被遮挡的控件。
3. 中文语言和 locale 不等于中国大陆 storefront。价格必须展示 Apple 返回值，登录目标沙盒地区后再回读；不能硬改价格文案或扩大正式销售范围掩盖差异。

## 本人操作顺序

先完成开发签名 App 的系统 Sandbox 登录与一次取消；再核对日志无成功交易、购买入口可恢复。随后确认一次 Sandbox 购买，回读 `support.json` 中的环境必须为 Sandbox，验证成功收据已保存、未重复感谢、流水数量和原账本均不变。密码及验证码只在设备上输入。

开发签名 App 可在未上传二进制时测试真实 Sandbox；无需退出日常 iCloud 或非沙盒 Apple 账号。首次尝试购买后，沙盒账号入口可出现在设置 → 开发者。只在系统明确显示 `[Environment: Sandbox]` 时确认；未出现时停止并定位。商品元数据变更可能最多延迟一小时。[Apple 官方 Sandbox 指南](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)

支付手动操作期间不在 A 端启动其他 UI 自动化。B 端可以先准备独立设备和 App；系统 iCloud 登录由本人完成，私有邀请在实际收件人与测试范围确认后再发。多账号完成后按[真实云验收回收表](../icloud-delivery-2026-10-08/real-cloud-acceptance.md)逐项留证，不以私有上传替代共享路径。

## 2026-10-14 跟进

[支付复审](../support-payment-2026-10-14/README.md)已安装 1.0 (3)，组件固定远端修复提交、PR #4 已创建。真机回读 1 笔已核实 Sandbox 小小鼓励收据，无未决；升级和重启后历史保留，真实目录显示 ¥6 / ¥18 / ¥30。旧版收据未保存金额/币种，不能回溯旧交易具体金额；后续新版操作用户已确认正常，并从正常应用目录回读新收据 Sandbox / ¥6 / CNY；自动观察用例先行超时，仍不记自动化通过。原批次个人账本与安装前后备份逐字节一致。后续正常启动自动发现 Development 验收账本，文件新增 3 笔测试数据，原有业务记录和当前选择保持相同，清理预览另有记录。

B 现已由本人登录获授权的 Mac 现有 iCloud，实时身份与 A 不同。Development 的指定私有成员邀请、首次下载、双向新增、重启、冷/热系统链接、重复接受/成员、SDK 只读/恢复编辑/撤权及 B 的真实 UI 拒绝写入、重新邀请恢复均通过。两端 3 笔，收入 ¥100、支出 ¥20、结余 ¥80。修复实际邀请权限缺失、全局 sheet 环境对象崩溃、重启账本选择丢失和磁盘重读后同账号缓存未激活；最终邀请断言等待真正关闭而不是读取底层旧界面。详见[真实双账号验收](../icloud-delivery-2026-10-08/dual-account-acceptance-2026-10-14.md)。完整矩阵和 Production 仍待验证；原发布账号登录卡住的根因未确定，Mac 用户与其 iCloud 未切换。

PR 远端 CI 的官方注记为账户付款或支出限额导致任务未启动，没有代码运行日志；本地通过不能写作远端通过。Development 验收未修改备案使用的分发证书、Production schema 或 App Store 提交状态。

正常启动新增的 3 笔 Development 验收数据已在备份、精确预览和用户授权后回收；真实 SDK 核对仅目标 zone 消失，A/B 本地回收及普通启动没有回流，原业务、其他云绑定和新 ¥6/CNY 收据保留，见[清理记录](../icloud-delivery-2026-10-08/test-fixture-cleanup-2026-10-14.md)。旧共享结果属于已归档夹具，不表示当前仍维持该测试共享。
